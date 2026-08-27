"""Build the common 2x2-tile trace used by dataset evaluations."""

from __future__ import annotations

import csv
import json
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class CommonEvent:
    """Dataset-loader output before clock quantization or spatial rebasing."""

    timestamp: float
    x: int
    y: int
    polarity: int


@dataclass(frozen=True)
class SourceEvent:
    event_id: int
    timestamp_s: float
    cycle: int
    x: int
    y: int
    polarity: int


@dataclass(frozen=True)
class TileTransaction:
    cycle: int
    tile_id: int
    on: int
    off: int
    source_event_count: int

    @property
    def canonical_event_count(self) -> int:
        return self.on.bit_count() + self.off.bit_count()


def load_uzh_events(path: Path, max_source_events: int = 200_000) -> list[CommonEvent]:
    """Parse UZH text rows into the dataset-independent loader interface."""

    events: list[CommonEvent] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            timestamp, x, y, polarity = text.replace(",", " ").split()
            events.append(
                CommonEvent(
                    timestamp=float(timestamp),
                    x=int(x),
                    y=int(y),
                    polarity=1 if int(polarity) == 1 else 0,
                )
            )
            if len(events) >= max_source_events:
                break
    if not events:
        raise ValueError(f"no events in {path}")
    return events


def prepare_source_events(
    events: Iterable[CommonEvent],
    crop: tuple[int, int, int, int] | None,
    clock_hz: float,
    playback_speed: float = 1.0,
) -> list[SourceEvent]:
    """Quantize common events and optionally crop/rebase them."""

    common_events = list(events)
    if not common_events:
        return []
    if clock_hz <= 0 or playback_speed <= 0:
        raise ValueError("clock_hz and playback_speed must be positive")

    start_timestamp = common_events[0].timestamp
    if crop is None:
        x0 = y0 = 0
        width = height = None
    else:
        x0, y0, width, height = crop
        if width <= 0 or height <= 0:
            raise ValueError("crop width and height must be positive")

    selected: list[SourceEvent] = []
    for event in common_events:
        if event.polarity not in (0, 1):
            raise ValueError(f"invalid polarity: {event.polarity}")
        if width is not None and height is not None and not (
            x0 <= event.x < x0 + width and y0 <= event.y < y0 + height
        ):
            continue
        cycle = max(
            0,
            int((event.timestamp - start_timestamp) * clock_hz / playback_speed),
        )
        selected.append(
            SourceEvent(
                event_id=len(selected),
                timestamp_s=event.timestamp - start_timestamp,
                cycle=cycle,
                x=event.x - x0,
                y=event.y - y0,
                polarity=event.polarity,
            )
        )
    return selected


def load_uzh_source(
    path: Path,
    max_source_events: int = 200_000,
    crop: tuple[int, int, int, int] = (56, 26, 128, 128),
    clock_hz: float = 100_000_000.0,
    playback_speed: float = 1.0,
) -> tuple[list[SourceEvent], dict[str, int | float | str]]:
    """Reproduce the pinned team loader order: limit, quantize, then crop."""

    x0, y0, width, height = crop
    common_events = load_uzh_events(path, max_source_events=max_source_events)
    start_timestamp = common_events[0].timestamp
    selected = prepare_source_events(
        common_events,
        crop=crop,
        clock_hz=clock_hz,
        playback_speed=playback_speed,
    )

    metadata: dict[str, int | float | str] = {
        "dataset": "UZH shapes_rotation",
        "source_rows_read": len(common_events),
        "cropped_source_events": len(selected),
        "crop_x": x0,
        "crop_y": y0,
        "crop_width": width,
        "crop_height": height,
        "clock_hz": clock_hz,
        "playback_speed": playback_speed,
        "first_source_timestamp_s": start_timestamp,
    }
    return selected, metadata


def flat_tile_id(x: int, y: int) -> tuple[int, int]:
    tile_x = x // 2
    tile_y = y // 2
    bank_id = (tile_y // 4) * 16 + (tile_x // 4)
    local_tile = (tile_y % 4) * 4 + (tile_x % 4)
    bit = (y % 2) * 2 + (x % 2)
    return bank_id * 16 + local_tile, bit


def canonicalize(events: Iterable[SourceEvent]) -> list[TileTransaction]:
    grouped: dict[tuple[int, int], list[int]] = defaultdict(lambda: [0, 0, 0])
    for event in events:
        tile_id, bit = flat_tile_id(event.x, event.y)
        record = grouped[(event.cycle, tile_id)]
        record[event.polarity] |= 1 << bit
        record[2] += 1
    return [
        TileTransaction(
            cycle=cycle,
            tile_id=tile_id,
            off=values[0],
            on=values[1],
            source_event_count=values[2],
        )
        for (cycle, tile_id), values in sorted(grouped.items())
    ]


def write_canonical_csv(path: Path, transactions: Iterable[TileTransaction]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["cycle", "tile_id", "on", "off", "source_event_count"],
        )
        writer.writeheader()
        for transaction in transactions:
            writer.writerow(asdict(transaction))


def choose_windows(
    transactions: list[TileTransaction], window_cycles: int = 1024
) -> dict[str, tuple[int, int]]:
    """Choose deterministic non-cherry-picked sparse/dense/burst windows."""

    if not transactions:
        raise ValueError("empty canonical trace")
    counts: dict[int, int] = defaultdict(int)
    for transaction in transactions:
        counts[transaction.cycle // window_cycles] += transaction.canonical_event_count
    occupied = sorted((count, index) for index, count in counts.items() if count > 0)
    sparse_count, sparse_index = occupied[max(0, len(occupied) // 4)]
    dense_count, dense_index = max(occupied)

    burst_span = max(64, window_cycles // 8)
    burst_counts: dict[int, int] = defaultdict(int)
    for transaction in transactions:
        burst_counts[transaction.cycle // burst_span] += transaction.canonical_event_count
    _, burst_index = max((count, index) for index, count in burst_counts.items())
    burst_center = burst_index * burst_span + burst_span // 2
    burst_start = max(0, burst_center - window_cycles // 2)

    windows = {
        "sparse": (sparse_index * window_cycles, window_cycles),
        "dense": (dense_index * window_cycles, window_cycles),
        "burst": (burst_start, window_cycles),
    }
    # Preserve deterministic labels even if dense and burst overlap.
    _ = sparse_count, dense_count
    return windows


def write_xsim_windows(
    output_dir: Path,
    transactions: list[TileTransaction],
    windows: dict[str, tuple[int, int]],
) -> dict[str, dict[str, int]]:
    """Write fixed-width memory vectors consumed by the XSim dataset TB."""

    by_cycle: dict[int, list[TileTransaction]] = defaultdict(list)
    for transaction in transactions:
        by_cycle[transaction.cycle].append(transaction)

    summary: dict[str, dict[str, int]] = {}
    for name, (start, length) in windows.items():
        target = output_dir / name
        target.mkdir(parents=True, exist_ok=True)
        valid_lines: list[str] = []
        on_lines: list[str] = []
        off_lines: list[str] = []
        canonical_events = 0
        transaction_count = 0
        for cycle in range(start, start + length):
            valid_vector = 0
            on_vector = 0
            off_vector = 0
            for transaction in by_cycle.get(cycle, []):
                valid_vector |= 1 << transaction.tile_id
                on_vector |= transaction.on << (transaction.tile_id * 4)
                off_vector |= transaction.off << (transaction.tile_id * 4)
                canonical_events += transaction.canonical_event_count
                transaction_count += 1
            valid_lines.append(f"{valid_vector:01024x}")
            on_lines.append(f"{on_vector:04096x}")
            off_lines.append(f"{off_vector:04096x}")
        (target / "valid.hex").write_text("\n".join(valid_lines) + "\n", encoding="ascii")
        (target / "on.hex").write_text("\n".join(on_lines) + "\n", encoding="ascii")
        (target / "off.hex").write_text("\n".join(off_lines) + "\n", encoding="ascii")
        summary[name] = {
            "start_cycle": start,
            "cycles": length,
            "transactions": transaction_count,
            "canonical_events": canonical_events,
        }
    (output_dir / "windows.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return summary
