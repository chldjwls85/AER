"""Convert a UZH event trace into cycle-accurate AER v1 tile vectors."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal, ROUND_FLOOR
from pathlib import Path


@dataclass(frozen=True, slots=True)
class SourceEvent:
    elapsed_ns: int
    cycle: int
    x: int
    y: int
    polarity: int


@dataclass(slots=True)
class TileGroup:
    cycle: int
    tile: int
    on_bitmap: int = 0
    off_bitmap: int = 0
    source_events: int = 0

    @property
    def represented_events(self) -> int:
        return self.on_bitmap.bit_count() + self.off_bitmap.bit_count()


def polarity_to_bit(text: str) -> int:
    value = text.strip().lower()
    if value in {"1", "+1", "true", "on"}:
        return 1
    if value in {"0", "-1", "false", "off"}:
        return 0
    raise ValueError(f"unsupported polarity: {text!r}")


def timestamp_to_cycle_exact(
    timestamp: Decimal,
    start: Decimal,
    clock_hz: Decimal,
    playback_speed: Decimal,
) -> int:
    if clock_hz <= 0 or playback_speed <= 0:
        raise ValueError("clock_hz and playback_speed must be positive")
    delta = timestamp - start
    if delta < 0:
        raise ValueError("timestamps must be ordered")
    return int((delta * clock_hz / playback_speed).to_integral_value(
        rounding=ROUND_FLOOR
    ))


def select_densest_window(
    rows: list[tuple[Decimal, int, int, int]],
    duration: Decimal,
) -> tuple[list[tuple[Decimal, int, int, int]], Decimal, Decimal]:
    """Return the most populated half-open timestamp window."""
    if duration <= 0:
        raise ValueError("duration must be positive")
    if not rows:
        return [], Decimal(0), Decimal(0)

    left = 0
    best_left = 0
    best_right = 1
    for right, row in enumerate(rows):
        while row[0] - rows[left][0] >= duration:
            left += 1
        if right + 1 - left > best_right - best_left:
            best_left = left
            best_right = right + 1

    start = rows[best_left][0]
    end = start + duration
    return rows[best_left:best_right], start, end


def load_cropped_events(
    path: Path,
    crop: tuple[int, int, int, int],
    max_events: int,
    clock_hz: Decimal,
    playback_speed: Decimal,
    densest_window_ms: Decimal | None = None,
    scan_input_events: int | None = None,
) -> tuple[list[SourceEvent], Decimal, dict[str, object]]:
    x0, y0, width, height = crop
    if max_events <= 0:
        raise ValueError("max_events must be positive")
    if min(x0, y0) < 0 or width <= 0 or height <= 0:
        raise ValueError("invalid crop")

    if densest_window_ms is not None and densest_window_ms <= 0:
        raise ValueError("densest_window_ms must be positive")
    if scan_input_events is not None and scan_input_events <= 0:
        raise ValueError("scan_input_events must be positive")

    selected_rows: list[tuple[Decimal, int, int, int]] = []
    parsed_rows = 0
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            fields = text.replace(",", " ").split()
            if len(fields) != 4:
                raise ValueError(f"{path}:{line_number}: expected four fields")
            parsed_rows += 1
            timestamp = Decimal(fields[0])
            x = int(fields[1])
            y = int(fields[2])
            if x0 <= x < x0 + width and y0 <= y < y0 + height:
                selected_rows.append(
                    (timestamp, x - x0, y - y0, polarity_to_bit(fields[3]))
                )
                if densest_window_ms is None and len(selected_rows) >= max_events:
                    break
            if scan_input_events is not None and parsed_rows >= scan_input_events:
                break

    if not selected_rows:
        return [], Decimal(0), {"mode": "empty", "parsed_input_events": parsed_rows}

    if densest_window_ms is not None:
        duration = densest_window_ms / Decimal(1000)
        selected_rows, window_start, window_end = select_densest_window(
            selected_rows, duration
        )
        selected_before_cap = len(selected_rows)
        selected_rows = selected_rows[:max_events]
        selection = {
            "mode": "densest_window",
            "window_ms": str(densest_window_ms),
            "window_start_timestamp_s": str(window_start),
            "window_end_timestamp_s": str(window_end),
            "events_in_window_before_cap": selected_before_cap,
            "parsed_input_events": parsed_rows,
        }
    else:
        selection = {
            "mode": "first_cropped_events",
            "parsed_input_events": parsed_rows,
        }

    start = selected_rows[0][0]
    events = [
        SourceEvent(
            elapsed_ns=int(((timestamp - start) * Decimal(1_000_000_000)).to_integral_value()),
            cycle=timestamp_to_cycle_exact(
                timestamp, start, clock_hz, playback_speed
            ),
            x=x,
            y=y,
            polarity=polarity,
        )
        for timestamp, x, y, polarity in selected_rows
    ]
    return events, start, selection


def tile_index_for_pixel(x: int, y: int) -> tuple[int, int]:
    tile_x = x >> 1
    tile_y = y >> 1
    bank_col = tile_x >> 2
    bank_row = tile_y >> 2
    bank_id = bank_row * 16 + bank_col
    local_tile = (tile_y & 3) * 4 + (tile_x & 3)
    tile = bank_id * 16 + local_tile
    pixel_bit = ((y & 1) << 1) | (x & 1)
    return tile, pixel_bit


def group_events(events: list[SourceEvent]) -> list[TileGroup]:
    grouped: dict[tuple[int, int], TileGroup] = {}
    for event in events:
        tile, pixel_bit = tile_index_for_pixel(event.x, event.y)
        key = (event.cycle, tile)
        group = grouped.get(key)
        if group is None:
            group = TileGroup(cycle=event.cycle, tile=tile)
            grouped[key] = group
        if event.polarity:
            group.on_bitmap |= 1 << pixel_bit
        else:
            group.off_bitmap |= 1 << pixel_bit
        group.source_events += 1
    return [grouped[key] for key in sorted(grouped)]


def write_vectors(groups: list[TileGroup], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as handle:
        for group_id, group in enumerate(groups):
            handle.write(
                f"{group_id} {group.cycle} {group.tile} "
                f"{group.on_bitmap:x} {group.off_bitmap:x} "
                f"{group.source_events}\n"
            )


def build_manifest(
    source: Path,
    crop: tuple[int, int, int, int],
    clock_hz: Decimal,
    playback_speed: Decimal,
    start_timestamp: Decimal,
    events: list[SourceEvent],
    groups: list[TileGroup],
    selection: dict[str, object] | None = None,
) -> dict[str, object]:
    format_candidates: defaultdict[str, int] = defaultdict(int)
    conflicts = 0
    for group in groups:
        conflict = bool(group.on_bitmap & group.off_bitmap)
        conflicts += int(conflict)
        if not conflict and group.on_bitmap == 0xF and group.off_bitmap == 0:
            format_candidates["BIN4"] += 1
        elif not conflict and group.off_bitmap == 0xF and group.on_bitmap == 0:
            format_candidates["BIN4"] += 1
        elif not conflict and (
            (group.off_bitmap == 0 and group.on_bitmap.bit_count() == 3)
            or (group.on_bitmap == 0 and group.off_bitmap.bit_count() == 3)
        ):
            format_candidates["GROUP3"] += 1
        else:
            format_candidates["RAW8"] += 1

    represented = sum(group.represented_events for group in groups)
    manifest = {
        "source": str(source.resolve()),
        "crop": list(crop),
        "sensor_width": crop[2],
        "sensor_height": crop[3],
        "clock_hz": int(clock_hz),
        "playback_speed": float(playback_speed),
        "start_timestamp_s": str(start_timestamp),
        "source_events": len(events),
        "tile_groups": len(groups),
        "represented_event_bits": represented,
        "collapsed_repeated_events": len(events) - represented,
        "conflicting_tile_groups": conflicts,
        "format_candidates": dict(sorted(format_candidates.items())),
        "source_duration_ns": events[-1].elapsed_ns if events else 0,
        "simulated_source_cycles": events[-1].cycle if events else 0,
        "events": [
            [event.elapsed_ns, event.x, event.y, event.polarity, event.cycle]
            for event in events
        ],
        "groups": [
            [
                group_id,
                group.cycle,
                group.tile,
                group.on_bitmap,
                group.off_bitmap,
                group.source_events,
            ]
            for group_id, group in enumerate(groups)
        ],
    }
    if selection is not None:
        manifest["selection"] = selection
    return manifest


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("events_txt", type=Path)
    parser.add_argument("vectors_txt", type=Path)
    parser.add_argument("manifest_json", type=Path)
    parser.add_argument("--max-events", type=int, default=5000)
    parser.add_argument("--clock-hz", default="100000000")
    parser.add_argument("--playback-speed", default="5000")
    parser.add_argument(
        "--densest-window-ms",
        help="select the densest cropped window from the scanned input",
    )
    parser.add_argument(
        "--scan-input-events",
        type=int,
        default=200000,
        help="raw input events to scan when selecting a dense window",
    )
    parser.add_argument(
        "--crop", type=int, nargs=4, default=(56, 26, 128, 128),
        metavar=("X0", "Y0", "WIDTH", "HEIGHT")
    )
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    crop = tuple(args.crop)
    clock_hz = Decimal(args.clock_hz)
    playback_speed = Decimal(args.playback_speed)
    densest_window_ms = (
        Decimal(args.densest_window_ms)
        if args.densest_window_ms is not None
        else None
    )
    events, start_timestamp, selection = load_cropped_events(
        args.events_txt,
        crop=crop,
        max_events=args.max_events,
        clock_hz=clock_hz,
        playback_speed=playback_speed,
        densest_window_ms=densest_window_ms,
        scan_input_events=(args.scan_input_events if densest_window_ms else None),
    )
    if not events:
        raise SystemExit("no events remained after cropping")
    if crop[2:] != (128, 128):
        raise SystemExit("AER v1 currently requires a 128x128 crop")

    groups = group_events(events)
    write_vectors(groups, args.vectors_txt)
    manifest = build_manifest(
        args.events_txt,
        crop,
        clock_hz,
        playback_speed,
        start_timestamp,
        events,
        groups,
        selection,
    )
    args.manifest_json.parent.mkdir(parents=True, exist_ok=True)
    args.manifest_json.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(
        "V1_UZH_VECTORS "
        f"events={len(events)} groups={len(groups)} "
        f"represented={manifest['represented_event_bits']} "
        f"cycles={manifest['simulated_source_cycles']}"
    )


if __name__ == "__main__":
    main()
