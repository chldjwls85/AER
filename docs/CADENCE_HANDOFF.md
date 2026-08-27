# Cadence Handoff

## Status: Historical V3 handoff record

> 이 문서는 V3를 Cadence에 전달하던 당시 조건을 보존한 기록임.
> 이후 V3 Genus run은 `syn_generic` 장시간 진행 후 수동 중단됐으며 full PPA는 없음.
> 최종 V3/V4 상태는 `AER_V3_V4_DESIGN_EVOLUTION.md` 참조 필요함.

- 7-speed UZH: RAW 대비 words/accepted-event 28.45~33.24% 감소
- Functional XSim: 5/5 PASS
- Dataset XSim/round-trip: 9/9 PASS
- Unintended loss: 0
- Cadence Xcelium representative compatibility: PASS
- Current full Genus: 2026-08-27 KST 기준 실행 중, Area/Timing/Power 미확정
- Innovus/P&R: 미수행

Candidate handoff 조건은 다음과 같음.

| Item | Candidate |
|---|---|
| Top | `aer_top_128` |
| Synthesizable filelist | `rtl/filelist.f` |
| Initial clock | 100 MHz / 10 ns |
| Input | 4096 tile valid/ready, 16384-bit ON and OFF buses |
| Output | 16-bit valid/ready/last |
| Activity | UZH 1000x sparse/dense/burst vectors under `data/generated` |
| Comparisons | pinned Fair RAW, pinned Team second, Current |
| Functional evidence | 5/5 regression, 9/9 dataset XSim/round-trip, unintended loss 0 |
| RTL candidate basis | `ad8fbd05b88e4645847dc438a5f3be668998882c` |

## Xcelium representative result

| Test | Result |
|---|---|
| SPARSE directed | PASS, `AER_BANK_PACKETIZER_TB_PASS` |
| 128×128 smoke | PASS, `AER_128_SMOKE_PASS`, packets=2, words=5 |
| Dense dataset | PASS, accepted=649, output words=1,298 |
| Dense round-trip | PASS, 649/649, mismatch=0 |

- Xcelium version: `23.09-s013`
- 목적: Cadence simulator compile/elaboration/simulation 호환성 확인
- Local 7-speed regression 반복 용도 아님

## Genus comparison condition

| Item | Condition |
|---|---|
| Genus | `23.14-s090_1` |
| Technology | GSCLIB 45nm |
| Library | `slow_vdd1v0_basicCells.lib`, `slow_vdd1v0` |
| PVT | 0.9V / 125°C |
| Clock | 10ns / 100MHz |
| Clock uncertainty | 0.2ns |
| Current top | `aer_top_128` |
| Filelist | `rtl/filelist.f` |

- 당시 상태: Current full Genus 진행 중이었음
- 기록 원칙: 최종 report 생성 전에는 Area/WNS/cell count/Power를 확정값으로 기록하지 않음
- 최종 결과: V3 full Genus report 미생성 상태로 종료됨

최종 PPA 분석 원칙은 다음과 같음.

- SPARSE cost-analysis logic의 Area/Timing/Power overhead 공개
- Team pinned result와 library/PVT/constraint 일치 여부 확인
- 1000x 이상 throughput-latency trade-off 병기
- 직접 comparable하지 않은 수치의 동일 조건 비교 금지
- UZH 외 dataset generality, timestamp wrap-around, formal proof는 후속 항목
- Genus 결과 확인 전 architecture 변경 금지
- Innovus/P&R은 별도 승인 전 미수행
