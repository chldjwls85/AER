"""Utilities for converting asynchronous timestamps to RTL clock cycles."""

from __future__ import annotations

from collections.abc import Iterable

from .aer_types import Event


def normalize_polarity(value: int | float | str | bool) -> int:
    """Normalize common event-dataset polarity encodings to 0 or 1."""

    if isinstance(value, str):
        text = value.strip().lower()
        if text in {"1", "+1", "true", "on"}:
            return 1
        if text in {"0", "-1", "false", "off"}:
            return 0
        raise ValueError(f"unsupported polarity value: {value!r}")

    numeric = int(value)
    if numeric == 1:
        return 1
    if numeric in (0, -1):
        return 0
    raise ValueError(f"unsupported polarity value: {value!r}")


def timestamp_to_cycle(
    timestamp_s: float,
    start_timestamp_s: float,
    clock_hz: float,
    playback_speed: float = 1.0,
) -> int:
    """Map a timestamp to a non-negative cycle using floor quantization.

    playback_speed greater than one accelerates a real trace and is useful for
    sweeping a fixed hardware link toward congestion.
    """

    if clock_hz <= 0:
        raise ValueError("clock_hz must be positive")
    if playback_speed <= 0:
        raise ValueError("playback_speed must be positive")
    delta = timestamp_s - start_timestamp_s
    if delta < -1e-12:
        raise ValueError("timestamps must not precede start_timestamp_s")
    return max(0, int(delta * clock_hz / playback_speed))


def events_from_rows(
    rows: Iterable[tuple[float, int, int, int | float | str | bool]],
    clock_hz: float,
    playback_speed: float = 1.0,
) -> list[Event]:
    """Convert timestamp/x/y/polarity rows into sorted Event objects."""

    buffered = list(rows)
    if not buffered:
        return []
    buffered.sort(key=lambda row: row[0])
    start = float(buffered[0][0])
    events: list[Event] = []
    for event_id, (timestamp_s, x, y, polarity) in enumerate(buffered):
        timestamp = float(timestamp_s)
        events.append(
            Event(
                event_id=event_id,
                timestamp_s=timestamp - start,
                cycle=timestamp_to_cycle(
                    timestamp,
                    start,
                    clock_hz,
                    playback_speed,
                ),
                x=int(x),
                y=int(y),
                polarity=normalize_polarity(polarity),
            )
        )
    return events


def crop_and_rebase(
    events: Iterable[Event],
    x0: int,
    y0: int,
    width: int,
    height: int,
) -> list[Event]:
    """Keep a rectangular sensor region and rebase it to coordinate (0, 0)."""

    if min(x0, y0) < 0 or width <= 0 or height <= 0:
        raise ValueError("crop origin must be non-negative and size must be positive")
    selected = [
        event
        for event in events
        if x0 <= event.x < x0 + width and y0 <= event.y < y0 + height
    ]
    return [
        Event(
            event_id=new_id,
            timestamp_s=event.timestamp_s,
            cycle=event.cycle,
            x=event.x - x0,
            y=event.y - y0,
            polarity=event.polarity,
        )
        for new_id, event in enumerate(selected)
    ]
