# V4 Genus Full-Synthesis Handoff

## Fixed comparison condition

- Top: `aer_top_v4_128`
- RTL filelist: `rtl/filelist_v4.f`
- Genus baseline: documented V3 `23.14-s090_1`
- Technology: GSCLIB 45nm
- Library/PVT: `slow_vdd1v0_basicCells.lib`, `slow_vdd1v0`, 0.9V/125C
- Clock: 10ns / 100MHz
- Clock uncertainty: 0.2ns

- Repository에 없는 정보: 대회 server의 V3 library path, I/O constraint, effort/option, power methodology임
- 원칙: 확인되지 않은 server 설정을 추측하지 않음
- 적용 방법: 기존 V3 flow에서 검증된 server fragment를 준비하고 환경 변수로 전달함

- `AER_GENUS_SERVER_SETUP_TCL`: library/PVT/search path and exact effort/options
- `AER_GENUS_V3_IO_CONSTRAINTS_TCL`: exact V3 I/O delay/drive/load constraints
- `AER_GENUS_V3_POWER_TCL`: optional exact V3 power methodology

- Example hook: placeholder를 검증된 server command로 교체하기 전에는 의도적으로 error 종료함

## Output

- 출력 분리: 실행마다 UTC tag가 포함된 별도 directory를 생성함

```text
results/genus_v4/<run_tag>/
├── logs/genus_console.log
├── reports/check_design.rpt
├── reports/area.rpt
├── reports/timing.rpt
├── reports/qor.rpt
├── reports/power.rpt
├── netlist/aer_top_v4_128_mapped.v
├── netlist/aer_top_v4_128_mapped.sdc
└── genus_v4_summary.txt
```

- Stage marker: `AER_STAGE_START`, `AER_STAGE_DONE` 사용함
- Runtime 정보: UTC, epoch, elapsed seconds 기록함
- Power hook 미제공: `POWER_METHOD_REQUIRES_EXISTING_SERVER_SETUP`을 log/summary에 기록함

## Server execution

```bash
cd <EXISTING_SERVER_AER_REPO>
git fetch origin
git switch AER_hyeonho
git pull --ff-only origin AER_hyeonho
```

```bash
export AER_GENUS_SERVER_SETUP_TCL=<VERIFIED_V3_SERVER_SETUP_TCL>
export AER_GENUS_V3_IO_CONSTRAINTS_TCL=<VERIFIED_V3_IO_CONSTRAINTS_TCL>
export AER_GENUS_V3_POWER_TCL=<VERIFIED_V3_POWER_TCL>  # omit only if unavailable
bash scripts/genus/run_genus_v4.sh
```

- Non-Git 전달: `scripts/genus/v4_handoff_manifest.txt`의 경로만 전달하면 됨
