from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from sw.aer_types import Event
from sw.analyze_features import analyze_features
from sw.care_aer_model import EncoderConfig, simulate_policy
from sw.event_to_cycle import events_from_rows, normalize_polarity
from sw.load_uzh_events import load_uzh_events
from sw.prepare_event_visual import build_sparse_snapshot, select_densest_window
from sw.packet_decoder import (
    decode_adaptive_word,
    decode_mask4_pair,
    pack_bin_128,
    pack_mask2_128,
    pack_mask4_body,
    pack_mask4_header_128,
    pack_raw_128,
    pack_raw_v0,
    pack_sync,
    unpack_raw_v0,
)
from sw.synthetic_traffic import generate_uniform_poisson


class TimestampAndLoaderTests(unittest.TestCase):
    def test_polarity_encodings(self) -> None:
        self.assertEqual(normalize_polarity("1"), 1)
        self.assertEqual(normalize_polarity("+1"), 1)
        self.assertEqual(normalize_polarity("true"), 1)
        self.assertEqual(normalize_polarity("0"), 0)
        self.assertEqual(normalize_polarity("-1"), 0)
        self.assertEqual(normalize_polarity("off"), 0)
        with self.assertRaises(ValueError):
            normalize_polarity("2")

    def test_timestamp_quantization_and_playback_speed(self) -> None:
        rows = [
            (1.0, 0, 0, 1),
            (1.000001, 1, 0, 0),
            (1.000002, 2, 0, 1),
        ]
        normal = events_from_rows(rows, clock_hz=1_000_000.0)
        faster = events_from_rows(
            rows, clock_hz=1_000_000.0, playback_speed=2.0
        )
        self.assertEqual([event.cycle for event in normal], [0, 0, 2])
        self.assertEqual([event.cycle for event in faster], [0, 0, 1])

    def test_uzh_text_load_and_crop(self) -> None:
        content = "\n".join(
            (
                "# timestamp x y polarity",
                "0.000000 10 20 1",
                "0.000001 11 20 0",
                "0.000002 30 40 -1",
            )
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.txt"
            path.write_text(content, encoding="utf-8")
            events = load_uzh_events(
                path,
                clock_hz=1_000_000.0,
                crop=(10, 20, 4, 4),
            )
        self.assertEqual(len(events), 2)
        self.assertEqual([(event.x, event.y) for event in events], [(0, 0), (1, 0)])
        self.assertEqual([event.polarity for event in events], [1, 0])


class PacketTests(unittest.TestCase):
    def test_raw_v0_round_trip(self) -> None:
        word = pack_raw_v0(1023, 511, 1, 255, 0)
        decoded = unpack_raw_v0(word)
        self.assertEqual(decoded["x"], 1023)
        self.assertEqual(decoded["y"], 511)
        self.assertEqual(decoded["polarity"], 1)
        self.assertEqual(decoded["time"], 255)

    def test_adaptive_packet_round_trips(self) -> None:
        raw = decode_adaptive_word(pack_raw_128(127, 3, 1, 250, 5))
        self.assertEqual(raw["type"], "RAW")
        self.assertEqual(raw["x"], 127)
        self.assertEqual(raw["delta_t"], 250)

        mask2 = decode_adaptive_word(pack_mask2_128(12, 14, 100, 0xA, 0x5))
        self.assertEqual(mask2["type"], "MASK2")
        self.assertEqual(mask2["on_mask"], 0xA)

        header = pack_mask4_header_128(31, 7, 90, 17, 3)
        body = pack_mask4_body(0xA55A, 0x5AA5)
        mask4 = decode_mask4_pair(header, body)
        self.assertEqual(mask4["type"], "MASK4")
        self.assertEqual(mask4["on_mask"], 0xA55A)
        self.assertEqual(mask4["off_mask"], 0x5AA5)

        bin_packet = decode_adaptive_word(pack_bin_128(4, 12, 16, 16, 7, 31))
        self.assertEqual(bin_packet["type"], "BIN4")
        self.assertEqual(bin_packet["on_count"], 16)
        self.assertEqual(bin_packet["off_count"], 7)

        sync = decode_adaptive_word(pack_sync(0x123456))
        self.assertEqual(sync, {"type": "SYNC", "payload": 0x123456})

    def test_packet_range_checks(self) -> None:
        with self.assertRaises(ValueError):
            pack_raw_128(128, 0, 0, 0)
        with self.assertRaises(ValueError):
            pack_mask2_128(1, 0, 0, 0, 0)
        with self.assertRaises(ValueError):
            pack_bin_128(3, 0, 0, 0, 0, 0)


class TrafficAndPolicyTests(unittest.TestCase):
    def test_synthetic_trace_is_deterministic(self) -> None:
        first = generate_uniform_poisson(
            width=8,
            height=8,
            cycles=100,
            rate_per_cycle=0.5,
            seed=77,
        )
        second = generate_uniform_poisson(
            width=8,
            height=8,
            cycles=100,
            rate_per_cycle=0.5,
            seed=77,
        )
        self.assertEqual(first, second)

    @staticmethod
    def _repeated_full_tile(cycles: int) -> list[Event]:
        events = []
        event_id = 0
        for cycle in range(cycles):
            for y in range(4):
                for x in range(4):
                    events.append(
                        Event(
                            event_id=event_id,
                            timestamp_s=cycle / 100_000_000.0,
                            cycle=cycle,
                            x=x,
                            y=y,
                            polarity=1,
                        )
                    )
                    event_id += 1
        return events

    def test_group_policies_reduce_dense_word_count(self) -> None:
        events = self._repeated_full_tile(1)
        config = EncoderConfig(
            sensor_width=4,
            sensor_height=4,
            window_cycles=1,
            fifo_capacity_words=32,
            fixed_group_size=2,
        )
        raw = simulate_policy(events, "raw", config)
        mask = simulate_policy(events, "mask", config)
        bin_result = simulate_policy(events, "bin", config)
        self.assertEqual(raw.output_words, 16)
        self.assertEqual(mask.output_words, 4)
        self.assertEqual(bin_result.output_words, 4)
        self.assertEqual(mask.position_preserved_fraction, 1.0)
        self.assertEqual(bin_result.position_preserved_fraction, 0.0)

    def test_care_adapts_under_repeated_congestion(self) -> None:
        events = self._repeated_full_tile(12)
        config = EncoderConfig(
            sensor_width=4,
            sensor_height=4,
            window_cycles=1,
            fifo_capacity_words=8,
            fixed_group_size=2,
            exact_age_limit=4,
        )
        raw = simulate_policy(events, "raw", config)
        care = simulate_policy(events, "care", config)
        self.assertIn("BIN4", care.token_counts)
        self.assertLess(care.loss_rate, raw.loss_rate)
        self.assertGreater(care.position_preserved_fraction, 0.0)

    def test_repeated_tile_is_summary_eligible(self) -> None:
        events = self._repeated_full_tile(4)
        stats = analyze_features(events, window_cycles=1)
        self.assertGreater(stats["summary_eligible_group_fraction"], 0.0)
        self.assertGreater(stats["exact_grouping_saved_words"], 0)

    def test_empty_trace(self) -> None:
        result = simulate_policy(
            [],
            "care",
            EncoderConfig(sensor_width=4, sensor_height=4),
        )
        self.assertEqual(result.input_events, 0)
        self.assertEqual(result.loss_rate, 0.0)

    def test_visual_snapshot_selects_dense_interval(self) -> None:
        events = [
            Event(0, 0.000, 0, 0, 0, 1),
            Event(1, 0.100, 10, 1, 1, 1),
            Event(2, 0.101, 11, 1, 1, 0),
            Event(3, 0.102, 12, 2, 1, 1),
        ]
        selected = select_densest_window(events, duration_s=0.01)
        self.assertEqual([event.event_id for event in selected], [1, 2, 3])

        snapshot = build_sparse_snapshot(
            events,
            width=4,
            height=4,
            duration_s=0.01,
        )
        self.assertEqual(snapshot["events"], 3)
        self.assertEqual(snapshot["active_pixels"], 2)
        self.assertEqual(snapshot["points"], [[5, 1, 1], [6, 1, 0]])


if __name__ == "__main__":
    unittest.main()
