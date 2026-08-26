"""Python architecture model for lossless and lossy 2x2 AER binning.

This is intentionally separate from the RTL.  It explores whether mapping both
3-of-4 and 4-of-4 same-polarity tile snapshots to the same one-bit BIN token can
reduce overload loss enough to offset the false event introduced by 3-of-4.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter, deque
from dataclasses import asdict, dataclass, field
from decimal import Decimal
from pathlib import Path

from sw.export_v1_aedat2_vectors import convert_records, load_aedat2_records
from sw.export_v1_uzh_vectors import SourceEvent


POLICIES = ("raw", "raw_bank", "lossless", "lossy")


@dataclass(frozen=True, slots=True)
class ModelConfig:
    sensor_width: int = 128
    sensor_height: int = 128
    tile_size: int = 2
    bank_tiles_x: int = 4
    bank_tiles_y: int = 4
    pixel_fifo_depth: int = 2
    link_word_bits: int = 16

    def __post_init__(self) -> None:
        if self.sensor_width <= 0 or self.sensor_height <= 0:
            raise ValueError("sensor dimensions must be positive")
        if self.tile_size != 2:
            raise ValueError("the lossy-binning model requires 2x2 tiles")
        if self.sensor_width % self.tile_size or self.sensor_height % self.tile_size:
            raise ValueError("sensor dimensions must be multiples of the tile size")
        if self.pixel_fifo_depth <= 0:
            raise ValueError("pixel_fifo_depth must be positive")
        if self.link_word_bits != 16:
            raise ValueError("the current packet-cost model assumes a 16-bit link")


@dataclass(frozen=True, slots=True)
class _PendingEvent:
    cycle: int
    polarity: int


@dataclass(frozen=True, slots=True)
class _TileView:
    tile: int
    on_bitmap: int
    off_bitmap: int
    source_events: int
    format: str
    bits_per_token: int
    false_positive_events: int


@dataclass(slots=True)
class ModelResult:
    policy: str
    clock_hz: int
    input_events: int
    accepted_events: int
    dropped_events: int
    drop_rate: float
    false_positive_events: int
    false_positive_rate: float
    total_event_errors: int
    total_error_rate: float
    precision: float
    recall: float
    f1: float
    output_words: int
    words_per_accepted_event: float
    link_payload_capacity_geps: float
    mean_latency_cycles: float
    p99_latency_cycles: int
    max_latency_cycles: int
    packets: int
    bank_fused_packets: int
    bank_fused_tiles: int
    token_counts: dict[str, int] = field(default_factory=dict)
    packet_mode_counts: dict[str, int] = field(default_factory=dict)

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


def classify_tile(
    on_bitmap: int,
    off_bitmap: int,
    policy: str,
) -> tuple[str, int, int]:
    """Return format, payload bits per tile, and introduced false events."""

    if policy not in POLICIES:
        raise ValueError(f"policy must be one of {POLICIES}")
    if not 0 <= on_bitmap <= 0xF or not 0 <= off_bitmap <= 0xF:
        raise ValueError("tile bitmaps must be four bits")

    if policy in {"raw", "raw_bank"}:
        return "RAW8", 8, 0

    conflict = bool(on_bitmap & off_bitmap)
    on_count = on_bitmap.bit_count()
    off_count = off_bitmap.bit_count()
    one_polarity = not conflict and (on_count == 0 or off_count == 0)
    active_count = on_count + off_count

    if one_polarity and active_count == 4:
        return "BIN", 1, 0
    if one_polarity and active_count == 3:
        if policy == "lossy":
            # The absent pixel is reconstructed as an event with the dominant
            # polarity.  It therefore shares the exact same wire token as BIN4.
            return "BIN", 1, 1
        return "GROUP3", 3, 0
    return "RAW8", 8, 0


def encode_lossy_bank_snapshot(
    tiles: list[tuple[int, int, int]],
    *,
    bank_id: int = 0,
    link_word_bits: int = 16,
) -> list[tuple[int, int]]:
    """Encode one 4x4-tile bank snapshot using the RTL lossy policy.

    Each input tuple is ``(local_tile, on_bitmap, off_bitmap)``.  The return
    value contains ``(word, last)`` pairs and is intentionally small enough to
    serve as an independent packet-level golden model for XSim tests.
    """

    if link_word_bits != 16:
        raise ValueError("the RTL packet reference currently requires 16-bit words")
    if not 0 <= bank_id <= 0xFF:
        raise ValueError("bank_id must fit the compact eight-bit bank header")
    if not tiles:
        return []
    ordered = sorted(tiles)
    if len({tile for tile, _, _ in ordered}) != len(ordered):
        raise ValueError("local tile indices must be unique")
    if any(not 0 <= tile < 16 for tile, _, _ in ordered):
        raise ValueError("local tile index must be in [0, 15]")

    active_mask = sum(1 << tile for tile, _, _ in ordered)
    active_rows = len({tile // 4 for tile, _, _ in ordered})
    row_words = len(ordered) + active_rows
    raw_bank_words = 2 + math.ceil(8 * len(ordered) / link_word_bits)
    classified = [
        (tile, on_bitmap, off_bitmap, classify_tile(on_bitmap, off_bitmap, "lossy"))
        for tile, on_bitmap, off_bitmap in ordered
    ]
    mixed_payload_bits = sum(item[3][1] for item in classified)
    mixed_words = 3 + math.ceil(mixed_payload_bits / link_word_bits)

    def payload_words(value: int, bit_count: int) -> list[int]:
        return [
            (value >> offset) & 0xFFFF
            for offset in range(0, bit_count, link_word_bits)
        ]

    if len(ordered) > 1 and mixed_words < raw_bank_words and mixed_words < row_words:
        bin_mask = 0
        payload = 0
        bit_index = 0
        for tile, on_bitmap, off_bitmap, (packet_format, width, _) in classified:
            if packet_format == "BIN":
                bin_mask |= 1 << tile
                polarity = 1 if on_bitmap else 0
                payload |= polarity << bit_index
            else:
                payload |= ((on_bitmap << 4) | off_bitmap) << bit_index
            bit_index += width
        words = [
            (0b10 << 14) | (bank_id << 6) | (0b11 << 4) | (len(ordered) - 1),
            active_mask,
            bin_mask,
            *payload_words(payload, bit_index),
        ]
        return [(word, int(index == len(words) - 1)) for index, word in enumerate(words)]

    if len(ordered) > 1 and raw_bank_words < row_words:
        payload = 0
        bit_index = 0
        for _, on_bitmap, off_bitmap in ordered:
            payload |= ((on_bitmap << 4) | off_bitmap) << bit_index
            bit_index += 8
        words = [
            (0b10 << 14) | (bank_id << 6) | (len(ordered) - 1),
            active_mask,
            *payload_words(payload, bit_index),
        ]
        return [(word, int(index == len(words) - 1)) for index, word in enumerate(words)]

    result: list[tuple[int, int]] = []
    for row in sorted({tile // 4 for tile, _, _ in ordered}):
        row_tiles = [item for item in ordered if item[0] // 4 == row]
        columns = sum(1 << (tile % 4) for tile, _, _ in row_tiles)
        result.append(((0b11 << 14) | (bank_id << 6) | (row << 4) | columns, 0))
        for index, (_, on_bitmap, off_bitmap) in enumerate(row_tiles):
            word = ((on_bitmap << 4) | off_bitmap) << 2
            result.append((word, int(index == len(row_tiles) - 1)))
    return result


def _percentile(values: list[int], fraction: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    index = min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1)
    return ordered[max(0, index)]


def simulate(
    events: list[SourceEvent],
    policy: str,
    config: ModelConfig,
    clock_hz: int,
) -> ModelResult:
    """Simulate pixel FIFOs, bank selection, packet packing, and one-word link.

    A packet is formed only from events already pending when the link becomes
    idle.  Within the selected bank, tiles with the anchor tile's format may be
    fused.  Fusion is used only when its exact word cost is lower than sending
    those tiles as individual two-word row packets.
    """

    if policy not in POLICIES:
        raise ValueError(f"policy must be one of {POLICIES}")
    if clock_hz <= 0:
        raise ValueError("clock_hz must be positive")
    if not events:
        return ModelResult(
            policy=policy,
            clock_hz=clock_hz,
            input_events=0,
            accepted_events=0,
            dropped_events=0,
            drop_rate=0.0,
            false_positive_events=0,
            false_positive_rate=0.0,
            total_event_errors=0,
            total_error_rate=0.0,
            precision=1.0,
            recall=1.0,
            f1=1.0,
            output_words=0,
            words_per_accepted_event=0.0,
            link_payload_capacity_geps=0.0,
            mean_latency_cycles=0.0,
            p99_latency_cycles=0,
            max_latency_cycles=0,
            packets=0,
            bank_fused_packets=0,
            bank_fused_tiles=0,
            packet_mode_counts={},
        )

    trace = sorted(events, key=lambda event: (event.cycle, event.y, event.x))
    tiles_x = config.sensor_width // config.tile_size
    tiles_y = config.sensor_height // config.tile_size
    banks_x = math.ceil(tiles_x / config.bank_tiles_x)
    banks_y = math.ceil(tiles_y / config.bank_tiles_y)
    bank_count = banks_x * banks_y
    pixel_count = config.sensor_width * config.sensor_height

    pixel_queues: list[deque[_PendingEvent]] = [deque() for _ in range(pixel_count)]
    active_by_bank: list[set[int]] = [set() for _ in range(bank_count)]
    bank_rr = 0
    tile_rr = [0] * bank_count

    def pixel_index(x: int, y: int) -> int:
        return y * config.sensor_width + x

    def tile_id(x: int, y: int) -> int:
        return (y // 2) * tiles_x + (x // 2)

    def bank_id_for_tile(tile: int) -> int:
        tile_y, tile_x = divmod(tile, tiles_x)
        return (tile_y // config.bank_tiles_y) * banks_x + (
            tile_x // config.bank_tiles_x
        )

    def local_tile_for_tile(tile: int) -> int:
        tile_y, tile_x = divmod(tile, tiles_x)
        return (tile_y % config.bank_tiles_y) * config.bank_tiles_x + (
            tile_x % config.bank_tiles_x
        )

    def view_tile(tile: int) -> _TileView:
        tile_y, tile_x = divmod(tile, tiles_x)
        origin_x = tile_x * 2
        origin_y = tile_y * 2
        on_bitmap = 0
        off_bitmap = 0
        source_events = 0
        for bit in range(4):
            x = origin_x + (bit & 1)
            y = origin_y + ((bit >> 1) & 1)
            queue = pixel_queues[pixel_index(x, y)]
            if not queue:
                continue
            source_events += 1
            if queue[0].polarity:
                on_bitmap |= 1 << bit
            else:
                off_bitmap |= 1 << bit
        packet_format, bits_per_token, false_events = classify_tile(
            on_bitmap, off_bitmap, policy
        )
        return _TileView(
            tile=tile,
            on_bitmap=on_bitmap,
            off_bitmap=off_bitmap,
            source_events=source_events,
            format=packet_format,
            bits_per_token=bits_per_token,
            false_positive_events=false_events,
        )

    def select_bank() -> int | None:
        nonlocal bank_rr
        for offset in range(bank_count):
            candidate = (bank_rr + offset) % bank_count
            if active_by_bank[candidate]:
                bank_rr = (candidate + 1) % bank_count
                return candidate
        return None

    def ordered_tiles(bank: int) -> list[int]:
        active = active_by_bank[bank]
        start = tile_rr[bank]
        return sorted(
            active,
            key=lambda tile: (
                local_tile_for_tile(tile) - start
            ) % (config.bank_tiles_x * config.bank_tiles_y),
        )

    event_index = 0
    cycle = trace[0].cycle
    busy_until = cycle
    dropped = 0
    transmitted = 0
    false_positive = 0
    output_words = 0
    packets = 0
    bank_fused_packets = 0
    bank_fused_tiles = 0
    latencies: list[int] = []
    token_counts: Counter[str] = Counter()
    packet_mode_counts: Counter[str] = Counter()

    while event_index < len(trace) or any(active_by_bank):
        next_input_cycle = trace[event_index].cycle if event_index < len(trace) else None

        if cycle < busy_until:
            if next_input_cycle is None:
                cycle = busy_until
            else:
                cycle = min(busy_until, max(cycle + 1, next_input_cycle))

        while event_index < len(trace) and trace[event_index].cycle <= cycle:
            event = trace[event_index]
            if not (0 <= event.x < config.sensor_width and 0 <= event.y < config.sensor_height):
                raise ValueError(f"event outside sensor: ({event.x}, {event.y})")
            queue = pixel_queues[pixel_index(event.x, event.y)]
            if len(queue) >= config.pixel_fifo_depth:
                dropped += 1
            else:
                queue.append(_PendingEvent(event.cycle, event.polarity))
                tile = tile_id(event.x, event.y)
                active_by_bank[bank_id_for_tile(tile)].add(tile)
            event_index += 1

        if cycle < busy_until:
            continue

        bank = select_bank()
        if bank is None:
            if next_input_cycle is None:
                break
            cycle = max(cycle + 1, next_input_cycle)
            continue

        candidates_in_order = ordered_tiles(bank)
        views = [view_tile(tile) for tile in candidates_in_order]
        anchor_view = views[0]

        # The conventional baseline reads one non-empty row at a time: one
        # header plus one RAW8 DATA word per active tile in that row.
        anchor_local_row = (
            local_tile_for_tile(anchor_view.tile) // config.bank_tiles_x
        )
        selected = [
            view
            for view in views
            if local_tile_for_tile(view.tile) // config.bank_tiles_x
            == anchor_local_row
        ]
        words = 1 + len(selected)
        packet_mode = "ROW_RAW"
        use_adaptive_formats = False
        active_rows = {
            local_tile_for_tile(view.tile) // config.bank_tiles_x for view in views
        }
        row_words_for_all = len(views) + len(active_rows)
        raw_bank_words = 2 + math.ceil(8 * len(views) / config.link_word_bits)
        allow_bank_raw = policy in {"raw_bank", "lossless", "lossy"}
        if allow_bank_raw and len(views) > 1 and raw_bank_words < row_words_for_all:
            selected = views
            words = raw_bank_words
            packet_mode = "BANK_RAW"

        # A mixed lossless packet uses an active-tile mask plus separate
        # GROUP3 and BIN masks.  A mixed lossy packet needs only one BIN mask
        # because 3-of-4 and 4-of-4 share the same one-bit token.  The encoder
        # selects either form only when it is strictly cheaper than RAW, so an
        # approximation is never introduced without a link-word benefit.
        if policy == "lossless":
            adaptive_words = 4 + math.ceil(
                sum(view.bits_per_token for view in views) / config.link_word_bits
            )
            adaptive_mode = "BANK_MIXED_LOSSLESS"
        elif policy == "lossy":
            adaptive_words = 3 + math.ceil(
                sum(view.bits_per_token for view in views) / config.link_word_bits
            )
            adaptive_mode = "BANK_MIXED_LOSSY"
        else:
            adaptive_words = math.inf
            adaptive_mode = ""

        if len(views) > 1 and adaptive_words < min(words, row_words_for_all):
            selected = views
            words = int(adaptive_words)
            packet_mode = adaptive_mode
            use_adaptive_formats = True

        if len(selected) > 1:
            bank_fused_packets += 1
            bank_fused_tiles += len(selected)

        finish_cycle = cycle + words - 1
        for view in selected:
            tile_y, tile_x = divmod(view.tile, tiles_x)
            origin_x = tile_x * 2
            origin_y = tile_y * 2
            popped = 0
            for bit in range(4):
                x = origin_x + (bit & 1)
                y = origin_y + ((bit >> 1) & 1)
                queue = pixel_queues[pixel_index(x, y)]
                if not queue:
                    continue
                pending = queue.popleft()
                popped += 1
                latencies.append(finish_cycle - pending.cycle + 1)
            if popped != view.source_events:
                raise AssertionError("tile snapshot changed before packet capture")
            transmitted += popped
            if use_adaptive_formats:
                false_positive += view.false_positive_events
                token_counts[view.format] += 1
            else:
                token_counts["RAW8"] += 1
            if all(
                not pixel_queues[pixel_index(origin_x + (bit & 1), origin_y + ((bit >> 1) & 1))]
                for bit in range(4)
            ):
                active_by_bank[bank].discard(view.tile)

        tile_rr[bank] = (
            local_tile_for_tile(selected[-1].tile) + 1
        ) % (config.bank_tiles_x * config.bank_tiles_y)
        output_words += words
        packets += 1
        packet_mode_counts[packet_mode] += 1
        busy_until = cycle + words

        if event_index >= len(trace) and any(active_by_bank):
            cycle = busy_until

    accepted = len(trace) - dropped
    if transmitted != accepted:
        raise AssertionError(
            f"transmitted {transmitted} events but accepted {accepted}"
        )
    total_errors = dropped + false_positive
    reconstructed = accepted + false_positive
    precision = accepted / reconstructed if reconstructed else 1.0
    recall = accepted / len(trace)
    f1 = (
        2 * precision * recall / (precision + recall)
        if precision + recall
        else 0.0
    )
    return ModelResult(
        policy=policy,
        clock_hz=clock_hz,
        input_events=len(trace),
        accepted_events=accepted,
        dropped_events=dropped,
        drop_rate=dropped / len(trace),
        false_positive_events=false_positive,
        false_positive_rate=false_positive / len(trace),
        total_event_errors=total_errors,
        total_error_rate=total_errors / len(trace),
        precision=precision,
        recall=recall,
        f1=f1,
        output_words=output_words,
        words_per_accepted_event=output_words / accepted if accepted else 0.0,
        link_payload_capacity_geps=(
            accepted / output_words * clock_hz / 1_000_000_000
            if output_words
            else 0.0
        ),
        mean_latency_cycles=sum(latencies) / len(latencies) if latencies else 0.0,
        p99_latency_cycles=_percentile(latencies, 0.99),
        max_latency_cycles=max(latencies, default=0),
        packets=packets,
        bank_fused_packets=bank_fused_packets,
        bank_fused_tiles=bank_fused_tiles,
        token_counts=dict(sorted(token_counts.items())),
        packet_mode_counts=dict(sorted(packet_mode_counts.items())),
    )


def compare_cifar10_dvs(
    dataset: Path,
    clock_rates: list[int],
    playback_speed: Decimal,
    max_events: int,
    config: ModelConfig,
) -> dict[str, object]:
    records = load_aedat2_records(dataset)
    cases: dict[str, object] = {}
    for clock_hz in clock_rates:
        events, _start_us, selection = convert_records(
            records,
            max_events=max_events,
            clock_hz=Decimal(clock_hz),
            playback_speed=playback_speed,
            densest_window_ms=None,
            start_event=0,
        )
        results = [simulate(events, policy, config, clock_hz) for policy in POLICIES]
        raw = results[0]
        raw_bank = results[1]
        cases[str(clock_hz)] = {
            "selection": selection,
            "results": [result.as_dict() for result in results],
            "lossy_vs_raw": {
                "drop_rate_reduction_percentage_points": 100
                * (raw.drop_rate - results[3].drop_rate),
                "total_error_rate_reduction_percentage_points": 100
                * (raw.total_error_rate - results[3].total_error_rate),
                "accepted_event_increase_percent": 100
                * (results[3].accepted_events - raw.accepted_events)
                / max(1, raw.accepted_events),
                "link_payload_capacity_increase_percent": 100
                * (
                    results[3].link_payload_capacity_geps
                    - raw.link_payload_capacity_geps
                )
                / max(1e-12, raw.link_payload_capacity_geps),
            },
            "lossy_vs_raw_bank": {
                "drop_rate_reduction_percentage_points": 100
                * (raw_bank.drop_rate - results[3].drop_rate),
                "total_error_rate_reduction_percentage_points": 100
                * (raw_bank.total_error_rate - results[3].total_error_rate),
                "accepted_event_increase_percent": 100
                * (results[3].accepted_events - raw_bank.accepted_events)
                / max(1, raw_bank.accepted_events),
                "link_payload_capacity_increase_percent": 100
                * (
                    results[3].link_payload_capacity_geps
                    - raw_bank.link_payload_capacity_geps
                )
                / max(1e-12, raw_bank.link_payload_capacity_geps),
            },
        }
    return {
        "model": "Python architecture exploration; not cycle-exact RTL",
        "dataset": str(dataset.resolve()),
        "playback_speed": str(playback_speed),
        "peak_definition": "same 1297.016861x replay used for the 1 ms peak = 1 GEPS study",
        "config": asdict(config),
        "cases": cases,
    }


def _print_results(report: dict[str, object]) -> None:
    cases = report["cases"]
    assert isinstance(cases, dict)
    for clock_text, case in cases.items():
        assert isinstance(case, dict)
        print(f"\n[{int(clock_text) / 1_000_000:g} MHz]")
        print(
            "policy     accepted  drop%   false%  total_error%  words/event  "
            "capacity(GEPS)"
        )
        for result in case["results"]:
            print(
                f"{result['policy']:<10} {result['accepted_events']:>8}  "
                f"{100 * result['drop_rate']:>6.2f}  "
                f"{100 * result['false_positive_rate']:>6.2f}  "
                f"{100 * result['total_error_rate']:>11.2f}  "
                f"{result['words_per_accepted_event']:>11.4f}  "
                f"{result['link_payload_capacity_geps']:>14.4f}"
            )
        delta = case["lossy_vs_raw"]
        print(
            "lossy-vs-raw: "
            f"drop {delta['drop_rate_reduction_percentage_points']:+.3f}%p, "
            f"total error {delta['total_error_rate_reduction_percentage_points']:+.3f}%p, "
            f"accepted {delta['accepted_event_increase_percent']:+.2f}%, "
            f"capacity {delta['link_payload_capacity_increase_percent']:+.2f}%"
        )
        bank_delta = case["lossy_vs_raw_bank"]
        print(
            "lossy-vs-raw-bank: "
            f"drop {bank_delta['drop_rate_reduction_percentage_points']:+.3f}%p, "
            f"total error {bank_delta['total_error_rate_reduction_percentage_points']:+.3f}%p, "
            f"accepted {bank_delta['accepted_event_increase_percent']:+.2f}%, "
            f"capacity {bank_delta['link_payload_capacity_increase_percent']:+.2f}%"
        )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path("data/cifar10_dvs/sample/cifar10_airplane_0.aedat"),
    )
    parser.add_argument("--clock-hz", type=int, nargs="+", default=[100_000_000, 200_000_000])
    parser.add_argument("--playback-speed", default="1297.016861")
    parser.add_argument("--max-events", type=int, default=178_165)
    parser.add_argument("--pixel-fifo-depth", type=int, default=2)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("results/lossy_binning_sw/summary.json"),
    )
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = ModelConfig(pixel_fifo_depth=args.pixel_fifo_depth)
    report = compare_cifar10_dvs(
        args.dataset,
        args.clock_hz,
        Decimal(args.playback_speed),
        args.max_events,
        config,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    _print_results(report)
    print(f"\nwrote {args.output}")


if __name__ == "__main__":
    main()
