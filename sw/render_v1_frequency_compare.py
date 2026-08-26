"""Compare peak-1-GEPS CIFAR reconstruction at two AER clock rates."""

from __future__ import annotations

import argparse
import bisect
import json
from pathlib import Path

from PIL import Image, ImageDraw

from sw.render_v1_cifar_pending import parse_pending_stats
from sw.render_v1_uzh_reconstruction import (
    activity_image,
    decode_words,
    load_fonts,
    parse_rtl_log,
    reconstructed_events,
)


def load_case(manifest_path: Path, log_path: Path) -> dict[str, object]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pending = parse_pending_stats(log_path)
    accepted, words = parse_rtl_log(log_path)
    decoded, errors, headers = decode_words(accepted, words, external_rx_timestamp=True)
    if errors:
        raise ValueError(f"packet errors in {log_path}: {errors[:3]}")
    rx_events = reconstructed_events(
        decoded,
        int(manifest["clock_hz"]),
        float(manifest["playback_speed"]),
        "rx_timestamp_cycle",
    )
    lost = pending["pixel_ignored_events"] + pending["same_cycle_duplicate_events"]
    return {
        "manifest": manifest,
        "pending": pending,
        "decoded": decoded,
        "rx_events": rx_events,
        "loss_percent": 100.0 * lost / pending["source_events"],
        "output_words": len(words),
        "row_headers": headers,
    }


def render_frames(
    source_events: list[tuple[int, int, int, int]],
    case_100: dict[str, object],
    case_200: dict[str, object],
    output_dir: Path,
    frame_count: int,
    trail_ms: float,
) -> list[Path]:
    frames_dir = output_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    title_font, panel_font, body_font = load_fonts()
    rx_100 = case_100["rx_events"]
    rx_200 = case_200["rx_events"]
    assert isinstance(rx_100, list) and isinstance(rx_200, list)
    duration_ns = max(source_events[-1][0], rx_100[-1][0], rx_200[-1][0])
    times = [
        round(duration_ns * index / max(1, frame_count - 1))
        for index in range(frame_count)
    ]
    time_lists = [[event[0] for event in events] for events in (source_events, rx_100, rx_200)]
    labels = (
        "AEDAT2 원본 이벤트",
        f"100MHz 수신 · 손실 {case_100['loss_percent']:.2f}%",
        f"200MHz 수신 · 손실 {case_200['loss_percent']:.2f}%",
    )
    events_by_panel = (source_events, rx_100, rx_200)
    paths: list[Path] = []
    panel_size = 464
    panel_x = (48, 568, 1088)

    for frame_index, time_ns in enumerate(times):
        canvas = Image.new("RGB", (1600, 620), (245, 247, 251))
        draw = ImageDraw.Draw(canvas)
        draw.text((48, 22), "Peak 1 GEPS: 주파수별 실제 RTL 수신 비교", font=title_font, fill=(23, 34, 59))
        draw.text(
            (48, 65),
            f"원본 환산 시간 {time_ns / 1_000_000:7.2f} ms · 최근 {trail_ms:g} ms 활동",
            font=body_font,
            fill=(89, 101, 124),
        )
        for x, label, events, event_times in zip(
            panel_x, labels, events_by_panel, time_lists, strict=True
        ):
            draw.text((x, 96), label, font=panel_font, fill=(23, 34, 59))
            image = activity_image(events, time_ns, round(trail_ms * 1_000_000))
            image = image.resize((panel_size, panel_size), Image.Resampling.NEAREST)
            canvas.paste(image, (x, 128))
            count = bisect.bisect_right(event_times, time_ns)
            draw.text((x, 596), f"누적 {count:,}개", font=body_font, fill=(89, 101, 124))
        path = frames_dir / f"frame_{frame_index:03d}.png"
        canvas.save(path)
        paths.append(path)

    images = [Image.open(path) for path in paths]
    images[0].save(
        output_dir / "peak1geps_frequency_compare.webp",
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


def sample_evenly(records: list[list[float | int]], limit: int) -> list[list[float | int]]:
    if len(records) <= limit:
        return records
    step = len(records) / limit
    sampled = [records[min(len(records) - 1, int(index * step))] for index in range(limit)]
    sampled[-1] = records[-1]
    return sampled


def write_fragment(
    path: Path,
    source_events: list[tuple[int, int, int, int]],
    case_100: dict[str, object],
    case_200: dict[str, object],
) -> None:
    source_full = [[round(t / 1_000_000, 3), x, y, p] for t, x, y, p in source_events]

    def groups(case: dict[str, object]) -> list[list[float | int]]:
        manifest = case["manifest"]
        assert isinstance(manifest, dict)
        clock_hz = int(manifest["clock_hz"])
        playback = float(manifest["playback_speed"])
        result: list[list[float | int]] = []
        decoded = case["decoded"]
        assert isinstance(decoded, list)
        for record in decoded:
            assert isinstance(record, dict)
            time_ms = int(record["rx_timestamp_cycle"]) * playback * 1000 / clock_hz
            result.append(
                [
                    round(time_ms, 3),
                    int(record["tile"]),
                    int(record["on"]),
                    int(record["off"]),
                ]
            )
        return result

    rx_100_full = groups(case_100)
    rx_200_full = groups(case_200)
    source = sample_evenly(source_full, 11_000)
    rx_100 = sample_evenly(rx_100_full, 11_000)
    rx_200 = sample_evenly(rx_200_full, 11_000)
    max_time = max(source_full[-1][0], rx_100_full[-1][0], rx_200_full[-1][0])
    pending_100 = case_100["pending"]
    pending_200 = case_200["pending"]
    assert isinstance(pending_100, dict) and isinstance(pending_200, dict)
    rx_events_100 = len(case_100["rx_events"])
    rx_events_200 = len(case_200["rx_events"])

    fragment = f'''<div id="aer-peak1g-frequency">
  <h2>Peak 1 GEPS: 100MHz와 200MHz 수신 비교</h2>
  <div class="viz-controls">
    <button type="button" class="btn btn-primary" id="aer-pf-play">일시정지</button>
    <label class="form-label" for="aer-pf-trail">표시 구간
      <select class="form-select" id="aer-pf-trail"><option value="20">최근 20 ms</option><option value="80" selected>최근 80 ms</option><option value="0">누적</option></select>
    </label>
    <label class="form-label" for="aer-pf-range">원본 환산 시간 <span id="aer-pf-time">0.00 ms</span></label>
    <input class="form-range" id="aer-pf-range" type="range" min="0" max="{max_time:.3f}" step="0.05" value="0">
  </div>
  <div class="aer-pf-panels">
    <section><h3>원본 · 178,165개</h3><canvas id="aer-pf-source" width="128" height="128" role="img" aria-label="CIFAR10-DVS 원본 이벤트"></canvas></section>
    <section><h3>100MHz · 수신 {rx_events_100:,} · 손실 {case_100['loss_percent']:.2f}%</h3><canvas id="aer-pf-100" width="128" height="128" role="img" aria-label="100MHz RTL 수신 이벤트"></canvas></section>
    <section><h3>200MHz · 수신 {rx_events_200:,} · 손실 {case_200['loss_percent']:.2f}%</h3><canvas id="aer-pf-200" width="128" height="128" role="img" aria-label="200MHz RTL 수신 이벤트"></canvas></section>
  </div>
  <div class="viz-row text-small" id="aer-pf-counts" aria-live="polite"></div>
  <div class="viz-row text-small"><span>파란색 ON</span><span>주황색 OFF</span><span>대화형 화면은 균일 시간 표본</span></div>
</div>
<style>
#aer-peak1g-frequency {{ width:100%; }}
#aer-peak1g-frequency .aer-pf-panels {{ display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:16px; }}
#aer-peak1g-frequency section {{ min-width:0; }}
#aer-peak1g-frequency canvas {{ display:block; width:100%; height:auto; aspect-ratio:1; image-rendering:pixelated; background:var(--card); }}
#aer-peak1g-frequency .form-range {{ flex:1 1 280px; }}
@media (max-width:700px) {{ #aer-peak1g-frequency .aer-pf-panels {{ grid-template-columns:1fr; }} }}
</style>
<script>
(() => {{
  const root = document.getElementById('aer-peak1g-frequency');
  const source = {json.dumps(source, separators=(',', ':'))};
  const rx100 = {json.dumps(rx_100, separators=(',', ':'))};
  const rx200 = {json.dumps(rx_200, separators=(',', ':'))};
  const maxTime = {max_time:.3f};
  const range = root.querySelector('#aer-pf-range');
  const trail = root.querySelector('#aer-pf-trail');
  const play = root.querySelector('#aer-pf-play');
  let playing = true;
  let last = performance.now();

  function color(token) {{
    const probe = document.createElement('span');
    probe.style.color = `var(${{token}})`;
    probe.style.display = 'none';
    root.appendChild(probe);
    const result = getComputedStyle(probe).color;
    probe.remove();
    return result;
  }}
  const background = color('--card');
  const onColor = color('--viz-series-1');
  const offColor = color('--viz-series-2');

  function upperBound(records, time) {{
    let lo = 0, hi = records.length;
    while (lo < hi) {{ const mid = (lo + hi) >> 1; if (records[mid][0] <= time) lo = mid + 1; else hi = mid; }}
    return lo;
  }}
  function tilePixel(tile, bit) {{
    const bank = Math.floor(tile / 16), local = tile % 16;
    const bankRow = Math.floor(bank / 16), bankCol = bank % 16;
    const localRow = Math.floor(local / 4), localCol = local % 4;
    return [(bankCol * 4 + localCol) * 2 + (bit & 1), (bankRow * 4 + localRow) * 2 + ((bit >> 1) & 1)];
  }}
  function clear(id) {{
    const canvas = root.querySelector(id), ctx = canvas.getContext('2d');
    ctx.globalAlpha = 1;
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, 128, 128);
    return ctx;
  }}
  function alpha(age, horizon) {{ return horizon === 0 ? 1 : Math.max(0.15, Math.exp(-age / Math.max(1, horizon * 0.42))); }}
  function drawSource(time, horizon) {{
    const ctx = clear('#aer-pf-source'), end = upperBound(source, time);
    for (let i = 0; i < end; i++) {{
      const event = source[i], age = time - event[0];
      if (horizon && age > horizon) continue;
      ctx.globalAlpha = alpha(age, horizon);
      ctx.fillStyle = event[3] ? onColor : offColor;
      ctx.fillRect(event[1], event[2], 1, 1);
    }}
    ctx.globalAlpha = 1;
    return end;
  }}
  function drawGroups(id, records, time, horizon) {{
    const ctx = clear(id), end = upperBound(records, time);
    let events = 0;
    for (let i = 0; i < end; i++) {{
      const group = records[i], age = time - group[0];
      if (horizon && age > horizon) continue;
      ctx.globalAlpha = alpha(age, horizon);
      for (const pair of [[1,group[2]],[0,group[3]]]) {{
        ctx.fillStyle = pair[0] ? onColor : offColor;
        for (let bit = 0; bit < 4; bit++) if (pair[1] & (1 << bit)) {{
          const pixel = tilePixel(group[1], bit);
          ctx.fillRect(pixel[0], pixel[1], 1, 1);
          events++;
        }}
      }}
    }}
    ctx.globalAlpha = 1;
    return [end,events];
  }}
  function update() {{
    const time = Number(range.value), horizon = Number(trail.value);
    const sourceCount = drawSource(time, horizon);
    const count100 = drawGroups('#aer-pf-100', rx100, time, horizon);
    const count200 = drawGroups('#aer-pf-200', rx200, time, horizon);
    root.querySelector('#aer-pf-time').textContent = `${{time.toFixed(2)}} ms`;
    root.querySelector('#aer-pf-counts').textContent = `표시 표본 · 원본 ${{sourceCount.toLocaleString()}}/${{source.length.toLocaleString()}} · 100MHz 그룹 ${{count100[0].toLocaleString()}}/${{rx100.length.toLocaleString()}} · 200MHz 그룹 ${{count200[0].toLocaleString()}}/${{rx200.length.toLocaleString()}}`;
  }}
  play.addEventListener('click', () => {{ playing = !playing; play.textContent = playing ? '일시정지' : '재생'; }});
  range.addEventListener('input', () => {{ playing = false; play.textContent = '재생'; update(); }});
  trail.addEventListener('change', update);
  function tick(now) {{
    if (playing) {{
      const next = Number(range.value) + (now - last) * maxTime / 7000;
      range.value = next >= maxTime ? 0 : next;
      update();
    }}
    last = now;
    requestAnimationFrame(tick);
  }}
  update();
  requestAnimationFrame(tick);
}})();
</script>
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(fragment, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest_100", type=Path)
    parser.add_argument("log_100", type=Path)
    parser.add_argument("manifest_200", type=Path)
    parser.add_argument("log_200", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--html-fragment", type=Path)
    parser.add_argument("--frames", type=int, default=72)
    parser.add_argument("--trail-ms", type=float, default=80.0)
    args = parser.parse_args()

    case_100 = load_case(args.manifest_100, args.log_100)
    case_200 = load_case(args.manifest_200, args.log_200)
    manifest_100 = case_100["manifest"]
    assert isinstance(manifest_100, dict)
    source_events = [
        (int(event[0]), int(event[1]), int(event[2]), int(event[3]))
        for event in manifest_100["events"]
    ]
    args.output_dir.mkdir(parents=True, exist_ok=True)
    comparison = {
        "source_events": len(source_events),
        "peak_definition": "1 ms sliding-window peak = 1 GEPS",
        "100mhz": {
            "accepted": case_100["pending"]["pixel_accepted_events"],
            "loss_percent": case_100["loss_percent"],
            "output_words": case_100["output_words"],
        },
        "200mhz": {
            "accepted": case_200["pending"]["pixel_accepted_events"],
            "loss_percent": case_200["loss_percent"],
            "output_words": case_200["output_words"],
        },
    }
    (args.output_dir / "summary.json").write_text(
        json.dumps(comparison, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    render_frames(
        source_events,
        case_100,
        case_200,
        args.output_dir,
        args.frames,
        args.trail_ms,
    )
    if args.html_fragment:
        write_fragment(args.html_fragment, source_events, case_100, case_200)
    print(
        "V1_FREQUENCY_COMPARE_DONE "
        f"source={len(source_events)} "
        f"loss100={case_100['loss_percent']:.3f} "
        f"loss200={case_200['loss_percent']:.3f}"
    )


if __name__ == "__main__":
    main()
