from __future__ import annotations

import unittest
from decimal import Decimal

from sw.export_v1_uzh_vectors import (
    SourceEvent,
    group_events,
    select_densest_window,
    tile_index_for_pixel,
    timestamp_to_cycle_exact,
)
from sw.render_v1_uzh_reconstruction import decode_words, reconstructed_events
from sw.render_v1_cycle_trace import annotate_words


class ExactTimestampTests(unittest.TestCase):
    def test_ten_nanoseconds_is_one_100mhz_cycle(self) -> None:
        start = Decimal("0.000000000")
        self.assertEqual(
            timestamp_to_cycle_exact(
                Decimal("0.000000010"),
                start,
                Decimal("100000000"),
                Decimal("1"),
            ),
            1,
        )


class TileMappingTests(unittest.TestCase):
    def test_bottom_right_pixel_of_first_tile(self) -> None:
        self.assertEqual(tile_index_for_pixel(1, 1), (0, 3))

    def test_group_keeps_on_and_off_bitmaps(self) -> None:
        events = [
            SourceEvent(0, 0, 0, 0, 1),
            SourceEvent(0, 0, 1, 1, 0),
            SourceEvent(0, 0, 1, 1, 0),
        ]
        groups = group_events(events)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0].on_bitmap, 0b0001)
        self.assertEqual(groups[0].off_bitmap, 0b1000)
        self.assertEqual(groups[0].source_events, 3)
        self.assertEqual(groups[0].represented_events, 2)


class DenseWindowTests(unittest.TestCase):
    def test_selects_most_populated_half_open_window(self) -> None:
        rows = [
            (Decimal("0.000"), 0, 0, 1),
            (Decimal("0.010"), 0, 0, 1),
            (Decimal("1.000"), 0, 0, 1),
            (Decimal("1.005"), 0, 0, 1),
            (Decimal("1.019"), 0, 0, 1),
            (Decimal("1.020"), 0, 0, 1),
        ]
        selected, start, end = select_densest_window(rows, Decimal("0.020"))
        self.assertEqual([row[0] for row in selected], [
            Decimal("1.000"), Decimal("1.005"), Decimal("1.019")
        ])
        self.assertEqual(start, Decimal("1.000"))
        self.assertEqual(end, Decimal("1.020"))


class PacketDecoderTests(unittest.TestCase):
    def test_external_timestamp_bank_packets_round_trip(self) -> None:
        accepted = []
        for tile in range(16):
            accepted.append({
                "group_id": tile,
                "source_cycle": 1,
                "accept_cycle": 2,
                "tile": tile,
                "on": 0xF,
                "off": 0,
                "source_events": 4,
            })
        for offset, (on_bitmap, off_bitmap) in enumerate(
            ((0x1, 0x2), (0x3, 0x4), (0x5, 0x6))
        ):
            accepted.append({
                "group_id": 16 + offset,
                "source_cycle": 3,
                "accept_cycle": 4,
                "tile": 16 + offset,
                "on": on_bitmap,
                "off": off_bitmap,
                "source_events": 2,
            })

        words = [
            (10, 0x802F, 0),
            (11, 0xFFFF, 0),
            (12, 0xFFFF, 1),
            (20, 0x8042, 0),
            (21, 0x0007, 0),
            (22, 0x3412, 0),
            (23, 0x0056, 1),
        ]
        decoded, errors, headers = decode_words(
            accepted,
            words,
            external_rx_timestamp=True,
        )
        self.assertEqual(errors, [])
        self.assertEqual(headers, 2)
        self.assertEqual(
            [record["format"] for record in decoded],
            ["BANK_BIN4"] * 16 + ["BANK_RAW8"] * 3,
        )
        self.assertEqual(
            [record["rx_timestamp_cycle"] for record in decoded],
            [10] * 16 + [20] * 3,
        )

    def test_external_timestamp_row_fusion_round_trip(self) -> None:
        accepted = []
        for column, polarity in enumerate((0, 1, 0, 1)):
            accepted.append({
                "group_id": column,
                "source_cycle": 1,
                "accept_cycle": 2,
                "tile": column,
                "on": 0xF if polarity else 0,
                "off": 0 if polarity else 0xF,
                "source_events": 4,
            })
        group_patterns = ((0xE, 0), (0xD, 0), (0, 0xB), (0, 0x7))
        for column, (on_bitmap, off_bitmap) in enumerate(group_patterns):
            accepted.append({
                "group_id": 4 + column,
                "source_cycle": 3,
                "accept_cycle": 4,
                "tile": 4 + column,
                "on": on_bitmap,
                "off": off_bitmap,
                "source_events": 3,
            })

        words = [
            (10, 0xC00F, 0),
            (11, 0xD400, 1),
            (20, 0xC01F, 0),
            (21, 0xED58, 1),
        ]
        decoded, errors, headers = decode_words(
            accepted,
            words,
            external_rx_timestamp=True,
        )
        self.assertEqual(errors, [])
        self.assertEqual(headers, 2)
        self.assertEqual(
            [record["format"] for record in decoded],
            ["ROW_BIN4"] * 4 + ["ROW_GROUP3"] * 4,
        )
        self.assertEqual([record["rx_timestamp_cycle"] for record in decoded], [10] * 4 + [20] * 4)

    def test_raw_row_packet_round_trip(self) -> None:
        bank_id = 17
        row = 1
        column = 1
        tile = bank_id * 16 + row * 4 + column
        accepted = [
            {
                "group_id": 7,
                "source_cycle": 10,
                "accept_cycle": 11,
                "tile": tile,
                "on": 0x5,
                "off": 0xA,
                "source_events": 4,
            }
        ]
        header = (0x3 << 14) | (bank_id << 6) | (row << 4) | (1 << column)
        data = (2 << 10) | (0x5A << 2)
        decoded, errors, headers = decode_words(
            accepted,
            [(12, header, 0), (13, 9, 0), (14, data, 1)],
        )
        self.assertEqual(errors, [])
        self.assertEqual(headers, 1)
        self.assertEqual(decoded[0]["group_id"], 7)
        self.assertEqual(decoded[0]["on"], 0x5)
        self.assertEqual(decoded[0]["off"], 0xA)
        self.assertEqual(decoded[0]["format"], "RAW8")

    def test_hardware_receive_time_does_not_use_playback_scale(self) -> None:
        decoded = [{
            "source_cycle": 2,
            "receive_cycle": 10,
            "tile": 0,
            "on": 1,
            "off": 0,
        }]
        source_time = reconstructed_events(decoded, 100_000_000, 100_000, "source_cycle")
        receive_time = reconstructed_events(decoded, 100_000_000, 1.0, "receive_cycle")
        self.assertEqual(source_time[0][0], 2_000_000)
        self.assertEqual(receive_time[0][0], 100)

    def test_cycle_trace_labels_packet_phases(self) -> None:
        header = (0x3 << 14) | (17 << 6) | (1 << 4) | 0b0010
        words = [(12, header, 0), (13, 9, 0), (14, 0x0568, 1)]
        annotated = annotate_words(words)
        self.assertEqual([record[3] for record in annotated], [0, 1, 2])
        self.assertEqual(annotated[0][4:7], [17, 1, 0b0010])
        self.assertEqual(annotated[2][7], 1)


if __name__ == "__main__":
    unittest.main()
