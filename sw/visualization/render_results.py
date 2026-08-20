"""Generate dependency-light PNG and GIF artifacts with Pillow."""

from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont

from sw.dataset.canonical_trace import TileTransaction


DESIGN_LABELS = {
    "raw_baseline": "Fair RAW",
    "team_second": "Team BIN/GROUP",
    "current_adaptive": "Current ROW/BANK",
}
DESIGN_COLORS = {
    "raw_baseline": (55, 126, 184),
    "team_second": (77, 175, 74),
    "current_adaptive": (228, 26, 28),
}


def _font(size: int) -> ImageFont.ImageFont:
    path = Path(r"C:\Windows\Fonts\arial.ttf")
    if path.exists():
        return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def _tile_origin(tile_id: int) -> tuple[int, int]:
    bank = tile_id // 16
    local = tile_id % 16
    tile_x = (bank % 16) * 4 + (local % 4)
    tile_y = (bank // 16) * 4 + (local // 4)
    return tile_x * 2, tile_y * 2


def _event_image(records: Iterable[tuple[int, int, int]], scale: int = 4) -> Image.Image:
    pixels = [[0, 0] for _ in range(128 * 128)]
    for tile_id, on, off in records:
        origin_x, origin_y = _tile_origin(tile_id)
        for bit in range(4):
            x = origin_x + bit % 2
            y = origin_y + bit // 2
            index = y * 128 + x
            if on & (1 << bit):
                pixels[index][0] += 1
            if off & (1 << bit):
                pixels[index][1] += 1
    maximum = max((max(value) for value in pixels), default=1) or 1
    image = Image.new("RGB", (128, 128), (4, 5, 10))
    target = image.load()
    for y in range(128):
        for x in range(128):
            on, off = pixels[y * 128 + x]
            target[x, y] = (
                min(255, int(255 * on / maximum)),
                min(255, int(220 * (on + off) / (2 * maximum))),
                min(255, int(255 * off / maximum)),
            )
    return image.resize((128 * scale, 128 * scale), Image.Resampling.NEAREST)


def render_event_comparison(
    path: Path,
    transactions: list[TileTransaction],
    accepted: dict[str, list[tuple[int, int, int, int, int]]],
    window: tuple[int, int],
) -> None:
    start, length = window
    original = [
        (record.tile_id, record.on, record.off)
        for record in transactions
        if start <= record.cycle < start + length
    ]
    panels = [("Original canonical input", _event_image(original))]
    for design in ("raw_baseline", "team_second", "current_adaptive"):
        records = [
            (tile, on, off)
            for tile, on, off, _timestamp, cycle in accepted[design]
            if start <= cycle < start + length
        ]
        panels.append((f"{DESIGN_LABELS[design]} accepted", _event_image(records)))

    canvas = Image.new("RGB", (1080, 1220), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 15), "UZH shapes_rotation — dense window event preservation", fill="black", font=_font(28))
    draw.text((24, 52), "Red=ON, blue=OFF, white=mixed; sensor coordinates x→, y↓", fill=(50, 50, 50), font=_font(18))
    for index, (label, panel) in enumerate(panels):
        x = 18 + (index % 2) * 535
        y = 90 + (index // 2) * 560
        canvas.paste(panel, (x, y + 30))
        draw.text((x, y), label, fill="black", font=_font(21))
        draw.rectangle((x, y + 30, x + 512, y + 542), outline=(60, 60, 60), width=1)
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def render_performance(path: Path, results: list[dict[str, object]]) -> None:
    metrics = [
        ("words_per_accepted_event", "Words / accepted event"),
        ("mean_latency_cycles", "Mean latency (cycles)"),
        ("p99_latency_cycles", "P99 latency (cycles)"),
        ("throughput_events_per_cycle", "Throughput (events/cycle)"),
        ("backpressure_fraction", "Backpressured event fraction"),
        ("bank_mode_fraction", "BANK packet fraction"),
    ]
    speeds = sorted({float(str(row["traffic_condition"]).rstrip("x")) for row in results})
    canvas = Image.new("RGB", (1500, 980), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((35, 18), "UZH shapes_rotation — common 16-bit-link software comparison", fill="black", font=_font(30))
    for design, color in DESIGN_COLORS.items():
        x = 420 + list(DESIGN_COLORS).index(design) * 300
        draw.line((x, 70, x + 34, 70), fill=color, width=5)
        draw.text((x + 42, 59), DESIGN_LABELS[design], fill=color, font=_font(17))

    for metric_index, (metric, title) in enumerate(metrics):
        left = 55 + (metric_index % 3) * 490
        top = 110 + (metric_index // 3) * 410
        width, height = 420, 315
        values: dict[str, list[float]] = {design: [] for design in DESIGN_LABELS}
        for design in DESIGN_LABELS:
            for speed in speeds:
                row = next(
                    item
                    for item in results
                    if item["design"] == design
                    and float(str(item["traffic_condition"]).rstrip("x")) == speed
                )
                if metric == "backpressure_fraction":
                    denominator = float(row["input_events"])
                    value = float(row["backpressured_events"]) / denominator if denominator else 0.0
                else:
                    value = float(row[metric])
                values[design].append(value)
        maximum = max(max(series) for series in values.values()) or 1.0
        minimum = 0.0
        draw.text((left, top), title, fill="black", font=_font(19))
        chart_top = top + 32
        chart_bottom = chart_top + height
        draw.line((left, chart_top, left, chart_bottom), fill=(80, 80, 80), width=1)
        draw.line((left, chart_bottom, left + width, chart_bottom), fill=(80, 80, 80), width=1)
        draw.text((left - 4, chart_top - 18), f"{maximum:.3g}", fill=(70, 70, 70), font=_font(13))
        for speed_index, speed in enumerate(speeds):
            x = left + int(speed_index * width / max(1, len(speeds) - 1))
            draw.text((x - 18, chart_bottom + 7), f"{speed:g}x", fill=(70, 70, 70), font=_font(12))
        for design, series in values.items():
            points = []
            for index, value in enumerate(series):
                x = left + int(index * width / max(1, len(series) - 1))
                y = chart_bottom - int((value - minimum) / (maximum - minimum) * height)
                points.append((x, y))
            draw.line(points, fill=DESIGN_COLORS[design], width=4)
            for point in points:
                draw.ellipse((point[0] - 3, point[1] - 3, point[0] + 3, point[1] + 3), fill=DESIGN_COLORS[design])
    draw.text((600, 945), "Playback acceleration (100 MHz clock)", fill=(40, 40, 40), font=_font(18))
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def render_activity_mode_map(
    path: Path, transactions: list[TileTransaction], window: tuple[int, int]
) -> None:
    start, length = window
    bank_counts = [0] * 256
    row_sets: dict[tuple[int, int], set[int]] = defaultdict(set)
    for record in transactions:
        if start <= record.cycle < start + length:
            bank = record.tile_id // 16
            bank_counts[bank] += record.canonical_event_count
            row_sets[(bank, record.cycle)].add((record.tile_id % 16) // 4)
    opportunities = [0] * 256
    for (bank, _cycle), rows in row_sets.items():
        if len(rows) >= 2:
            opportunities[bank] += 1
    max_count = max(bank_counts) or 1
    max_opportunity = max(opportunities) or 1
    canvas = Image.new("RGB", (900, 470), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((25, 15), "Dense-window bank activity and same-cycle multi-row opportunity", fill="black", font=_font(24))
    for panel, (values, maximum, title) in enumerate(
        ((bank_counts, max_count, "Canonical event activity"), (opportunities, max_opportunity, "Multi-row opportunity cycles"))
    ):
        origin_x = 35 + panel * 440
        origin_y = 85
        draw.text((origin_x, 58), title, fill="black", font=_font(18))
        for bank in range(256):
            x = bank % 16
            y = bank // 16
            intensity = int(255 * values[bank] / maximum)
            color = (intensity, 30, 255 - intensity) if panel == 0 else (255, 180 - intensity // 2, 20)
            box = (origin_x + x * 24, origin_y + y * 22, origin_x + x * 24 + 22, origin_y + y * 22 + 20)
            draw.rectangle(box, fill=color)
        draw.text((origin_x, 445), "bank_col →; bank_row ↓", fill=(60, 60, 60), font=_font(14))
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def render_animation(
    path: Path,
    transactions: list[TileTransaction],
    current_accepted: list[tuple[int, int, int, int, int]],
    window: tuple[int, int],
    frames: int = 24,
) -> None:
    start, length = window
    frame_span = max(1, length // frames)
    images: list[Image.Image] = []
    for frame in range(frames):
        frame_start = start + frame * frame_span
        frame_end = start + length if frame == frames - 1 else frame_start + frame_span
        original = [
            (record.tile_id, record.on, record.off)
            for record in transactions
            if frame_start <= record.cycle < frame_end
        ]
        decoded = [
            (tile, on, off)
            for tile, on, off, _timestamp, cycle in current_accepted
            if frame_start <= cycle < frame_end
        ]
        left = _event_image(original, scale=3)
        right = _event_image(decoded, scale=3)
        canvas = Image.new("RGB", (800, 440), "white")
        draw = ImageDraw.Draw(canvas)
        draw.text((18, 10), f"Original input — frame {frame + 1}/{frames}", fill="black", font=_font(19))
        draw.text((420, 10), "Current accepted/decoded", fill="black", font=_font(19))
        canvas.paste(left, (10, 42))
        canvas.paste(right, (410, 42))
        draw.text((240, 425), "Red=ON  Blue=OFF  x→  y↓", fill=(40, 40, 40), font=_font(15))
        images.append(canvas)
    path.parent.mkdir(parents=True, exist_ok=True)
    images[0].save(path, save_all=True, append_images=images[1:], duration=140, loop=0, optimize=False)
