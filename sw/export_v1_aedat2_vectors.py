"""Convert a DVS128 AER-DAT2.0 recording into AER v1 tile vectors."""

from __future__ import annotations

import argparse
import json
from decimal import Decimal, ROUND_FLOOR
from pathlib import Path

import numpy as np

from sw.export_v1_uzh_vectors import (
    SourceEvent,
    build_manifest,
    group_events,
    write_vectors,
)


AEDAT2_DTYPE = np.dtype([("address", ">u4"), ("timestamp", ">u4")])


def write_pixel_vectors(events: list[SourceEvent], path: Path) -> None:
    """Write one source event per line for the pixel-pending RTL front end."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as handle:
        for event_id, event in enumerate(events):
            handle.write(
                f"{event_id} {event.cycle} {event.x} {event.y} "
                f"{event.polarity} {event.elapsed_ns}\n"
            )


def find_binary_offset(path: Path) -> int:
    """Return the first byte after the leading AER-DAT comment header."""
    offset = 0
    with path.open("rb") as handle:
        while True:
            marker = handle.read(1)
            if marker != b"#":
                return offset
            line = marker + handle.readline()
            offset += len(line)
            if offset > 1_000_000:
                raise ValueError(f"unreasonably large AER-DAT header: {path}")


def load_aedat2_records(path: Path) -> np.ndarray:
    offset = find_binary_offset(path)
    payload_bytes = path.stat().st_size - offset
    if payload_bytes <= 0 or payload_bytes % AEDAT2_DTYPE.itemsize:
        raise ValueError(f"invalid AER-DAT2.0 payload length: {path}")
    return np.fromfile(path, dtype=AEDAT2_DTYPE, offset=offset)


def unwrap_timestamps(raw: np.ndarray) -> np.ndarray:
    """Convert wrapping uint32 microsecond timestamps into uint64 values."""
    values = raw.astype(np.uint64)
    if len(values) < 2:
        return values
    wraps = np.zeros(len(values), dtype=np.uint64)
    wraps[1:] = np.cumsum(raw[1:] < raw[:-1], dtype=np.uint64)
    return values + (wraps << np.uint64(32))


def densest_window_indices(timestamps: np.ndarray, duration_us: int) -> tuple[int, int]:
    if duration_us <= 0:
        raise ValueError("duration_us must be positive")
    if len(timestamps) == 0:
        return 0, 0
    left = 0
    best_left = 0
    best_right = 1
    for right in range(len(timestamps)):
        while timestamps[right] - timestamps[left] >= duration_us:
            left += 1
        if right + 1 - left > best_right - best_left:
            best_left = left
            best_right = right + 1
    return best_left, best_right


def timestamp_to_cycle(
    elapsed_us: int, clock_hz: Decimal, playback_speed: Decimal
) -> int:
    if clock_hz <= 0 or playback_speed <= 0:
        raise ValueError("clock_hz and playback_speed must be positive")
    return int(
        (Decimal(elapsed_us) * clock_hz / (Decimal(1_000_000) * playback_speed))
        .to_integral_value(rounding=ROUND_FLOOR)
    )


def convert_records(
    records: np.ndarray,
    max_events: int,
    clock_hz: Decimal,
    playback_speed: Decimal,
    densest_window_ms: Decimal | None,
    start_event: int | None = None,
) -> tuple[list[SourceEvent], int, dict[str, object]]:
    if max_events <= 0:
        raise ValueError("max_events must be positive")
    if len(records) == 0:
        return [], 0, {"mode": "empty"}

    timestamps = unwrap_timestamps(records["timestamp"])
    if start_event is not None:
        if start_event < 0 or start_event >= len(records):
            raise ValueError("start_event is outside the recording")
        left = start_event
        right = min(len(records), left + max_events)
        selection = {
            "mode": "event_offset",
            "start_event": start_event,
            "total_file_events": len(records),
        }
    elif densest_window_ms is not None:
        duration_us = int(
            (densest_window_ms * Decimal(1000)).to_integral_value(
                rounding=ROUND_FLOOR
            )
        )
        left, right = densest_window_indices(timestamps, duration_us)
        selected_before_cap = right - left
        right = min(right, left + max_events)
        selection = {
            "mode": "densest_window",
            "window_ms": str(densest_window_ms),
            "window_start_timestamp_us": int(timestamps[left]),
            "window_end_timestamp_us": int(timestamps[left]) + duration_us,
            "events_in_window_before_cap": selected_before_cap,
            "total_file_events": len(records),
        }
    else:
        left = 0
        right = min(len(records), max_events)
        selection = {
            "mode": "first_events",
            "total_file_events": len(records),
        }

    selected = records[left:right]
    selected_timestamps = timestamps[left:right]
    start_us = int(selected_timestamps[0])
    addresses = selected["address"].astype(np.uint32)

    # DVS128 mapping from the dataset-provided dat2mat.m:
    # x is reversed, y is direct, address bit 0 is 0 for ON and 1 for OFF.
    x_values = 127 - ((addresses & np.uint32(0xFE)) >> np.uint32(1))
    y_values = (addresses & np.uint32(0x7F00)) >> np.uint32(8)
    polarity_values = 1 - (addresses & np.uint32(1))

    events = []
    for timestamp, x, y, polarity in zip(
        selected_timestamps, x_values, y_values, polarity_values, strict=True
    ):
        elapsed_us = int(timestamp) - start_us
        events.append(
            SourceEvent(
                elapsed_ns=elapsed_us * 1000,
                cycle=timestamp_to_cycle(elapsed_us, clock_hz, playback_speed),
                x=int(x),
                y=int(y),
                polarity=int(polarity),
            )
        )
    return events, start_us, selection


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("aedat2", type=Path)
    parser.add_argument("vectors_txt", type=Path)
    parser.add_argument("manifest_json", type=Path)
    parser.add_argument("--max-events", type=int, default=20_000)
    parser.add_argument("--clock-hz", default="100000000")
    parser.add_argument("--playback-speed", default="5000")
    parser.add_argument("--densest-window-ms", default="40")
    parser.add_argument("--start-event", type=int)
    parser.add_argument("--pixel-vectors", type=Path)
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    clock_hz = Decimal(args.clock_hz)
    playback_speed = Decimal(args.playback_speed)
    densest_window_ms = (
        Decimal(args.densest_window_ms)
        if args.densest_window_ms is not None
        and Decimal(args.densest_window_ms) > 0
        else None
    )
    records = load_aedat2_records(args.aedat2)
    events, start_us, selection = convert_records(
        records,
        max_events=args.max_events,
        clock_hz=clock_hz,
        playback_speed=playback_speed,
        densest_window_ms=densest_window_ms,
        start_event=args.start_event,
    )
    if not events:
        raise SystemExit("no events were selected")

    groups = group_events(events)
    write_vectors(groups, args.vectors_txt)
    if args.pixel_vectors is not None:
        write_pixel_vectors(events, args.pixel_vectors)
    manifest = build_manifest(
        args.aedat2,
        (0, 0, 128, 128),
        clock_hz,
        playback_speed,
        Decimal(start_us) / Decimal(1_000_000),
        events,
        groups,
        selection,
    )
    manifest.update(
        {
            "dataset": "CIFAR10-DVS",
            "aedat_version": "2.0",
            "timestamp_tick_us": 1,
        }
    )
    args.manifest_json.parent.mkdir(parents=True, exist_ok=True)
    args.manifest_json.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(
        "V1_AEDAT2_VECTORS "
        f"events={len(events)} groups={len(groups)} "
        f"represented={manifest['represented_event_bits']} "
        f"cycles={manifest['simulated_source_cycles']}"
    )


if __name__ == "__main__":
    main()
