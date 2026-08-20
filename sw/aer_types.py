"""Shared data types for the CARE-AER software model."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Tuple


@dataclass(frozen=True, slots=True)
class Event:
    """One polarity event after conversion to the simulated clock domain."""

    event_id: int
    timestamp_s: float
    cycle: int
    x: int
    y: int
    polarity: int

    def __post_init__(self) -> None:
        if self.event_id < 0:
            raise ValueError("event_id must be non-negative")
        if self.timestamp_s < 0.0:
            raise ValueError("timestamp_s must be non-negative")
        if self.cycle < 0:
            raise ValueError("cycle must be non-negative")
        if self.x < 0 or self.y < 0:
            raise ValueError("event coordinates must be non-negative")
        if self.polarity not in (0, 1):
            raise ValueError("polarity must be 0 or 1")


@dataclass(frozen=True, slots=True)
class EncodedToken:
    """One logical encoded item occupying one or more 32-bit link words."""

    kind: str
    tile: Tuple[int, int]
    window: int
    ready_cycle: int
    words: int
    events: Tuple[Event, ...]
    position_preserved: bool
    timestamp_preserved: bool

    def __post_init__(self) -> None:
        if self.words <= 0:
            raise ValueError("words must be positive")
        if not self.events:
            raise ValueError("an encoded token must represent at least one event")
        if self.ready_cycle < 0:
            raise ValueError("ready_cycle must be non-negative")


def validate_unique_event_ids(events: list[Event]) -> None:
    """Reject ambiguous traces before metrics are computed."""

    ids = [event.event_id for event in events]
    if len(ids) != len(set(ids)):
        raise ValueError("event_id values must be unique")
