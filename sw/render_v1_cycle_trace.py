"""Render an interactive, cycle-by-cycle view of an AER v1 XSim log."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from sw.render_v1_uzh_reconstruction import decode_words, parse_rtl_log


def annotate_words(words: list[tuple[int, int, int]]) -> list[list[int]]:
    """Attach packet phase and selected hierarchy fields to every output word."""
    annotated: list[list[int]] = []
    phase = 0
    bank = -1
    row = -1
    column_mask = 0
    columns: list[int] = []

    for cycle, word, last in words:
        column = -1
        format_code = -1
        delta = -1
        if phase == 0:
            if word >> 14 != 0x3:
                raise ValueError(f"expected header at cycle {cycle}: 0x{word:04x}")
            bank = (word >> 6) & 0xFF
            row = (word >> 4) & 0x3
            column_mask = word & 0xF
            columns = [index for index in range(4) if column_mask & (1 << index)]
            phase = 1
            word_type = 0
        elif phase == 1:
            word_type = 1
            phase = 2
        else:
            if not columns:
                raise ValueError(f"data word has no pending column at cycle {cycle}")
            word_type = 2
            column = columns.pop(0)
            format_code = (word >> 14) & 0x3
            delta = (word >> 10) & 0xF
            if last:
                if columns:
                    raise ValueError(f"early last at cycle {cycle}")
                phase = 0
        annotated.append([
            cycle, word, last, word_type, bank, row, column_mask,
            column, format_code, delta,
        ])

    if phase != 0:
        raise ValueError("truncated packet at end of log")
    return annotated


def write_fragment(
    path: Path,
    accepted: list[dict[str, int]],
    decoded: list[dict[str, int | str]],
    words: list[tuple[int, int, int]],
    clock_hz: int,
) -> None:
    accepted_data = [
        [
            record["accept_cycle"], record["tile"], record["on"], record["off"],
            record["source_events"], record["source_cycle"],
        ]
        for record in accepted
    ]
    format_codes = {"RAW8": 0, "GROUP3": 1, "BIN4": 2}
    decoded_data = [
        [
            int(record["receive_cycle"]), int(record["tile"]), int(record["on"]),
            int(record["off"]), format_codes[str(record["format"])],
            int(record["group_id"]),
        ]
        for record in decoded
    ]
    word_data = annotate_words(words)
    last_cycle = max(
        max((record[0] for record in accepted_data), default=0),
        max((record[0] for record in decoded_data), default=0),
        max((record[0] for record in word_data), default=0),
    )
    clock_ns = 1_000_000_000 / clock_hz

    fragment = f'''<div id="aer-cycle-trace">
  <h2>RTL 클록별 AER 처리</h2>
  <div class="viz-controls">
    <button type="button" class="btn btn-primary" id="aer-cycle-play">일시정지</button>
    <button type="button" class="btn" id="aer-cycle-prev">이전 클록</button>
    <button type="button" class="btn" id="aer-cycle-next">다음 클록</button>
    <label class="form-label" for="aer-cycle-speed">재생 속도
      <select class="form-select" id="aer-cycle-speed"><option value="1">1클록</option><option value="10" selected>10클록</option><option value="50">50클록</option><option value="200">200클록</option></select>
    </label>
  </div>
  <label class="form-label" for="aer-cycle-range">클록 <span id="aer-cycle-label">0</span></label>
  <input class="form-range" id="aer-cycle-range" type="range" min="0" max="{last_cycle}" step="1" value="0">
  <div class="viz-row text-small" id="aer-cycle-counts"></div>
  <div class="aer-cycle-panels">
    <section><h3>타일 수락 · 최근 64클록</h3><canvas id="aer-cycle-input" width="128" height="128" role="img" aria-label="클록별 타일 입력 수락 이벤트"></canvas><p class="text-small text-muted" id="aer-cycle-input-detail"></p></section>
    <section><h3>링크 수신 · 최근 64클록</h3><canvas id="aer-cycle-output" width="128" height="128" role="img" aria-label="클록별 링크 수신 이벤트"></canvas><p class="text-small text-muted" id="aer-cycle-output-detail"></p></section>
  </div>
  <div class="aer-cycle-lower">
    <section><h3>16×16 뱅크</h3><canvas id="aer-cycle-banks" width="256" height="256" role="img" aria-label="현재 클록의 입력 뱅크와 출력 선택 뱅크"></canvas><p class="text-small text-muted">입력 수락 뱅크 · 현재 출력 뱅크</p></section>
    <section class="card" aria-live="polite"><h3>현재 16비트 출력</h3><p id="aer-cycle-word"></p><p class="text-small text-muted" id="aer-cycle-word-detail"></p></section>
  </div>
  <div class="viz-row text-small"><span>파란색 ON</span><span>주황색 OFF</span><span>보라색 GROUP3</span><span>초록색 BIN4</span></div>
</div>
<style>
#aer-cycle-trace {{ width:100%; }}
#aer-cycle-trace .aer-cycle-panels {{ display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:20px; }}
#aer-cycle-trace .aer-cycle-lower {{ display:grid; grid-template-columns:minmax(220px,0.7fr) minmax(280px,1.3fr); gap:20px; align-items:start; margin-top:20px; }}
#aer-cycle-trace section {{ min-width:0; }}
#aer-cycle-trace #aer-cycle-input, #aer-cycle-trace #aer-cycle-output {{ width:100%; height:auto; aspect-ratio:1; image-rendering:pixelated; background:var(--card); }}
#aer-cycle-trace #aer-cycle-banks {{ width:min(100%,256px); height:auto; aspect-ratio:1; background:var(--card); }}
#aer-cycle-trace .form-range {{ width:100%; }}
#aer-cycle-trace code {{ overflow-wrap:anywhere; }}
@media (max-width:560px) {{ #aer-cycle-trace .aer-cycle-panels, #aer-cycle-trace .aer-cycle-lower {{ grid-template-columns:1fr; }} }}
</style>
<script>
(() => {{
  const root = document.getElementById('aer-cycle-trace');
  const accepted = {json.dumps(accepted_data, separators=(',', ':'))};
  const decoded = {json.dumps(decoded_data, separators=(',', ':'))};
  const words = {json.dumps(word_data, separators=(',', ':'))};
  const lastCycle = {last_cycle};
  const clockNs = {clock_ns:g};
  const formatNames = ['RAW8','GROUP3','BIN4','RESERVED'];
  const wordTypeNames = ['HEADER','TIME','DATA'];
  const range = root.querySelector('#aer-cycle-range');
  const label = root.querySelector('#aer-cycle-label');
  const play = root.querySelector('#aer-cycle-play');
  const speed = root.querySelector('#aer-cycle-speed');
  const inputCanvas = root.querySelector('#aer-cycle-input');
  const outputCanvas = root.querySelector('#aer-cycle-output');
  const bankCanvas = root.querySelector('#aer-cycle-banks');
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
  const foreground = resolvedColor('--foreground');
  const muted = resolvedColor('--muted');
  const onColor = resolvedColor('--viz-series-1');
  const offColor = resolvedColor('--viz-series-2');
  const groupColor = resolvedColor('--viz-series-3');
  const binColor = resolvedColor('--viz-series-4');
  let playing = true;
  let lastFrame = performance.now();

  function tilePixel(tile, bit) {{
    const bank = Math.floor(tile / 16), local = tile % 16;
    const bankRow = Math.floor(bank / 16), bankCol = bank % 16;
    const localRow = Math.floor(local / 4), localCol = local % 4;
    return [(bankCol * 4 + localCol) * 2 + (bit & 1), (bankRow * 4 + localRow) * 2 + ((bit >> 1) & 1)];
  }}
  function upperBound(records, cycle) {{
    let lo = 0, hi = records.length;
    while (lo < hi) {{ const mid = (lo + hi) >> 1; if (records[mid][0] <= cycle) lo = mid + 1; else hi = mid; }}
    return lo;
  }}
  function drawEvents(canvas, records, cycle, isOutput) {{
    const ctx = canvas.getContext('2d');
    ctx.globalAlpha = 1; ctx.fillStyle = background; ctx.fillRect(0,0,128,128);
    let current = 0;
    const start = Math.max(0, cycle - 63);
    const endIndex = upperBound(records, cycle);
    for (let i = endIndex - 1; i >= 0 && records[i][0] >= start; i--) {{
      const record = records[i], age = cycle - record[0];
      ctx.globalAlpha = age === 0 ? 1 : Math.max(0.14, Math.exp(-age / 20));
      for (const [polarity, bitmap] of [[1,record[2]],[0,record[3]]]) {{
        ctx.fillStyle = polarity ? onColor : offColor;
        for (let bit=0; bit<4; bit++) if (bitmap & (1<<bit)) {{ const [x,y]=tilePixel(record[1],bit); ctx.fillRect(x,y,1,1); }}
      }}
      if (isOutput && record[4] > 0) {{
        const [x,y] = tilePixel(record[1],0);
        ctx.strokeStyle = record[4] === 2 ? binColor : groupColor;
        ctx.lineWidth = 0.7; ctx.strokeRect(x-0.25,y-0.25,2.5,2.5);
      }}
      if (age === 0) current++;
    }}
    ctx.globalAlpha = 1;
    return current;
  }}
  function recordsAt(records, cycle) {{
    const end = upperBound(records, cycle), result = [];
    for (let i=end-1; i>=0 && records[i][0]===cycle; i--) result.push(records[i]);
    return result;
  }}
  function drawBanks(cycle, word) {{
    const ctx = bankCanvas.getContext('2d'), cell = 16;
    ctx.fillStyle = background; ctx.fillRect(0,0,256,256);
    ctx.strokeStyle = muted; ctx.lineWidth = 0.5;
    for (let i=0;i<16;i++) for(let j=0;j<16;j++) ctx.strokeRect(j*cell,i*cell,cell,cell);
    const banks = new Set(recordsAt(accepted,cycle).map(r => Math.floor(r[1]/16)));
    ctx.globalAlpha = 0.65; ctx.fillStyle = onColor;
    for (const bank of banks) ctx.fillRect((bank%16)*cell,Math.floor(bank/16)*cell,cell,cell);
    if (word) {{ ctx.globalAlpha=1; ctx.strokeStyle=groupColor; ctx.lineWidth=2; ctx.strokeRect((word[4]%16)*cell+1,Math.floor(word[4]/16)*cell+1,cell-2,cell-2); }}
    ctx.globalAlpha=1;
  }}
  function wordAt(cycle) {{
    const end = upperBound(words,cycle);
    return end && words[end-1][0]===cycle ? words[end-1] : null;
  }}
  function update() {{
    const cycle = Number(range.value), acceptedNow = drawEvents(inputCanvas,accepted,cycle,false), decodedNow = drawEvents(outputCanvas,decoded,cycle,true);
    const acceptedTotal = upperBound(accepted,cycle), decodedTotal = upperBound(decoded,cycle), wordTotal = upperBound(words,cycle);
    const word = wordAt(cycle);
    label.textContent = `${{cycle.toLocaleString()}} / ${{lastCycle.toLocaleString()}} · ${{(cycle*clockNs/1000).toFixed(2)}} μs`;
    root.querySelector('#aer-cycle-counts').textContent = `누적 타일 수락 ${{acceptedTotal.toLocaleString()}}/${{accepted.length.toLocaleString()}} · 누적 데이터 수신 ${{decodedTotal.toLocaleString()}}/${{decoded.length.toLocaleString()}} · 출력 워드 ${{wordTotal.toLocaleString()}}/${{words.length.toLocaleString()}}`;
    root.querySelector('#aer-cycle-input-detail').textContent = `이번 클록 수락 타일 ${{acceptedNow.toLocaleString()}}개`;
    root.querySelector('#aer-cycle-output-detail').textContent = `이번 클록 수신 데이터 ${{decodedNow.toLocaleString()}}개`;
    drawBanks(cycle,word);
    if (!word) {{
      root.querySelector('#aer-cycle-word').innerHTML = '<code>출력 없음</code>';
      root.querySelector('#aer-cycle-word-detail').textContent = 'out_valid 또는 out_ready 전송이 없는 클록';
      return;
    }}
    const bits = word[1].toString(2).padStart(16,'0');
    root.querySelector('#aer-cycle-word').innerHTML = `<code>${{bits.slice(0,2)}} ${{bits.slice(2,6)}} ${{bits.slice(6,10)}} ${{bits.slice(10)}} · 0x${{word[1].toString(16).padStart(4,'0')}}</code>`;
    let detail = `${{wordTypeNames[word[3]]}} · bank ${{word[4]}} · row ${{word[5]}}`;
    if (word[3]===0) detail += ` · column mask 0b${{word[6].toString(2).padStart(4,'0')}}`;
    if (word[3]===1) detail += ` · row timestamp ${{word[1]}}`;
    if (word[3]===2) detail += ` · column ${{word[7]}} · ${{formatNames[word[8]]}} · delta ${{word[9]}} · last ${{word[2]}}`;
    root.querySelector('#aer-cycle-word-detail').textContent = detail;
  }}
  function move(delta) {{ range.value = Math.max(0,Math.min(lastCycle,Number(range.value)+delta)); update(); }}
  play.addEventListener('click',()=>{{ playing=!playing; play.textContent=playing?'일시정지':'재생'; }});
  root.querySelector('#aer-cycle-prev').addEventListener('click',()=>{{playing=false;play.textContent='재생';move(-1);}});
  root.querySelector('#aer-cycle-next').addEventListener('click',()=>{{playing=false;play.textContent='재생';move(1);}});
  range.addEventListener('input',()=>{{playing=false;play.textContent='재생';update();}});
  function tick(now) {{
    if (playing && now-lastFrame>=50) {{ const next=Number(range.value)+Number(speed.value); range.value=next>lastCycle?0:next; update(); lastFrame=now; }}
    requestAnimationFrame(tick);
  }}
  update(); requestAnimationFrame(tick);
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
    write_fragment(args.html_fragment, accepted, decoded, words, int(manifest["clock_hz"]))
    print(
        f"V1_CYCLE_TRACE cycles={max((word[0] for word in words), default=0)+1} "
        f"accepted={len(accepted)} words={len(words)} decoded={len(decoded)}"
    )


if __name__ == "__main__":
    main()
