"""Inspect tile statistics before choosing CARE-AER hardware thresholds."""

from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict
from pathlib import Path

from .aer_types import Event
from .load_uzh_events import load_uzh_events


def _percentile(values: list[int], fraction: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    index = max(0, math.ceil(fraction * len(ordered)) - 1)
    return ordered[index]


def analyze_features(
    events: list[Event],
    tile_size: int = 4,
    window_cycles: int = 8,
    dominant_ratio: int = 3,
    variation_threshold: int = 4,
    bin4_density_threshold: int = 8,
) -> dict[str, int | float]:
    if tile_size != 4:
        raise ValueError("the current feature analyzer uses 4x4 tiles")
    if window_cycles <= 0:
        raise ValueError("window_cycles must be positive")

    grouped: dict[tuple[int, int, int], list[Event]] = defaultdict(list)
    for event in events:
        grouped[
            (
                event.cycle // window_cycles,
                event.x // tile_size,
                event.y // tile_size,
            )
        ].append(event)

    previous_masks: dict[tuple[int, int], int] = {}
    event_counts: list[int] = []
    densities: list[int] = []
    variations: list[int] = []
    dominant_groups = 0
    stable_groups = 0
    eligible_groups = 0
    eligible_events = 0
    exact_grouping_saves_words = 0

    for (window, tile_x, tile_y), group in sorted(grouped.items()):
        del window
        origin_x = tile_x * tile_size
        origin_y = tile_y * tile_size
        location_mask = 0
        on_positions: set[tuple[int, int]] = set()
        off_positions: set[tuple[int, int]] = set()
        active_subregions: set[tuple[int, int]] = set()
        for event in group:
            rel_x = event.x - origin_x
            rel_y = event.y - origin_y
            location_mask |= 1 << (rel_y * tile_size + rel_x)
            active_subregions.add((rel_x // 2, rel_y // 2))
            target = on_positions if event.polarity else off_positions
            target.add((event.x, event.y))

        tile = (tile_x, tile_y)
        previous = previous_masks.get(tile)
        variation = (
            16 if previous is None else (location_mask ^ previous).bit_count()
        )
        previous_masks[tile] = location_mask
        density = location_mask.bit_count()
        on_count = len(on_positions)
        off_count = len(off_positions)
        larger = max(on_count, off_count)
        smaller = min(on_count, off_count)
        dominant = (
            on_count + off_count >= 2
            and (smaller == 0 or larger >= dominant_ratio * smaller)
        )
        stable = previous is not None and variation <= variation_threshold

        raw_words = len(group)
        mask2_words = len(active_subregions)
        mask4_words = 2
        exact_words = min(raw_words, mask2_words, mask4_words)
        exact_grouping_saves_words += raw_words - exact_words

        summary_words = (
            1
            if density >= bin4_density_threshold
            else len(active_subregions)
        )
        eligible = (
            stable
            and dominant
            and density >= 2
            and summary_words < exact_words
        )

        event_counts.append(len(group))
        densities.append(density)
        variations.append(variation)
        dominant_groups += int(dominant)
        stable_groups += int(stable)
        eligible_groups += int(eligible)
        eligible_events += len(group) if eligible else 0

    group_count = len(event_counts)
    return {
        "events": len(events),
        "groups": group_count,
        "events_per_group_mean": (
            sum(event_counts) / group_count if group_count else 0.0
        ),
        "events_per_group_p50": _percentile(event_counts, 0.50),
        "events_per_group_p90": _percentile(event_counts, 0.90),
        "events_per_group_p99": _percentile(event_counts, 0.99),
        "events_per_group_max": max(event_counts, default=0),
        "density_p50": _percentile(densities, 0.50),
        "density_p90": _percentile(densities, 0.90),
        "density_p99": _percentile(densities, 0.99),
        "variation_p50": _percentile(variations, 0.50),
        "variation_p90": _percentile(variations, 0.90),
        "variation_p99": _percentile(variations, 0.99),
        "dominant_group_fraction": (
            dominant_groups / group_count if group_count else 0.0
        ),
        "stable_group_fraction": (
            stable_groups / group_count if group_count else 0.0
        ),
        "summary_eligible_group_fraction": (
            eligible_groups / group_count if group_count else 0.0
        ),
        "summary_eligible_event_fraction": (
            eligible_events / len(events) if events else 0.0
        ),
        "exact_grouping_saved_words": exact_grouping_saves_words,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uzh", required=True, type=Path)
    parser.add_argument("--crop", type=int, nargs=4, required=True)
    parser.add_argument("--clock-hz", type=float, default=100_000_000.0)
    parser.add_argument("--playback-speed", type=float, default=1.0)
    parser.add_argument("--max-events", type=int)
    parser.add_argument(
        "--window-cycles",
        type=int,
        nargs="+",
        default=[8, 16, 32, 64],
    )
    parser.add_argument("--dominant-ratio", type=int, default=3)
    parser.add_argument("--variation-threshold", type=int, default=4)
    parser.add_argument("--json", type=Path)
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    events = load_uzh_events(
        args.uzh,
        clock_hz=args.clock_hz,
        playback_speed=args.playback_speed,
        max_events=args.max_events,
        crop=tuple(args.crop),
    )
    output = {}
    for window_cycles in args.window_cycles:
        stats = analyze_features(
            events,
            window_cycles=window_cycles,
            dominant_ratio=args.dominant_ratio,
            variation_threshold=args.variation_threshold,
        )
        output[str(window_cycles)] = stats
        print(
            f"window={window_cycles:>3} groups={stats['groups']:>6} "
            f"event/group={stats['events_per_group_mean']:.2f} "
            f"density_p90={stats['density_p90']} "
            f"variation_p90={stats['variation_p90']} "
            f"dominant={100 * stats['dominant_group_fraction']:.1f}% "
            f"stable={100 * stats['stable_group_fraction']:.1f}% "
            f"summary_eligible={100 * stats['summary_eligible_group_fraction']:.2f}%"
        )
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(output, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        print(f"wrote {args.json}")


if __name__ == "__main__":
    main()
