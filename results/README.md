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

대회 서버 최종 run에서 생성된 report를 기준으로 결과를 확정함.

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

원본 report에서 다음을 추가 확인함.

- `check_design`: unresolved reference 없음, empty module 없음.
- `area`: 16개 Regional Timebase hierarchy가 각각 존재함.
- `timing`: worst setup path가 `pending_reg[0] → sparse_pixel_reg[0]`임.
- `power`: total 0.0438355 W, register 64.99%, logic 35.01%임.
- console stage: `read_hdl → elaborate → check_design → syn_generic → syn_map → syn_opt → report` 전체 DONE임.
- `Error:` / `Fatal:` marker 없음.

상세 해석은 `docs/GENUS_V5_RESULTS.md`에 정리함.

## 문서

- 설계 진화: `docs/AER_V3_V5_DESIGN_EVOLUTION.md`
- 연구실 DC 비교: `docs/DC_SAED32_COMPARISON.md`
- 대회 Genus 결과: `docs/GENUS_V5_RESULTS.md`
