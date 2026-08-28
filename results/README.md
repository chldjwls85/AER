# Results

## Dataset / traffic

- `summary.csv`: RAW/Team/V3 dataset metrics를 저장함.
- `metrics/`: compact JSON measurements와 조건을 저장함.
- `figures/`: representative comparison plot을 저장함.
- `logs/`: XSim regression과 dataset summary를 저장함.
- `summary.csv`의 `Current`는 V3 full-evaluation 당시 명칭임.

## V5 synthesis

### Research DC

`results/synthesis/dc_v5/`

- `run_summary.txt`
- `qor.rpt`
- `area_summary.rpt`
- `timing_summary.rpt`
- `check_design_summary.txt`

핵심 결과:

- Critical Path 25.26 ns
- WNS -15.49 ns
- TNS -770,141.69 ns
- Design Area 3,502,284.69
- Runtime 3,045 s

### Competition Genus

`results/synthesis/genus_v5/`

- `genus_v5_summary.txt`: 실제 완료 run의 original summary임.
- `results_summary.txt`: 최종 QoR/area/power/timing 핵심 수치를 정리함.

핵심 결과:

- 100 MHz Timing **MET**
- WNS +0.5819 ns
- TNS 0 ns
- Violating Paths 0
- Cell Area 1,590,675.448
- Power estimate 약 43.84 mW
- Elapsed Runtime 9,207 s

> 업로드된 competition archive에는 full raw `area/qor/timing/power` report가 포함되지 않아, original `genus_v5_summary.txt`와 최종 report 수치 summary를 추적함.

## 문서

- 설계 진화: `docs/AER_V3_V5_DESIGN_EVOLUTION.md`
- 연구실 DC 비교: `docs/DC_SAED32_COMPARISON.md`
- 대회 Genus 결과: `docs/GENUS_V5_RESULTS.md`
