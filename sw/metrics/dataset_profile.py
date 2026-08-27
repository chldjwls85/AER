"""Dataset-independent transaction profiling and lossless encoding word costs."""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Callable, Iterable

from sw.dataset.canonical_trace import TileTransaction
from sw.metrics.architecture_models import (
    CURRENT_MAX_DELTA,
    FAIR_RAW_MAX_DELTA,
    bank_word_cost,
    row_only_word_cost,
    sparse_row_word_cost,
)


POLICIES = ("FAIR_RAW", "SPARSE_FALLBACK", "SPARSE_ROW", "SPARSE_ROW_BANK")


def _distribution(values: Iterable[int]) -> dict[str, int]:
    return {str(value): count for value, count in sorted(Counter(values).items())}


def _validate_transactions(transactions: list[TileTransaction]) -> None:
    for transaction in transactions:
        if transaction.cycle < 0 or not 0 <= transaction.tile_id < 4096:
            raise ValueError(f"invalid cycle/tile: {transaction}")
        if not 0 <= transaction.on <= 0xF or not 0 <= transaction.off <= 0xF:
            raise ValueError(f"bitmap is not four bits: {transaction}")
        if transaction.canonical_event_count == 0:
            raise ValueError(f"empty transaction: {transaction}")
        if transaction.source_event_count < transaction.canonical_event_count:
            raise ValueError(f"source count is smaller than bitmap popcount: {transaction}")


def _locality(
    transactions: list[TileTransaction],
    bucket: Callable[[int], int],
) -> dict[str, Any]:
    row_tiles: dict[tuple[int, int, int], set[int]] = defaultdict(set)
    bank_tiles: dict[tuple[int, int], set[int]] = defaultdict(set)
    bank_rows: dict[tuple[int, int], set[int]] = defaultdict(set)
    for transaction in transactions:
        group = bucket(transaction.cycle)
        bank = transaction.tile_id // 16
        row = (transaction.tile_id % 16) // 4
        row_tiles[(group, bank, row)].add(transaction.tile_id)
        bank_tiles[(group, bank)].add(transaction.tile_id)
        bank_rows[(group, bank)].add(row)

    def summarize(groups: Iterable[set[int]]) -> dict[str, Any]:
        counts = [len(group) for group in groups]
        multi_count = sum(count > 1 for count in counts)
        return {
            "active_group_count": len(counts),
            "distribution": _distribution(counts),
            "multi_active_group_count": multi_count,
            "multi_active_group_ratio": multi_count / len(counts) if counts else 0.0,
        }

    return {
        "active_tiles_per_row": summarize(row_tiles.values()),
        "active_tiles_per_bank": summarize(bank_tiles.values()),
        "active_rows_per_bank": summarize(bank_rows.values()),
    }


def profile_transactions(
    transactions: Iterable[TileTransaction],
    *,
    source_event_count: int | None = None,
    window_cycles: int = 1,
) -> dict[str, Any]:
    """Compute workload statistics without an architecture acceptance model."""

    records = sorted(transactions, key=lambda item: (item.cycle, item.tile_id))
    _validate_transactions(records)
    if window_cycles <= 0:
        raise ValueError("window_cycles must be positive")

    bitmap_counts = [record.canonical_event_count for record in records]
    inferred_source_count = sum(record.source_event_count for record in records)
    source_count = inferred_source_count if source_event_count is None else source_event_count
    if source_count < inferred_source_count:
        raise ValueError("source_event_count is smaller than transaction source counts")

    singleton_count = sum(count == 1 for count in bitmap_counts)
    multi_bit_count = len(records) - singleton_count
    on_only = sum(bool(record.on) and not record.off for record in records)
    off_only = sum(bool(record.off) and not record.on for record in records)
    mixed = sum(bool(record.on) and bool(record.off) for record in records)
    conflicts = sum(bool(record.on & record.off) for record in records)

    return {
        "source_event_count": source_count,
        "canonical_polarity_bits": sum(bitmap_counts),
        "tile_transaction_count": len(records),
        "source_events_per_transaction_distribution": _distribution(
            record.source_event_count for record in records
        ),
        "bitmap_popcount_per_transaction_distribution": _distribution(bitmap_counts),
        "singleton_transaction_count": singleton_count,
        "singleton_ratio": singleton_count / len(records) if records else 0.0,
        "multi_bit_transaction_count": multi_bit_count,
        "multi_bit_ratio": multi_bit_count / len(records) if records else 0.0,
        "on_only_transaction_count": on_only,
        "off_only_transaction_count": off_only,
        "mixed_transaction_count": mixed,
        "same_pixel_on_off_conflict_transaction_count": conflicts,
        "same_cycle_locality": _locality(records, lambda cycle: cycle),
        "window_cycles": window_cycles,
        "window_locality": _locality(records, lambda cycle: cycle // window_cycles),
    }


def _greedy_packets(
    transactions: Iterable[TileTransaction],
    *,
    key: Callable[[TileTransaction], tuple[int, ...]],
    max_delta: int,
) -> list[list[TileTransaction]]:
    """Pack one transaction/tile into earliest-timestamp lossless snapshots."""

    if max_delta < 0:
        raise ValueError("max_delta must be non-negative")
    grouped: dict[tuple[int, ...], list[TileTransaction]] = defaultdict(list)
    for transaction in transactions:
        grouped[key(transaction)].append(transaction)

    packets: list[list[TileTransaction]] = []
    for group_key in sorted(grouped):
        remaining = sorted(grouped[group_key], key=lambda item: (item.cycle, item.tile_id))
        while remaining:
            base_cycle = remaining[0].cycle
            used_tiles: set[int] = set()
            packet: list[TileTransaction] = []
            deferred: list[TileTransaction] = []
            for transaction in remaining:
                if (
                    transaction.cycle - base_cycle <= max_delta
                    and transaction.tile_id not in used_tiles
                ):
                    packet.append(transaction)
                    used_tiles.add(transaction.tile_id)
                else:
                    deferred.append(transaction)
            packets.append(packet)
            remaining = deferred
    return packets


def _row_choice(packet: list[TileTransaction]) -> tuple[int, Counter[str]]:
    sparse_count = sum(record.canonical_event_count == 1 for record in packet)
    nonsparse_count = len(packet) - sparse_count
    row_cost = row_only_word_cost(len(packet))
    hybrid_cost = sparse_row_word_cost(sparse_count, nonsparse_count)
    if hybrid_cost <= row_cost:
        modes: Counter[str] = Counter({"SPARSE": sparse_count})
        if nonsparse_count:
            modes["ROW"] += 1
        return hybrid_cost, modes
    return row_cost, Counter({"ROW": 1})


def _policy_result(
    total_words: int,
    transaction_count: int,
    modes: Counter[str],
) -> dict[str, Any]:
    return {
        "total_words": total_words,
        "words_per_transaction": (
            total_words / transaction_count if transaction_count else 0.0
        ),
        "reduction_vs_raw": 0.0,
        "mode_counts": dict(sorted((mode, count) for mode, count in modes.items() if count)),
        "encoded_transactions": transaction_count,
        "dropped_transactions": 0,
    }


def compare_encoding_costs(
    transactions: Iterable[TileTransaction],
    *,
    max_delta: int = CURRENT_MAX_DELTA,
    fair_raw_max_delta: int = FAIR_RAW_MAX_DELTA,
) -> dict[str, dict[str, Any]]:
    """Compare four lossless policies on one identical canonical input set."""

    records = sorted(transactions, key=lambda item: (item.cycle, item.tile_id))
    _validate_transactions(records)

    raw_packets = _greedy_packets(
        records,
        key=lambda item: (item.tile_id // 16, (item.tile_id % 16) // 4),
        max_delta=fair_raw_max_delta,
    )
    raw_words = sum(row_only_word_cost(len(packet)) for packet in raw_packets)
    results = {
        "FAIR_RAW": _policy_result(
            raw_words,
            len(records),
            Counter({"ROW_RAW8": len(raw_packets)}),
        )
    }

    fallback_modes: Counter[str] = Counter()
    fallback_words = 0
    for record in records:
        if record.canonical_event_count == 1:
            fallback_words += 2
            fallback_modes["SPARSE"] += 1
        else:
            fallback_words += row_only_word_cost(1)
            fallback_modes["ROW_FALLBACK"] += 1
    results["SPARSE_FALLBACK"] = _policy_result(
        fallback_words,
        len(records),
        fallback_modes,
    )

    row_packets = _greedy_packets(
        records,
        key=lambda item: (item.tile_id // 16, (item.tile_id % 16) // 4),
        max_delta=max_delta,
    )
    row_modes: Counter[str] = Counter()
    row_words = 0
    for packet in row_packets:
        cost, modes = _row_choice(packet)
        row_words += cost
        row_modes.update(modes)
    results["SPARSE_ROW"] = _policy_result(row_words, len(records), row_modes)

    bank_packets = _greedy_packets(
        records,
        key=lambda item: (item.tile_id // 16,),
        max_delta=max_delta,
    )
    bank_modes: Counter[str] = Counter()
    bank_words = 0
    for packet in bank_packets:
        rows: dict[int, list[TileTransaction]] = defaultdict(list)
        for record in packet:
            rows[(record.tile_id % 16) // 4].append(record)
        row_choices = [_row_choice(row_packet) for row_packet in rows.values()]
        nonbank_cost = sum(cost for cost, _ in row_choices)
        candidate_bank_cost = bank_word_cost(len(packet))
        if len(rows) >= 2 and candidate_bank_cost < nonbank_cost:
            bank_words += candidate_bank_cost
            bank_modes["BANK"] += 1
        else:
            bank_words += nonbank_cost
            for _, modes in row_choices:
                bank_modes.update(modes)
    results["SPARSE_ROW_BANK"] = _policy_result(
        bank_words,
        len(records),
        bank_modes,
    )

    for result in results.values():
        result["reduction_vs_raw"] = (
            (raw_words - result["total_words"]) / raw_words if raw_words else 0.0
        )
    return results


def build_profile_report(
    transactions: Iterable[TileTransaction],
    *,
    source_event_count: int | None = None,
    provenance: dict[str, Any] | None = None,
    window_cycles: int = 1,
    max_delta: int = CURRENT_MAX_DELTA,
) -> dict[str, Any]:
    """Return a JSON-friendly profile and encoding comparison."""

    records = list(transactions)
    return {
        "provenance": {
            **(provenance or {}),
            "window_cycles": window_cycles,
            "max_delta": max_delta,
            "fair_raw_max_delta": FAIR_RAW_MAX_DELTA,
            "cost_model": "lossless greedy timestamp-window snapshots; no queue/backpressure",
        },
        "dataset_profile": profile_transactions(
            records,
            source_event_count=source_event_count,
            window_cycles=window_cycles,
        ),
        "encoding_comparison": compare_encoding_costs(records, max_delta=max_delta),
    }


def format_profile_summary(report: dict[str, Any]) -> str:
    """Format the key profile and encoding results for console review."""

    profile = report["dataset_profile"]
    lines = [
        (
            f"transactions={profile['tile_transaction_count']} "
            f"singleton_ratio={profile['singleton_ratio']:.4f} "
            f"multi_bit_ratio={profile['multi_bit_ratio']:.4f}"
        )
    ]
    for policy in POLICIES:
        result = report["encoding_comparison"][policy]
        lines.append(
            f"{policy}: words={result['total_words']} "
            f"wpt={result['words_per_transaction']:.4f} "
            f"reduction={result['reduction_vs_raw']:.2%} "
            f"modes={result['mode_counts']}"
        )
    return "\n".join(lines)


def write_profile_json(path: Path, report: dict[str, Any]) -> None:
    """Write a profile report without changing its JSON-friendly structure."""

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
