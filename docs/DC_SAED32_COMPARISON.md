# Synopsys DC SAED32 V3/V4/V5 comparison

## 목적

- 동일 연구실 Synopsys DC/SAED32 조건에서 architecture iteration을 상대 비교함.
- 공식 대회 PPA 결과가 아니라 structural/timing screening 용도임.
- 대회 Genus 절대값과 직접 비교하지 않음.

## Fixed conditions

- Tool: Synopsys Design Compiler V-2023.12-SP4
- Library: `saed32hvt_ff0p95v125c.db`
- Corner: SAED32 HVT FF, 0.95 V, 125°C
- Clock: 10.0 ns
- Clock uncertainty: 0.2 ns
- Reset: `set_false_path -from [get_ports rst_n]`
- Optimization: basic `compile`
- Common flow: `scripts/dc/dc_common.tcl`

## V4 → V5 결과

| 항목 | V4 | V5 | 변화 |
|---|---:|---:|---:|
| Critical Path | 28.05 ns | **25.26 ns** | **-9.9%** |
| WNS | -18.27 ns | **-15.49 ns** | +2.78 ns |
| TNS | -1,058,885.12 ns | **-770,141.69 ns** | 약 27.3% 감소 |
| Violating Paths | 77,829 | 78,304 | +0.6% |
| Leaf Cells | 724,826 | 725,497 | +0.09% |
| Combinational Cells | 613,457 | 613,888 | +0.07% |
| Sequential Cells | 111,369 | **111,609** | **+240** |
| Cell Area | 2,359,467.60 | **2,347,645.58** | -0.50% |
| Design Area | 3,511,071.11 | **3,502,284.69** | -0.25% |
| Runtime | 2,776 s | **3,045 s** | +9.7% |

- V5 sequential +240은 추가 15 timebases × 16 bit와 일치함.
- V5 area가 소폭 감소했으나 원인은 report만으로 단정하지 않음.
- Regional Timebase 도입에 따른 유의미한 area penalty가 관찰되지 않았다고 판단함.

## Critical path migration

V4:

```text
global aer_timebase
  -> global time_now distribution
  -> bank capture logic
  -> stored_time_reg
```

V5:

```text
pending_reg
  -> bank packetizer internal analysis/selection
  -> sparse_pixel_reg
```

- timestamp distribution path가 V5 worst path에서 사라짐.
- Regional Timebase가 목표한 global timestamp fan-out bottleneck을 제거함.
- bank-local analyze/selection path가 다음 bottleneck으로 드러남.

## V5 reports

`results/synthesis/dc_v5/`

- `run_summary.txt`
- `qor.rpt`
- `area_summary.rpt`
- `timing_summary.rpt`
- `check_design_summary.txt`

## V5 run facts

- Start: 2026-08-28 04:24:02 KST
- End: 2026-08-28 05:14:47 KST
- Elapsed: 3,045 s
- Top: `aer_top_v5_128`
- `check_design` raw reports에는 repetitive lint warnings가 존재하나 synthesis error는 확인되지 않음.
