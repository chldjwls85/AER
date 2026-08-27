# Synopsys DC SAED32 V3/V4 comparison

- 목적: 동일한 연구실 Synopsys Design Compiler/SAED32 조건에서 V3와 V4를 상대 비교함
- 용도: synthesis runtime, Area, Timing의 보조 structural screening임
- 공식성: 대회 공식 Genus/PPA flow가 아님
- 주의: SAED32 절대 PPA를 대회 공식 결과로 사용하면 안 됨

## Fixed comparison conditions

- Tool: Synopsys Design Compiler V-2023.12-SP4
- Library: `/home/KNUEEhdd1/idec/techfiles/saed28edk/saed32hvt_ff0p95v125c.db`
- Corner: SAED32 HVT FF, 0.95 V, 125 C
- Clock: 10.0 ns (100 MHz)
- Clock uncertainty: 0.2 ns
- Reset constraint: `set_false_path -from [get_ports rst_n]`
- HDL parser: `analyze -format sverilog`, followed by `elaborate` and `link`
- Optimization: basic `compile` for both versions
- V3 top/filelist: `aer_top_128`, `rtl/filelist.f`
- V4 top/filelist: `aer_top_v4_128`, `rtl/filelist_v4.f`

- 공통 flow: `scripts/dc/dc_common.tcl` 사용함
- 동일 조건: library, constraint, optimization, report command가 V3/V4에서 동일함
- 유일한 차이: top module과 RTL filelist임

## Server boundary and outputs

Repository root는 다음 경로로 고정함.

`/home/KNUEEhdd1/kimdo904/02-dc/hyeonho`

- 위치 보호: Tcl과 launcher가 다른 repository root를 거부함
- 수정 금지: `/01-aes`, `/04-aer`, `/05-aer_ej` 등 기존 server workspace 사용 금지함
- 출력 분리: `dc_results/v3/`, `dc_results/v4/`에 각각 저장함
- 기록 항목: console log, start/end/elapsed time, pre/post `check_design`, QoR, Area, Timing임
- 생성물: mapped Verilog와 generated SDC임
- Git 정책: `dc_results/`는 추적하지 않음

## Run

연구실 server의 repository root에서 다음 명령을 실행함.

```csh
chmod +x scripts/dc/run_dc_v3.csh scripts/dc/run_dc_v4.csh
./scripts/dc/run_dc_v3.csh
./scripts/dc/run_dc_v4.csh
```
