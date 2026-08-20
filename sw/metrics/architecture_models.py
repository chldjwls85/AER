"""Common-link cycle model for RAW, team BIN/GROUP, and ROW/BANK designs."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from sw.dataset.canonical_trace import TileTransaction


DESIGNS = ("raw_baseline", "team_second", "current_adaptive")


@dataclass
class PendingRecord:
    transaction: TileTransaction
    accepted_cycle: int
    timestamp: int


@dataclass
class PacketWord:
    release_tiles: tuple[int, ...] = ()


@dataclass
class Packet:
    bank_id: int
    mode: str
    words: list[PacketWord]
    index: int = 0


def _team_format(on: int, off: int, enabled: bool) -> str:
    if not enabled:
        return "RAW8"
    conflict = bool(on & off)
    if not conflict and ((on == 0xF and off == 0) or (off == 0xF and on == 0)):
        return "BIN4"
    group_values = {0x7, 0xB, 0xD, 0xE}
    if not conflict and ((on in group_values and off == 0) or (off in group_values and on == 0)):
        return "GROUP3"
    return "RAW8"


def _percentile99(values: list[int]) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, math.ceil(0.99 * len(ordered)) - 1)]


class ArchitectureModel:
    def __init__(self, design: str) -> None:
        if design not in DESIGNS:
            raise ValueError(design)
        self.design = design
        self.pending: list[PendingRecord | None] = [None] * 4096
        self.pending_count = 0
        self.pending_banks: set[int] = set()
        self.bank_packets: list[Packet | None] = [None] * 256
        self.row_base: list[list[int | None]] = [[None] * 4 for _ in range(256)]
        self.row_pointer = [-1] * 256
        self.root_pointer = -1
        self.active_bank: int | None = None
        self.accepted_events = 0
        self.accepted_transactions = 0
        self.rejected_events = 0
        self.rejected_transactions = 0
        self.output_words = 0
        self.latencies: list[int] = []
        self.max_pending = 0
        self.packet_counts: dict[str, int] = {}
        self.format_counts: dict[str, int] = {}
        self.accepted_records: list[tuple[int, int, int, int, int]] = []
        self.first_cycle: int | None = None
        self.last_completion_cycle = 0

    def _tile_ready(self, transaction: TileTransaction, timestamp: int) -> bool:
        if self.pending[transaction.tile_id] is not None:
            return False
        if self.design == "current_adaptive":
            return True
        bank = transaction.tile_id // 16
        row = (transaction.tile_id % 16) // 4
        base = self.row_base[bank][row]
        return base is None or ((timestamp - base) & 0xFFFF) <= 15

    def accept(self, transaction: TileTransaction, cycle: int) -> None:
        timestamp = cycle & 0xFFFF
        event_count = transaction.canonical_event_count
        if not self._tile_ready(transaction, timestamp):
            self.rejected_transactions += 1
            self.rejected_events += event_count
            return
        record = PendingRecord(transaction, cycle, timestamp)
        self.pending[transaction.tile_id] = record
        self.pending_count += 1
        self.pending_banks.add(transaction.tile_id // 16)
        self.accepted_transactions += 1
        self.accepted_events += event_count
        self.accepted_records.append(
            (transaction.tile_id, transaction.on, transaction.off, timestamp, cycle)
        )
        if self.first_cycle is None:
            self.first_cycle = cycle
        if self.design != "current_adaptive":
            bank = transaction.tile_id // 16
            row = (transaction.tile_id % 16) // 4
            if self.row_base[bank][row] is None:
                self.row_base[bank][row] = timestamp

    def _bank_pending_tiles(self, bank: int) -> list[int]:
        start = bank * 16
        return [tile for tile in range(start, start + 16) if self.pending[tile] is not None]

    def _form_current_packet(self, bank: int, tiles: list[int]) -> Packet:
        records = [self.pending[tile] for tile in tiles]
        assert all(record is not None for record in records)
        timestamps = [record.timestamp for record in records if record is not None]
        local_rows = sorted({(tile % 16) // 4 for tile in tiles})
        use_bank = len(local_rows) >= 2 and max(timestamps) - min(timestamps) <= 31
        if use_bank:
            selected = sorted(tiles)
            words = [PacketWord(), PacketWord(), PacketWord()]
            words.extend(PacketWord((tile,)) for tile in selected)
            return Packet(bank, "BANK", words)

        selected_row = local_rows[0]
        row_tiles = [tile for tile in tiles if (tile % 16) // 4 == selected_row]
        base = min(self.pending[tile].timestamp for tile in row_tiles if self.pending[tile])
        selected = sorted(
            tile
            for tile in row_tiles
            if ((self.pending[tile].timestamp - base) & 0xFFFF) <= 31  # type: ignore[union-attr]
        )
        words = [PacketWord(), PacketWord()]
        words.extend(PacketWord((tile,)) for tile in selected)
        return Packet(bank, "ROW", words)

    def _form_team_packet(self, bank: int, tiles: list[int]) -> Packet:
        active_rows = sorted({(tile % 16) // 4 for tile in tiles})
        pointer = self.row_pointer[bank]
        selected_row = next((row for row in active_rows if row > pointer), active_rows[0])
        self.row_pointer[bank] = selected_row
        selected = sorted(tile for tile in tiles if (tile % 16) // 4 == selected_row)
        words = [PacketWord(), PacketWord()]
        enabled = self.design == "team_second"
        column = 0
        while column < len(selected):
            tile = selected[column]
            record = self.pending[tile]
            assert record is not None
            first_format = _team_format(record.transaction.on, record.transaction.off, enabled)
            self.format_counts[first_format] = self.format_counts.get(first_format, 0) + 1
            if enabled and first_format == "BIN4" and column + 1 < len(selected):
                paired_tile = selected[column + 1]
                paired_record = self.pending[paired_tile]
                assert paired_record is not None
                paired_format = _team_format(
                    paired_record.transaction.on, paired_record.transaction.off, enabled
                )
                if paired_format == "BIN4":
                    self.format_counts[paired_format] = self.format_counts.get(paired_format, 0) + 1
                    self.format_counts["BIN_PAIR_WORD"] = self.format_counts.get("BIN_PAIR_WORD", 0) + 1
                    words.append(PacketWord((tile, paired_tile)))
                    column += 2
                    continue
            words.append(PacketWord((tile,)))
            column += 1
        return Packet(bank, "ROW", words)

    def form_packets(self) -> None:
        for bank in tuple(self.pending_banks):
            if self.bank_packets[bank] is not None:
                continue
            tiles = self._bank_pending_tiles(bank)
            if not tiles:
                continue
            packet = (
                self._form_current_packet(bank, tiles)
                if self.design == "current_adaptive"
                else self._form_team_packet(bank, tiles)
            )
            self.bank_packets[bank] = packet
            self.packet_counts[packet.mode] = self.packet_counts.get(packet.mode, 0) + 1

    def _select_root(self) -> None:
        if self.active_bank is not None:
            return
        for offset in range(1, 257):
            bank = (self.root_pointer + offset) % 256
            if self.bank_packets[bank] is not None:
                self.active_bank = bank
                return

    def transmit(self, cycle: int) -> None:
        self._select_root()
        if self.active_bank is None:
            return
        bank = self.active_bank
        packet = self.bank_packets[bank]
        assert packet is not None
        word = packet.words[packet.index]
        self.output_words += 1
        for tile in word.release_tiles:
            record = self.pending[tile]
            if record is None:
                raise AssertionError(f"released empty tile {tile}")
            latency = cycle - record.accepted_cycle
            self.latencies.extend([latency] * record.transaction.canonical_event_count)
            self.last_completion_cycle = max(self.last_completion_cycle, cycle)
            self.pending[tile] = None
            self.pending_count -= 1
            if self.design != "current_adaptive":
                row = (tile % 16) // 4
                start = bank * 16 + row * 4
                if not any(self.pending[index] is not None for index in range(start, start + 4)):
                    self.row_base[bank][row] = None
            if not self._bank_pending_tiles(bank):
                self.pending_banks.discard(bank)
        packet.index += 1
        if packet.index == len(packet.words):
            self.bank_packets[bank] = None
            self.root_pointer = bank
            self.active_bank = None

    def has_work(self) -> bool:
        return self.pending_count > 0

    def result(
        self,
        source_events: int,
        canonical_events: int,
        canonical_transactions: int,
        playback_speed: float,
    ) -> dict[str, Any]:
        elapsed = max(1, self.last_completion_cycle - (self.first_cycle or 0) + 1)
        mode_total = sum(self.packet_counts.values())
        return {
            "dataset": "UZH shapes_rotation",
            "traffic_condition": f"{playback_speed:g}x",
            "design": self.design,
            "source_events": source_events,
            "input_events": canonical_events,
            "input_transactions": canonical_transactions,
            "source_to_interface_coalesced": source_events - canonical_events,
            "accepted_events": self.accepted_events,
            "accepted_transactions": self.accepted_transactions,
            "backpressured_events": self.rejected_events,
            "backpressured_transactions": self.rejected_transactions,
            "unintended_loss": 0,
            "output_words": self.output_words,
            "output_bits": self.output_words * 16,
            "words_per_input_event": self.output_words / canonical_events if canonical_events else 0.0,
            "words_per_accepted_event": self.output_words / self.accepted_events if self.accepted_events else 0.0,
            "bits_per_accepted_event": self.output_words * 16 / self.accepted_events if self.accepted_events else 0.0,
            "mean_latency_cycles": sum(self.latencies) / len(self.latencies) if self.latencies else 0.0,
            "p99_latency_cycles": _percentile99(self.latencies),
            "throughput_events_per_cycle": self.accepted_events / elapsed,
            "max_pending_tiles": self.max_pending,
            "row_packets": self.packet_counts.get("ROW", 0),
            "bank_packets": self.packet_counts.get("BANK", 0),
            "raw8_count": self.format_counts.get("RAW8", 0),
            "group3_count": self.format_counts.get("GROUP3", 0),
            "bin4_count": self.format_counts.get("BIN4", 0),
            "bin_pair_words": self.format_counts.get("BIN_PAIR_WORD", 0),
            "bank_mode_fraction": self.packet_counts.get("BANK", 0) / mode_total if mode_total else 0.0,
            "backpressure_cycles": 0,
            "elapsed_cycles": elapsed,
        }


def simulate(
    transactions: list[TileTransaction],
    design: str,
    source_events: int,
    playback_speed: float,
) -> tuple[dict[str, Any], list[tuple[int, int, int, int, int]]]:
    model = ArchitectureModel(design)
    canonical_events = sum(t.canonical_event_count for t in transactions)
    input_index = 0
    cycle = transactions[0].cycle if transactions else 0
    while input_index < len(transactions) or model.has_work():
        if not model.has_work() and input_index < len(transactions) and cycle < transactions[input_index].cycle:
            cycle = transactions[input_index].cycle
        while input_index < len(transactions) and transactions[input_index].cycle == cycle:
            model.accept(transactions[input_index], cycle)
            input_index += 1
        model.form_packets()
        model.max_pending = max(model.max_pending, model.pending_count)
        model.transmit(cycle)
        cycle += 1
    return (
        model.result(
            source_events=source_events,
            canonical_events=canonical_events,
            canonical_transactions=len(transactions),
            playback_speed=playback_speed,
        ),
        model.accepted_records,
    )
