from __future__ import annotations

import unittest

from sw.export_v1_uzh_vectors import SourceEvent
from sw.rtl_cycle_model import RtlCycleConfig, simulate_rtl_cycle_exact


def _event(cycle: int, x: int, y: int, polarity: int) -> SourceEvent:
    return SourceEvent(
        elapsed_ns=cycle * 10,
        cycle=cycle,
        x=x,
        y=y,
        polarity=polarity,
    )


class RtlCycleModelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = RtlCycleConfig(pixel_fifo_depth=2)

    def test_same_cycle_request_bitmap_matches_rtl_accounting(self) -> None:
        events = [
            _event(0, 0, 0, 1),
            _event(0, 0, 0, 1),
            _event(0, 0, 0, 0),
        ]
        result = simulate_rtl_cycle_exact(events, "raw", self.config, 100_000_000)

        self.assertEqual(result.accepted_events, 1)
        self.assertEqual(result.ignored_events, 1)
        self.assertEqual(result.same_cycle_duplicate_events, 1)
        self.assertEqual(result.loss_events, 2)
        self.assertEqual(result.output_words, 2)

    def test_lossy_fusion_obeys_registered_hierarchy(self) -> None:
        events = []
        for tile_index, pixel_count in enumerate((3, 4, 3, 4, 3)):
            tile_x = tile_index % 4
            tile_y = tile_index // 4
            for pixel in range(pixel_count):
                events.append(
                    _event(
                        0,
                        tile_x * 2 + (pixel & 1),
                        tile_y * 2 + ((pixel >> 1) & 1),
                        1,
                    )
                )

        result = simulate_rtl_cycle_exact(
            events, "lossy", self.config, 100_000_000
        )

        self.assertEqual(result.accepted_events, 17)
        self.assertEqual(result.accepted_tile_groups, 5)
        self.assertEqual(result.false_positive_events, 3)
        self.assertEqual(result.output_words, 4)
        self.assertEqual(result.packet_mode_counts, {"BANK_LOSSY": 1})

    def test_combined_policy_uses_one_word_sparse_packet(self) -> None:
        result = simulate_rtl_cycle_exact(
            [_event(0, 0, 0, 1)], "combined", self.config, 100_000_000
        )

        self.assertEqual(result.accepted_events, 1)
        self.assertEqual(result.output_words, 1)
        self.assertEqual(result.packet_mode_counts, {"SPARSE": 1})

    def test_combined_policy_keeps_dense_lossy_bank_packet(self) -> None:
        events = []
        for tile_index, pixel_count in enumerate((3, 4, 3, 4, 3)):
            tile_x = tile_index % 4
            tile_y = tile_index // 4
            for pixel in range(pixel_count):
                events.append(
                    _event(
                        0,
                        tile_x * 2 + (pixel & 1),
                        tile_y * 2 + ((pixel >> 1) & 1),
                        1,
                    )
                )

        result = simulate_rtl_cycle_exact(
            events, "combined", self.config, 100_000_000
        )

        self.assertEqual(result.output_words, 4)
        self.assertEqual(result.false_positive_events, 3)
        self.assertEqual(result.packet_mode_counts, {"BANK_LOSSY": 1})


if __name__ == "__main__":
    unittest.main()
