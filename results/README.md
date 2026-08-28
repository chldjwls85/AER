# Results

## Dataset / traffic

- `summary.csv`: RAW/Team/V3 dataset metrics를 저장함.
- `metrics/`: compact JSON measurements와 조건을 저장함.
- `figures/`: representative comparison plot을 저장함.
- `logs/`: XSim regression과 dataset summary를 저장함.
- `summary.csv`의 `Current`는 V3 full-evaluation 당시 명칭임.

## V5 Synthesis

### Research DC

`results/synthesis/dc_v5/`

- `run_summary.txt`
- `qor.rpt`
- `area_summary.rpt`
- `timing_summary.rpt`
- `check_design_summary.txt`

핵심 결과:

- Critical Path: 25.26 ns
- WNS: -15.49 ns
- TNS: -770,141.69 ns
- Design Area: 3,502,284.69
- Runtime: 3,045 s

연구실 원본 report 기준으로 V4의 global timestamp distribution worst path가 V5에서 제거되고, bank-local `pending_reg → sparse_pixel_reg`가 다음 critical path로 이동함을 확인함.

### Competition Genus

`results/synthesis/genus_v5/`

실제 대회 서버 최종 run의 report bundle을 직접 확인한 뒤 결과를 확정함.

보존 파일:

- `genus_v5_summary.txt`: 실제 run summary임.
- `check_design.rpt`: 원본 check-design report임.
- `qor.rpt`: 원본 QoR report임.
- `power.rpt`: 원본 power report임.
- `area_summary.rpt`: 원본 `area.rpt`에서 top-level area와 16 Regional Timebase hierarchy 근거를 추출함.
- `timing_worst_path.rpt`: 원본 `timing.rpt`의 worst setup path를 추출함.
- `source_manifest.txt`: 전달받은 full-report archive와 각 원본 파일의 SHA-256을 기록함.

핵심 결과:

- Target Clock: 100 MHz (10 ns)
- Timing: **MET**
- WNS: +0.5819 ns
- TNS: 0 ns
- Violating Paths: 0
- Worst Data Path: 9.075 ns
- Cell Area: 1,590,675.448
- Power Estimate: 43.84 mW
- Elapsed Runtime: 9,207 s

추가 확인:

- unresolved reference 없음.
- empty module 없음.
- 16개 Regional Timebase hierarchy가 합성 결과에 유지됨.
- worst setup path는 `pending_reg[0] → sparse_pixel_reg[0]`임.
- V4의 global timestamp distribution은 최종 worst path에서 제외됨.
- console 기준 전체 synthesis stage 완료 및 `Error:` / `Fatal:` marker 없음.

상세 해석은 `docs/GENUS_V5_RESULTS.md`에 정리함.

## 문서

- 설계 진화: `docs/AER_V3_V5_DESIGN_EVOLUTION.md`
- 연구실 DC 비교: `docs/DC_SAED32_COMPARISON.md`
- 대회 Genus 결과: `docs/GENUS_V5_RESULTS.md`
