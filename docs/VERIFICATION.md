# Verification

## V5 verification status

V5의 핵심 변경은 packet architecture가 아니라 Global Timebase → Regional Timebase 변경임.
따라서 다음 두 검증을 우선 수행함.

### 1. Regional Timebase sanity

Testbench: `tb/regression/tb_aer_v5_timebase_sanity.v`

확인 항목:

- 16 regional counters elaboration 확인함.
- reset 후 모든 counter가 0임.
- 64 cycles 동안 동일하게 +1 lockstep 동작함.
- re-reset 후 0 → lockstep recovery를 확인함.
- 각 region이 정확히 16 banks를 포함함.
- 4×4-bank region boundary가 Global Readout grouping과 일치함.
- 전체 256 banks mapping mismatch 0임.

Result:

```text
AER_V5_TIMEBASE_SANITY_PASS
```

### 2. V4 ↔ V5 functional equivalence

Testbench: `tb/regression/tb_aer_v4_v5_equiv.v`

Scenario:

- singleton ON/OFF events
- 5 spatial regions
- multi-tile ROW
- 5-region simultaneous requests
- 6-cycle output backpressure

Result:

- SPARSE equivalence PASS함.
- ROW equivalence PASS함.
- simultaneous packets equivalence PASS함.
- backpressure equivalence PASS함.
- `tile_in_ready` mismatch 0임.
- output mismatch 0임.
- deadlock 없음.

```text
AER_V4_V5_EQUIV_PASS
```

## V4 lightweight regression

V4 SPARSE/ROW architecture는 별도 directed regression과 random exact reconstruction을 통과함.

- directed regression PASS함.
- random exact reconstruction 2,050/2,050 PASS함.
- reset/backpressure/simultaneous request를 확인함.
- V5는 V4 packetizer/global readout을 유지하고 timestamp distribution만 변경함.

## V3 full functional/dataset gate

V3 SPARSE/ROW/BANK frozen candidate에서 수행한 검증은 legacy traffic evidence로 유지함.

| Scope | Result |
|---|---|
| Functional XSim tops | 5/5 PASS |
| Random round-trip | 2,050/2,050 PASS |
| Dataset RTL windows | 9/9 PASS |
| Dataset decoder round-trip | 9/9 PASS |
| Accepted record loss | 0 |

UZH full sweep과 대표 windows 결과는 `docs/DATASET_EVALUATION.md`, `results/summary.csv`를 참조함.

## Remaining limits

- Timestamp wrap-around formal proof 미수행함.
- Full-chip formal equivalence 미수행함.
- Innovus post-layout timing/power 검증 미수행함.
- Genus 결과는 logic synthesis 기준이며 P&R signoff 결과가 아님.
