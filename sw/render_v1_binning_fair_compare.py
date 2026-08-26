"""Render fair RAW8 versus adaptive AER comparisons at 100 and 200 MHz."""

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
from sw.render_v1_uzh_reconstruction import activity_image, load_fonts, percentile


def case_metrics(case: dict[str, object]) -> dict[str, object]:
    pending = case["pending"]
    assert isinstance(pending, dict)
    received = len(case["rx_events"])
    decoded = case["decoded"]
    assert isinstance(decoded, list)
    manifest = case["manifest"]
    assert isinstance(manifest, dict)
    format_counts = Counter(str(record["format"]) for record in decoded)
    tile_to_rx = [
        int(record["rx_timestamp_cycle"]) - int(record["accept_cycle"])
        for record in decoded
    ]
    source_last_cycle = max((int(event[4]) for event in manifest["events"]), default=0)
    last_receive_cycle = max(
        (int(record["receive_cycle"]) for record in decoded), default=0
    )
    row_headers = int(case["row_headers"])
    data_words = int(case["output_words"]) - row_headers
    paired_bin4_words = max(0, int(pending["decoded_tile_groups"]) - data_words)
    paired_bin4_groups = 2 * paired_bin4_words
    bin4_groups = format_counts.get("BIN4", 0)
    return {
        "accepted_events": pending["pixel_accepted_events"],
        "readout_events": pending["pixel_readout_events"],
        "loss_events": pending["pixel_ignored_events"]
        + pending["same_cycle_duplicate_events"],
        "loss_percent": case["loss_percent"],
        "tile_groups": pending["decoded_tile_groups"],
        "output_words": case["output_words"],
        "row_headers": row_headers,
        "words_per_event": case["output_words"] / max(1, received),
        "format_counts": dict(sorted(format_counts.items())),
        "paired_bin4_words": paired_bin4_words,
        "paired_bin4_groups": paired_bin4_groups,
        "paired_bin4_percent": 100.0 * paired_bin4_groups / max(1, bin4_groups),
        "tile_accept_to_rx_mean_cycles": mean(tile_to_rx) if tile_to_rx else 0.0,
        "tile_accept_to_rx_p99_cycles": percentile(tile_to_rx, 0.99),
        "tile_accept_to_rx_max_cycles": max(tile_to_rx, default=0),
        "post_input_drain_cycles": max(0, last_receive_cycle - source_last_cycle),
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def render_frames(
    source_events: list[tuple[int, int, int, int]],
    cases: dict[str, dict[str, object]],
    output_dir: Path,
    frame_count: int,
    trail_ms: float,
    pixel_fifo_depth: int,
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
        (
            f"100MHz 비닝 · 손실 {cases['adaptive100']['loss_percent']:.2f}%",
            cases["adaptive100"]["rx_events"],
        ),
        (
            f"100MHz RAW8 · 손실 {cases['raw100']['loss_percent']:.2f}%",
            cases["raw100"]["rx_events"],
        ),
        ("200MHz 원본", source_events),
        (
            f"200MHz 비닝 · 손실 {cases['adaptive200']['loss_percent']:.2f}%",
            cases["adaptive200"]["rx_events"],
        ),
        (
            f"200MHz RAW8 · 손실 {cases['raw200']['loss_percent']:.2f}%",
            cases["raw200"]["rx_events"],
        ),
    )
    panel_positions = ((48, 126), (568, 126), (1088, 126), (48, 668), (568, 668), (1088, 668))
    event_times = [[event[0] for event in events] for _, events in panels]
    paths: list[Path] = []

    for frame_index, time_ns in enumerate(times):
        canvas = Image.new("RGB", (1600, 1180), (245, 247, 251))
        draw = ImageDraw.Draw(canvas)
        draw.text(
            (48, 22),
            f"Peak 1 GEPS: 픽셀 {pixel_fifo_depth}-entry · 비닝 공정 비교",
            font=title_font,
            fill=(23, 34, 59),
        )
        draw.text(
            (48, 65),
            f"원본 환산 시간 {time_ns / 1_000_000:7.2f} ms · 최근 {trail_ms:g} ms 활동",
            font=body_font,
            fill=(89, 101, 124),
        )
        for index, ((label, events), (x, y)) in enumerate(
            zip(panels, panel_positions, strict=True)
        ):
            draw.text((x, y - 30), label, font=panel_font, fill=(23, 34, 59))
            image = activity_image(events, time_ns, round(trail_ms * 1_000_000))
            image = image.resize((464, 464), Image.Resampling.NEAREST)
            canvas.paste(image, (x, y))
            count = bisect.bisect_right(event_times[index], time_ns)
            draw.text((x, y + 468), f"누적 {count:,}개", font=body_font, fill=(89, 101, 124))
        path = frames_dir / f"frame_{frame_index:03d}.png"
        canvas.save(path)
        paths.append(path)

    images = [Image.open(path) for path in paths]
    images[0].save(
        output_dir / "peak1geps_binning_fair_compare.webp",
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


def write_fragment(
    path: Path,
    source_events: list[tuple[int, int, int, int]],
    cases: dict[str, dict[str, object]],
    pixel_fifo_depth: int,
) -> None:
    source_full = [[round(t / 1_000_000, 3), x, y, p] for t, x, y, p in source_events]

    def groups(case: dict[str, object]) -> list[list[float | int]]:
        manifest = case["manifest"]
        decoded = case["decoded"]
        assert isinstance(manifest, dict) and isinstance(decoded, list)
        clock_hz = int(manifest["clock_hz"])
        playback = float(manifest["playback_speed"])
        result: list[list[float | int]] = []
        for record in decoded:
            assert isinstance(record, dict)
            result.append(
                [
                    round(int(record["rx_timestamp_cycle"]) * playback * 1000 / clock_hz, 3),
                    int(record["tile"]),
                    int(record["on"]),
                    int(record["off"]),
                ]
            )
        return result

    source = sample_evenly(source_full, 8_000)
    group_full = {name: groups(case) for name, case in cases.items()}
    group_sample = {name: sample_evenly(records, 8_000) for name, records in group_full.items()}
    max_time = max(
        source_full[-1][0],
        *(records[-1][0] for records in group_full.values()),
    )
    metrics = {name: case_metrics(case) for name, case in cases.items()}
    data_json = json.dumps(group_sample, separators=(",", ":"))

    fragment = f'''<div id="aer-binning-fair-compare">
  <h2>Peak 1 GEPS: 픽셀 {pixel_fifo_depth}-entry · 비닝과 RAW8 비교</h2>
  <div class="viz-controls">
    <button type="button" class="btn btn-primary" id="aer-bf-play">일시정지</button>
    <label class="form-label" for="aer-bf-trail">표시 구간
      <select class="form-select" id="aer-bf-trail"><option value="20">최근 20 ms</option><option value="80" selected>최근 80 ms</option><option value="0">누적</option></select>
    </label>
    <label class="form-label" for="aer-bf-range">원본 환산 시간 <span id="aer-bf-time">0.00 ms</span></label>
    <input class="form-range" id="aer-bf-range" type="range" min="0" max="{max_time:.3f}" step="0.05" value="0">
  </div>
  <div class="aer-bf-grid">
    <section><h3>100MHz 원본</h3><canvas id="aer-bf-source100" width="128" height="128" role="img" aria-label="100MHz 비교 원본 이벤트"></canvas></section>
    <section><h3>100MHz 비닝 · 손실 {metrics['adaptive100']['loss_percent']:.2f}%</h3><canvas id="aer-bf-adaptive100" width="128" height="128" role="img" aria-label="100MHz 비닝 수신 이벤트"></canvas></section>
    <section><h3>100MHz RAW8 · 손실 {metrics['raw100']['loss_percent']:.2f}%</h3><canvas id="aer-bf-raw100" width="128" height="128" role="img" aria-label="100MHz RAW8 수신 이벤트"></canvas></section>
    <section><h3>200MHz 원본</h3><canvas id="aer-bf-source200" width="128" height="128" role="img" aria-label="200MHz 비교 원본 이벤트"></canvas></section>
    <section><h3>200MHz 비닝 · 손실 {metrics['adaptive200']['loss_percent']:.2f}%</h3><canvas id="aer-bf-adaptive200" width="128" height="128" role="img" aria-label="200MHz 비닝 수신 이벤트"></canvas></section>
    <section><h3>200MHz RAW8 · 손실 {metrics['raw200']['loss_percent']:.2f}%</h3><canvas id="aer-bf-raw200" width="128" height="128" role="img" aria-label="200MHz RAW8 수신 이벤트"></canvas></section>
  </div>
  <div class="table-responsive">
    <table class="table table-sm">
      <thead><tr><th>조건</th><th class="text-end">수신 이벤트</th><th class="text-end">손실률</th><th class="text-end">워드/이벤트</th><th class="text-end">평균 지연</th><th class="text-end">BIN4 짝 비율</th></tr></thead>
      <tbody>
        <tr><td>100MHz 비닝</td><td class="text-end">{metrics['adaptive100']['accepted_events']:,}</td><td class="text-end">{metrics['adaptive100']['loss_percent']:.2f}%</td><td class="text-end">{metrics['adaptive100']['words_per_event']:.4f}</td><td class="text-end">{metrics['adaptive100']['tile_accept_to_rx_mean_cycles']:.0f} clk</td><td class="text-end">{metrics['adaptive100']['paired_bin4_percent']:.2f}%</td></tr>
        <tr><td>100MHz RAW8</td><td class="text-end">{metrics['raw100']['accepted_events']:,}</td><td class="text-end">{metrics['raw100']['loss_percent']:.2f}%</td><td class="text-end">{metrics['raw100']['words_per_event']:.4f}</td><td class="text-end">{metrics['raw100']['tile_accept_to_rx_mean_cycles']:.0f} clk</td><td class="text-end">-</td></tr>
        <tr><td>200MHz 비닝</td><td class="text-end">{metrics['adaptive200']['accepted_events']:,}</td><td class="text-end">{metrics['adaptive200']['loss_percent']:.2f}%</td><td class="text-end">{metrics['adaptive200']['words_per_event']:.4f}</td><td class="text-end">{metrics['adaptive200']['tile_accept_to_rx_mean_cycles']:.0f} clk</td><td class="text-end">{metrics['adaptive200']['paired_bin4_percent']:.2f}%</td></tr>
        <tr><td>200MHz RAW8</td><td class="text-end">{metrics['raw200']['accepted_events']:,}</td><td class="text-end">{metrics['raw200']['loss_percent']:.2f}%</td><td class="text-end">{metrics['raw200']['words_per_event']:.4f}</td><td class="text-end">{metrics['raw200']['tile_accept_to_rx_mean_cycles']:.0f} clk</td><td class="text-end">-</td></tr>
      </tbody>
    </table>
  </div>
  <div class="viz-row text-small" id="aer-bf-counts" aria-live="polite"></div>
  <div class="viz-row text-small"><span>파란색 ON</span><span>주황색 OFF</span><span>모든 비교에 동일 입력 사용</span></div>
</div>
<style>
#aer-binning-fair-compare {{ width:100%; }}
#aer-binning-fair-compare .aer-bf-grid {{ display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:16px; }}
#aer-binning-fair-compare section {{ min-width:0; }}
#aer-binning-fair-compare canvas {{ display:block; width:100%; height:auto; aspect-ratio:1; image-rendering:pixelated; background:var(--card); }}
#aer-binning-fair-compare .form-range {{ flex:1 1 280px; }}
@media (max-width:700px) {{ #aer-binning-fair-compare .aer-bf-grid {{ grid-template-columns:1fr; }} }}
</style>
<script>
(() => {{
  const root = document.getElementById('aer-binning-fair-compare');
  const source = {json.dumps(source, separators=(',', ':'))};
  const groups = {data_json};
  const maxTime = {max_time:.3f};
  const range = root.querySelector('#aer-bf-range');
  const trail = root.querySelector('#aer-bf-trail');
  const play = root.querySelector('#aer-bf-play');
  let playing = true;
  let last = performance.now();
  function color(token) {{
    const probe = document.createElement('span'); probe.style.color = `var(${{token}})`; probe.style.display = 'none'; root.appendChild(probe);
    const result = getComputedStyle(probe).color; probe.remove(); return result;
  }}
  const background = color('--card'), onColor = color('--viz-series-1'), offColor = color('--viz-series-2');
  function upperBound(records, time) {{ let lo=0,hi=records.length; while(lo<hi){{const mid=(lo+hi)>>1;if(records[mid][0]<=time)lo=mid+1;else hi=mid;}} return lo; }}
  function tilePixel(tile, bit) {{ const bank=Math.floor(tile/16),local=tile%16; const br=Math.floor(bank/16),bc=bank%16,lr=Math.floor(local/4),lc=local%4; return [(bc*4+lc)*2+(bit&1),(br*4+lr)*2+((bit>>1)&1)]; }}
  function clear(id) {{ const ctx=root.querySelector(id).getContext('2d'); ctx.globalAlpha=1; ctx.fillStyle=background; ctx.fillRect(0,0,128,128); return ctx; }}
  function alpha(age,horizon) {{ return horizon===0?1:Math.max(0.15,Math.exp(-age/Math.max(1,horizon*0.42))); }}
  function drawSource(id,time,horizon) {{ const ctx=clear(id),end=upperBound(source,time); for(let i=0;i<end;i++){{const e=source[i],age=time-e[0];if(horizon&&age>horizon)continue;ctx.globalAlpha=alpha(age,horizon);ctx.fillStyle=e[3]?onColor:offColor;ctx.fillRect(e[1],e[2],1,1);}}ctx.globalAlpha=1;return end; }}
  function drawGroups(id,records,time,horizon) {{ const ctx=clear(id),end=upperBound(records,time);for(let i=0;i<end;i++){{const g=records[i],age=time-g[0];if(horizon&&age>horizon)continue;ctx.globalAlpha=alpha(age,horizon);for(const pair of [[1,g[2]],[0,g[3]]]){{ctx.fillStyle=pair[0]?onColor:offColor;for(let bit=0;bit<4;bit++)if(pair[1]&(1<<bit)){{const p=tilePixel(g[1],bit);ctx.fillRect(p[0],p[1],1,1);}}}}}}ctx.globalAlpha=1;return end; }}
  function update() {{
    const time=Number(range.value),horizon=Number(trail.value); const sc=drawSource('#aer-bf-source100',time,horizon);drawSource('#aer-bf-source200',time,horizon);
    const a100=drawGroups('#aer-bf-adaptive100',groups.adaptive100,time,horizon),r100=drawGroups('#aer-bf-raw100',groups.raw100,time,horizon),a200=drawGroups('#aer-bf-adaptive200',groups.adaptive200,time,horizon),r200=drawGroups('#aer-bf-raw200',groups.raw200,time,horizon);
    root.querySelector('#aer-bf-time').textContent=`${{time.toFixed(2)}} ms`; root.querySelector('#aer-bf-counts').textContent=`표시 표본 · 원본 ${{sc.toLocaleString()}}/${{source.length.toLocaleString()}} · 100MHz 비닝/RAW ${{a100.toLocaleString()}}/${{r100.toLocaleString()}} · 200MHz 비닝/RAW ${{a200.toLocaleString()}}/${{r200.toLocaleString()}}`;
  }}
  play.addEventListener('click',()=>{{playing=!playing;play.textContent=playing?'일시정지':'재생';}}); range.addEventListener('input',()=>{{playing=false;play.textContent='재생';update();}}); trail.addEventListener('change',update);
  function tick(now){{if(playing){{const next=Number(range.value)+(now-last)*maxTime/7000;range.value=next>=maxTime?0:next;update();}}last=now;requestAnimationFrame(tick);}} update();requestAnimationFrame(tick);
}})();
</script>
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(fragment, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("adaptive100", "raw100", "adaptive200", "raw200"):
        parser.add_argument(f"manifest_{name}", type=Path)
        parser.add_argument(f"log_{name}", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--html-fragment", type=Path)
    parser.add_argument("--frames", type=int, default=64)
    parser.add_argument("--trail-ms", type=float, default=80.0)
    parser.add_argument("--pixel-fifo-depth", type=int, choices=(1, 2), default=1)
    args = parser.parse_args()

    cases = {
        name: load_case(getattr(args, f"manifest_{name}"), getattr(args, f"log_{name}"))
        for name in ("adaptive100", "raw100", "adaptive200", "raw200")
    }
    manifest = cases["adaptive100"]["manifest"]
    assert isinstance(manifest, dict)
    source_events = [
        (int(event[0]), int(event[1]), int(event[2]), int(event[3]))
        for event in manifest["events"]
    ]
    input_hashes = {
        name: sha256(getattr(args, f"manifest_{name}").with_name("pixel_vectors.txt"))
        for name in cases
    }
    if input_hashes["adaptive100"] != input_hashes["raw100"]:
        raise ValueError("100MHz adaptive/RAW input vectors differ")
    if input_hashes["adaptive200"] != input_hashes["raw200"]:
        raise ValueError("200MHz adaptive/RAW input vectors differ")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    comparison = {
        "source_events": len(source_events),
        "peak_definition": "1 ms sliding-window peak = 1 GEPS",
        "pixel_fifo_depth": args.pixel_fifo_depth,
        "input_sha256": input_hashes,
        "cases": {name: case_metrics(case) for name, case in cases.items()},
    }
    (args.output_dir / "summary.json").write_text(
        json.dumps(comparison, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    render_frames(
        source_events,
        cases,
        args.output_dir,
        args.frames,
        args.trail_ms,
        args.pixel_fifo_depth,
    )
    if args.html_fragment:
        write_fragment(args.html_fragment, source_events, cases, args.pixel_fifo_depth)
    print(
        "V1_BINNING_FAIR_COMPARE_DONE "
        f"loss100={cases['adaptive100']['loss_percent']:.3f}/{cases['raw100']['loss_percent']:.3f} "
        f"loss200={cases['adaptive200']['loss_percent']:.3f}/{cases['raw200']['loss_percent']:.3f}"
    )


if __name__ == "__main__":
    main()
