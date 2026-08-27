# V5 Genus 합성 Handoff

## 배경

- 목적: V4 global timebase와 V5 regional timebase의 timing/area를 동일 조건으로 비교함.
- V5 top: `aer_top_v5_128`을 사용함.
- V5 filelist: `rtl/filelist_v5.f`를 사용함.
- 원칙: V4 RTL, V5 RTL, 기존 V4 Genus flow를 수정하지 않음.
- 원칙: 첫 clean synthesis에서 `dont_touch`, `preserve`, `keep`, synthesis attribute를 적용하지 않음.
- 실행 주체: 장시간 Genus 합성은 대회 서버에서 사용자가 직접 실행함.

## 동일 비교 조건

- Genus 기준: 문서화된 V3/V4 `23.14-s090_1` 조건을 재사용함.
- Technology: GSCLIB 45 nm를 사용함.
- Library/PVT: `slow_vdd1v0_basicCells.lib`, `slow_vdd1v0`, 0.9 V/125°C 조건을 재사용함.
- Library 절대경로: repository에 없으므로 검증된 V4/V3 server setup fragment에서 제공함.
- Clock: 기존 `constraints/aer_v4_100mhz.sdc`의 10.000 ns/100 MHz를 그대로 사용함.
- Clock uncertainty: 기존 SDC의 0.200 ns를 그대로 사용함.
- Reset/I/O constraint: 검증된 V4/V3 `AER_GENUS_V3_IO_CONSTRAINTS_TCL`을 그대로 source함.
- Synthesis: V4와 동일하게 `syn_generic`, `syn_map`, `syn_opt` 순서로 실행함.
- Effort/option: 검증된 `AER_GENUS_SERVER_SETUP_TCL`에서 V4와 동일하게 적용함.
- Power: V4와 동일한 power hook이 있을 때만 적용함. 없으면 신규 방법을 추가하지 않음.

## `/tmp` 실행 구조

- 다른 사용자 directory를 재사용하지 않음.
- 현재 사용자명, UTC run tag, PID로 unique directory를 생성함.
- 기존 directory가 있으면 삭제하지 않고 즉시 오류 종료함.

```text
/tmp/<user>_aer_genus_v5_<run_tag>_<pid>/
├── scripts/
│   └── genus_v5_full.tcl
├── reports/
│   ├── check_design.rpt
│   ├── area.rpt
│   ├── timing.rpt
│   ├── qor.rpt
│   └── power.rpt
├── logs/
│   └── genus_console.log
├── out/
│   ├── aer_top_v5_128_mapped.v
│   └── aer_top_v5_128_mapped.sdc
├── work/
│   └── tmp/
├── home/
└── genus_v5_summary.txt
```

- `HOME`: run directory의 `home/`으로 격리함.
- `TMPDIR`, `TMP`, `TEMP`: run directory의 `work/tmp/`으로 격리함.
- Genus working directory: run directory의 `work/`를 사용함.
- Console log: run directory의 `logs/genus_console.log`에 저장함.

## 실행 방법

- 대회 서버에서 기존 Genus 환경을 먼저 설정함.
- 검증된 V4/V3 server fragment의 실제 절대경로를 사용함.
- V4에서 power hook을 사용하지 않았다면 `AER_GENUS_V3_POWER_TCL`을 설정하지 않음.

```bash
cd <EXISTING_SERVER_AER_REPO>
git fetch origin
git switch AER_hyeonho
git pull --ff-only origin AER_hyeonho

source <EXISTING_CADENCE_GENUS_ENV_SETUP>

export AER_GENUS_SERVER_SETUP_TCL=<VERIFIED_V4_V3_SERVER_SETUP_TCL>
export AER_GENUS_V3_IO_CONSTRAINTS_TCL=<VERIFIED_V4_V3_IO_CONSTRAINTS_TCL>
unset AER_GENUS_V3_POWER_TCL

export AER_GENUS_RUN_TAG="$(date -u +%Y%m%d_%H%M%S)"
export AER_GENUS_RUN_DIR="/tmp/$(id -un)_aer_genus_v5_${AER_GENUS_RUN_TAG}_$$"

bash scripts/genus/run_genus_v5_tmp.sh
```

- V4에서 검증된 power fragment를 실제로 사용한 경우에만 실행 전에 다음을 적용함.

```bash
export AER_GENUS_V3_POWER_TCL=<VERIFIED_V4_V3_POWER_TCL>
```

## 결과 확인 방법

- Stage 완료: console log에서 `AER_STAGE_START`, `AER_STAGE_DONE`을 확인함.
- 전체 완료: `AER_GENUS_V5_FULL_SYNTHESIS_DONE`을 확인함.
- Tool/version: `logs/genus_console.log`의 Genus 시작 banner를 확인함.
- Library/PVT/option: console log와 `genus_v5_summary.txt`의 setup fragment 경로를 확인함.
- Runtime: 각 stage marker의 `elapsed_sec`와 console timestamp를 확인함.
- Area/cell 정보: `reports/area.rpt`, `reports/qor.rpt`를 확인함.
- Timing/WNS/TNS/violating path: `reports/timing.rpt`, `reports/qor.rpt`를 확인함.
- Critical path: `reports/timing.rpt`의 max path를 확인함.
- Estimated Fmax: clock period와 critical path delay를 기준으로 별도 계산함.
- Hierarchical area: `reports/area.rpt`가 제공하는 hierarchy 내용을 확인함.
- Mapped netlist/constraint: `out/aer_top_v5_128_mapped.v`, `out/aer_top_v5_128_mapped.sdc`를 확인함.

```bash
grep -E "AER_STAGE_(START|DONE)|AER_GENUS_V5_FULL_SYNTHESIS_DONE" \
    "$AER_GENUS_RUN_DIR/logs/genus_console.log"
grep -Ei "area|cell|sequential|combinational" \
    "$AER_GENUS_RUN_DIR/reports/area.rpt" \
    "$AER_GENUS_RUN_DIR/reports/qor.rpt"
grep -Ei "slack|wns|tns|violat|path" \
    "$AER_GENUS_RUN_DIR/reports/timing.rpt" \
    "$AER_GENUS_RUN_DIR/reports/qor.rpt"
```

## Regional Timebase merge 사후 확인

- 1차 확인: mapped netlist에 regional generate/instance/net 이름이 남았는지 검색함.
- 2차 확인: timebase 관련 hierarchy가 16개인지 area/qor report에서 검색함.
- 3차 확인: Genus session에서 regional counter output net의 load/fanout을 확인함.
- 주의: mapped netlist에 원래 이름이 없다는 사실만으로 counter merge를 확정하지 않음.
- 판단: hierarchy flatten/rename 가능성이 있으므로 instance 수와 fanout을 함께 확인함.

```bash
grep -nE "gen_regional_timebase|regional_timebase_i|regional_time_flat|time_now" \
    "$AER_GENUS_RUN_DIR/out/aer_top_v5_128_mapped.v"
grep -niE "regional|timebase" \
    "$AER_GENUS_RUN_DIR/reports/area.rpt" \
    "$AER_GENUS_RUN_DIR/reports/qor.rpt"
```

- Genus session에서 사용 가능한 기존 UI command 기준으로 다음 대상을 확인함.

```tcl
get_cells -hierarchical *regional_timebase*
get_nets -hierarchical *regional_time_flat*
report_net -connections [get_nets -hierarchical *regional_time_flat*]
```

- 위 query 결과가 비어 있으면 mapped netlist와 fanout report를 기준으로 rename/flatten/merge 여부를 추가 판단함.
