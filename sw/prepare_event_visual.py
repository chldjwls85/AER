"""Prepare a compact real-event snapshot for pixel-binning visualization."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .aer_types import Event
from .load_uzh_events import load_uzh_events


def select_densest_window(events: list[Event], duration_s: float) -> list[Event]:
    """Return the densest half-open time window of the requested duration."""

    if duration_s <= 0.0:
        raise ValueError("duration_s must be positive")
    if not events:
        return []

    ordered = sorted(events, key=lambda event: (event.timestamp_s, event.event_id))
    left = 0
    best_left = 0
    best_right = 0
    for right, event in enumerate(ordered):
        while event.timestamp_s - ordered[left].timestamp_s >= duration_s:
            left += 1
        if right + 1 - left > best_right - best_left:
            best_left = left
            best_right = right + 1

    start_s = ordered[best_left].timestamp_s
    end_s = start_s + duration_s
    return [
        event
        for event in ordered
        if start_s <= event.timestamp_s < end_s
    ]


def build_sparse_snapshot(
    events: list[Event],
    width: int,
    height: int,
    duration_s: float,
) -> dict[str, object]:
    """Aggregate ON/OFF counts and keep only active pixel entries."""

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")

    selected = select_densest_window(events, duration_s)
    counts: dict[int, list[int]] = {}
    for event in selected:
        if not (0 <= event.x < width and 0 <= event.y < height):
            raise ValueError("event lies outside the requested snapshot dimensions")
        index = event.y * width + event.x
        pair = counts.setdefault(index, [0, 0])
        pair[0 if event.polarity else 1] += 1

    start_s = selected[0].timestamp_s if selected else 0.0
    points = [[index, pair[0], pair[1]] for index, pair in sorted(counts.items())]
    on_events = sum(pair[0] for pair in counts.values())
    off_events = sum(pair[1] for pair in counts.values())
    return {
        "width": width,
        "height": height,
        "duration_ms": duration_s * 1_000.0,
        "start_ms": start_s * 1_000.0,
        "end_ms": (start_s + duration_s) * 1_000.0,
        "events": len(selected),
        "on_events": on_events,
        "off_events": off_events,
        "active_pixels": len(points),
        "points": points,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("events_txt", type=Path)
    parser.add_argument("--clock-hz", type=float, default=100_000_000.0)
    parser.add_argument("--max-events", type=int, default=200_000)
    parser.add_argument("--duration-ms", type=float, default=20.0)
    parser.add_argument(
        "--crop",
        type=int,
        nargs=4,
        metavar=("X0", "Y0", "WIDTH", "HEIGHT"),
        default=(56, 26, 128, 128),
    )
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    x0, y0, width, height = args.crop
    events = load_uzh_events(
        args.events_txt,
        clock_hz=args.clock_hz,
        max_events=args.max_events,
        crop=(x0, y0, width, height),
    )
    snapshot = build_sparse_snapshot(
        events,
        width=width,
        height=height,
        duration_s=args.duration_ms / 1_000.0,
    )
    snapshot["source"] = args.events_txt.name
    snapshot["crop"] = [x0, y0, width, height]
    print(json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
