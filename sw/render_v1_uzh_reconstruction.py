"""Decode AER v1 XSim output and render source-versus-receiver timelines."""

from __future__ import annotations

import argparse
import bisect
import json
import math
from collections import Counter, defaultdict, deque
from pathlib import Path
from statistics import mean

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def parse_rtl_log(path: Path) -> tuple[list[dict[str, int]], list[tuple[int, int, int]]]:
    accepted: list[dict[str, int]] = []
    words: list[tuple[int, int, int]] = []
    with path.open("r", encoding="ascii") as handle:
        for line_number, line in enumerate(handle, start=1):
            fields = line.split()
            if not fields:
                continue
            if fields[0] == "A" and len(fields) == 8:
                accepted.append(
                    {
                        "group_id": int(fields[1]),
                        "source_cycle": int(fields[2]),
                        "accept_cycle": int(fields[3]),
                        "tile": int(fields[4]),
                        "on": int(fields[5], 16),
                        "off": int(fields[6], 16),
                        "source_events": int(fields[7]),
                    }
                )
            elif fields[0] == "W" and len(fields) == 4:
                words.append((int(fields[1]), int(fields[2], 16), int(fields[3])))
            elif fields[0] not in {"M", "D", "S"}:
                raise ValueError(f"{path}:{line_number}: unsupported record")
    return accepted, words


def decode_payload(word: int) -> tuple[str, int, int]:
    format_code = (word >> 14) & 0x3
    payload = (word >> 2) & 0xFF
    if format_code == 0:
        return "RAW8", (payload >> 4) & 0xF, payload & 0xF
    if format_code == 1:
        polarity = (payload >> 7) & 1
        missing = (payload >> 5) & 0x3
        bitmap = 0xF ^ (1 << missing)
        return "GROUP3", bitmap if polarity else 0, 0 if polarity else bitmap
    if format_code == 2:
        polarity = (word >> 8) & 1
        return "BIN4", 0xF if polarity else 0, 0 if polarity else 0xF
    raise ValueError(f"reserved format in data word 0x{word:04x}")


def tile_pixel(tile: int, pixel_bit: int) -> tuple[int, int]:
    bank_id, local_tile = divmod(tile, 16)
    bank_row, bank_col = divmod(bank_id, 16)
    local_row, local_col = divmod(local_tile, 4)
    tile_x = bank_col * 4 + local_col
    tile_y = bank_row * 4 + local_row
    return tile_x * 2 + (pixel_bit & 1), tile_y * 2 + ((pixel_bit >> 1) & 1)


def decode_words(
    accepted: list[dict[str, int]],
    words: list[tuple[int, int, int]],
    *,
    external_rx_timestamp: bool = False,
    extended_bank_id: bool = False,
) -> tuple[list[dict[str, int | str]], list[str], int]:
    waiting: defaultdict[int, deque[dict[str, int]]] = defaultdict(deque)
    for record in accepted:
        waiting[record["tile"]].append(record)

    decoded: list[dict[str, int | str]] = []
    errors: list[str] = []
    # 0=header, 1=bank extension, 2=time, 3=row data,
    # 4=bank active mask, 5=bank data, 6=lossy BIN mask.
    phase = 0
    bank_id = 0
    row = 0
    columns: list[int] = []
    bank_mode = 0
    bank_count = 0
    bank_tiles: list[int] = []
    bank_bits_per_token = 0
    bank_payload_buffer = 0
    bank_payload_bits = 0
    bank_bin_mask = 0
    headers = 0
    row_time = 0
    packet_receive_cycle = 0

    def append_tile_decoded(
        tile: int,
        kind: str,
        on_bitmap: int,
        off_bitmap: int,
        delta: int,
        receive_cycle: int,
    ) -> None:
        encoded_time = (
            packet_receive_cycle
            if external_rx_timestamp
            else (row_time + delta) & 0xFFFF
        )
        false_positive_events = 0
        if not waiting[tile]:
            errors.append(f"output for tile {tile} has no accepted input")
            expected = {
                "group_id": -1,
                "source_cycle": -1,
                "accept_cycle": -1,
                "source_events": 0,
            }
        else:
            expected = waiting[tile].popleft()
            if expected["on"] != on_bitmap or expected["off"] != off_bitmap:
                expected_on = int(expected["on"])
                expected_off = int(expected["off"])
                lossy_bin_match = kind == "BANK_LOSSY_BIN" and (
                    (expected_on.bit_count() == 3 and expected_off == 0 and on_bitmap == 0xF and off_bitmap == 0)
                    or (expected_off.bit_count() == 3 and expected_on == 0 and off_bitmap == 0xF and on_bitmap == 0)
                )
                if lossy_bin_match:
                    false_positive_events = 1
                else:
                    errors.append(
                        f"group {expected['group_id']} bitmap mismatch: "
                        f"expected {expected_on:x}/{expected_off:x}, "
                        f"decoded {on_bitmap:x}/{off_bitmap:x}"
                    )
            if (
                not external_rx_timestamp
                and (expected["accept_cycle"] & 0xFFFF) != encoded_time
            ):
                errors.append(
                    f"group {expected['group_id']} timestamp mismatch: "
                    f"expected {expected['accept_cycle'] & 0xFFFF}, "
                    f"decoded {encoded_time}"
                )
        decoded.append(
            {
                "group_id": expected["group_id"],
                "source_cycle": expected["source_cycle"],
                "accept_cycle": expected["accept_cycle"],
                "receive_cycle": receive_cycle,
                "rx_timestamp_cycle": packet_receive_cycle,
                "tile": tile,
                "on": on_bitmap,
                "off": off_bitmap,
                "source_events": expected["source_events"],
                "format": kind,
                "encoded_time": encoded_time,
                "false_positive_events": false_positive_events,
            }
        )

    def append_decoded(
        column: int,
        kind: str,
        on_bitmap: int,
        off_bitmap: int,
        delta: int,
        receive_cycle: int,
    ) -> None:
        append_tile_decoded(
            bank_id * 16 + row * 4 + column,
            kind,
            on_bitmap,
            off_bitmap,
            delta,
            receive_cycle,
        )

    for receive_cycle, word, last in words:
        if phase == 0:
            if (word >> 15) == 0:
                sparse_bank = (word >> 7) & 0xFF
                sparse_local_tile = (word >> 3) & 0xF
                sparse_pixel = (word >> 1) & 0x3
                sparse_polarity = word & 0x1
                packet_receive_cycle = receive_cycle
                headers += 1
                if not external_rx_timestamp:
                    errors.append(
                        f"SPARSE packet requires external receive timestamps at cycle {receive_cycle}"
                    )
                if extended_bank_id:
                    errors.append(
                        f"SPARSE packet does not support extended bank IDs at cycle {receive_cycle}"
                    )
                if not last:
                    errors.append(
                        f"SPARSE packet did not assert out_last at cycle {receive_cycle}"
                    )
                sparse_bitmap = 1 << sparse_pixel
                append_tile_decoded(
                    sparse_bank * 16 + sparse_local_tile,
                    "SPARSE",
                    sparse_bitmap if sparse_polarity else 0,
                    0 if sparse_polarity else sparse_bitmap,
                    0,
                    receive_cycle,
                )
                continue
            packet_type = word >> 14
            if packet_type == 0x2:
                bank_id = (word >> 6) & 0xFF
                bank_mode = (word >> 4) & 0x3
                bank_count = (word & 0xF) + 1
                bank_tiles = []
                bank_payload_buffer = 0
                bank_payload_bits = 0
                bank_bin_mask = 0
                headers += 1
                packet_receive_cycle = receive_cycle
                if not external_rx_timestamp:
                    errors.append(
                        f"bank packet requires external receive timestamps at cycle {receive_cycle}"
                    )
                if extended_bank_id:
                    errors.append(
                        f"bank packet does not support extended bank IDs at cycle {receive_cycle}"
                    )
                if last:
                    errors.append(f"bank header asserted out_last at cycle {receive_cycle}")
                phase = 4
                continue
            if packet_type != 0x3:
                errors.append(f"expected header, got 0x{word:04x}")
                continue
            bank_id = (word >> 6) & 0xFF
            row = (word >> 4) & 0x3
            columns = [column for column in range(4) if word & (1 << column)]
            if not columns:
                errors.append(f"empty header at receive cycle {receive_cycle}")
            headers += 1
            packet_receive_cycle = receive_cycle
            if extended_bank_id:
                phase = 1
            elif external_rx_timestamp:
                phase = 3
            else:
                phase = 2
            continue
        if phase == 1:
            bank_id |= (word & 0xFF) << 8
            phase = 3 if external_rx_timestamp else 2
            continue
        if phase == 2:
            row_time = word
            phase = 3
            continue

        if phase == 4:
            bank_tiles = [
                bank_id * 16 + local_tile
                for local_tile in range(16)
                if word & (1 << local_tile)
            ]
            if len(bank_tiles) != bank_count:
                errors.append(
                    f"bank mask count mismatch at cycle {receive_cycle}: "
                    f"header {bank_count}, mask {len(bank_tiles)}"
                )
            if last:
                errors.append(f"bank mask asserted out_last at cycle {receive_cycle}")
            if bank_mode == 0:
                bank_bits_per_token = 8
            elif bank_mode == 1:
                bank_bits_per_token = 3
            elif bank_mode == 2:
                bank_bits_per_token = 1
            elif bank_mode == 3:
                phase = 6
                continue
            else:
                errors.append(f"reserved bank mode at cycle {receive_cycle}")
                bank_bits_per_token = 1
            phase = 5
            continue

        if phase == 6:
            bank_bin_mask = word
            active_mask = sum(1 << (tile % 16) for tile in bank_tiles)
            if bank_bin_mask & ~active_mask:
                errors.append(
                    f"lossy BIN mask is not a subset of the active mask at cycle {receive_cycle}"
                )
            if last:
                errors.append(f"lossy BIN mask asserted out_last at cycle {receive_cycle}")
            phase = 5
            continue

        if phase == 5:
            bank_payload_buffer |= word << bank_payload_bits
            bank_payload_bits += 16
            while bank_tiles:
                if bank_mode == 3:
                    next_width = (
                        1
                        if bank_bin_mask & (1 << (bank_tiles[0] % 16))
                        else 8
                    )
                else:
                    next_width = bank_bits_per_token
                if bank_payload_bits < next_width:
                    break
                bank_bits_per_token = next_width
                token_mask = (1 << bank_bits_per_token) - 1
                token = bank_payload_buffer & token_mask
                bank_payload_buffer >>= bank_bits_per_token
                bank_payload_bits -= bank_bits_per_token
                tile = bank_tiles.pop(0)
                if bank_mode == 0:
                    kind = "BANK_RAW8"
                    on_bitmap = (token >> 4) & 0xF
                    off_bitmap = token & 0xF
                elif bank_mode == 1:
                    kind = "BANK_GROUP3"
                    polarity = (token >> 2) & 1
                    missing = token & 0x3
                    bitmap = 0xF ^ (1 << missing)
                    on_bitmap = bitmap if polarity else 0
                    off_bitmap = 0 if polarity else bitmap
                elif bank_mode == 2:
                    kind = "BANK_BIN4"
                    polarity = token & 1
                    on_bitmap = 0xF if polarity else 0
                    off_bitmap = 0 if polarity else 0xF
                elif bank_bin_mask & (1 << (tile % 16)):
                    kind = "BANK_LOSSY_BIN"
                    polarity = token & 1
                    on_bitmap = 0xF if polarity else 0
                    off_bitmap = 0 if polarity else 0xF
                else:
                    kind = "BANK_RAW8"
                    on_bitmap = (token >> 4) & 0xF
                    off_bitmap = token & 0xF
                append_tile_decoded(
                    tile,
                    kind,
                    on_bitmap,
                    off_bitmap,
                    0,
                    receive_cycle,
                )
            expected_last = not bank_tiles
            if bool(last) != expected_last:
                errors.append(
                    f"bank out_last mismatch at receive cycle {receive_cycle}: "
                    f"expected {int(expected_last)}, got {last}"
                )
            if expected_last:
                phase = 0
            continue

        if not columns:
            errors.append(f"data word without a remaining column at cycle {receive_cycle}")
            phase = 0
            continue

        format_code = (word >> 14) & 0x3
        if format_code == 3:
            fusion_columns = list(columns)
            columns.clear()
            if ((word >> 13) & 1) == 0:
                for column in fusion_columns:
                    polarity = (word >> (9 + column)) & 1
                    append_decoded(
                        column,
                        "ROW_BIN4",
                        0xF if polarity else 0,
                        0 if polarity else 0xF,
                        0,
                        receive_cycle,
                    )
            else:
                for column in fusion_columns:
                    token = (word >> (1 + column * 3)) & 0x7
                    polarity = (token >> 2) & 1
                    missing = token & 0x3
                    bitmap = 0xF ^ (1 << missing)
                    append_decoded(
                        column,
                        "ROW_GROUP3",
                        bitmap if polarity else 0,
                        0 if polarity else bitmap,
                        0,
                        receive_cycle,
                    )
        elif format_code == 2 and ((word >> 13) & 1):
            if len(columns) < 2:
                errors.append(f"packed BIN4 lacks two columns at cycle {receive_cycle}")
                columns.clear()
            else:
                first_column = columns.pop(0)
                second_column = columns.pop(0)
                first_polarity = (word >> 8) & 1
                second_polarity = (word >> 3) & 1
                append_decoded(
                    first_column,
                    "BIN4",
                    0xF if first_polarity else 0,
                    0 if first_polarity else 0xF,
                    (word >> 9) & 0xF,
                    receive_cycle,
                )
                append_decoded(
                    second_column,
                    "BIN4",
                    0xF if second_polarity else 0,
                    0 if second_polarity else 0xF,
                    (word >> 4) & 0xF,
                    receive_cycle,
                )
        else:
            column = columns.pop(0)
            kind, on_bitmap, off_bitmap = decode_payload(word)
            delta = (word >> 9) & 0xF if format_code == 2 else (word >> 10) & 0xF
            append_decoded(
                column,
                kind,
                on_bitmap,
                off_bitmap,
                delta,
                receive_cycle,
            )
        expected_last = not columns
        if bool(last) != expected_last:
            errors.append(
                f"out_last mismatch at receive cycle {receive_cycle}: "
                f"expected {int(expected_last)}, got {last}"
            )
        if expected_last:
            phase = 0

    if phase != 0:
        errors.append("truncated output packet")
    for tile, queue in waiting.items():
        if queue:
            errors.append(f"tile {tile} has {len(queue)} accepted but undecoded groups")
    return decoded, errors, headers


def percentile(values: list[int], fraction: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    index = min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1)
    return ordered[max(0, index)]


def reconstructed_events(
    decoded: list[dict[str, int | str]],
    clock_hz: int,
    time_scale: float,
    cycle_field: str,
) -> list[tuple[int, int, int, int]]:
    events: list[tuple[int, int, int, int]] = []
    for group in decoded:
        event_ns = round(
            int(group[cycle_field]) * time_scale * 1_000_000_000 / clock_hz
        )
        tile = int(group["tile"])
        for polarity, bitmap in ((1, int(group["on"])), (0, int(group["off"]))):
            for pixel_bit in range(4):
                if bitmap & (1 << pixel_bit):
                    x, y = tile_pixel(tile, pixel_bit)
                    events.append((event_ns, x, y, polarity))
    events.sort()
    return events


def build_summary(
    manifest: dict[str, object],
    accepted: list[dict[str, int]],
    words: list[tuple[int, int, int]],
    decoded: list[dict[str, int | str]],
    errors: list[str],
    headers: int,
    rx_events: list[tuple[int, int, int, int]],
) -> dict[str, object]:
    input_latency = [record["accept_cycle"] - record["source_cycle"] for record in accepted]
    total_latency = [
        int(record["receive_cycle"]) - int(record["source_cycle"])
        for record in decoded
    ]
    format_counts = Counter(str(record["format"]) for record in decoded)
    return {
        "source": manifest["source"],
        "crop": manifest["crop"],
        "clock_hz": manifest["clock_hz"],
        "playback_speed": manifest["playback_speed"],
        "source_events": manifest["source_events"],
        "source_duration_ms": float(manifest["source_duration_ns"]) / 1_000_000,
        "tile_groups": manifest["tile_groups"],
        "accepted_tile_groups": len(accepted),
        "decoded_tile_groups": len(decoded),
        "represented_event_bits": manifest["represented_event_bits"],
        "reconstructed_event_bits": len(rx_events),
        "collapsed_repeated_events": manifest["collapsed_repeated_events"],
        "packet_integrity_errors": errors,
        "format_counts": dict(sorted(format_counts.items())),
        "output_words": len(words),
        "row_headers": headers,
        "words_per_reconstructed_event": (
            len(words) / len(rx_events) if rx_events else 0.0
        ),
        "input_wait_cycles_mean": mean(input_latency) if input_latency else 0.0,
        "input_wait_cycles_p99": percentile(input_latency, 0.99),
        "end_to_end_cycles_mean": mean(total_latency) if total_latency else 0.0,
        "end_to_end_cycles_p99": percentile(total_latency, 0.99),
        "end_to_end_cycles_max": max(total_latency, default=0),
        "last_receive_cycle": max((int(record["receive_cycle"]) for record in decoded), default=0),
    }


def load_fonts() -> tuple[ImageFont.FreeTypeFont, ImageFont.FreeTypeFont, ImageFont.FreeTypeFont]:
    font_root = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
    regular = font_root / "Pretendard-Regular.otf"
    semibold = font_root / "Pretendard-SemiBold.otf"
    fallback = Path("C:/Windows/Fonts/malgun.ttf")
    regular = regular if regular.exists() else fallback
    semibold = semibold if semibold.exists() else fallback
    return (
        ImageFont.truetype(str(semibold), 30),
        ImageFont.truetype(str(semibold), 20),
        ImageFont.truetype(str(regular), 16),
    )


def activity_image(
    events: list[tuple[int, int, int, int]], time_ns: int, trail_ns: int
) -> Image.Image:
    last_on = np.full((128, 128), -1, dtype=np.int64)
    last_off = np.full((128, 128), -1, dtype=np.int64)
    start = time_ns - trail_ns
    for event_ns, x, y, polarity in events:
        if event_ns > time_ns:
            break
        if event_ns < start:
            continue
        (last_on if polarity else last_off)[y, x] = event_ns

    background = np.array([14.0, 20.0, 32.0])
    on_color = np.array([46.0, 196.0, 255.0])
    off_color = np.array([255.0, 143.0, 64.0])
    rgb = np.broadcast_to(background, (128, 128, 3)).copy()
    for latest, color in ((last_on, on_color), (last_off, off_color)):
        active = latest >= 0
        alpha = np.zeros((128, 128), dtype=float)
        alpha[active] = np.exp(-(time_ns - latest[active]) / max(1.0, trail_ns * 0.45))
        rgb = rgb * (1.0 - alpha[..., None]) + color * alpha[..., None]
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), mode="RGB")


def render_frames(
    source_events: list[tuple[int, int, int, int]],
    rx_events: list[tuple[int, int, int, int]],
    summary: dict[str, object],
    output_dir: Path,
    frame_count: int,
    trail_ms: float,
) -> list[Path]:
    frames_dir = output_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    title_font, panel_font, body_font = load_fonts()
    duration_ns = max(
        source_events[-1][0] if source_events else 0,
        rx_events[-1][0] if rx_events else 0,
    )
    times = [round(duration_ns * index / max(1, frame_count - 1)) for index in range(frame_count)]
    source_times = [event[0] for event in source_events]
    rx_times = [event[0] for event in rx_events]
    timestamp_quantum_ms = (
        float(summary["playback_speed"]) * 1000 / int(summary["clock_hz"])
    )
    paths: list[Path] = []

    for frame_index, time_ns in enumerate(times):
        canvas = Image.new("RGB", (1200, 680), (245, 247, 251))
        draw = ImageDraw.Draw(canvas)
        external_timestamp = summary.get("timestamp_mode") == "external_link_first_word"
        title = (
            "원본 이벤트와 외부 링크 수신 시각"
            if external_timestamp
            else "원본 이벤트와 XSim 수신 패킷"
        )
        draw.text((48, 25), title, font=title_font, fill=(23, 34, 59))
        time_ms = time_ns / 1_000_000
        draw.text(
            (48, 69),
            f"원본 시간 {time_ms:7.2f} ms · 최근 {trail_ms:g} ms 활동",
            font=body_font,
            fill=(89, 101, 124),
        )

        source = activity_image(source_events, time_ns, round(trail_ms * 1_000_000))
        received = activity_image(rx_events, time_ns, round(trail_ms * 1_000_000))
        source = source.resize((512, 512), Image.Resampling.NEAREST)
        received = received.resize((512, 512), Image.Resampling.NEAREST)
        canvas.paste(source, (48, 126))
        canvas.paste(received, (640, 126))
        draw.text((48, 96), "AEDAT2 실제 입력 이벤트", font=panel_font, fill=(23, 34, 59))
        right_title = (
            f"패킷 첫 워드 수신 시각 · {timestamp_quantum_ms:g} ms 환산"
            if external_timestamp
            else f"XSim 수신 패킷 복호화 · {timestamp_quantum_ms:g} ms 정렬"
        )
        draw.text(
            (640, 96),
            right_title,
            font=panel_font,
            fill=(23, 34, 59),
        )

        source_count = bisect.bisect_right(source_times, time_ns)
        rx_count = bisect.bisect_right(rx_times, time_ns)
        draw.text(
            (48, 646),
            f"누적 원본 {source_count:,}개",
            font=body_font,
            fill=(89, 101, 124),
        )
        draw.text(
            (640, 646),
            f"누적 수신 {rx_count:,}개 · 파란색 ON · 주황색 OFF",
            font=body_font,
            fill=(89, 101, 124),
        )
        path = frames_dir / f"frame_{frame_index:03d}.png"
        canvas.save(path)
        paths.append(path)

    images = [Image.open(path) for path in paths]
    images[0].save(
        output_dir / "source_vs_aer.webp",
        save_all=True,
        append_images=images[1:],
        duration=100,
        loop=0,
        lossless=True,
        method=6,
    )
    for image in images:
        image.close()
    return paths


def write_html_fragment(
    path: Path,
    source_events: list[tuple[int, int, int, int]],
    rx_source_events: list[tuple[int, int, int, int]],
    input_hardware_events: list[tuple[int, int, int, int]],
    rx_receive_events: list[tuple[int, int, int, int]],
    compressed_groups: list[list[float | int | str]],
    summary: dict[str, object],
    trail_ms: float,
) -> None:
    source_js = [[round(t / 1_000_000, 3), x, y, p] for t, x, y, p in source_events]
    rx_source_js = [
        [round(t / 1_000_000, 3), x, y, p] for t, x, y, p in rx_source_events
    ]
    input_hardware_js = [
        [round(t / 1_000_000, 6), x, y, p] for t, x, y, p in input_hardware_events
    ]
    rx_receive_js = [
        [round(t / 1_000_000, 6), x, y, p] for t, x, y, p in rx_receive_events
    ]
    source_duration_ms = source_js[-1][0] if source_js else 0
    hardware_duration_ms = max(
        input_hardware_js[-1][0] if input_hardware_js else 0,
        rx_receive_js[-1][0] if rx_receive_js else 0,
    )
    source_quantum_ms = (
        float(summary["playback_speed"]) * 1000 / int(summary["clock_hz"])
    )
    hardware_trail_ms = max(0.001, min(0.02, hardware_duration_ms / 4))
    template = f'''<div id="aer-real-trace">
  <h2>원본 이벤트와 XSim 수신 패킷</h2>
  <div class="viz-controls">
    <button type="button" class="btn btn-primary" id="aer-play">일시정지</button>
    <label class="form-label" for="aer-timeline">비교 기준
      <select class="form-select" id="aer-timeline"><option value="source">원본 시간 · 검증용 정렬</option><option value="hardware">RTL 하드웨어 시간</option></select>
    </label>
    <label class="form-label" for="aer-time">시간 <span id="aer-time-label">0.00 ms</span></label>
    <input class="form-range" id="aer-time" type="range" min="0" max="{source_duration_ms:.3f}" step="0.05" value="0">
  </div>
  <div class="aer-panels">
    <section><h3 id="aer-source-title">AEDAT2 실제 입력 이벤트</h3><canvas id="aer-source" width="128" height="128" role="img" aria-label="시간에 따른 원본 ON OFF 이벤트"></canvas><p class="text-small text-muted" id="aer-source-count"></p></section>
    <section><h3 id="aer-rx-title">XSim 수신 패킷 복호화</h3><canvas id="aer-rx" width="128" height="128" role="img" aria-label="RTL을 거쳐 XSim 로그에서 복호화한 ON OFF 이벤트"></canvas><p class="text-small text-muted" id="aer-rx-count"></p></section>
  </div>
  <div class="viz-row text-small"><span>파란색 ON</span><span>주황색 OFF</span><span>보라색 GROUP3</span><span>초록색 BIN4</span><span id="aer-time-note">검증용 정렬 간격 {source_quantum_ms:g} ms · 패킷 시각 아님</span></div>
</div>
<style>
#aer-real-trace {{ width:100%; }}
#aer-real-trace .aer-panels {{ display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:20px; }}
#aer-real-trace section {{ min-width:0; }}
#aer-real-trace canvas {{ width:100%; height:auto; aspect-ratio:1; image-rendering:pixelated; background:var(--card); }}
#aer-real-trace .form-range {{ flex:1 1 280px; }}
@media (max-width:560px) {{ #aer-real-trace .aer-panels {{ grid-template-columns:1fr; }} }}
</style>
<script>
(() => {{
  const root = document.getElementById('aer-real-trace');
  const source = {json.dumps(source_js, separators=(',', ':'))};
  const sourceAligned = {json.dumps(rx_source_js, separators=(',', ':'))};
  const inputHardware = {json.dumps(input_hardware_js, separators=(',', ':'))};
  const receivedHardware = {json.dumps(rx_receive_js, separators=(',', ':'))};
  const compressed = {json.dumps(compressed_groups, separators=(',', ':'))};
  const sourceDuration = {source_duration_ms:.3f};
  const hardwareDuration = {hardware_duration_ms:.6f};
  const sourceTrail = {trail_ms:g};
  const hardwareTrail = {hardware_trail_ms:.6f};
  const range = root.querySelector('#aer-time');
  const timeline = root.querySelector('#aer-timeline');
  const label = root.querySelector('#aer-time-label');
  const play = root.querySelector('#aer-play');
  const sourceCanvas = root.querySelector('#aer-source');
  const rxCanvas = root.querySelector('#aer-rx');
  const styles = getComputedStyle(root);
  const background = styles.getPropertyValue('--card').trim();
  const onColor = styles.getPropertyValue('--viz-series-1').trim();
  const offColor = styles.getPropertyValue('--viz-series-2').trim();
  const groupColor = styles.getPropertyValue('--viz-series-3').trim();
  const binColor = styles.getPropertyValue('--viz-series-4').trim();
  let playing = true;
  let last = performance.now();

  function draw(canvas, events, time, activeTrail) {{
    const ctx = canvas.getContext('2d');
    ctx.globalAlpha = 1;
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, 128, 128);
    for (const event of events) {{
      if (event[0] > time) break;
      const age = time - event[0];
      if (age > activeTrail) continue;
      ctx.globalAlpha = Math.max(0.16, Math.exp(-age / (activeTrail * 0.45)));
      ctx.fillStyle = event[3] ? onColor : offColor;
      ctx.fillRect(event[1], event[2], 1, 1);
    }}
    ctx.globalAlpha = 1;
  }}
  function countAt(events, time) {{
    let lo = 0, hi = events.length;
    while (lo < hi) {{ const mid = (lo + hi) >> 1; if (events[mid][0] <= time) lo = mid + 1; else hi = mid; }}
    return lo;
  }}
  function drawCompressed(canvas, time, hardwareMode, activeTrail) {{
    const ctx = canvas.getContext('2d');
    let group3 = 0, bin4 = 0;
    for (const group of compressed) {{
      const stamp = hardwareMode ? group[1] : group[0];
      if (stamp > time || time - stamp > activeTrail) continue;
      const age = time - stamp;
      ctx.globalAlpha = Math.max(0.35, Math.exp(-age / (activeTrail * 0.45)));
      ctx.strokeStyle = group[4] === 'BIN4' ? binColor : groupColor;
      ctx.lineWidth = 0.7;
      ctx.strokeRect(group[2] - 0.25, group[3] - 0.25, 2.5, 2.5);
      if (group[4] === 'BIN4') bin4 += 1; else group3 += 1;
    }}
    ctx.globalAlpha = 1;
    return [group3, bin4];
  }}
  function update() {{
    const time = Number(range.value);
    const hardwareMode = timeline.value === 'hardware';
    const leftEvents = hardwareMode ? inputHardware : source;
    const received = hardwareMode ? receivedHardware : sourceAligned;
    const activeTrail = hardwareMode ? hardwareTrail : sourceTrail;
    draw(sourceCanvas, leftEvents, time, activeTrail);
    draw(rxCanvas, received, time, activeTrail);
    const compressedNow = drawCompressed(rxCanvas, time, hardwareMode, activeTrail);
    label.textContent = hardwareMode ? `${{(time * 1000).toFixed(1)}} μs` : `${{time.toFixed(2)}} ms`;
    root.querySelector('#aer-source-count').textContent = `${{hardwareMode ? '누적 타일 수락' : '누적 원본'}} ${{countAt(leftEvents,time).toLocaleString()}}개`;
    root.querySelector('#aer-rx-count').textContent = `누적 수신 ${{countAt(received,time).toLocaleString()}}개 · 현재 GROUP3 ${{compressedNow[0]}} · BIN4 ${{compressedNow[1]}}`;
    root.querySelector('#aer-source-title').textContent = hardwareMode ? 'RTL 입력 이벤트 수락' : 'AEDAT2 실제 입력 이벤트';
    root.querySelector('#aer-rx-title').textContent = hardwareMode ? 'RTL 링크 실제 수신 패킷' : 'XSim 수신 패킷 복호화';
    root.querySelector('#aer-time-note').textContent = hardwareMode ? `패킷 기록 시각 기준 · 최근 ${{(activeTrail * 1000).toFixed(1)}} μs 활동` : `검증용 정렬 간격 {source_quantum_ms:g} ms · 패킷 시각 아님`;
  }}
  function tick(now) {{
    if (playing) {{
      const duration = timeline.value === 'source' ? sourceDuration : hardwareDuration;
      const next = Number(range.value) + (now - last) * duration / 5000;
      range.value = next >= duration ? 0 : next;
      update();
    }}
    last = now;
    requestAnimationFrame(tick);
  }}
  play.addEventListener('click', () => {{ playing = !playing; play.textContent = playing ? '일시정지' : '재생'; }});
  timeline.addEventListener('change', () => {{
    const hardwareMode = timeline.value === 'hardware';
    range.max = hardwareMode ? hardwareDuration : sourceDuration;
    range.step = hardwareMode ? 0.0001 : 0.05;
    range.value = 0;
    update();
  }});
  range.addEventListener('input', update);
  update();
  requestAnimationFrame(tick);
}})();
</script>
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(template, encoding="utf-8")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest_json", type=Path)
    parser.add_argument("rtl_log", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--frames", type=int, default=36)
    parser.add_argument("--trail-ms", type=float, default=40.0)
    parser.add_argument("--html-fragment", type=Path)
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    manifest = json.loads(args.manifest_json.read_text(encoding="utf-8"))
    accepted, words = parse_rtl_log(args.rtl_log)
    decoded, errors, headers = decode_words(accepted, words)
    rx_source_events = reconstructed_events(
        decoded,
        int(manifest["clock_hz"]),
        float(manifest["playback_speed"]),
        "source_cycle",
    )
    input_hardware_events = reconstructed_events(
        decoded,
        int(manifest["clock_hz"]),
        1.0,
        "accept_cycle",
    )
    rx_receive_events = reconstructed_events(
        decoded,
        int(manifest["clock_hz"]),
        1.0,
        "receive_cycle",
    )
    source_events = [
        (int(event[0]), int(event[1]), int(event[2]), int(event[3]))
        for event in manifest["events"]
    ]
    summary = build_summary(
        manifest, accepted, words, decoded, errors, headers, rx_source_events
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (args.output_dir / "reconstructed_events.json").write_text(
        json.dumps(
            {
                "source_aligned": rx_source_events,
                "receive_timeline": rx_receive_events,
            },
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )
    render_frames(
        source_events,
        rx_source_events,
        summary,
        args.output_dir,
        frame_count=args.frames,
        trail_ms=args.trail_ms,
    )
    if args.html_fragment:
        compressed_groups: list[list[float | int | str]] = []
        for group in decoded:
            if group["format"] == "RAW8":
                continue
            x, y = tile_pixel(int(group["tile"]), 0)
            source_ms = (
                int(group["source_cycle"])
                * float(manifest["playback_speed"])
                * 1000
                / int(manifest["clock_hz"])
            )
            receive_ms = (
                int(group["receive_cycle"])
                * 1000
                / int(manifest["clock_hz"])
            )
            compressed_groups.append(
                [round(source_ms, 3), round(receive_ms, 3), x, y, str(group["format"])]
            )
        write_html_fragment(
            args.html_fragment,
            source_events,
            rx_source_events,
            input_hardware_events,
            rx_receive_events,
            compressed_groups,
            summary,
            args.trail_ms,
        )
    print(
        "V1_UZH_RECONSTRUCTION "
        f"groups={len(decoded)} events={len(rx_source_events)} "
        f"errors={len(errors)} mean_latency={summary['end_to_end_cycles_mean']:.2f}"
    )
    if errors:
        raise SystemExit("RTL packet integrity validation failed")


if __name__ == "__main__":
    main()
