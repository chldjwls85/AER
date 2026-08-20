"""Cycle-level software reference model for RAW, MASK, BIN, and CARE-AER."""

from __future__ import annotations

import math
from collections import defaultdict, deque
from dataclasses import asdict, dataclass, field
from typing import Deque, Iterable

from .aer_types import EncodedToken, Event, validate_unique_event_ids


SUPPORTED_POLICIES = ("raw", "mask", "bin", "care")


@dataclass(frozen=True, slots=True)
class EncoderConfig:
    sensor_width: int
    sensor_height: int
    tile_size: int = 4
    window_cycles: int = 8
    fifo_capacity_words: int = 8
    fixed_group_size: int = 2
    dominant_ratio: int = 3
    variation_threshold: int = 4
    exact_age_limit: int = 4
    bin4_density_threshold: int = 8
    word_bits: int = 32

    def __post_init__(self) -> None:
        if self.sensor_width <= 0 or self.sensor_height <= 0:
            raise ValueError("sensor dimensions must be positive")
        if self.tile_size != 4:
            raise ValueError("the current CARE-AER reference model uses 4x4 tiles")
        if self.window_cycles <= 0 or self.fifo_capacity_words <= 0:
            raise ValueError("window and FIFO sizes must be positive")
        if self.fixed_group_size not in (2, 4):
            raise ValueError("fixed_group_size must be 2 or 4")
        if self.dominant_ratio < 1 or self.exact_age_limit < 1:
            raise ValueError("dominance ratio and exact age limit must be positive")
        if not 1 <= self.bin4_density_threshold <= 16:
            raise ValueError("bin4 density threshold must be between 1 and 16")


@dataclass(slots=True)
class SimulationResult:
    policy: str
    input_events: int
    accepted_events: int
    dropped_events: int
    output_words: int
    output_bits: int
    mean_latency_cycles: float
    p99_latency_cycles: int
    loss_rate: float
    bits_per_input_event: float
    bits_per_accepted_event: float
    events_per_cycle: float
    position_preserved_events: int
    position_preserved_fraction: float
    intentionally_merged_events: int
    max_tile_fifo_words: int
    token_counts: dict[str, int] = field(default_factory=dict)
    event_counts_by_token: dict[str, int] = field(default_factory=dict)

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(slots=True)
class _QueuedToken:
    token: EncodedToken
    remaining_words: int


class _RoundRobinLink:
    """One 32-bit output link fed by per-tile word-capacity FIFOs."""

    def __init__(self, tiles: list[tuple[int, int]], fifo_capacity_words: int):
        self.tiles = sorted(tiles, key=lambda tile: (tile[1], tile[0]))
        self.tile_index = {tile: index for index, tile in enumerate(self.tiles)}
        self.capacity = fifo_capacity_words
        self.queues: dict[tuple[int, int], Deque[_QueuedToken]] = {
            tile: deque() for tile in self.tiles
        }
        self.occupancy = {tile: 0 for tile in self.tiles}
        self.max_occupancy = {tile: 0 for tile in self.tiles}
        self.time = 0
        self.last_grant_index = -1
        self.active_tile: tuple[int, int] | None = None
        self.active: _QueuedToken | None = None
        self.completed: list[tuple[EncodedToken, int]] = []

    def occupancy_words(self, tile: tuple[int, int]) -> int:
        return self.occupancy[tile]

    def enqueue(self, token: EncodedToken) -> bool:
        tile = token.tile
        if self.occupancy[tile] + token.words > self.capacity:
            return False
        self.queues[tile].append(_QueuedToken(token, token.words))
        self.occupancy[tile] += token.words
        self.max_occupancy[tile] = max(
            self.max_occupancy[tile], self.occupancy[tile]
        )
        return True

    def _select_next(self) -> None:
        if self.active is not None:
            return
        tile_count = len(self.tiles)
        for offset in range(1, tile_count + 1):
            index = (self.last_grant_index + offset) % tile_count
            tile = self.tiles[index]
            if self.queues[tile]:
                self.active_tile = tile
                self.active = self.queues[tile].popleft()
                self.last_grant_index = index
                return

    def advance(self, target_cycle: int) -> None:
        if target_cycle < self.time:
            raise ValueError("link time cannot move backwards")
        while self.time < target_cycle:
            self._select_next()
            if self.active is None:
                self.time = target_cycle
                return
            assert self.active_tile is not None
            budget = target_cycle - self.time
            sent = min(budget, self.active.remaining_words)
            self.active.remaining_words -= sent
            self.occupancy[self.active_tile] -= sent
            self.time += sent
            if self.active.remaining_words == 0:
                self.completed.append((self.active.token, self.time - 1))
                self.active = None
                self.active_tile = None

    def drain_all(self) -> None:
        while self.active is not None or any(self.queues[tile] for tile in self.tiles):
            remaining = sum(self.occupancy.values())
            self.advance(self.time + max(1, remaining))


def _make_token(
    kind: str,
    tile: tuple[int, int],
    window: int,
    ready_cycle: int,
    words: int,
    events: Iterable[Event],
    position_preserved: bool,
    timestamp_preserved: bool,
) -> EncodedToken:
    return EncodedToken(
        kind=kind,
        tile=tile,
        window=window,
        ready_cycle=ready_cycle,
        words=words,
        events=tuple(events),
        position_preserved=position_preserved,
        timestamp_preserved=timestamp_preserved,
    )


def _raw_tokens(
    events: list[Event],
    tile: tuple[int, int],
    window: int,
    ready_cycle: int,
) -> list[EncodedToken]:
    return [
        _make_token("RAW", tile, window, ready_cycle, 1, [event], True, True)
        for event in events
    ]


def _partition_2x2(
    events: list[Event],
    tile: tuple[int, int],
    tile_size: int,
) -> list[list[Event]]:
    groups: dict[tuple[int, int], list[Event]] = defaultdict(list)
    origin_x = tile[0] * tile_size
    origin_y = tile[1] * tile_size
    for event in events:
        sub_x = (event.x - origin_x) // 2
        sub_y = (event.y - origin_y) // 2
        groups[(sub_x, sub_y)].append(event)
    return [groups[key] for key in sorted(groups, key=lambda key: (key[1], key[0]))]


def _mask2_tokens(
    events: list[Event],
    tile: tuple[int, int],
    window: int,
    ready_cycle: int,
    tile_size: int,
) -> list[EncodedToken]:
    return [
        _make_token("MASK2", tile, window, ready_cycle, 1, group, True, False)
        for group in _partition_2x2(events, tile, tile_size)
    ]


def _mask4_tokens(
    events: list[Event],
    tile: tuple[int, int],
    window: int,
    ready_cycle: int,
) -> list[EncodedToken]:
    return [
        _make_token("MASK4", tile, window, ready_cycle, 2, events, True, False)
    ]


def _bin2_tokens(
    events: list[Event],
    tile: tuple[int, int],
    window: int,
    ready_cycle: int,
    tile_size: int,
) -> list[EncodedToken]:
    return [
        _make_token("BIN2", tile, window, ready_cycle, 1, group, False, False)
        for group in _partition_2x2(events, tile, tile_size)
    ]


def _bin4_tokens(
    events: list[Event],
    tile: tuple[int, int],
    window: int,
    ready_cycle: int,
) -> list[EncodedToken]:
    return [
        _make_token("BIN4", tile, window, ready_cycle, 1, events, False, False)
    ]


def _word_cost(tokens: list[EncodedToken]) -> int:
    return sum(token.words for token in tokens)


class _CareSelector:
    def __init__(self, config: EncoderConfig):
        self.config = config
        self.previous_masks: dict[tuple[int, int], int] = {}
        self.last_exact_window: dict[tuple[int, int], int] = {}

    def mark_exact(self, tile: tuple[int, int], window: int) -> None:
        self.last_exact_window[tile] = window

    def _mask(self, events: list[Event], tile: tuple[int, int]) -> int:
        origin_x = tile[0] * self.config.tile_size
        origin_y = tile[1] * self.config.tile_size
        value = 0
        for event in events:
            rel_x = event.x - origin_x
            rel_y = event.y - origin_y
            value |= 1 << (rel_y * self.config.tile_size + rel_x)
        return value

    @staticmethod
    def _is_dominant(on_count: int, off_count: int, ratio: int) -> bool:
        total = on_count + off_count
        if total < 2:
            return False
        larger = max(on_count, off_count)
        smaller = min(on_count, off_count)
        return smaller == 0 or larger >= ratio * smaller

    def _exact_candidates(
        self,
        events: list[Event],
        tile: tuple[int, int],
        window: int,
        ready_cycle: int,
    ) -> list[list[EncodedToken]]:
        return [
            _raw_tokens(events, tile, window, ready_cycle),
            _mask2_tokens(
                events, tile, window, ready_cycle, self.config.tile_size
            ),
            _mask4_tokens(events, tile, window, ready_cycle),
        ]

    def select(
        self,
        events: list[Event],
        tile: tuple[int, int],
        window: int,
        ready_cycle: int,
        congestion: int,
    ) -> list[EncodedToken]:
        current_mask = self._mask(events, tile)
        previous_mask = self.previous_masks.get(tile)
        variation = (
            16
            if previous_mask is None
            else (current_mask ^ previous_mask).bit_count()
        )
        self.previous_masks[tile] = current_mask

        on_count = len({(event.x, event.y) for event in events if event.polarity})
        off_count = len(
            {(event.x, event.y) for event in events if not event.polarity}
        )
        density = current_mask.bit_count()
        dominant = self._is_dominant(
            on_count, off_count, self.config.dominant_ratio
        )
        stable = (
            previous_mask is not None
            and variation <= self.config.variation_threshold
        )
        last_exact = self.last_exact_window.get(tile)
        exact_age = (
            self.config.exact_age_limit
            if last_exact is None
            else window - last_exact
        )

        exact = min(self._exact_candidates(events, tile, window, ready_cycle), key=_word_cost)
        if exact_age >= self.config.exact_age_limit or congestion == 0:
            return exact

        if stable and dominant and density >= 2:
            if density >= self.config.bin4_density_threshold:
                summary = _bin4_tokens(events, tile, window, ready_cycle)
            else:
                summary = _bin2_tokens(
                    events, tile, window, ready_cycle, self.config.tile_size
                )
            if _word_cost(summary) < _word_cost(exact):
                return summary
        return exact


def _congestion_level(occupancy_words: int, capacity_words: int) -> int:
    if occupancy_words * 4 < capacity_words:
        return 0
    if occupancy_words * 2 < capacity_words:
        return 1
    if occupancy_words * 4 < capacity_words * 3:
        return 2
    return 3


def _encode_fixed(
    policy: str,
    events: list[Event],
    tile: tuple[int, int],
    window: int,
    ready_cycle: int,
    config: EncoderConfig,
) -> list[EncodedToken]:
    if policy == "raw":
        return _raw_tokens(events, tile, window, ready_cycle)
    if policy == "mask" and config.fixed_group_size == 2:
        return _mask2_tokens(events, tile, window, ready_cycle, config.tile_size)
    if policy == "mask":
        return _mask4_tokens(events, tile, window, ready_cycle)
    if policy == "bin" and config.fixed_group_size == 2:
        return _bin2_tokens(events, tile, window, ready_cycle, config.tile_size)
    if policy == "bin":
        return _bin4_tokens(events, tile, window, ready_cycle)
    raise ValueError(f"unsupported policy: {policy}")


def simulate_policy(
    events: Iterable[Event],
    policy: str,
    config: EncoderConfig,
) -> SimulationResult:
    """Encode a trace and simulate one word/cycle round-robin output link.

    This model is intended for architecture exploration. It models per-tile FIFO
    capacity and an atomic one- or two-word token grant, but it is not a
    cycle-exact replacement for the Verilog hierarchy.
    """

    if policy not in SUPPORTED_POLICIES:
        raise ValueError(f"policy must be one of {SUPPORTED_POLICIES}")
    trace = sorted(list(events), key=lambda event: (event.cycle, event.event_id))
    validate_unique_event_ids(trace)
    for event in trace:
        if event.x >= config.sensor_width or event.y >= config.sensor_height:
            raise ValueError(
                f"event ({event.x}, {event.y}) exceeds sensor dimensions"
            )
    if not trace:
        return SimulationResult(
            policy=policy,
            input_events=0,
            accepted_events=0,
            dropped_events=0,
            output_words=0,
            output_bits=0,
            mean_latency_cycles=0.0,
            p99_latency_cycles=0,
            loss_rate=0.0,
            bits_per_input_event=0.0,
            bits_per_accepted_event=0.0,
            events_per_cycle=0.0,
            position_preserved_events=0,
            position_preserved_fraction=0.0,
            intentionally_merged_events=0,
            max_tile_fifo_words=0,
        )

    tiles_x = math.ceil(config.sensor_width / config.tile_size)
    tiles_y = math.ceil(config.sensor_height / config.tile_size)
    tiles = [(x, y) for y in range(tiles_y) for x in range(tiles_x)]
    link = _RoundRobinLink(tiles, config.fifo_capacity_words)
    selector = _CareSelector(config)

    grouped: dict[tuple[int, tuple[int, int]], list[Event]] = defaultdict(list)
    for event in trace:
        window = event.cycle // config.window_cycles
        tile = (event.x // config.tile_size, event.y // config.tile_size)
        grouped[(window, tile)].append(event)

    accepted_ids: set[int] = set()
    position_ids: set[int] = set()
    output_words = 0
    intentionally_merged = 0
    token_counts: dict[str, int] = defaultdict(int)
    event_counts_by_token: dict[str, int] = defaultdict(int)

    current_window = -1
    for (window, tile), group in sorted(
        grouped.items(), key=lambda item: (item[0][0], item[0][1][1], item[0][1][0])
    ):
        ready_cycle = (window + 1) * config.window_cycles
        if window != current_window:
            link.advance(ready_cycle)
            current_window = window

        if policy == "care":
            congestion = _congestion_level(
                link.occupancy_words(tile), config.fifo_capacity_words
            )
            tokens = selector.select(
                group, tile, window, ready_cycle, congestion
            )
        else:
            tokens = _encode_fixed(
                policy, group, tile, window, ready_cycle, config
            )

        group_fully_accepted = True
        group_position_preserved = all(
            token.position_preserved for token in tokens
        )
        for token in tokens:
            if not link.enqueue(token):
                group_fully_accepted = False
                continue
            output_words += token.words
            token_counts[token.kind] += 1
            event_counts_by_token[token.kind] += len(token.events)
            accepted_ids.update(event.event_id for event in token.events)
            if token.position_preserved:
                position_ids.update(event.event_id for event in token.events)
            if token.kind.startswith(("MASK", "BIN")):
                unique_states = {
                    (event.x, event.y, event.polarity) for event in token.events
                }
                intentionally_merged += len(token.events) - len(unique_states)

        if (
            policy == "care"
            and group_fully_accepted
            and group_position_preserved
        ):
            selector.mark_exact(tile, window)

    link.drain_all()
    latency_by_id: dict[int, int] = {}
    for token, finish_cycle in link.completed:
        for event in token.events:
            latency_by_id[event.event_id] = finish_cycle - event.cycle + 1

    latencies = sorted(latency_by_id.values())
    accepted = len(accepted_ids)
    dropped = len(trace) - accepted
    p99_index = max(0, math.ceil(0.99 * len(latencies)) - 1)
    p99_latency = latencies[p99_index] if latencies else 0
    first_cycle = min(event.cycle for event in trace)
    last_finish = max(
        (finish for _token, finish in link.completed),
        default=first_cycle,
    )
    elapsed_cycles = max(1, last_finish - first_cycle + 1)

    return SimulationResult(
        policy=policy,
        input_events=len(trace),
        accepted_events=accepted,
        dropped_events=dropped,
        output_words=output_words,
        output_bits=output_words * config.word_bits,
        mean_latency_cycles=(
            sum(latencies) / len(latencies) if latencies else 0.0
        ),
        p99_latency_cycles=p99_latency,
        loss_rate=dropped / len(trace),
        bits_per_input_event=(output_words * config.word_bits) / len(trace),
        bits_per_accepted_event=(
            (output_words * config.word_bits) / accepted if accepted else 0.0
        ),
        events_per_cycle=accepted / elapsed_cycles,
        position_preserved_events=len(position_ids),
        position_preserved_fraction=len(position_ids) / len(trace),
        intentionally_merged_events=intentionally_merged,
        max_tile_fifo_words=max(link.max_occupancy.values(), default=0),
        token_counts=dict(sorted(token_counts.items())),
        event_counts_by_token=dict(sorted(event_counts_by_token.items())),
    )
