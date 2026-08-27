"""Clock-accurate Python model of the current AER v1 RTL data path.

The model mirrors the control behavior that affects loss and throughput in:

* ``aer_pixel_pending_array`` with one-bit ON/OFF requests and depth-1/2 FIFOs
* 256 ``aer_bank_row_reader`` instances for a 128x128 sensor
* the two registered selector-tree levels and their two-entry stream FIFOs
* a permanently-ready 16-bit root link

It intentionally models control, packet length, and lossy reconstruction error
rather than reproducing every payload bit.  Packet bit layout continues to be
checked independently by ``encode_lossy_bank_snapshot`` and the RTL golden
tests.
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
from sw.lossy_binning_model import classify_tile


@dataclass(frozen=True, slots=True)
class RtlCycleConfig:
    sensor_width: int = 128
    sensor_height: int = 128
    tile_size: int = 2
    bank_tiles_x: int = 4
    bank_tiles_y: int = 4
    region_bank_rows: int = 4
    region_bank_cols: int = 4
    pixel_fifo_depth: int = 2
    link_word_bits: int = 16

    def __post_init__(self) -> None:
        if self.sensor_width % 8 or self.sensor_height % 8:
            raise ValueError("sensor dimensions must be positive multiples of eight")
        if self.tile_size != 2:
            raise ValueError("the current RTL uses 2x2-pixel tiles")
        if (self.bank_tiles_x, self.bank_tiles_y) != (4, 4):
            raise ValueError("the current RTL uses 4x4-tile banks")
        if (self.region_bank_rows, self.region_bank_cols) != (4, 4):
            raise ValueError("the current RTL uses 4x4-bank selector regions")
        if self.pixel_fifo_depth not in (1, 2):
            raise ValueError("the RTL pixel FIFO depth must be one or two")
        if self.link_word_bits != 16:
            raise ValueError("the current RTL root link is 16 bits")


@dataclass(frozen=True, slots=True)
class _PixelEvent:
    cycle: int
    polarity: int


@dataclass(frozen=True, slots=True)
class _TileSnapshot:
    on_bitmap: int
    off_bitmap: int
    source_events: int


@dataclass(frozen=True, slots=True)
class _StreamWord:
    last: bool


@dataclass(frozen=True, slots=True)
class _PacketPlan:
    mode: str
    selected_tiles: tuple[int, ...]
    selected_row: int
    payload_words: int
    false_positive_events: int
    pack_group_bits: tuple[int, ...] = ()


@dataclass(frozen=True, slots=True)
class _BankEval:
    word: _StreamWord | None
    plan: _PacketPlan | None = None
    selected_tile: int | None = None


@dataclass(slots=True)
class RtlCycleResult:
    policy: str
    clock_hz: int
    input_events: int
    accepted_events: int
    ignored_events: int
    same_cycle_duplicate_events: int
    readout_events: int
    accepted_tile_groups: int
    output_words: int
    loss_events: int
    loss_rate: float
    false_positive_events: int
    false_positive_rate: float
    total_event_errors: int
    total_error_rate: float
    packets: int
    packet_mode_counts: dict[str, int] = field(default_factory=dict)
    simulated_cycles: int = 0

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


class _LockedRoundRobin:
    def __init__(self, streams: int) -> None:
        self.streams = streams
        self.pointer = 0
        self.selected = 0
        self.locked = False

    def grant(self, requests: list[bool]) -> int | None:
        if self.locked:
            return self.selected
        for offset in range(self.streams):
            candidate = (self.pointer + offset) % self.streams
            if requests[candidate]:
                return candidate
        return None

    def update(self, requests: list[bool], advance: bool) -> None:
        candidate = self.grant(requests)
        if not self.locked and candidate is not None:
            self.selected = candidate
            if advance:
                self.pointer = (candidate + 1) % self.streams
            else:
                self.locked = True
        elif self.locked and advance:
            self.pointer = (self.selected + 1) % self.streams
            self.locked = False


class _Fifo2:
    def __init__(self) -> None:
        self.words: deque[_StreamWord] = deque()

    @property
    def valid(self) -> bool:
        return bool(self.words)

    @property
    def head(self) -> _StreamWord | None:
        return self.words[0] if self.words else None

    def input_ready(self, output_ready: bool) -> bool:
        pop = bool(self.words) and output_ready
        return len(self.words) < 2 or pop

    def update(
        self,
        input_word: _StreamWord | None,
        input_valid: bool,
        input_ready: bool,
        output_ready: bool,
    ) -> None:
        pop = bool(self.words) and output_ready
        push = input_valid and input_ready
        if pop:
            self.words.popleft()
        if push:
            if input_word is None:
                raise AssertionError("valid FIFO push has no word")
            self.words.append(input_word)
        if len(self.words) > 2:
            raise AssertionError("selector FIFO overflow")


class _BankReader:
    IDLE = "IDLE"
    HEADER_HOLD = "HEADER_HOLD"
    DATA = "DATA"
    BANK_MASK = "BANK_MASK"
    BANK_BINMASK = "BANK_BINMASK"
    BANK_DATA = "BANK_DATA"

    def __init__(self, *, lossy: bool, sparse: bool = False) -> None:
        self.lossy = lossy
        self.sparse = sparse
        self.pending: dict[int, _TileSnapshot] = {}
        self.pending_mask = 0
        self.state = self.IDLE
        self.row_arbiter = _LockedRoundRobin(4)
        self.plan: _PacketPlan | None = None
        self.remaining_tiles: set[int] = set()
        self.payload_words_remaining = 0
        self.pack_bit_count = 0
        self.pack_group = 0
        self.pack_scan_done = False

    @staticmethod
    def _is_sparse(snapshot: _TileSnapshot) -> bool:
        return (snapshot.on_bitmap | snapshot.off_bitmap).bit_count() == 1

    def tile_ready(self, local_tile: int) -> bool:
        # The RTL deliberately does not accept a replacement on the same edge
        # that a pending tile is cleared.
        return not bool(self.pending_mask & (1 << local_tile))

    def _row_requests(self) -> list[bool]:
        return [bool(self.pending_mask & (0xF << (row * 4))) for row in range(4)]

    def _make_plan(self, accepts: dict[int, _TileSnapshot], row: int) -> _PacketPlan:
        candidate = dict(self.pending)
        candidate.update(accepts)
        candidate_tiles = tuple(sorted(candidate))

        if self.lossy and len(candidate_tiles) > 1:
            row_counts = Counter(tile // 4 for tile in candidate_tiles)
            if self.sparse:
                row_cost = 0
                for active_row, count in row_counts.items():
                    sparse_count = sum(
                        self._is_sparse(candidate[tile])
                        for tile in candidate_tiles
                        if tile // 4 == active_row
                    )
                    nonsparse_count = count - sparse_count
                    row_cost += sparse_count
                    if nonsparse_count:
                        row_cost += 1 + nonsparse_count
            else:
                row_cost = sum(1 + count for count in row_counts.values())
            raw_bank_cost = 2 + math.ceil(len(candidate_tiles) / 2)
            payload_bits = 0
            false_events = 0
            lossy_widths: dict[int, int] = {}
            for tile in candidate_tiles:
                snapshot = candidate[tile]
                packet_format, width, introduced = classify_tile(
                    snapshot.on_bitmap, snapshot.off_bitmap, "lossy"
                )
                del packet_format
                payload_bits += width
                lossy_widths[tile] = width
                false_events += introduced
            lossy_payload_words = math.ceil(payload_bits / 16)
            lossy_cost = 3 + lossy_payload_words
            if lossy_cost < raw_bank_cost and lossy_cost < row_cost:
                return _PacketPlan(
                    mode="BANK_LOSSY",
                    selected_tiles=candidate_tiles,
                    selected_row=row,
                    payload_words=lossy_payload_words,
                    false_positive_events=false_events,
                    pack_group_bits=tuple(
                        sum(
                            lossy_widths.get(group * 4 + lane, 0)
                            for lane in range(4)
                        )
                        for group in range(4)
                    ),
                )
            if raw_bank_cost < row_cost:
                return _PacketPlan(
                    mode="BANK_RAW",
                    selected_tiles=candidate_tiles,
                    selected_row=row,
                    payload_words=math.ceil(len(candidate_tiles) / 2),
                    false_positive_events=0,
                    pack_group_bits=tuple(
                        8
                        * sum(
                            (group * 4 + lane) in candidate
                            for lane in range(4)
                        )
                        for group in range(4)
                    ),
                )

        row_tiles = tuple(tile for tile in candidate_tiles if tile // 4 == row)
        if not row_tiles:
            raise AssertionError("granted RTL row has no candidate tiles")
        if self.sparse:
            sparse_tiles = tuple(
                tile for tile in row_tiles if self._is_sparse(candidate[tile])
            )
            if sparse_tiles:
                return _PacketPlan(
                    mode="SPARSE",
                    selected_tiles=(sparse_tiles[0],),
                    selected_row=row,
                    payload_words=0,
                    false_positive_events=0,
                )
        return _PacketPlan(
            mode="ROW_RAW",
            selected_tiles=row_tiles,
            selected_row=row,
            payload_words=len(row_tiles),
            false_positive_events=0,
        )

    def evaluate(self, accepts: dict[int, _TileSnapshot]) -> _BankEval:
        if self.state == self.IDLE:
            requests = self._row_requests()
            row = self.row_arbiter.grant(requests)
            if row is None:
                return _BankEval(None)
            plan = self._make_plan(accepts, row)
            return _BankEval(_StreamWord(last=plan.mode == "SPARSE"), plan)
        if self.state == self.HEADER_HOLD:
            return _BankEval(
                _StreamWord(last=self.plan is not None and self.plan.mode == "SPARSE")
            )
        if self.state == self.BANK_MASK:
            return _BankEval(_StreamWord(last=False))
        if self.state == self.BANK_BINMASK:
            return _BankEval(_StreamWord(last=False))
        if self.state == self.BANK_DATA:
            if self.payload_words_remaining <= 0:
                raise AssertionError("bank DATA state has no payload")
            if self.lossy and not (
                self.pack_bit_count >= 16
                or (self.pack_scan_done and self.pack_bit_count > 0)
            ):
                return _BankEval(None)
            return _BankEval(
                _StreamWord(last=self.payload_words_remaining == 1)
            )
        if self.state == self.DATA:
            if not self.remaining_tiles:
                raise AssertionError("row DATA state has no remaining tile")
            tile = min(self.remaining_tiles)
            return _BankEval(
                _StreamWord(last=len(self.remaining_tiles) == 1),
                selected_tile=tile,
            )
        raise AssertionError(f"unknown bank state {self.state}")

    def update(
        self,
        accepts: dict[int, _TileSnapshot],
        evaluation: _BankEval,
        output_ready: bool,
    ) -> tuple[int, str | None]:
        old_state = self.state
        old_plan = self.plan
        word = evaluation.word
        handshake = word is not None and output_ready
        clear_tiles: set[int] = set()
        completed_mode: str | None = None

        requests = self._row_requests()
        row_advance = (
            handshake
            and bool(word.last)
            and (
                self.state in (self.DATA, self.BANK_DATA)
                or (
                    self.state == self.IDLE
                    and evaluation.plan is not None
                    and evaluation.plan.mode == "SPARSE"
                )
                or (
                    self.state == self.HEADER_HOLD
                    and self.plan is not None
                    and self.plan.mode == "SPARSE"
                )
            )
        )

        introduced_false = 0
        if self.state == self.IDLE and evaluation.plan is not None:
            self.plan = evaluation.plan
            self.remaining_tiles = set(evaluation.plan.selected_tiles)
            self.payload_words_remaining = evaluation.plan.payload_words
            self.pack_bit_count = 0
            self.pack_group = 0
            self.pack_scan_done = False
            introduced_false = evaluation.plan.false_positive_events
            if handshake:
                if evaluation.plan.mode == "SPARSE":
                    clear_tiles.update(evaluation.plan.selected_tiles)
                    completed_mode = evaluation.plan.mode
                    self.remaining_tiles.clear()
                    self.plan = None
                    self.state = self.IDLE
                elif evaluation.plan.mode == "ROW_RAW":
                    self.state = self.DATA
                else:
                    self.state = self.BANK_MASK
            else:
                self.state = self.HEADER_HOLD
        elif self.state == self.HEADER_HOLD and handshake:
            if self.plan is None:
                raise AssertionError("held header lost its packet plan")
            if self.plan.mode == "SPARSE":
                clear_tiles.update(self.remaining_tiles)
                completed_mode = self.plan.mode
                self.remaining_tiles.clear()
                self.plan = None
                self.state = self.IDLE
            elif self.plan.mode == "ROW_RAW":
                self.state = self.DATA
            else:
                self.state = self.BANK_MASK
        elif self.state == self.BANK_MASK and handshake:
            if self.plan is None:
                raise AssertionError("bank mask lost its packet plan")
            self.state = (
                self.BANK_BINMASK
                if self.plan.mode == "BANK_LOSSY"
                else self.BANK_DATA
            )
        elif self.state == self.BANK_BINMASK and handshake:
            self.state = self.BANK_DATA
        elif self.state == self.BANK_DATA and handshake:
            if word is None:
                raise AssertionError("bank DATA handshake has no word")
            if word.last:
                clear_tiles.update(self.remaining_tiles)
                completed_mode = self.plan.mode if self.plan else None
                self.remaining_tiles.clear()
                self.payload_words_remaining = 0
                self.pack_bit_count = 0
                self.pack_group = 0
                self.pack_scan_done = False
                self.plan = None
                self.state = self.IDLE
            else:
                self.payload_words_remaining -= 1
        elif self.state == self.DATA and handshake:
            if evaluation.selected_tile is None:
                raise AssertionError("row DATA handshake has no tile")
            clear_tiles.add(evaluation.selected_tile)
            self.remaining_tiles.remove(evaluation.selected_tile)
            if word is not None and word.last:
                completed_mode = self.plan.mode if self.plan else None
                self.plan = None
                self.state = self.IDLE

        # Match the bounded four-tile RTL packer.  It scans during a held bank
        # header and the mask phases, drains one 16-bit word when accepted,
        # and pauses under backpressure once a complete word is buffered.
        if (
            self.lossy
            and old_plan is not None
            and old_plan.mode in {"BANK_LOSSY", "BANK_RAW"}
            and old_state != self.IDLE
        ):
            output_fire = old_state == self.BANK_DATA and handshake
            base_count = self.pack_bit_count
            if output_fire:
                base_count = max(0, base_count - 16)
            append = (
                not self.pack_scan_done
                and base_count <= 16
                and not (output_fire and word is not None and word.last)
            )
            if append:
                if self.pack_group >= len(old_plan.pack_group_bits):
                    raise AssertionError("packer group index exceeds packet plan")
                base_count += old_plan.pack_group_bits[self.pack_group]
                self.pack_group += 1
                if self.pack_group == len(old_plan.pack_group_bits):
                    self.pack_scan_done = True
            self.pack_bit_count = base_count

        for tile in clear_tiles:
            self.pending.pop(tile, None)
            self.pending_mask &= ~(1 << tile)
        for tile, snapshot in accepts.items():
            if tile in self.pending:
                raise AssertionError("RTL accepted a tile into a full bank slot")
            self.pending[tile] = snapshot
            self.pending_mask |= 1 << tile

        self.row_arbiter.update(requests, row_advance)
        return introduced_false, completed_mode

    @property
    def empty(self) -> bool:
        return self.pending_mask == 0 and self.state == self.IDLE


def _pixel_and_tile_geometry(
    x: int, y: int, config: RtlCycleConfig
) -> tuple[int, int, int]:
    pixel = y * config.sensor_width + x
    tile_x = x // 2
    tile_y = y // 2
    banks_x = config.sensor_width // 8
    bank = (tile_y // 4) * banks_x + (tile_x // 4)
    local_tile = (tile_y % 4) * 4 + (tile_x % 4)
    return pixel, bank, local_tile


def simulate_rtl_cycle_exact(
    events: list[SourceEvent],
    policy: str,
    config: RtlCycleConfig,
    clock_hz: int,
    *,
    max_drain_cycles: int = 1_000_000,
) -> RtlCycleResult:
    """Replay events with the same request, FIFO, arbitration and backpressure RTL.

    ``policy='raw'`` matches ``ENABLE_BINNING=0`` and no bank fusion.
    ``policy='lossy'`` matches ``ENABLE_BINNING=1``, ``ENABLE_BANK_FUSION=1``
    and ``ENABLE_LOSSY_BINNING=1``. ``policy='combined'`` additionally enables
    the one-word lossless SPARSE path. ``out_ready`` is held high, as in the
    CIFAR10-DVS XSim testbench.
    """

    if policy not in {"raw", "lossy", "combined"}:
        raise ValueError(
            "cycle-exact RTL policy must be 'raw', 'lossy', or 'combined'"
        )
    if clock_hz <= 0:
        raise ValueError("clock_hz must be positive")
    if not events:
        return RtlCycleResult(
            policy=policy,
            clock_hz=clock_hz,
            input_events=0,
            accepted_events=0,
            ignored_events=0,
            same_cycle_duplicate_events=0,
            readout_events=0,
            accepted_tile_groups=0,
            output_words=0,
            loss_events=0,
            loss_rate=0.0,
            false_positive_events=0,
            false_positive_rate=0.0,
            total_event_errors=0,
            total_error_rate=0.0,
            packets=0,
            simulated_cycles=0,
        )

    trace = sorted(events, key=lambda event: event.cycle)
    if any(
        event.x < 0
        or event.x >= config.sensor_width
        or event.y < 0
        or event.y >= config.sensor_height
        for event in trace
    ):
        raise ValueError("event lies outside the configured sensor")

    pixel_count = config.sensor_width * config.sensor_height
    bank_rows = config.sensor_height // 8
    bank_cols = config.sensor_width // 8
    bank_count = bank_rows * bank_cols
    region_rows = bank_rows // config.region_bank_rows
    region_cols = bank_cols // config.region_bank_cols
    region_count = region_rows * region_cols
    if region_count != 16 or bank_count != 256:
        raise ValueError("this first cycle-exact model targets the 128x128 RTL")

    pixel_queues: list[deque[_PixelEvent]] = [deque() for _ in range(pixel_count)]
    frontend_active: list[set[int]] = [set() for _ in range(bank_count)]
    banks = [
        _BankReader(
            lossy=policy in {"lossy", "combined"},
            sparse=policy == "combined",
        )
        for _ in range(bank_count)
    ]

    level1_arbiters = [_LockedRoundRobin(16) for _ in range(region_count)]
    level1_fifos = [_Fifo2() for _ in range(region_count)]
    level2_arbiter = _LockedRoundRobin(region_count)
    root_fifo = _Fifo2()

    def region_and_input(bank: int) -> tuple[int, int]:
        bank_y, bank_x = divmod(bank, bank_cols)
        region = (
            (bank_y // config.region_bank_rows) * region_cols
            + bank_x // config.region_bank_cols
        )
        local = (
            (bank_y % config.region_bank_rows) * config.region_bank_cols
            + bank_x % config.region_bank_cols
        )
        return region, local

    bank_to_region = [region_and_input(bank) for bank in range(bank_count)]
    region_banks: list[list[int]] = [[0] * 16 for _ in range(region_count)]
    for bank, (region, local) in enumerate(bank_to_region):
        region_banks[region][local] = bank

    event_index = 0
    accepted = 0
    ignored = 0
    duplicate = 0
    readout = 0
    accepted_tiles = 0
    false_positive = 0
    output_words = 0
    packets = 0
    packet_modes: Counter[str] = Counter()
    active_bank_readers: set[int] = set()
    cycle = 0
    last_input_cycle = trace[-1].cycle

    while True:
        # Match the testbench's one-bit ON/OFF vector.  Repeated assertions of
        # the same polarity at one pixel and cycle cannot be represented.
        requests: dict[int, tuple[bool, bool]] = {}
        while event_index < len(trace) and trace[event_index].cycle <= cycle:
            event = trace[event_index]
            pixel, _bank, _tile = _pixel_and_tile_geometry(
                event.x, event.y, config
            )
            on, off = requests.get(pixel, (False, False))
            if event.polarity:
                if on:
                    duplicate += 1
                on = True
            else:
                if off:
                    duplicate += 1
                off = True
            requests[pixel] = (on, off)
            event_index += 1

        # The bank accepts a snapshot of every ready, active front-end tile.
        bank_accepts: dict[int, dict[int, _TileSnapshot]] = {}
        popped_pixels: set[int] = set()
        touched_tiles: set[tuple[int, int]] = set()
        for bank_id, active_tiles in enumerate(frontend_active):
            if not active_tiles:
                continue
            bank = banks[bank_id]
            for local_tile in tuple(active_tiles):
                if not bank.tile_ready(local_tile):
                    continue
                bank_y, bank_x = divmod(bank_id, bank_cols)
                local_y, local_x = divmod(local_tile, 4)
                origin_x = (bank_x * 8) + (local_x * 2)
                origin_y = (bank_y * 8) + (local_y * 2)
                on_bitmap = 0
                off_bitmap = 0
                source_events = 0
                for bit in range(4):
                    x = origin_x + (bit & 1)
                    y = origin_y + ((bit >> 1) & 1)
                    pixel = y * config.sensor_width + x
                    queue = pixel_queues[pixel]
                    if not queue:
                        continue
                    source_events += 1
                    popped_pixels.add(pixel)
                    if queue[0].polarity:
                        on_bitmap |= 1 << bit
                    else:
                        off_bitmap |= 1 << bit
                if source_events == 0:
                    raise AssertionError("active front-end tile has no head event")
                bank_accepts.setdefault(bank_id, {})[local_tile] = _TileSnapshot(
                    on_bitmap=on_bitmap,
                    off_bitmap=off_bitmap,
                    source_events=source_events,
                )
                accepted_tiles += 1
                readout += source_events
                touched_tiles.add((bank_id, local_tile))

        banks_to_evaluate = active_bank_readers | set(bank_accepts)
        bank_evaluations: dict[int, _BankEval] = {
            bank_id: banks[bank_id].evaluate(bank_accepts.get(bank_id, {}))
            for bank_id in banks_to_evaluate
        }

        # Evaluate downstream to upstream, exactly following ready propagation.
        root_output_ready = True
        root_output_valid = root_fifo.valid
        root_input_ready = root_fifo.input_ready(root_output_ready)

        level2_requests = [fifo.valid for fifo in level1_fifos]
        level2_grant = level2_arbiter.grant(level2_requests)
        level2_word = (
            level1_fifos[level2_grant].head
            if level2_grant is not None
            else None
        )
        level2_valid = level2_word is not None
        level2_push = level2_valid and root_input_ready

        level1_output_ready = [False] * region_count
        if level2_grant is not None:
            level1_output_ready[level2_grant] = root_input_ready

        level1_input_ready = [
            fifo.input_ready(level1_output_ready[region])
            for region, fifo in enumerate(level1_fifos)
        ]
        region_requests: dict[int, list[bool]] = {}
        for bank_id, evaluation in bank_evaluations.items():
            if evaluation.word is None:
                continue
            region, local = bank_to_region[bank_id]
            region_requests.setdefault(region, [False] * 16)[local] = True
        level1_words: dict[int, _StreamWord | None] = {}
        bank_ready = [False] * bank_count
        for region, requests_in_region in region_requests.items():
            grant = level1_arbiters[region].grant(requests_in_region)
            word = (
                bank_evaluations[region_banks[region][grant]].word
                if grant is not None
                else None
            )
            level1_words[region] = word
            if grant is not None:
                bank_ready[region_banks[region][grant]] = level1_input_ready[region]

        if root_output_valid:
            output_words += 1
            if root_fifo.head is not None and root_fifo.head.last:
                packets += 1

        # Update selectors and registered FIFOs at the clock edge.
        for region in range(region_count):
            word = level1_words.get(region)
            push = word is not None and level1_input_ready[region]
            advance = push and bool(word.last)
            if region in region_requests:
                level1_arbiters[region].update(region_requests[region], advance)
            level1_fifos[region].update(
                word,
                word is not None,
                level1_input_ready[region],
                level1_output_ready[region],
            )

        level2_advance = level2_push and bool(level2_word.last)
        level2_arbiter.update(level2_requests, level2_advance)
        root_fifo.update(
            level2_word,
            level2_valid,
            root_input_ready,
            root_output_ready,
        )

        for bank_id in banks_to_evaluate:
            bank = banks[bank_id]
            introduced, completed_mode = bank.update(
                bank_accepts.get(bank_id, {}),
                bank_evaluations[bank_id],
                bank_ready[bank_id],
            )
            false_positive += introduced
            if completed_mode is not None:
                packet_modes[completed_mode] += 1
            if bank.empty:
                active_bank_readers.discard(bank_id)
            else:
                active_bank_readers.add(bank_id)

        # Pixel FIFO pop and request acceptance happen on the same edge.
        affected_pixels = set(requests) | popped_pixels
        for pixel in affected_pixels:
            queue = pixel_queues[pixel]
            pop = pixel in popped_pixels
            on, off = requests.get(pixel, (False, False))
            request_present = on or off
            has_room = len(queue) < config.pixel_fifo_depth or pop
            accept = request_present and has_room

            if pop:
                if not queue:
                    raise AssertionError("front-end pop on an empty pixel")
                queue.popleft()
            if request_present:
                if accept:
                    accepted += 1
                    if on and off:
                        ignored += 1
                    queue.append(_PixelEvent(cycle=cycle, polarity=int(on)))
                else:
                    ignored += int(on) + int(off)

            y, x = divmod(pixel, config.sensor_width)
            _pixel, bank_id, local_tile = _pixel_and_tile_geometry(x, y, config)
            touched_tiles.add((bank_id, local_tile))

        # Recompute only tiles whose pixel queues changed.
        for bank_id, local_tile in touched_tiles:
            bank_y, bank_x = divmod(bank_id, bank_cols)
            local_y, local_x = divmod(local_tile, 4)
            origin_x = (bank_x * 8) + (local_x * 2)
            origin_y = (bank_y * 8) + (local_y * 2)
            active = False
            for bit in range(4):
                x = origin_x + (bit & 1)
                y = origin_y + ((bit >> 1) & 1)
                if pixel_queues[y * config.sensor_width + x]:
                    active = True
                    break
            if active:
                frontend_active[bank_id].add(local_tile)
            else:
                frontend_active[bank_id].discard(local_tile)

        cycle += 1
        input_done = event_index == len(trace)
        frontend_empty = not any(frontend_active)
        banks_empty = not active_bank_readers
        selectors_empty = not any(fifo.valid for fifo in level1_fifos) and not root_fifo.valid
        if input_done and frontend_empty and banks_empty and selectors_empty:
            break
        if cycle > last_input_cycle + max_drain_cycles:
            raise TimeoutError(
                "cycle-exact model did not drain within the configured limit"
            )

    if accepted + ignored + duplicate != len(trace):
        raise AssertionError(
            "source accounting mismatch: "
            f"{accepted}+{ignored}+{duplicate}!={len(trace)}"
        )
    if readout != accepted:
        raise AssertionError(f"readout {readout} != accepted {accepted}")

    loss = ignored + duplicate
    total_errors = loss + false_positive
    return RtlCycleResult(
        policy=policy,
        clock_hz=clock_hz,
        input_events=len(trace),
        accepted_events=accepted,
        ignored_events=ignored,
        same_cycle_duplicate_events=duplicate,
        readout_events=readout,
        accepted_tile_groups=accepted_tiles,
        output_words=output_words,
        loss_events=loss,
        loss_rate=loss / len(trace),
        false_positive_events=false_positive,
        false_positive_rate=false_positive / len(trace),
        total_event_errors=total_errors,
        total_error_rate=total_errors / len(trace),
        packets=packets,
        packet_mode_counts=dict(sorted(packet_modes.items())),
        simulated_cycles=cycle,
    )


def compare_cifar10_dvs_cycle_exact(
    dataset: Path,
    clock_rates: list[int],
    playback_speed: Decimal,
    max_events: int,
    config: RtlCycleConfig,
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
        raw = simulate_rtl_cycle_exact(events, "raw", config, clock_hz)
        lossy = simulate_rtl_cycle_exact(events, "lossy", config, clock_hz)
        combined = simulate_rtl_cycle_exact(events, "combined", config, clock_hz)
        relative_reduction = (
            (raw.total_error_rate - lossy.total_error_rate)
            / raw.total_error_rate
            if raw.total_error_rate
            else 0.0
        )
        cases[str(clock_hz)] = {
            "selection": selection,
            "results": [raw.as_dict(), lossy.as_dict(), combined.as_dict()],
            "lossy_vs_raw": {
                "total_error_rate_reduction_percentage_points": 100
                * (raw.total_error_rate - lossy.total_error_rate),
                "relative_total_error_reduction_percent": 100 * relative_reduction,
                "accepted_event_increase_percent": 100
                * (lossy.accepted_events - raw.accepted_events)
                / max(1, raw.accepted_events),
                "output_word_reduction_percent": 100
                * (raw.output_words - lossy.output_words)
                / max(1, raw.output_words),
            },
            "combined_vs_raw": {
                "total_error_rate_reduction_percentage_points": 100
                * (raw.total_error_rate - combined.total_error_rate),
                "relative_total_error_reduction_percent": 100
                * (raw.total_error_rate - combined.total_error_rate)
                / max(raw.total_error_rate, 1 / max(1, raw.input_events)),
                "accepted_event_increase_percent": 100
                * (combined.accepted_events - raw.accepted_events)
                / max(1, raw.accepted_events),
                "output_word_reduction_percent": 100
                * (raw.output_words - combined.output_words)
                / max(1, raw.output_words),
            },
        }
    return {
        "model": "Python clock-accurate control model of current AER v1 RTL",
        "dataset": str(dataset.resolve()),
        "playback_speed": str(playback_speed),
        "peak_definition": "same 1297.016861x replay used for the 1 GEPS RTL study",
        "config": asdict(config),
        "cases": cases,
    }


def _print_report(report: dict[str, object]) -> None:
    for clock_text, case in report["cases"].items():
        print(f"\n[{int(clock_text) / 1_000_000:g} MHz]")
        print("policy  accepted  ignored  duplicate  false  words  total_error%")
        for result in case["results"]:
            print(
                f"{result['policy']:<6} {result['accepted_events']:>9} "
                f"{result['ignored_events']:>8} "
                f"{result['same_cycle_duplicate_events']:>9} "
                f"{result['false_positive_events']:>6} "
                f"{result['output_words']:>6} "
                f"{100 * result['total_error_rate']:>12.4f}"
            )
        delta = case["lossy_vs_raw"]
        print(
            "lossy-vs-raw: "
            f"{delta['total_error_rate_reduction_percentage_points']:+.4f}%p, "
            f"relative {delta['relative_total_error_reduction_percent']:+.4f}%, "
            f"words {delta['output_word_reduction_percent']:+.4f}%"
        )
        delta = case["combined_vs_raw"]
        print(
            "combined-vs-raw: "
            f"{delta['total_error_rate_reduction_percentage_points']:+.4f}%p, "
            f"relative {delta['relative_total_error_reduction_percent']:+.4f}%, "
            f"words {delta['output_word_reduction_percent']:+.4f}%"
        )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path("data/cifar10_dvs/sample/cifar10_airplane_0.aedat"),
    )
    parser.add_argument(
        "--clock-hz", type=int, nargs="+", default=[100_000_000, 200_000_000]
    )
    parser.add_argument("--playback-speed", default="1297.016861")
    parser.add_argument("--max-events", type=int, default=178_165)
    parser.add_argument("--pixel-fifo-depth", type=int, default=2)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("results/lossy_binning_rtl_cycle_model/summary.json"),
    )
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    report = compare_cifar10_dvs_cycle_exact(
        args.dataset,
        args.clock_hz,
        Decimal(args.playback_speed),
        args.max_events,
        RtlCycleConfig(pixel_fifo_depth=args.pixel_fifo_depth),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    _print_report(report)
    print(f"\nwrote {args.output}")


if __name__ == "__main__":
    main()
