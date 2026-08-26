"""Find CIFAR10-DVS event windows that exercise 2x2 pixel binning."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from decimal import Decimal
from pathlib import Path

from sw.export_v1_aedat2_vectors import convert_records, load_aedat2_records
from sw.export_v1_uzh_vectors import TileGroup, group_events


def classify(group: TileGroup) -> str:
    conflict = bool(group.on_bitmap & group.off_bitmap)
    if not conflict and (
        (group.on_bitmap == 0xF and group.off_bitmap == 0)
        or (group.off_bitmap == 0xF and group.on_bitmap == 0)
    ):
        return "BIN4"
    if not conflict and (
        (group.off_bitmap == 0 and group.on_bitmap.bit_count() == 3)
        or (group.on_bitmap == 0 and group.off_bitmap.bit_count() == 3)
    ):
        return "GROUP3"
    return "RAW8"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("aedat2", type=Path)
    parser.add_argument("--window-events", type=int, default=8_000)
    parser.add_argument("--step-events", type=int, default=250)
    parser.add_argument("--clock-hz", default="100000000")
    parser.add_argument("--playback-speed", default="5000")
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()

    if args.window_events <= 0 or args.step_events <= 0 or args.top <= 0:
        raise SystemExit("window-events, step-events, and top must be positive")

    records = load_aedat2_records(args.aedat2)
    clock_hz = Decimal(args.clock_hz)
    playback_speed = Decimal(args.playback_speed)
    stop = max(1, len(records) - args.window_events + 1)
    starts = list(range(0, stop, args.step_events))
    last_start = max(0, len(records) - args.window_events)
    if starts[-1] != last_start:
        starts.append(last_start)

    results: list[dict[str, int | float]] = []
    for start in starts:
        window = records[start : start + args.window_events]
        events, start_us, _ = convert_records(
            window,
            max_events=len(window),
            clock_hz=clock_hz,
            playback_speed=playback_speed,
            densest_window_ms=None,
        )
        groups = group_events(events)
        counts = Counter(classify(group) for group in groups)
        binned_tiles = counts["GROUP3"] + counts["BIN4"]
        binned_events = 3 * counts["GROUP3"] + 4 * counts["BIN4"]
        represented = sum(group.represented_events for group in groups)
        results.append(
            {
                "start_event": start,
                "start_timestamp_us": start_us,
                "source_events": len(events),
                "duration_us": events[-1].elapsed_ns // 1000 if events else 0,
                "simulated_cycles": events[-1].cycle if events else 0,
                "tile_groups": len(groups),
                "raw8": counts["RAW8"],
                "group3": counts["GROUP3"],
                "bin4": counts["BIN4"],
                "binned_tiles": binned_tiles,
                "binned_tile_percent": 100.0 * binned_tiles / max(1, len(groups)),
                "binned_events": binned_events,
                "binned_event_percent": 100.0 * binned_events / max(1, represented),
            }
        )

    results.sort(
        key=lambda item: (
            int(item["binned_events"]),
            int(item["binned_tiles"]),
            -int(item["duration_us"]),
        ),
        reverse=True,
    )
    payload = {
        "source": str(args.aedat2.resolve()),
        "window_events": args.window_events,
        "step_events": args.step_events,
        "clock_hz": int(clock_hz),
        "playback_speed": float(playback_speed),
        "windows_scanned": len(starts),
        "top_windows": results[: args.top],
    }
    output = json.dumps(payload, ensure_ascii=False, indent=2)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(output, encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
