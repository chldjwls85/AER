# Results

> 명칭 주의: `summary.csv`와 `xsim_current_adaptive_*`의 `Current`는 V3를 의미함.
> V4 full UZH sweep 결과는 포함하지 않음.

- 목적: 재현 가능한 소형 summary와 대표 media만 Git으로 관리함
- 제외 대상: raw dataset, XSim build tree, wave database, 정리되지 않은 log임

- `summary.csv`: machine-readable cross-design dataset metrics
- `metrics/`: compact JSON measurements and experiment conditions
- `figures/`: representative static comparisons and performance plots
- `animations/`: representative event-flow animation
- `logs/regression_summary.txt`: curated XSim regression result
- `logs/dataset_xsim_summary.txt`: nine representative RTL runs
- `logs/evaluation_summary.txt`: compact decision evidence

- Full sweep: `summary.csv`에 RAW/Team/Current 결과를 저장함
- Representative window: `metrics/xsim_*.json`에 accepted/decoded count를 저장함

- 당시 final status: `READY FOR CADENCE EVALUATION`임
- UZH 결과: 7-speed full sweep 완료함
- RTL 결과: representative round-trip 9/9 PASS함
- Unintended loss: 0임
- Cadence tool: 이 results set 생성 단계에서는 실행하지 않음
- 이후 V3/V4 최종 상태: `docs/AER_V3_V4_DESIGN_EVOLUTION.md` 참조 필요함
