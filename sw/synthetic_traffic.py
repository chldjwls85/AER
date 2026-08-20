"""Deterministic synthetic event traffic for pre-RTL validation."""

from __future__ import annotations

import argparse
import math
import random
from collections.abc import Callable

from .aer_types import Event


def _sample_poisson(rng: random.Random, rate: float) -> int:
    if rate < 0:
        raise ValueError("event rate must be non-negative")
    if rate == 0:
        return 0
    if rate >= 30:
        return max(0, int(round(rng.gauss(rate, math.sqrt(rate)))))
    threshold = math.exp(-rate)
    product = 1.0
    count = 0
    while product > threshold:
        count += 1
        product *= rng.random()
    return count - 1


def _validate_shape(width: int, height: int, cycles: int, clock_hz: float) -> None:
    if width <= 0 or height <= 0 or cycles <= 0:
        raise ValueError("width, height, and cycles must be positive")
    if clock_hz <= 0:
        raise ValueError("clock_hz must be positive")


def _generate_poisson_trace(
    width: int,
    height: int,
    cycles: int,
    rate_for_cycle: Callable[[int], float],
    choose_xy: Callable[[random.Random], tuple[int, int]],
    seed: int,
    clock_hz: float,
) -> list[Event]:
    _validate_shape(width, height, cycles, clock_hz)
    rng = random.Random(seed)
    events: list[Event] = []
    event_id = 0
    for cycle in range(cycles):
        for _ in range(_sample_poisson(rng, rate_for_cycle(cycle))):
            x, y = choose_xy(rng)
            events.append(
                Event(
                    event_id=event_id,
                    timestamp_s=cycle / clock_hz,
                    cycle=cycle,
                    x=x,
                    y=y,
                    polarity=rng.randrange(2),
                )
            )
            event_id += 1
    return events


def generate_uniform_poisson(
    width: int = 16,
    height: int = 16,
    cycles: int = 2_000,
    rate_per_cycle: float = 0.5,
    seed: int = 1,
    clock_hz: float = 100_000_000.0,
) -> list[Event]:
    """Generate spatially uniform Poisson arrivals."""

    rng_xy = lambda rng: (rng.randrange(width), rng.randrange(height))
    return _generate_poisson_trace(
        width,
        height,
        cycles,
        lambda _cycle: rate_per_cycle,
        rng_xy,
        seed,
        clock_hz,
    )


def generate_hotspot(
    width: int = 16,
    height: int = 16,
    cycles: int = 2_000,
    rate_per_cycle: float = 2.0,
    hotspot_event_fraction: float = 0.8,
    seed: int = 2,
    clock_hz: float = 100_000_000.0,
) -> list[Event]:
    """Generate 80/20-style traffic concentrated in a central quarter."""

    if not 0.0 <= hotspot_event_fraction <= 1.0:
        raise ValueError("hotspot_event_fraction must be between zero and one")
    hot_width = max(1, width // 2)
    hot_height = max(1, height // 2)
    x0 = (width - hot_width) // 2
    y0 = (height - hot_height) // 2

    def choose_xy(rng: random.Random) -> tuple[int, int]:
        if rng.random() < hotspot_event_fraction:
            return x0 + rng.randrange(hot_width), y0 + rng.randrange(hot_height)
        return rng.randrange(width), rng.randrange(height)

    return _generate_poisson_trace(
        width,
        height,
        cycles,
        lambda _cycle: rate_per_cycle,
        choose_xy,
        seed,
        clock_hz,
    )


def generate_burst(
    width: int = 16,
    height: int = 16,
    cycles: int = 2_000,
    base_rate_per_cycle: float = 0.25,
    burst_multiplier: float = 4.0,
    burst_start: int = 800,
    burst_duration: int = 128,
    seed: int = 3,
    clock_hz: float = 100_000_000.0,
) -> list[Event]:
    """Generate a uniform background with a bounded high-rate burst."""

    if burst_multiplier < 1.0 or burst_duration <= 0:
        raise ValueError("burst multiplier and duration must be positive")

    def rate(cycle: int) -> float:
        if burst_start <= cycle < burst_start + burst_duration:
            return base_rate_per_cycle * burst_multiplier
        return base_rate_per_cycle

    rng_xy = lambda rng: (rng.randrange(width), rng.randrange(height))
    return _generate_poisson_trace(
        width,
        height,
        cycles,
        rate,
        rng_xy,
        seed,
        clock_hz,
    )


def generate_moving_edge(
    width: int = 16,
    height: int = 16,
    cycles: int = 512,
    step_cycles: int = 4,
    seed: int = 4,
    clock_hz: float = 100_000_000.0,
) -> list[Event]:
    """Generate a vertical edge that repeatedly moves across the sensor."""

    _validate_shape(width, height, cycles, clock_hz)
    if step_cycles <= 0:
        raise ValueError("step_cycles must be positive")
    rng = random.Random(seed)
    events: list[Event] = []
    event_id = 0
    for cycle in range(0, cycles, step_cycles):
        phase = cycle // step_cycles
        period = max(1, 2 * width - 2)
        folded = phase % period
        x = folded if folded < width else period - folded
        polarity = 1 if folded < width else 0
        for y in range(height):
            if rng.random() < 0.95:
                events.append(
                    Event(
                        event_id=event_id,
                        timestamp_s=cycle / clock_hz,
                        cycle=cycle,
                        x=x,
                        y=y,
                        polarity=polarity,
                    )
                )
                event_id += 1
    return events


GENERATORS = {
    "uniform": generate_uniform_poisson,
    "hotspot": generate_hotspot,
    "burst": generate_burst,
    "moving_edge": generate_moving_edge,
}


def build_synthetic_scenario(
    name: str,
    width: int,
    height: int,
    cycles: int,
    rate_per_cycle: float,
    seed: int,
    clock_hz: float,
) -> list[Event]:
    if name == "uniform":
        return generate_uniform_poisson(
            width, height, cycles, rate_per_cycle, seed, clock_hz
        )
    if name == "hotspot":
        return generate_hotspot(
            width, height, cycles, rate_per_cycle, 0.8, seed, clock_hz
        )
    if name == "burst":
        return generate_burst(
            width=width,
            height=height,
            cycles=cycles,
            base_rate_per_cycle=rate_per_cycle,
            burst_multiplier=4.0,
            burst_start=max(1, cycles // 3),
            burst_duration=max(1, cycles // 8),
            seed=seed,
            clock_hz=clock_hz,
        )
    if name == "moving_edge":
        return generate_moving_edge(
            width,
            height,
            cycles,
            max(1, int(round(1.0 / max(rate_per_cycle, 1e-9)))),
            seed,
            clock_hz,
        )
    raise ValueError(f"unknown synthetic scenario: {name}")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", choices=sorted(GENERATORS))
    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--height", type=int, default=16)
    parser.add_argument("--cycles", type=int, default=2_000)
    parser.add_argument("--rate", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=1)
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    events = build_synthetic_scenario(
        args.scenario,
        args.width,
        args.height,
        args.cycles,
        args.rate,
        args.seed,
        100_000_000.0,
    )
    on_count = sum(event.polarity for event in events)
    print(
        f"scenario={args.scenario} events={len(events)} "
        f"on={on_count} off={len(events) - on_count}"
    )


if __name__ == "__main__":
    main()
