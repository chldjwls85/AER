"""Render CIFAR source events versus packets timestamped at link reception."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from pathlib import Path
from statistics import mean

from sw.render_v1_uzh_reconstruction import (
    decode_words,
    parse_rtl_log,
    percentile,
    reconstructed_events,
    render_frames,
    tile_pixel,
)


def parse_pending_stats(path: Path) -> dict[str, int]:
    names = [
        "source_events",
        "pixel_accepted_events",
        "pixel_ignored_events",
        "same_cycle_duplicate_events",
        "pixel_readout_events",
        "accepted_tile_groups",
        "decoded_tile_groups",
        "output_words",
    ]
    with path.open("r", encoding="ascii") as handle:
        for line in handle:
            fields = line.split()
            if fields and fields[0] == "S" and len(fields) == 9:
                return dict(zip(names, (int(value) for value in fields[1:]), strict=True))
    raise ValueError(f"pending-array summary record was not found: {path}")


def write_fragment(
    path: Path,
    source_events: list[tuple[int, int, int, int]],
    decoded: list[dict[str, int | str]],
    summary: dict[str, object],
) -> None:
    clock_hz = int(summary["clock_hz"])
    playback_speed = float(summary["playback_speed"])
    source_full = [
        [round(timestamp_ns / 1_000_000, 3), x, y, polarity]
        for timestamp_ns, x, y, polarity in source_events
    ]
    format_code = {
        "RAW8": 0,
        "BANK_RAW8": 0,
        "GROUP3": 1,
        "ROW_GROUP3": 1,
        "BANK_GROUP3": 1,
        "BIN4": 2,
        "ROW_BIN4": 2,
        "BANK_BIN4": 2,
        "BANK_LOSSY_BIN": 2,
    }
    received_full: list[list[float | int]] = []
    for record in decoded:
        timestamp_ms = (
            int(record["rx_timestamp_cycle"])
            * playback_speed
            * 1000
            / clock_hz
        )
        received_full.append(
            [
                round(timestamp_ms, 3),
                int(record["tile"]),
                int(record["on"]),
                int(record["off"]),
                format_code[str(record["format"])],
            ]
        )
    received_full.sort(key=lambda item: float(item[0]))

    # Keep the in-conversation animation responsive and below the 1 MB host
    # limit for full CIFAR recordings.  The PNG/WebP/MP4 path still renders
    # every source and reconstructed event.
    def sample_evenly(records: list[list[float | int]], limit: int) -> list[list[float | int]]:
        if len(records) <= limit:
            return records
        step = len(records) / limit
        sampled = [records[min(len(records) - 1, int(index * step))] for index in range(limit)]
        sampled[-1] = records[-1]
        return sampled

    source = sample_evenly(source_full, 18_000)
    received = sample_evenly(received_full, 18_000)
    max_time = max(
        source_full[-1][0] if source_full else 0,
        received_full[-1][0] if received_full else 0,
    )
    fragment = f'''<div id="aer-cifar-pending-rx">
  <h2>실제 이벤트 발생 ↔ 외부 링크 수신 시각</h2>
  <div class="viz-controls">
    <button type="button" class="btn btn-primary" id="aer-cp-play">일시정지</button>
    <label class="form-label" for="aer-cp-trail">표시 구간
      <select class="form-select" id="aer-cp-trail"><option value="20">최근 20 ms</option><option value="100">최근 100 ms</option><option value="0" selected>누적</option></select>
    </label>
    <label class="form-label" for="aer-cp-range">원본 환산 시간 <span id="aer-cp-time">0.00 ms</span></label>
    <input class="form-range" id="aer-cp-range" type="range" min="0" max="{max_time:.3f}" step="0.05" value="0">
  </div>
  <div class="viz-row text-small" id="aer-cp-counts" aria-live="polite"></div>
  <div class="aer-cp-panels">
    <section><h3>AEDAT2 원본 발생 시각</h3><canvas id="aer-cp-source" width="128" height="128" role="img" aria-label="CIFAR10-DVS 원본 이벤트 발생"></canvas></section>
    <section><h3>패킷 첫 워드 수신 시각</h3><canvas id="aer-cp-rx" width="128" height="128" role="img" aria-label="RTL 패킷을 복호화하고 외부 수신 시각을 부여한 이벤트"></canvas></section>
  </div>
  <div class="viz-row text-small"><span>파란색 ON</span><span>주황색 OFF</span><span>보라색 GROUP3</span><span>초록색 BIN4</span></div>
</div>
<style>
#aer-cifar-pending-rx {{ width:100%; }}
#aer-cifar-pending-rx .aer-cp-panels {{ display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:20px; }}
#aer-cifar-pending-rx section {{ min-width:0; }}
#aer-cifar-pending-rx canvas {{ display:block; width:100%; height:auto; aspect-ratio:1; image-rendering:pixelated; background:var(--card); }}
#aer-cifar-pending-rx .form-range {{ flex:1 1 280px; }}
@media (max-width:560px) {{ #aer-cifar-pending-rx .aer-cp-panels {{ grid-template-columns:1fr; }} }}
</style>
<script>
(() => {{
  const root = document.getElementById('aer-cifar-pending-rx');
  const source = {json.dumps(source, separators=(',', ':'))};
  const received = {json.dumps(received, separators=(',', ':'))};
  const maxTime = {max_time:.3f};
  const playback = {playback_speed:g};
  const ignored = {int(summary['pixel_ignored_events']) + int(summary['same_cycle_duplicate_events'])};
  const fullSourceTotal = {len(source_events)};
  const fullRxGroupTotal = {len(decoded)};
  const fullRxEventTotal = {int(summary['reconstructed_event_bits'])};
  const range = root.querySelector('#aer-cp-range');
  const trail = root.querySelector('#aer-cp-trail');
  const play = root.querySelector('#aer-cp-play');
  const sourceCanvas = root.querySelector('#aer-cp-source');
  const rxCanvas = root.querySelector('#aer-cp-rx');
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
  const groupColor = color('--viz-series-3');
  const binColor = color('--viz-series-4');

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
  function clear(canvas) {{
    const ctx = canvas.getContext('2d');
    ctx.globalAlpha = 1;
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, 128, 128);
    return ctx;
  }}
  function alpha(age, horizon) {{ return horizon === 0 ? 1 : Math.max(0.15, Math.exp(-age / Math.max(1, horizon * 0.42))); }}
  function drawSource(time, horizon) {{
    const ctx = clear(sourceCanvas), end = upperBound(source, time);
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
  function drawReceived(time, horizon) {{
    const ctx = clear(rxCanvas), end = upperBound(received, time);
    let eventCount = 0;
    for (let i = 0; i < end; i++) {{
      const group = received[i], age = time - group[0];
      if (horizon && age > horizon) continue;
      ctx.globalAlpha = alpha(age, horizon);
      for (const pair of [[1,group[2]],[0,group[3]]]) {{
        ctx.fillStyle = pair[0] ? onColor : offColor;
        for (let bit = 0; bit < 4; bit++) if (pair[1] & (1 << bit)) {{
          const pixel = tilePixel(group[1], bit);
          ctx.fillRect(pixel[0], pixel[1], 1, 1);
          eventCount++;
        }}
      }}
      if (group[4] > 0) {{
        const pixel = tilePixel(group[1], 0);
        ctx.strokeStyle = group[4] === 2 ? binColor : groupColor;
        ctx.lineWidth = 0.7;
        ctx.strokeRect(pixel[0] - 0.25, pixel[1] - 0.25, 2.5, 2.5);
      }}
    }}
    ctx.globalAlpha = 1;
    return [end,eventCount];
  }}
  function update() {{
    const time = Number(range.value), horizon = Number(trail.value);
    const sourceCount = drawSource(time, horizon);
    const rx = drawReceived(time, horizon);
    const hardwareUs = time * 1000 / playback;
    root.querySelector('#aer-cp-time').textContent = `${{time.toFixed(2)}} ms · 실제 RTL ${{hardwareUs.toFixed(2)}} μs`;
    root.querySelector('#aer-cp-counts').textContent = `화면 표본: 원본 ${{sourceCount.toLocaleString()}}/${{source.length.toLocaleString()}} · 수신 그룹 ${{rx[0].toLocaleString()}}/${{received.length.toLocaleString()}} · 전체 원본 ${{fullSourceTotal.toLocaleString()}} · 전체 수신 이벤트 ${{fullRxEventTotal.toLocaleString()}} · 전체 수신 그룹 ${{fullRxGroupTotal.toLocaleString()}} · ACK 전 무시 ${{ignored.toLocaleString()}}`;
  }}
  play.addEventListener('click', () => {{ playing = !playing; play.textContent = playing ? '일시정지' : '재생'; }});
  range.addEventListener('input', () => {{ playing = false; play.textContent = '재생'; update(); }});
  trail.addEventListener('change', update);
  function tick(now) {{
    if (playing) {{
      const next = Number(range.value) + (now - last) * maxTime / 6000;
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
    parser.add_argument("manifest_json", type=Path)
    parser.add_argument("rtl_log", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--frames", type=int, default=48)
    parser.add_argument("--trail-ms", type=float, default=1000.0)
    parser.add_argument("--html-fragment", type=Path)
    args = parser.parse_args()

    manifest = json.loads(args.manifest_json.read_text(encoding="utf-8"))
    pending_stats = parse_pending_stats(args.rtl_log)
    accepted, words = parse_rtl_log(args.rtl_log)
    decoded, errors, headers = decode_words(
        accepted, words, external_rx_timestamp=True
    )
    source_events = [
        (int(event[0]), int(event[1]), int(event[2]), int(event[3]))
        for event in manifest["events"]
    ]
    rx_timestamp_events = reconstructed_events(
        decoded,
        int(manifest["clock_hz"]),
        float(manifest["playback_speed"]),
        "rx_timestamp_cycle",
    )
    tile_to_rx = [
        int(record["rx_timestamp_cycle"]) - int(record["accept_cycle"])
        for record in decoded
    ]
    format_counts = Counter(str(record["format"]) for record in decoded)
    source_duration_ms = max((event[0] for event in source_events), default=0) / 1_000_000
    source_last_cycle = max((int(event[4]) for event in manifest["events"]), default=0)
    last_data_receive_cycle = max(
        (int(record["receive_cycle"]) for record in decoded), default=0
    )
    post_input_drain_cycles = max(0, last_data_receive_cycle - source_last_cycle)
    lost = (
        pending_stats["pixel_ignored_events"]
        + pending_stats["same_cycle_duplicate_events"]
    )
    false_positive_events = sum(
        int(record.get("false_positive_events", 0)) for record in decoded
    )
    total_event_errors = lost + false_positive_events
    summary: dict[str, object] = {
        "source": manifest["source"],
        "clock_hz": manifest["clock_hz"],
        "playback_speed": manifest["playback_speed"],
        "timestamp_mode": "external_link_first_word",
        "source_duration_ms": source_duration_ms,
        "source_last_cycle": source_last_cycle,
        **pending_stats,
        "loss_events": lost,
        "loss_percent": 100.0 * lost / max(1, pending_stats["source_events"]),
        "false_positive_events": false_positive_events,
        "false_positive_percent": 100.0
        * false_positive_events
        / max(1, pending_stats["source_events"]),
        "total_event_errors": total_event_errors,
        "total_error_percent": 100.0
        * total_event_errors
        / max(1, pending_stats["source_events"]),
        "reconstructed_event_bits": len(rx_timestamp_events),
        "packet_integrity_errors": errors,
        "format_counts": dict(sorted(format_counts.items())),
        "packet_headers": headers,
        "row_headers": headers,
        "timestamp_words": 0,
        "words_per_reconstructed_event": len(words) / max(1, len(rx_timestamp_events)),
        "tile_accept_to_rx_timestamp_mean_cycles": mean(tile_to_rx) if tile_to_rx else 0.0,
        "tile_accept_to_rx_timestamp_p99_cycles": percentile(tile_to_rx, 0.99),
        "tile_accept_to_rx_timestamp_max_cycles": max(tile_to_rx, default=0),
        "last_rx_timestamp_cycle": max(
            (int(record["rx_timestamp_cycle"]) for record in decoded), default=0
        ),
        "last_data_receive_cycle": last_data_receive_cycle,
        "post_input_drain_cycles": post_input_drain_cycles,
        "post_input_drain_hardware_us": post_input_drain_cycles
        * 1_000_000
        / int(manifest["clock_hz"]),
        "post_input_drain_source_equivalent_ms": post_input_drain_cycles
        * float(manifest["playback_speed"])
        * 1000
        / int(manifest["clock_hz"]),
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (args.output_dir / "reconstructed_events.json").write_text(
        json.dumps({"external_rx_timestamp": rx_timestamp_events}, separators=(",", ":")),
        encoding="utf-8",
    )
    if args.frames > 0:
        render_frames(
            source_events,
            rx_timestamp_events,
            summary,
            args.output_dir,
            frame_count=args.frames,
            trail_ms=args.trail_ms,
        )
    if args.html_fragment:
        write_fragment(args.html_fragment, source_events, decoded, summary)
    print(
        "V1_CIFAR_PENDING_RECONSTRUCTION "
        f"source={pending_stats['source_events']} "
        f"accepted={pending_stats['pixel_accepted_events']} "
        f"ignored={lost} false_positive={false_positive_events} "
        f"total_error={total_event_errors} groups={len(decoded)} errors={len(errors)}"
    )
    if errors:
        raise SystemExit("RTL packet integrity validation failed")


if __name__ == "__main__":
    main()
