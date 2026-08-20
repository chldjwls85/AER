"""Compare AER encoding policies on synthetic or UZH event traces."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .aer_types import Event
from .care_aer_model import (
    SUPPORTED_POLICIES,
    EncoderConfig,
    SimulationResult,
    simulate_policy,
)
from .load_uzh_events import load_uzh_events
from .synthetic_traffic import build_synthetic_scenario


SCENARIOS = ("uniform", "hotspot", "burst", "moving_edge")


def _infer_sensor_size(events: list[Event]) -> tuple[int, int]:
    if not events:
        raise ValueError("cannot infer sensor dimensions from an empty trace")
    return (
        max(event.x for event in events) + 1,
        max(event.y for event in events) + 1,
    )


def evaluate_trace(
    events: list[Event],
    config: EncoderConfig,
    policies: list[str] | tuple[str, ...] = SUPPORTED_POLICIES,
) -> list[SimulationResult]:
    return [simulate_policy(events, policy, config) for policy in policies]


def _print_table(name: str, events: list[Event], results: list[SimulationResult]) -> None:
    print()
    print(f"[{name}] input_events={len(events)}")
    headers = (
        "policy",
        "accepted",
        "loss%",
        "bit/input",
        "bit/accepted",
        "mean_lat",
        "p99_lat",
        "event/cycle",
        "position%",
        "fifo_max",
    )
    rows = []
    for result in results:
        rows.append(
            (
                result.policy,
                str(result.accepted_events),
                f"{100.0 * result.loss_rate:.2f}",
                f"{result.bits_per_input_event:.2f}",
                f"{result.bits_per_accepted_event:.2f}",
                f"{result.mean_latency_cycles:.2f}",
                str(result.p99_latency_cycles),
                f"{result.events_per_cycle:.4f}",
                f"{100.0 * result.position_preserved_fraction:.2f}",
                str(result.max_tile_fifo_words),
            )
        )
    widths = [
        max(len(headers[index]), *(len(row[index]) for row in rows))
        for index in range(len(headers))
    ]
    print("  ".join(value.ljust(widths[index]) for index, value in enumerate(headers)))
    print("  ".join("-" * width for width in widths))
    for row in rows:
        print("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)))
    for result in results:
        print(
            f"  {result.policy}: tokens={result.token_counts} "
            f"merged={result.intentionally_merged_events}"
        )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--synthetic",
        choices=(*SCENARIOS, "all"),
        help="generate one or all deterministic synthetic scenarios",
    )
    source.add_argument("--uzh", type=Path, help="path to UZH events.txt")

    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--height", type=int, default=16)
    parser.add_argument("--cycles", type=int, default=2_000)
    parser.add_argument("--rate", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--clock-hz", type=float, default=100_000_000.0)
    parser.add_argument(
        "--playback-speed",
        type=float,
        default=1.0,
        help="accelerate a real trace by this factor before cycle quantization",
    )
    parser.add_argument("--max-events", type=int)
    parser.add_argument(
        "--crop",
        type=int,
        nargs=4,
        metavar=("X0", "Y0", "WIDTH", "HEIGHT"),
    )
    parser.add_argument("--window-cycles", type=int, default=8)
    parser.add_argument("--fifo-words", type=int, default=8)
    parser.add_argument("--fixed-group-size", choices=(2, 4), type=int, default=2)
    parser.add_argument(
        "--policies",
        nargs="+",
        choices=SUPPORTED_POLICIES,
        default=list(SUPPORTED_POLICIES),
    )
    parser.add_argument("--json", type=Path, help="write machine-readable results")
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    traces: list[tuple[str, list[Event], int, int]] = []
    if args.synthetic:
        names = SCENARIOS if args.synthetic == "all" else (args.synthetic,)
        for index, name in enumerate(names):
            events = build_synthetic_scenario(
                name=name,
                width=args.width,
                height=args.height,
                cycles=args.cycles,
                rate_per_cycle=args.rate,
                seed=args.seed + index,
                clock_hz=args.clock_hz,
            )
            traces.append((name, events, args.width, args.height))
    else:
        crop = tuple(args.crop) if args.crop else None
        events = load_uzh_events(
            args.uzh,
            clock_hz=args.clock_hz,
            playback_speed=args.playback_speed,
            max_events=args.max_events,
            crop=crop,
        )
        if crop:
            width, height = crop[2], crop[3]
        else:
            width, height = _infer_sensor_size(events)
        traces.append((args.uzh.stem, events, width, height))

    output: dict[str, object] = {
        "model": {
            "word_bits": 32,
            "link_words_per_cycle": 1,
            "note": "architecture exploration model, not cycle-exact RTL",
        },
        "traces": {},
    }
    for name, events, width, height in traces:
        config = EncoderConfig(
            sensor_width=width,
            sensor_height=height,
            window_cycles=args.window_cycles,
            fifo_capacity_words=args.fifo_words,
            fixed_group_size=args.fixed_group_size,
        )
        results = evaluate_trace(events, config, args.policies)
        _print_table(name, events, results)
        output["traces"][name] = {
            "sensor_width": width,
            "sensor_height": height,
            "input_events": len(events),
            "config": {
                "window_cycles": args.window_cycles,
                "fifo_capacity_words": args.fifo_words,
                "fixed_group_size": args.fixed_group_size,
                "clock_hz": args.clock_hz,
                "playback_speed": args.playback_speed,
            },
            "results": [result.as_dict() for result in results],
        }

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(output, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        print(f"\nwrote {args.json}")


if __name__ == "__main__":
    main()
