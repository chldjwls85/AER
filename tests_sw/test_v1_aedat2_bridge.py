from __future__ import annotations

import struct
from decimal import Decimal
from pathlib import Path

from sw.export_v1_aedat2_vectors import (
    convert_records,
    find_binary_offset,
    load_aedat2_records,
)


def _address(x: int, y: int, polarity: int) -> int:
    raw_x = 127 - x
    polarity_bit = 0 if polarity else 1
    return (y << 8) | (raw_x << 1) | polarity_bit


def test_aedat2_parser_and_cycle_mapping(tmp_path: Path) -> None:
    path = tmp_path / "sample.aedat"
    header = b"#!AER-DAT2.0\r\n# Timestamps tick is 1 us\r\n"
    records = [
        (_address(3, 7, 1), 100),
        (_address(126, 65, 0), 109),
        (_address(10, 20, 1), 110),
    ]
    path.write_bytes(
        header + b"".join(struct.pack(">II", address, timestamp) for address, timestamp in records)
    )

    assert find_binary_offset(path) == len(header)
    raw = load_aedat2_records(path)
    events, start_us, selection = convert_records(
        raw,
        max_events=3,
        clock_hz=Decimal(100_000_000),
        playback_speed=Decimal(1),
        densest_window_ms=None,
    )

    assert start_us == 100
    assert selection["total_file_events"] == 3
    assert [(event.x, event.y, event.polarity) for event in events] == [
        (3, 7, 1),
        (126, 65, 0),
        (10, 20, 1),
    ]
    assert [event.cycle for event in events] == [0, 900, 1000]
