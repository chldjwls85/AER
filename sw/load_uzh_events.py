"""Load UZH Event-Camera Dataset text files."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterator

from .aer_types import Event
from .event_to_cycle import crop_and_rebase, events_from_rows


def iter_uzh_rows(path: str | Path) -> Iterator[tuple[float, int, int, str]]:
    """Yield rows from an events.txt file.

    Expected format: timestamp x y polarity
    """

    source = Path(path)
    with source.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            fields = text.replace(",", " ").split()
            if len(fields) != 4:
                raise ValueError(
                    f"{source}:{line_number}: expected 4 fields, got {len(fields)}"
                )
            timestamp, x, y, polarity = fields
            yield float(timestamp), int(x), int(y), polarity


def load_uzh_events(
    path: str | Path,
    clock_hz: float,
    playback_speed: float = 1.0,
    max_events: int | None = None,
    crop: tuple[int, int, int, int] | None = None,
) -> list[Event]:
    """Load, optionally crop, and quantize a UZH event text file."""

    if max_events is not None and max_events <= 0:
        raise ValueError("max_events must be positive")

    rows = []
    for row in iter_uzh_rows(path):
        rows.append(row)
        if max_events is not None and len(rows) >= max_events:
            break

    events = events_from_rows(rows, clock_hz, playback_speed)
    if crop is not None:
        events = crop_and_rebase(events, *crop)
    return events


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("events_txt", type=Path)
    parser.add_argument("--clock-hz", type=float, default=100_000_000.0)
    parser.add_argument("--playback-speed", type=float, default=1.0)
    parser.add_argument("--max-events", type=int)
    parser.add_argument(
        "--crop",
        type=int,
        nargs=4,
        metavar=("X0", "Y0", "WIDTH", "HEIGHT"),
    )
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    crop = tuple(args.crop) if args.crop else None
    events = load_uzh_events(
        args.events_txt,
        clock_hz=args.clock_hz,
        playback_speed=args.playback_speed,
        max_events=args.max_events,
        crop=crop,
    )
    if not events:
        print("events=0")
        return
    max_x = max(event.x for event in events)
    max_y = max(event.y for event in events)
    max_cycle = max(event.cycle for event in events)
    on_count = sum(event.polarity for event in events)
    print(
        f"events={len(events)} size={max_x + 1}x{max_y + 1} "
        f"cycles=0..{max_cycle} on={on_count} off={len(events) - on_count}"
    )


if __name__ == "__main__":
    main()
