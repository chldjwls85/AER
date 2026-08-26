"""Compare bank fusion, row fusion, adaptive packing, and RAW8."""

from __future__ import annotations

import argparse
import bisect
import hashlib
import json
from collections import Counter
from pathlib import Path
from statistics import mean

from PIL import Image, ImageDraw

from sw.render_v1_frequency_compare import load_case, sample_evenly
from sw.render_v1_uzh_reconstruction import (
    activity_image,
    load_fonts,
    parse_rtl_log,
    percentile,
)


CASE_NAMES = (
    "bankfusion100",
    "rowfusion100",
    "adaptive100",
    "raw100",
    "bankfusion200",
    "rowfusion200",
    "adaptive200",
    "raw200",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def link_format_stats(words: list[tuple[int, int, int]]) -> dict[str, int]:
    phase = 0  # 0=header, 1=row data, 2=bank mask, 3=bank payload
    remaining = 0
    row_headers = 0
    row_bin4_words = 0
    row_group3_words = 0
    row_bin4_groups = 0
    row_group3_groups = 0
    row_words_saved = 0
    bank_packets = 0
    bank_tiles = 0
    bank_payload_words = 0
    bank_words_saved = 0
    bank_mode = 0
    bank_count = 0
    bank_payload_remaining = 0
    bank_mask = 0
    bank_mode_packets = Counter()
    bank_mode_tiles = Counter()
    for receive_cycle, word, last in words:
        if phase == 0:
            packet_type = word >> 14
            if packet_type == 0x2:
                bank_mode = (word >> 4) & 0x3
                bank_count = (word & 0xF) + 1
                if bank_mode not in (0, 1, 2):
                    raise ValueError(f"reserved bank mode at cycle {receive_cycle}")
                bank_packets += 1
                bank_tiles += bank_count
                bank_mode_packets[bank_mode] += 1
                bank_mode_tiles[bank_mode] += bank_count
                if last:
                    raise ValueError(f"bank header asserted out_last at cycle {receive_cycle}")
                phase = 2
                continue
            if packet_type != 0x3:
                raise ValueError(f"header expected at cycle {receive_cycle}")
            remaining = (word & 0xF).bit_count()
            row_headers += 1
            if remaining == 0:
                raise ValueError(f"empty header at cycle {receive_cycle}")
            phase = 1
            continue

        if phase == 1:
            format_code = (word >> 14) & 0x3
            if format_code == 3:
                groups = remaining
                if (word >> 13) & 1:
                    row_group3_words += 1
                    row_group3_groups += groups
                    row_words_saved += max(0, groups - 1)
                else:
                    row_bin4_words += 1
                    row_bin4_groups += groups
                    row_words_saved += max(0, (groups + 1) // 2 - 1)
                remaining = 0
            elif format_code == 2 and ((word >> 13) & 1):
                remaining -= 2
            else:
                remaining -= 1
            if remaining < 0:
                raise ValueError(f"row packet underflow at cycle {receive_cycle}")
            if bool(last) != (remaining == 0):
                raise ValueError(f"row out_last mismatch at cycle {receive_cycle}")
            if remaining == 0:
                phase = 0
            continue

        if phase == 2:
            bank_mask = word
            if bank_mask.bit_count() != bank_count:
                raise ValueError(f"bank mask mismatch at cycle {receive_cycle}")
            if last:
                raise ValueError(f"bank mask asserted out_last at cycle {receive_cycle}")
            if bank_mode == 0:
                bank_payload_remaining = (bank_count + 1) // 2
            elif bank_mode == 1:
                bank_payload_remaining = (bank_count * 3 + 15) // 16
            else:
                bank_payload_remaining = 1
            bank_payload_words += bank_payload_remaining

            row_cost = 0
            for row in range(4):
                row_count = ((bank_mask >> (row * 4)) & 0xF).bit_count()
                if not row_count:
                    continue
                row_cost += 1
                row_cost += (row_count + 1) // 2 if bank_mode == 2 else row_count
            bank_words_saved += row_cost - (2 + bank_payload_remaining)
            phase = 3
            continue

        bank_payload_remaining -= 1
        if bank_payload_remaining < 0:
            raise ValueError(f"bank packet underflow at cycle {receive_cycle}")
        if bool(last) != (bank_payload_remaining == 0):
            raise ValueError(f"bank out_last mismatch at cycle {receive_cycle}")
        if bank_payload_remaining == 0:
            phase = 0

    if phase != 0:
        raise ValueError("truncated packet")
    return {
        "packet_headers": row_headers + bank_packets,
        "row_headers": row_headers,
        "row_bin4_words": row_bin4_words,
        "row_group3_words": row_group3_words,
        "row_fusion_words": row_bin4_words + row_group3_words,
        "row_bin4_groups": row_bin4_groups,
        "row_group3_groups": row_group3_groups,
        "row_fusion_groups": row_bin4_groups + row_group3_groups,
        "row_words_saved": row_words_saved,
        "bank_packets": bank_packets,
        "bank_tiles": bank_tiles,
        "bank_payload_words": bank_payload_words,
        "bank_words_saved": bank_words_saved,
        "bank_raw8_packets": bank_mode_packets[0],
        "bank_group3_packets": bank_mode_packets[1],
        "bank_bin4_packets": bank_mode_packets[2],
        "bank_raw8_tiles": bank_mode_tiles[0],
        "bank_group3_tiles": bank_mode_tiles[1],
        "bank_bin4_tiles": bank_mode_tiles[2],
    }


def case_metrics(case: dict[str, object]) -> dict[str, object]:
    pending = case["pending"]
    decoded = case["decoded"]
    words = case["words"]
    assert isinstance(pending, dict)
    assert isinstance(decoded, list)
    assert isinstance(words, list)
    formats = Counter(str(record["format"]) for record in decoded)
    latency = [
        int(record["rx_timestamp_cycle"]) - int(record["accept_cycle"])
        for record in decoded
    ]
    received_events = len(case["rx_events"])
    link = link_format_stats(words)
    return {
        "accepted_events": int(pending["pixel_accepted_events"]),
        "readout_events": int(pending["pixel_readout_events"]),
        "loss_events": int(pending["pixel_ignored_events"])
        + int(pending["same_cycle_duplicate_events"]),
        "loss_percent": float(case["loss_percent"]),
        "tile_groups": int(pending["decoded_tile_groups"]),
        "output_words": int(case["output_words"]),
        "words_per_event": int(case["output_words"]) / max(1, received_events),
        "format_counts": dict(sorted(formats.items())),
        "tile_accept_to_rx_mean_cycles": mean(latency) if latency else 0.0,
        "tile_accept_to_rx_p99_cycles": percentile(latency, 0.99),
        "tile_accept_to_rx_max_cycles": max(latency, default=0),
        **link,
    }


def render_frames(
    source_events: list[tuple[int, int, int, int]],
    cases: dict[str, dict[str, object]],
    output_dir: Path,
    frame_count: int,
    trail_ms: float,
) -> list[Path]:
    frames_dir = output_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    title_font, panel_font, body_font = load_fonts()
    duration_ns = max(
        source_events[-1][0],
        *(case["rx_events"][-1][0] for case in cases.values()),
    )
    times = [
        round(duration_ns * index / max(1, frame_count - 1))
        for index in range(frame_count)
    ]
    panels = (
        ("100MHz 원본", source_events),
        (f"뱅크 융합 · 손실 {cases['bankfusion100']['loss_percent']:.2f}%", cases["bankfusion100"]["rx_events"]),
        (f"행 융합 · 손실 {cases['rowfusion100']['loss_percent']:.2f}%", cases["rowfusion100"]["rx_events"]),
        (f"기존 비닝 · 손실 {cases['adaptive100']['loss_percent']:.2f}%", cases["adaptive100"]["rx_events"]),
        (f"RAW8 · 손실 {cases['raw100']['loss_percent']:.2f}%", cases["raw100"]["rx_events"]),
        ("200MHz 원본", source_events),
        (f"뱅크 융합 · 손실 {cases['bankfusion200']['loss_percent']:.2f}%", cases["bankfusion200"]["rx_events"]),
        (f"행 융합 · 손실 {cases['rowfusion200']['loss_percent']:.2f}%", cases["rowfusion200"]["rx_events"]),
        (f"기존 비닝 · 손실 {cases['adaptive200']['loss_percent']:.2f}%", cases["adaptive200"]["rx_events"]),
        (f"RAW8 · 손실 {cases['raw200']['loss_percent']:.2f}%", cases["raw200"]["rx_events"]),
    )
    positions = tuple(
        (28 + column * 440, 122 + row * 500)
        for row in range(2)
        for column in range(5)
    )
    event_times = [[event[0] for event in events] for _, events in panels]
    paths: list[Path] = []
    for frame_index, time_ns in enumerate(times):
        canvas = Image.new("RGB", (2200, 1080), (245, 247, 251))
        draw = ImageDraw.Draw(canvas)
        draw.text((32, 20), "Peak 1 GEPS · 뱅크 융합 / 행 융합 / 기존 비닝 / RAW8", font=title_font, fill=(23, 34, 59))
        draw.text(
            (32, 65),
            f"원본 환산 {time_ns / 1_000_000:7.2f} ms · 최근 {trail_ms:g} ms 활동",
            font=body_font,
            fill=(89, 101, 124),
        )
        for index, ((label, events), (x, y)) in enumerate(zip(panels, positions, strict=True)):
            draw.text((x, y - 30), label, font=panel_font, fill=(23, 34, 59))
            image = activity_image(events, time_ns, round(trail_ms * 1_000_000))
            canvas.paste(image.resize((396, 396), Image.Resampling.NEAREST), (x, y))
            count = bisect.bisect_right(event_times[index], time_ns)
            draw.text((x, y + 401), f"누적 {count:,}개", font=body_font, fill=(89, 101, 124))
        path = frames_dir / f"frame_{frame_index:03d}.png"
        canvas.save(path)
        paths.append(path)

    images = [Image.open(path) for path in paths]
    images[0].save(
        output_dir / "peak1geps_bank_fusion_compare.webp",
        save_all=True,
        append_images=images[1:],
        duration=130,
        loop=0,
        lossless=True,
        method=6,
    )
    for image in images:
        image.close()
    return paths


def write_fragment(
    path: Path,
    source_events: list[tuple[int, int, int, int]],
    cases: dict[str, dict[str, object]],
    metrics: dict[str, dict[str, object]],
) -> None:
    source_full = [[round(t / 1_000_000, 3), x, y, p] for t, x, y, p in source_events]

    def groups(case: dict[str, object]) -> list[list[float | int]]:
        manifest = case["manifest"]
        decoded = case["decoded"]
        assert isinstance(manifest, dict) and isinstance(decoded, list)
        clock_hz = int(manifest["clock_hz"])
        playback = float(manifest["playback_speed"])
        return [
            [
                round(int(record["rx_timestamp_cycle"]) * playback * 1000 / clock_hz, 3),
                int(record["tile"]),
                int(record["on"]),
                int(record["off"]),
            ]
            for record in decoded
        ]

    source = sample_evenly(source_full, 3_500)
    group_full = {name: groups(case) for name, case in cases.items()}
    group_sample = {name: sample_evenly(records, 3_500) for name, records in group_full.items()}
    max_time = max(source_full[-1][0], *(records[-1][0] for records in group_full.values()))

    labels = {
        "bankfusion100": "100MHz 뱅크 융합",
        "rowfusion100": "100MHz 행 융합",
        "adaptive100": "100MHz 기존 비닝",
        "raw100": "100MHz RAW8",
        "bankfusion200": "200MHz 뱅크 융합",
        "rowfusion200": "200MHz 행 융합",
        "adaptive200": "200MHz 기존 비닝",
        "raw200": "200MHz RAW8",
    }
    panel_order = (
        ("source100", "100MHz 원본"),
        ("bankfusion100", labels["bankfusion100"]),
        ("rowfusion100", labels["rowfusion100"]),
        ("adaptive100", labels["adaptive100"]),
        ("raw100", labels["raw100"]),
        ("source200", "200MHz 원본"),
        ("bankfusion200", labels["bankfusion200"]),
        ("rowfusion200", labels["rowfusion200"]),
        ("adaptive200", labels["adaptive200"]),
        ("raw200", labels["raw200"]),
    )
    panels_html = []
    for name, label in panel_order:
        suffix = "" if name.startswith("source") else f" · 손실 {metrics[name]['loss_percent']:.2f}%"
        panels_html.append(
            f'<section><h3>{label}{suffix}</h3><canvas id="aer-rf-{name}" width="128" height="128" role="img" aria-label="{label} 이벤트"></canvas></section>'
        )
    rows = []
    for name in CASE_NAMES:
        bank_packets = int(metrics[name]["bank_packets"])
        bank_value = "-" if bank_packets == 0 else f"{bank_packets:,}개"
        rows.append(
            f'<tr><td>{labels[name]}</td><td class="text-end">{metrics[name]["accepted_events"]:,}</td>'
            f'<td class="text-end">{metrics[name]["loss_percent"]:.3f}%</td>'
            f'<td class="text-end">{metrics[name]["output_words"]:,}</td>'
            f'<td class="text-end">{metrics[name]["words_per_event"]:.4f}</td>'
            f'<td class="text-end">{metrics[name]["tile_accept_to_rx_mean_cycles"]:.0f} clk</td>'
            f'<td class="text-end">{bank_value}</td></tr>'
        )

    fragment = f'''<div id="aer-bank-fusion-compare">
  <h2>Peak 1 GEPS · 뱅크 내부 묶음 전송 비교</h2>
  <div class="viz-controls">
    <button type="button" class="btn btn-primary" id="aer-bf-play">일시정지</button>
    <label class="form-label" for="aer-bf-trail">표시 구간
      <select class="form-select" id="aer-bf-trail"><option value="20">최근 20 ms</option><option value="80" selected>최근 80 ms</option><option value="0">누적</option></select>
    </label>
    <label class="form-label" for="aer-bf-range">원본 환산 시간 <span id="aer-bf-time">0.00 ms</span></label>
    <input class="form-range" id="aer-bf-range" type="range" min="0" max="{max_time:.3f}" step="0.05" value="0">
  </div>
  <div class="aer-bf-grid">{''.join(panels_html)}</div>
  <div class="table-responsive">
    <table class="table table-sm">
      <thead><tr><th>조건</th><th class="text-end">수신 이벤트</th><th class="text-end">손실률</th><th class="text-end">출력 워드</th><th class="text-end">워드/이벤트</th><th class="text-end">평균 지연</th><th class="text-end">뱅크 패킷</th></tr></thead>
      <tbody>{''.join(rows)}</tbody>
    </table>
  </div>
  <div class="viz-row text-small" id="aer-bf-counts" aria-live="polite"></div>
  <div class="viz-row text-small"><span>파란색 ON</span><span>주황색 OFF</span><span>모든 구조에 같은 입력·중재·16비트 링크 사용</span></div>
</div>
<style>
#aer-bank-fusion-compare {{ width:100%; }}
#aer-bank-fusion-compare .aer-bf-grid {{ display:grid; grid-template-columns:repeat(5,minmax(0,1fr)); gap:12px; }}
#aer-bank-fusion-compare section {{ min-width:0; }}
#aer-bank-fusion-compare canvas {{ display:block; width:100%; height:auto; aspect-ratio:1; image-rendering:pixelated; background:var(--card); }}
#aer-bank-fusion-compare .form-range {{ flex:1 1 280px; }}
@media (max-width:1000px) {{ #aer-bank-fusion-compare .aer-bf-grid {{ grid-template-columns:repeat(2,minmax(0,1fr)); }} }}
@media (max-width:480px) {{ #aer-bank-fusion-compare .aer-bf-grid {{ grid-template-columns:1fr; }} }}
</style>
<script>
(() => {{
  const root = document.getElementById('aer-bank-fusion-compare');
  const source = {json.dumps(source, separators=(',', ':'))};
  const groups = {json.dumps(group_sample, separators=(',', ':'))};
  const maxTime = {max_time:.3f};
  const range = root.querySelector('#aer-bf-range'), trail = root.querySelector('#aer-bf-trail'), play = root.querySelector('#aer-bf-play');
  let playing = true, last = performance.now();
  function color(token) {{ const probe=document.createElement('span');probe.style.color=`var(${{token}})`;probe.style.display='none';root.appendChild(probe);const value=getComputedStyle(probe).color;probe.remove();return value; }}
  const background=color('--card'),onColor=color('--viz-series-1'),offColor=color('--viz-series-2');
  function upperBound(records,time) {{ let lo=0,hi=records.length;while(lo<hi){{const mid=(lo+hi)>>1;if(records[mid][0]<=time)lo=mid+1;else hi=mid;}}return lo; }}
  function tilePixel(tile,bit) {{ const bank=Math.floor(tile/16),local=tile%16,br=Math.floor(bank/16),bc=bank%16,lr=Math.floor(local/4),lc=local%4;return[(bc*4+lc)*2+(bit&1),(br*4+lr)*2+((bit>>1)&1)]; }}
  function clear(id) {{ const ctx=root.querySelector(id).getContext('2d');ctx.globalAlpha=1;ctx.fillStyle=background;ctx.fillRect(0,0,128,128);return ctx; }}
  function alpha(age,horizon) {{ return horizon===0?1:Math.max(0.15,Math.exp(-age/Math.max(1,horizon*0.42))); }}
  function drawSource(id,time,horizon) {{ const ctx=clear(id),end=upperBound(source,time);for(let i=0;i<end;i++){{const e=source[i],age=time-e[0];if(horizon&&age>horizon)continue;ctx.globalAlpha=alpha(age,horizon);ctx.fillStyle=e[3]?onColor:offColor;ctx.fillRect(e[1],e[2],1,1);}}ctx.globalAlpha=1;return end; }}
  function drawGroups(id,records,time,horizon) {{ const ctx=clear(id),end=upperBound(records,time);for(let i=0;i<end;i++){{const g=records[i],age=time-g[0];if(horizon&&age>horizon)continue;ctx.globalAlpha=alpha(age,horizon);for(const pair of [[1,g[2]],[0,g[3]]]){{ctx.fillStyle=pair[0]?onColor:offColor;for(let bit=0;bit<4;bit++)if(pair[1]&(1<<bit)){{const p=tilePixel(g[1],bit);ctx.fillRect(p[0],p[1],1,1);}}}}}}ctx.globalAlpha=1;return end; }}
  function update() {{ const time=Number(range.value),horizon=Number(trail.value);const sourceCount=drawSource('#aer-rf-source100',time,horizon);drawSource('#aer-rf-source200',time,horizon);const counts={{}};for(const name of {json.dumps(list(CASE_NAMES))})counts[name]=drawGroups(`#aer-rf-${{name}}`,groups[name],time,horizon);root.querySelector('#aer-bf-time').textContent=`${{time.toFixed(2)}} ms`;root.querySelector('#aer-bf-counts').textContent=`표시 표본 · 원본 ${{sourceCount.toLocaleString()}}/${{source.length.toLocaleString()}} · 100MHz 뱅크/행/기존/RAW ${{counts.bankfusion100.toLocaleString()}}/${{counts.rowfusion100.toLocaleString()}}/${{counts.adaptive100.toLocaleString()}}/${{counts.raw100.toLocaleString()}} · 200MHz 뱅크/행/기존/RAW ${{counts.bankfusion200.toLocaleString()}}/${{counts.rowfusion200.toLocaleString()}}/${{counts.adaptive200.toLocaleString()}}/${{counts.raw200.toLocaleString()}}`; }}
  play.addEventListener('click',()=>{{playing=!playing;play.textContent=playing?'일시정지':'재생';}});range.addEventListener('input',()=>{{playing=false;play.textContent='재생';update();}});trail.addEventListener('change',update);
  function tick(now) {{ if(playing){{const next=Number(range.value)+(now-last)*maxTime/7500;range.value=next>=maxTime?0:next;update();}}last=now;requestAnimationFrame(tick); }}
  update();requestAnimationFrame(tick);
}})();
</script>
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(fragment, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in CASE_NAMES:
        parser.add_argument(f"manifest_{name}", type=Path)
        parser.add_argument(f"log_{name}", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--html-fragment", type=Path)
    parser.add_argument("--frames", type=int, default=48)
    parser.add_argument("--trail-ms", type=float, default=80.0)
    args = parser.parse_args()

    cases = {
        name: load_case(getattr(args, f"manifest_{name}"), getattr(args, f"log_{name}"))
        for name in CASE_NAMES
    }
    for name in CASE_NAMES:
        _, words = parse_rtl_log(getattr(args, f"log_{name}"))
        cases[name]["words"] = words
    source_manifest = cases["bankfusion100"]["manifest"]
    assert isinstance(source_manifest, dict)
    source_events = [
        (int(event[0]), int(event[1]), int(event[2]), int(event[3]))
        for event in source_manifest["events"]
    ]
    input_hashes = {
        name: sha256(getattr(args, f"manifest_{name}").with_name("pixel_vectors.txt"))
        for name in CASE_NAMES
    }
    if len({input_hashes[name] for name in CASE_NAMES[:4]}) != 1:
        raise ValueError("100MHz input vectors differ")
    if len({input_hashes[name] for name in CASE_NAMES[4:]}) != 1:
        raise ValueError("200MHz input vectors differ")
    metrics = {name: case_metrics(case) for name, case in cases.items()}
    comparison = {
        "source_events": len(source_events),
        "peak_definition": "1 ms sliding-window peak = 1 GEPS",
        "pixel_fifo_depth": 2,
        "input_sha256": input_hashes,
        "cases": metrics,
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "summary.json").write_text(
        json.dumps(comparison, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    if args.frames > 0:
        render_frames(source_events, cases, args.output_dir, args.frames, args.trail_ms)
    if args.html_fragment:
        write_fragment(args.html_fragment, source_events, cases, metrics)
    print(
        "V1_BANK_FUSION_COMPARE_DONE "
        f"loss100={metrics['bankfusion100']['loss_percent']:.3f}/"
        f"{metrics['rowfusion100']['loss_percent']:.3f}/"
        f"{metrics['adaptive100']['loss_percent']:.3f}/"
        f"{metrics['raw100']['loss_percent']:.3f} "
        f"loss200={metrics['bankfusion200']['loss_percent']:.3f}/"
        f"{metrics['rowfusion200']['loss_percent']:.3f}/"
        f"{metrics['adaptive200']['loss_percent']:.3f}/"
        f"{metrics['raw200']['loss_percent']:.3f}"
    )


if __name__ == "__main__":
    main()
