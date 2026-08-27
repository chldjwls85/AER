from __future__ import annotations

import unittest

from sw.dataset.canonical_trace import (
    CommonEvent,
    TileTransaction,
    canonicalize,
    prepare_source_events,
)
from sw.metrics.dataset_profile import build_profile_report


def transaction(cycle: int, tile_id: int, on: int, off: int = 0) -> TileTransaction:
    return TileTransaction(
        cycle=cycle,
        tile_id=tile_id,
        on=on,
        off=off,
        source_event_count=on.bit_count() + off.bit_count(),
    )


class DatasetProfileSmokeTest(unittest.TestCase):
    def test_pure_sparse(self) -> None:
        common = [
            CommonEvent(0.0, 0, 0, 1),
            CommonEvent(0.0, 0, 2, 0),
            CommonEvent(0.0, 0, 4, 1),
            CommonEvent(0.0, 0, 6, 0),
        ]
        records = canonicalize(
            prepare_source_events(common, crop=None, clock_hz=100.0)
        )
        report = build_profile_report(records, source_event_count=len(common))
        costs = report["encoding_comparison"]
        self.assertEqual(report["dataset_profile"]["singleton_ratio"], 1.0)
        self.assertLess(
            costs["SPARSE_FALLBACK"]["total_words"],
            costs["FAIR_RAW"]["total_words"],
        )

    def test_row_dense(self) -> None:
        records = [transaction(10, tile, 1) for tile in range(4)]
        costs = build_profile_report(records)["encoding_comparison"]
        self.assertLessEqual(
            costs["SPARSE_ROW"]["total_words"],
            costs["SPARSE_FALLBACK"]["total_words"],
        )

    def test_bank_dense(self) -> None:
        records = [transaction(20, tile, 1) for tile in range(8)]
        costs = build_profile_report(records)["encoding_comparison"]
        self.assertLessEqual(
            costs["SPARSE_ROW_BANK"]["total_words"],
            costs["SPARSE_ROW"]["total_words"],
        )
        self.assertEqual(
            costs["SPARSE_ROW_BANK"]["mode_counts"].get("BANK"),
            1,
        )

    def test_multi_bit_tile_is_lossless_for_every_policy(self) -> None:
        records = [transaction(30, 0, on=0b0011, off=0b0001)]
        report = build_profile_report(records)
        profile = report["dataset_profile"]
        self.assertEqual(profile["multi_bit_transaction_count"], 1)
        self.assertEqual(
            profile["same_pixel_on_off_conflict_transaction_count"],
            1,
        )
        for result in report["encoding_comparison"].values():
            self.assertEqual(result["encoded_transactions"], 1)
            self.assertEqual(result["dropped_transactions"], 0)
            self.assertEqual(result["total_words"], 3)


if __name__ == "__main__":
    unittest.main()
