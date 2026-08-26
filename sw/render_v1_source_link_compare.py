"""Render true source-event occurrence versus external AER-link reception."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from sw.render_v1_cycle_trace import annotate_words
from sw.render_v1_uzh_reconstruction import decode_words, parse_rtl_log


def write_fragment(
    path: Path,
    manifest: dict[str, object],
    decoded: list[dict[str, int | str]],
    words: list[tuple[int, int, int]],
) -> None:
    source = [
        [int(event[4]), int(event[1]), int(event[2]), int(event[3]), int(event[0])]
        for event in manifest["events"]  # type: ignore[index]
    ]
    source.sort(key=lambda item: (item[0], item[4]))

    groups = [
        [int(value) for value in group]
        for group in manifest["groups"]  # type: ignore[index]
    ]
    groups.sort(key=lambda item: item[0])

    format_codes = {"RAW8": 0, "GROUP3": 1, "BIN4": 2}
    received: list[list[int]] = []
    received_total = 0
    receive_cycles = [-1] * len(groups)
    for record in sorted(decoded, key=lambda item: int(item["receive_cycle"])):
        group_id = int(record["group_id"])
        source_events = int(record["source_events"])
        received_total += source_events
        received.append(
            [
                int(record["receive_cycle"]),
                group_id,
                int(record["tile"]),
                int(record["on"]),
                int(record["off"]),
                format_codes[str(record["format"])],
                source_events,
                int(record["source_cycle"]),
                received_total,
            ]
        )
        if 0 <= group_id < len(receive_cycles):
            receive_cycles[group_id] = int(record["receive_cycle"])

    annotated_words = annotate_words(words)
    last_cycle = max(
        max((event[0] for event in source), default=0),
        max((record[0] for record in received), default=0),
        max((record[0] for record in annotated_words), default=0),
    )
    clock_hz = int(manifest["clock_hz"])
    clock_ns = 1_000_000_000 / clock_hz
    playback_speed = float(manifest["playback_speed"])
    source_duration_ms = int(manifest["source_duration_ns"]) / 1_000_000
    source_end_cycle = max((event[0] for event in source), default=0)

    fragment = f'''<div id="aer-source-link-compare">
  <h2>실제 이벤트 발생 ↔ 외부 AER 링크 수신</h2>
  <div class="viz-controls">
    <button type="button" class="btn btn-primary" id="aer-sl-play">일시정지</button>
    <button type="button" class="btn" id="aer-sl-prev">이전 클록</button>
    <button type="button" class="btn" id="aer-sl-next">다음 클록</button>
    <label class="form-label" for="aer-sl-speed">재생 속도
      <select class="form-select" id="aer-sl-speed"><option value="1">1클록</option><option value="10" selected>10클록</option><option value="50">50클록</option><option value="200">200클록</option></select>
    </label>
    <label class="form-label" for="aer-sl-view">표시 방식
      <select class="form-select" id="aer-sl-view"><option value="64" selected>최근 64클록</option><option value="16">최근 16클록</option><option value="0">누적</option></select>
    </label>
  </div>
  <label class="form-label" for="aer-sl-range">RTL 클록 <span id="aer-sl-label">0</span></label>
  <input class="form-range" id="aer-sl-range" type="range" min="0" max="{last_cycle}" step="1" value="0">
  <div class="viz-row text-small" id="aer-sl-counts" aria-live="polite"></div>
  <div class="aer-sl-panels">
    <section><h3>센서에서 실제 발생</h3><canvas id="aer-sl-source" width="128" height="128" role="img" aria-label="원본 데이터셋 타임스탬프에 따라 발생한 이벤트"></canvas><p class="text-small text-muted" id="aer-sl-source-detail"></p></section>
    <section><h3>외부 링크에서 수신</h3><canvas id="aer-sl-received" width="128" height="128" role="img" aria-label="외부 AER 링크에서 데이터 워드까지 수신한 이벤트"></canvas><p class="text-small text-muted" id="aer-sl-received-detail"></p></section>
    <section><h3>발생했지만 아직 미수신</h3><canvas id="aer-sl-pending" width="128" height="128" role="img" aria-label="센서에서 발생했지만 링크에서 아직 수신되지 않은 이벤트"></canvas><p class="text-small text-muted" id="aer-sl-pending-detail"></p></section>
  </div>
  <div class="aer-sl-word"><span class="text-small text-muted">현재 링크</span><code id="aer-sl-word">출력 없음</code><span class="text-small" id="aer-sl-word-detail"></span></div>
  <div class="viz-row text-small"><span>파란색 ON</span><span>주황색 OFF</span><span>보라색 GROUP3</span><span>초록색 BIN4</span></div>
</div>
<style>
#aer-source-link-compare {{ width:100%; }}
#aer-source-link-compare .aer-sl-panels {{ display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:18px; }}
#aer-source-link-compare section {{ min-width:0; }}
#aer-source-link-compare canvas {{ display:block; width:100%; height:auto; aspect-ratio:1; image-rendering:pixelated; background:var(--card); }}
#aer-source-link-compare .form-range {{ width:100%; }}
#aer-source-link-compare .aer-sl-word {{ display:flex; flex-wrap:wrap; align-items:center; gap:10px; margin-top:16px; }}
#aer-source-link-compare code {{ overflow-wrap:anywhere; }}
@media (max-width:560px) {{ #aer-source-link-compare .aer-sl-panels {{ grid-template-columns:1fr; }} }}
</style>
<script>
(() => {{
  const root = document.getElementById('aer-source-link-compare');
  const source = {json.dumps(source, separators=(',', ':'))};
  const groups = {json.dumps(groups, separators=(',', ':'))};
  const received = {json.dumps(received, separators=(',', ':'))};
  const receiveCycles = {json.dumps(receive_cycles, separators=(',', ':'))};
  const words = {json.dumps(annotated_words, separators=(',', ':'))};
  const lastCycle = {last_cycle};
  const sourceEndCycle = {source_end_cycle};
  const clockNs = {clock_ns:g};
  const playbackSpeed = {playback_speed:g};
  const sourceDurationMs = {source_duration_ms:g};
  const sourceTotal = {len(source)};
  const formatNames = ['RAW8','GROUP3','BIN4','RESERVED'];
  const wordTypeNames = ['HEADER','TIME','DATA'];
  const range = root.querySelector('#aer-sl-range');
  const play = root.querySelector('#aer-sl-play');
  const speed = root.querySelector('#aer-sl-speed');
  const view = root.querySelector('#aer-sl-view');
  const sourceCanvas = root.querySelector('#aer-sl-source');
  const receivedCanvas = root.querySelector('#aer-sl-received');
  const pendingCanvas = root.querySelector('#aer-sl-pending');

  function resolvedColor(token) {{
    const probe = document.createElement('span');
    probe.style.color = `var(${{token}})`;
    probe.style.display = 'none';
    root.appendChild(probe);
    const value = getComputedStyle(probe).color;
    probe.remove();
    return value;
  }}
  const background = resolvedColor('--card');
  const onColor = resolvedColor('--viz-series-1');
  const offColor = resolvedColor('--viz-series-2');
  const groupColor = resolvedColor('--viz-series-3');
  const binColor = resolvedColor('--viz-series-4');
  let playing = true;
  let lastFrame = performance.now();

  function upperBound(records, cycle) {{
    let lo = 0, hi = records.length;
    while (lo < hi) {{
      const mid = (lo + hi) >> 1;
      if (records[mid][0] <= cycle) lo = mid + 1;
      else hi = mid;
    }}
    return lo;
  }}
  function lowerBound(records, cycle) {{
    let lo = 0, hi = records.length;
    while (lo < hi) {{
      const mid = (lo + hi) >> 1;
      if (records[mid][0] < cycle) lo = mid + 1;
      else hi = mid;
    }}
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
  function alphaFor(age, horizon) {{
    if (horizon === 0) return 1;
    return age === 0 ? 1 : Math.max(0.14, Math.exp(-age / Math.max(4, horizon / 3)));
  }}
  function drawSource(cycle, horizon) {{
    const ctx = clear(sourceCanvas);
    const end = upperBound(source, cycle);
    const startCycle = horizon === 0 ? 0 : Math.max(0, cycle - horizon + 1);
    const start = lowerBound(source, startCycle);
    for (let i = start; i < end; i++) {{
      const event = source[i];
      ctx.globalAlpha = alphaFor(cycle - event[0], horizon);
      ctx.fillStyle = event[3] ? onColor : offColor;
      ctx.fillRect(event[1], event[2], 1, 1);
    }}
    ctx.globalAlpha = 1;
    return [end, end - lowerBound(source, cycle)];
  }}
  function drawReceived(cycle, horizon) {{
    const ctx = clear(receivedCanvas);
    const end = upperBound(received, cycle);
    const startCycle = horizon === 0 ? 0 : Math.max(0, cycle - horizon + 1);
    const start = lowerBound(received, startCycle);
    let nowEvents = 0;
    for (let i = start; i < end; i++) {{
      const record = received[i];
      ctx.globalAlpha = alphaFor(cycle - record[0], horizon);
      for (const [polarity, bitmap] of [[1,record[3]],[0,record[4]]]) {{
        ctx.fillStyle = polarity ? onColor : offColor;
        for (let bit = 0; bit < 4; bit++) if (bitmap & (1 << bit)) {{
          const pixel = tilePixel(record[2], bit);
          ctx.fillRect(pixel[0], pixel[1], 1, 1);
        }}
      }}
      if (record[5] > 0) {{
        const pixel = tilePixel(record[2], 0);
        ctx.strokeStyle = record[5] === 2 ? binColor : groupColor;
        ctx.lineWidth = 0.7;
        ctx.strokeRect(pixel[0] - 0.25, pixel[1] - 0.25, 2.5, 2.5);
      }}
      if (record[0] === cycle) nowEvents += record[6];
    }}
    ctx.globalAlpha = 1;
    return [end ? received[end - 1][8] : 0, nowEvents, end];
  }}
  function drawPending(cycle) {{
    const ctx = clear(pendingCanvas);
    let pendingGroups = 0, pendingEvents = 0, oldest = 0;
    for (const group of groups) {{
      if (group[1] > cycle) break;
      const receiveCycle = receiveCycles[group[0]];
      if (receiveCycle >= 0 && receiveCycle <= cycle) continue;
      pendingGroups++;
      pendingEvents += group[5];
      oldest = Math.max(oldest, cycle - group[1]);
      ctx.globalAlpha = Math.max(0.28, Math.min(1, (cycle - group[1] + 1) / 64));
      for (const [polarity, bitmap] of [[1,group[3]],[0,group[4]]]) {{
        ctx.fillStyle = polarity ? onColor : offColor;
        for (let bit = 0; bit < 4; bit++) if (bitmap & (1 << bit)) {{
          const pixel = tilePixel(group[2], bit);
          ctx.fillRect(pixel[0], pixel[1], 1, 1);
        }}
      }}
    }}
    ctx.globalAlpha = 1;
    return [pendingGroups, pendingEvents, oldest];
  }}
  function wordAt(cycle) {{
    const end = upperBound(words, cycle);
    return end && words[end - 1][0] === cycle ? words[end - 1] : null;
  }}
  function updateWord(cycle) {{
    const word = wordAt(cycle);
    const wordElement = root.querySelector('#aer-sl-word');
    const detailElement = root.querySelector('#aer-sl-word-detail');
    if (!word) {{
      wordElement.textContent = '출력 없음';
      detailElement.textContent = '이 클록에는 링크 전송이 없음';
      return;
    }}
    const bits = word[1].toString(2).padStart(16, '0');
    wordElement.textContent = `${{bits.slice(0,2)}} ${{bits.slice(2,6)}} ${{bits.slice(6,10)}} ${{bits.slice(10)}} · 0x${{word[1].toString(16).padStart(4,'0')}}`;
    let detail = `${{wordTypeNames[word[3]]}} · bank ${{word[4]}} · row ${{word[5]}}`;
    if (word[3] === 0) detail += ` · column mask 0b${{word[6].toString(2).padStart(4,'0')}}`;
    if (word[3] === 1) detail += ` · row timestamp ${{word[1]}}`;
    if (word[3] === 2) detail += ` · column ${{word[7]}} · ${{formatNames[word[8]]}} · delta ${{word[9]}} · 이벤트 수신 완료`;
    detailElement.textContent = detail;
  }}
  function update() {{
    const cycle = Number(range.value);
    const horizon = Number(view.value);
    const sourceStats = drawSource(cycle, horizon);
    const receivedStats = drawReceived(cycle, horizon);
    const pendingStats = drawPending(cycle);
    const hardwareUs = cycle * clockNs / 1000;
    root.querySelector('#aer-sl-label').textContent = `${{cycle.toLocaleString()}} / ${{lastCycle.toLocaleString()}} · ${{hardwareUs.toFixed(2)}} μs`;
    root.querySelector('#aer-sl-counts').textContent = `실제 발생 ${{sourceStats[0].toLocaleString()}}/${{sourceTotal.toLocaleString()}} · 링크 수신 ${{receivedStats[0].toLocaleString()}}/${{sourceTotal.toLocaleString()}} · 통신 대기 ${{pendingStats[1].toLocaleString()}}`;
    root.querySelector('#aer-sl-source-detail').textContent = `이번 클록 ${{sourceStats[1].toLocaleString()}}개 발생 · 원본 ${{sourceDurationMs.toFixed(3)}} ms를 ${{sourceEndCycle + 1}}클록으로 압축 (${{playbackSpeed.toLocaleString()}}×)`;
    root.querySelector('#aer-sl-received-detail').textContent = `이번 클록 ${{receivedStats[1].toLocaleString()}}개 수신 · DATA 워드에서만 화면에 반영`;
    root.querySelector('#aer-sl-pending-detail').textContent = `${{pendingStats[0].toLocaleString()}}개 타일 그룹 · 가장 오래 기다린 이벤트 ${{pendingStats[2].toLocaleString()}}클록`;
    updateWord(cycle);
  }}
  function move(delta) {{
    range.value = Math.max(0, Math.min(lastCycle, Number(range.value) + delta));
    update();
  }}
  play.addEventListener('click', () => {{ playing = !playing; play.textContent = playing ? '일시정지' : '재생'; }});
  root.querySelector('#aer-sl-prev').addEventListener('click', () => {{ playing = false; play.textContent = '재생'; move(-1); }});
  root.querySelector('#aer-sl-next').addEventListener('click', () => {{ playing = false; play.textContent = '재생'; move(1); }});
  range.addEventListener('input', () => {{ playing = false; play.textContent = '재생'; update(); }});
  view.addEventListener('change', update);
  function tick(now) {{
    if (playing && now - lastFrame >= 50) {{
      const next = Number(range.value) + Number(speed.value);
      range.value = next > lastCycle ? 0 : next;
      update();
      lastFrame = now;
    }}
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
    parser.add_argument("html_fragment", type=Path)
    args = parser.parse_args()

    manifest = json.loads(args.manifest_json.read_text(encoding="utf-8"))
    accepted, words = parse_rtl_log(args.rtl_log)
    decoded, errors, _ = decode_words(accepted, words)
    if errors:
        raise SystemExit("cannot render invalid RTL log: " + "; ".join(errors[:3]))
    write_fragment(args.html_fragment, manifest, decoded, words)
    print(
        f"V1_SOURCE_LINK_COMPARE source={len(manifest['events'])} "
        f"received={sum(int(record['source_events']) for record in decoded)} "
        f"cycles={max((record[0] for record in words), default=0) + 1}"
    )


if __name__ == "__main__":
    main()
