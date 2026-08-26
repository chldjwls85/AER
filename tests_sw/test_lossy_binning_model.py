from __future__ import annotations

import unittest

from sw.export_v1_uzh_vectors import SourceEvent
from sw.lossy_binning_model import (
    ModelConfig,
    classify_tile,
    encode_lossy_bank_snapshot,
    simulate,
)
from sw.render_v1_uzh_reconstruction import decode_words


class LossyBinningModelTests(unittest.TestCase):
    def test_three_of_four_becomes_same_bin_token_as_four_of_four(self) -> None:
        self.assertEqual(classify_tile(0b0111, 0, "lossy"), ("BIN", 1, 1))
        self.assertEqual(classify_tile(0b1111, 0, "lossy"), ("BIN", 1, 0))
        self.assertEqual(classify_tile(0, 0b1011, "lossy"), ("BIN", 1, 1))

    def test_lossless_keeps_group3_and_mixed_polarity_raw(self) -> None:
        self.assertEqual(classify_tile(0b0111, 0, "lossless"), ("GROUP3", 3, 0))
        self.assertEqual(classify_tile(0b0111, 0b1000, "lossy"), ("RAW8", 8, 0))

    @staticmethod
    def _event(event_id: int, x: int, y: int, polarity: int = 1) -> SourceEvent:
        del event_id
        return SourceEvent(elapsed_ns=0, cycle=0, x=x, y=y, polarity=polarity)

    def test_lossy_packs_three_and_four_pixel_tiles_together(self) -> None:
        events = []
        event_id = 0
        # Five tiles in one bank alternate between 3-of-4 and 4-of-4.  The
        # lossy packet can represent all five with one BIN mask and five
        # polarity bits; the lossless packet needs a separate GROUP3 mask and
        # missing-pixel payload, so RAW remains cheaper for this snapshot.
        for tile_index, pixels in enumerate((3, 4, 3, 4, 3)):
            tile_x = tile_index % 4
            tile_y = tile_index // 4
            for pixel in range(pixels):
                events.append(
                    self._event(
                        event_id,
                        tile_x * 2 + (pixel & 1),
                        tile_y * 2 + ((pixel >> 1) & 1),
                    )
                )
                event_id += 1
        config = ModelConfig(sensor_width=8, sensor_height=8)
        lossless = simulate(events, "lossless", config, 100_000_000)
        lossy = simulate(events, "lossy", config, 100_000_000)

        self.assertEqual(lossless.output_words, 5)
        self.assertEqual(lossy.output_words, 4)
        self.assertEqual(lossy.bank_fused_tiles, 5)
        self.assertEqual(lossy.false_positive_events, 3)
        self.assertEqual(lossy.token_counts, {"BIN": 5})
        self.assertEqual(lossy.packet_mode_counts, {"BANK_MIXED_LOSSY": 1})

    def test_packet_golden_matches_rtl_mixed_and_fallback_cases(self) -> None:
        mixed = [
            (0, 0x1, 0x0),
            (1, 0xE, 0x0),
            (2, 0x0, 0xF),
            (3, 0x0, 0xE),
            (4, 0xF, 0x0),
            (5, 0xE, 0x0),
            (6, 0x0, 0xF),
            (7, 0x2, 0x4),
        ]
        self.assertEqual(
            encode_lossy_bank_snapshot(mixed, bank_id=5),
            [
                (0x8177, 0),
                (0x00FF, 0),
                (0x007E, 0),
                (0x1910, 0),
                (0x0009, 1),
            ],
        )

        self.assertEqual(
            encode_lossy_bank_snapshot([(0, 0xE, 0), (1, 0x1, 0)], bank_id=5),
            [(0xC143, 0), (0x0380, 0), (0x0040, 1)],
        )
        self.assertEqual(
            encode_lossy_bank_snapshot(
                [(0, 0xF, 0), (4, 0xF, 0), (8, 0xF, 0), (12, 0xF, 0)],
                bank_id=5,
            ),
            [(0x8143, 0), (0x1111, 0), (0xF0F0, 0), (0xF0F0, 1)],
        )

    def test_lossy_packet_decoder_counts_intentional_false_pixels(self) -> None:
        tiles = [
            (0, 0x1, 0x0),
            (1, 0xE, 0x0),
            (2, 0x0, 0xF),
            (3, 0x0, 0xE),
            (4, 0xF, 0x0),
            (5, 0xE, 0x0),
            (6, 0x0, 0xF),
            (7, 0x2, 0x4),
        ]
        accepted = [
            {
                "group_id": index,
                "source_cycle": 0,
                "accept_cycle": 0,
                "tile": 5 * 16 + tile,
                "on": on_bitmap,
                "off": off_bitmap,
                "source_events": on_bitmap.bit_count() + off_bitmap.bit_count(),
            }
            for index, (tile, on_bitmap, off_bitmap) in enumerate(tiles)
        ]
        encoded = encode_lossy_bank_snapshot(tiles, bank_id=5)
        words = [
            (cycle, word, last)
            for cycle, (word, last) in enumerate(encoded, start=10)
        ]
        decoded, errors, headers = decode_words(
            accepted, words, external_rx_timestamp=True
        )

        self.assertEqual(errors, [])
        self.assertEqual(headers, 1)
        self.assertEqual(len(decoded), 8)
        self.assertEqual(
            sum(int(record["false_positive_events"]) for record in decoded), 3
        )


if __name__ == "__main__":
    unittest.main()
