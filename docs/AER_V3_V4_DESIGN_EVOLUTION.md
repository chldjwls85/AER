# AER V3/V4 설계 진화와 최종 상태

- 목적: Design Direction 2 → V3 → V4로 Architecture가 변경된 이유와 최종 상태를 기록함
- Branch: `AER_hyeonho`임
- 구분 기준: Functional correctness, transmission efficiency, latency, synthesis feasibility, Area/Timing, official competition PPA임
- 원칙: 기능 PASS와 PPA 적합성을 같은 의미로 사용하지 않음

## 결론 요약

| Candidate | 핵심 최적화 | Functional | Transmission / latency | Synthesis / PPA | 판단 |
|---|---|---|---|---|---|
| Design Direction 2 | ROW/BANK metadata 공유 | Regression 5/5, round-trip 2050/2050 PASS | Dense word 3.65% 개선, BANK 0.2~3%, 1000× P99 6,380 cycles | 복잡도 대비 workload benefit 부족 | **NO-GO** |
| V3 | 흔한 singleton을 SPARSE 2 words로 전송 | Regression 5/5, round-trip 2050/2050 PASS | RAW 대비 28.45~33.24% word 감소, high-load tail latency 증가 | Genus `syn_generic` 장시간 진행 후 수동 중단, full PPA 없음 | **NO-GO** |
| V4 | SPARSE 유지, BANK와 bank-wide 분석 제거 | Regression 4/4, random round-trip 2050/2050 PASS | V4 full UZH sweep은 확인된 결과 없음 | SAED32 DC full synthesis 46m16s, 100 MHz timing FAIL | **다음 timing 최적화 기준선** |

```text
Design Direction 2: ROW / BANK
  -> BANK opportunity 부족
  -> Dense word improvement 3.65%
  -> NO-GO
        |
        v
V3: SPARSE / ROW / BANK
  -> Singleton workload 직접 최적화
  -> RAW 대비 28.45~33.24% word reduction
  -> Functional PASS
  -> Genus synthesis complexity excessive, full PPA unavailable
  -> NO-GO
        |
        v
V4: Lightweight SPARSE / ROW
  -> BANK / bank-wide analysis 제거
  -> Functional PASS
  -> Research-lab DC full synthesis 46m16s
  -> timestamp capture timing bottleneck 확인
  -> estimated Fmax 약 35 MHz
  -> next timing optimization candidate
```

## 1. Design Direction 2: ROW/BANK의 문제

### 문제와 가설

- Sensor 구성: 128×128 pixels를 2×2 pixel tile로 나눔
- Bank 구성: 4×4 tiles(8×8 pixels)를 1 bank로 묶어 총 256 banks 구성함
- BANK 조건: 같은 bank의 여러 row가 활성화되고 timestamp delta가 31 이내여야 함
- 초기 가설: BANK packet의 metadata 공유로 dense/clustered traffic word 수를 크게 줄일 수 있다고 예상함

### 검증 결과

- Lossless ROW/BANK functional regression: 5/5 PASS
- Directed/random round-trip: 2050/2050 exact reconstruction PASS
- UZH workload BANK 사용률: 약 0.2~3%
- Dense RTL word-efficiency 개선: 약 3.65%
- 1000× P99 latency: 6,380 cycles
- 일부 고부하 구간에서는 RAW보다 words/accepted가 악화

### 판단

- Functional correctness: 확보함
- 실제 문제: UZH workload의 multi-row BANK opportunity가 매우 드묾
- Trade-off: 희소한 pattern을 위해 bank-wide logic과 긴 packet lock이 필요함
- 결론: 구조 복잡도를 정당화할 전송 효율이 없어 **NO-GO**로 판단함

## 2. V3: SPARSE/ROW/BANK

### 변경 원인

- 재분석 대상: UZH tile-cycle transaction 분포임
- 관측 결과: `ON[3:0]`과 `OFF[3:0]` 전체 중 event bit 1개인 singleton이 지배적임
- 설계 방향: 드문 multi-row BANK 추가 최적화보다 흔한 singleton의 packet cost 감소를 우선함
- V3 핵심 변경: singleton을 위한 SPARSE packet 추가함

### Architecture와 packet format

- 256 × `aer_bank_packetizer`, bank당 16 pending tiles
- lossless SPARSE / ROW / BANK 선택
- bank-wide 16-slot scan, multi-row timestamp/cost 분석
- packet-locked 2-stage hierarchical global readout
- pixel position, polarity, 16-bit timestamp 보존

- 기존 singleton ROW cost: `HEADER + TIMESTAMP + DATA` = 3 words임
- V3 SPARSE cost: 다음 2 words로 동일 정보를 lossless하게 표현함

| Word | 내용 |
|---|---|
| WORD0 | Bank / Tile / Pixel / Polarity |
| WORD1 | Full 16-bit Timestamp |

### Functional correctness

- Self-checking regression: 5/5 PASS
- Directed/random round-trip: 2050/2050 exact reconstruction PASS
- unintended loss: 0

- 의미: packet 길이 감소와 별개로 accepted pixel/polarity/timestamp가 decoder에서 정확히 복원됨

### Transmission efficiency와 latency trade-off

- 수치 범위: 아래 값은 **V3 full UZH evaluation 결과**임
- 주의: V4 Dataset 결과로 재사용하면 안 됨

| Playback speed | RAW 대비 V3 word 감소 |
|---:|---:|
| 1× | 33.24% |
| 10× | 33.24% |
| 100× | 33.24% |
| 500× | 32.78% |
| 1000× | 31.90% |
| 2000× | 30.88% |
| 5000× | 28.45% |

- 1000× accepted transaction: RAW 46,610 → V3 63,458로 36.15% 증가함
- 1000× P99 latency: RAW 502 cycles → V3 2,577 cycles로 증가함
- 2000×/5000×: 긴 tail latency가 계속 관측됨
- 이점: link word efficiency와 accepted-event 수가 개선됨
- 한계: single global link queue 증가로 high-load latency가 악화됨
- 해석: throughput/acceptance와 tail latency 사이의 trade-off임

## 3. V3 Genus synthesis 최종 상태

- 핵심 구분: V3 중단 원인은 RTL functional bug가 아님
- 실제 진행 순서는 다음과 같음

1. 초기 Genus run: 공유 `/home` storage 감소로 disk guard 동작 이력 있음
2. 재진행 환경: `/tmp` 중심으로 정리함
3. RTL read/elaboration: 정상 완료함
4. `syn_generic`: Distributed Optimization까지 진입함
5. Runtime: 9시간 이상 진행했으나 `syn_generic`에서 완료되지 않음
6. 종료 사유: 제출 일정 때문에 사용자가 수동 중단함
7. 미도달 단계: `syn_map`, `syn_opt`임
8. 미생성 결과: Area/Timing/Power report임

V3 상태는 다음과 같이 분리함.

- Functional / transmission efficiency: **SUCCESS**
- Synthesis feasibility / completion time: **NO-GO**
- Official GSCLIB045 45 nm Genus PPA: **N/A**

### 장시간 synthesis의 가장 유력한 structural cause

- Bank당 logic: 16 tile pending scan 수행함
- Timestamp logic: bank-wide min/max와 delta 계산함
- Cost logic: multi-row 합산과 SPARSE/ROW/BANK 3-way 비교 수행함
- Snapshot logic: BANK 대상 tile을 결정함
- Replication: 위 logic이 256 banks에 반복됨

```text
bank-wide 16-slot analysis
  + multi-row timestamp / cost calculation
  + 3-mode decision
  × 256 banks
```

- 확정 여부: EDA tool 내부 원인에 대한 확정 진단은 아님
- 판단 근거: 반복 RTL 구조와 장시간 `syn_generic` 진행을 함께 고려함
- 결론: optimization complexity를 키운 **가장 유력한 structural cause**로 판단함

## 4. V4: Lightweight SPARSE/ROW

### 변경 원인과 목표

- V3 교훈: 전송 효율이 좋아도 제한 시간 안에 synthesis가 끝나야 hardware candidate로 사용 가능함
- Workload 근거: 개선의 대부분이 BANK가 아니라 SPARSE에서 발생함
- V4 원칙: V3의 useful path는 유지하고 rare-case optimization은 제거함
- 설계 성격: synthesis-aware simplification임

### Architecture

- SPARSE / ROW only, BANK mode 제거
- lossless ON/OFF bitmap과 16-bit timestamp 보존
- 256 banks, 8×8 pixels/bank, 4×4 tiles/bank 유지
- 기존 packet-locked 2-stage global readout 재사용
- active row 하나를 선택하고 해당 row의 최대 4 tiles만 분석

- V3 대비 제거: BANK header/mask/timestamp serialization임
- V3 대비 제거: bank-wide 16-tile min/max scan임
- V3 대비 제거: multi-row bank cost와 3-way mode comparison임
- 보존 원칙: V3 파일을 덮어쓰지 않고 V4 RTL을 별도 파일로 유지함
- V4 주요 RTL은 다음과 같음

- `rtl/bank/aer_bank_packetizer_v4.v`
- `rtl/aer_top_v4.v`
- `rtl/filelist_v4.f`
- synthesis top: `aer_top_v4_128`

- Cost 정의: `S`=singleton 수, `N`=non-singleton 수, `P=S+N`임
- Individual cost: `2*S+3*N`임
- ROW cost: `P+2`임
- ROW 선택: `RowCost`가 strictly smaller일 때만 수행함
- Tie-break: individual SPARSE 또는 single-tile ROW fallback을 사용함

### Functional verification

- V4 regression: 4/4 PASS
- Random accepted-to-decoded round-trip: 2050/2050 exact reconstruction PASS
- reset, output wait, contention, backpressure test PASS
- pixel position, polarity, timestamp lossless reconstruction PASS

- Tracked V4 결과: `results/logs/regression_v4_summary.txt`의 functional summary임
- V4 full UZH sweep: 확인된 tracked metric 없음
- 금지 사항: V3의 28.45~33.24%를 V4 transmission result로 재사용하지 않음

## 5. V4 research-lab DC structural screening

- 목적: V4 synthesis feasibility와 structural hotspot 확인함
- 성격: 연구실 보조 screening임
- 공식성: **대회 공식 Genus/PPA 결과가 아님**

### 조건

| 항목 | 조건 |
|---|---|
| Tool | Synopsys Design Compiler V-2023.12-SP4 |
| Library | SAED32 HVT `saed32hvt_ff0p95v125c.db` |
| Corner | FF / 0.95 V / 125°C |
| Clock | 10.0 ns, 100 MHz |
| Clock uncertainty | 0.2 ns |
| Compile | 기본 `compile` |

### 결과

| Metric | V4 DC result |
|---|---:|
| Runtime | 2,776 s = 46m16s |
| Critical Path Length | 28.05 ns |
| WNS | -18.27 ns |
| TNS | -1,058,885.12 ns |
| Setup Violating Paths | 77,829 |
| Estimated Fmax | 약 35 MHz |
| Leaf Cell Count | 724,826 |
| Combinational Cells | 613,457 |
| Sequential Cells | 111,369 |
| Cell Area | 2,359,467.60 |
| Design Area | 3,511,071.11 |
| Power | N/A (`report_power` 미실행) |

- `Estimated Fmax`: `1 / 28.05 ns`로 계산한 약 35 MHz임
- 해석 범위: pre-layout/pre-CTS DC screening 추정치임
- 주의: final silicon/signoff Fmax가 아님
- 100 MHz 결과: 10 ns constraint에서 WNS -18.27 ns이므로 timing FAIL함

### Timing root cause

- Worst setup path 형태는 다음과 같음

```text
aer_timebase/time_now register
  -> top-level time_now distribution
  -> bank packetizer capture/mux logic
  -> stored_time register
```

- Source: `rtl/common/aer_timebase.v`의 `time_now` register임
- Distribution: `rtl/aer_top_v4.v`에서 256 bank의 `time_now` 입력으로 연결함
- Capture: `rtl/bank/aer_bank_packetizer_v4.v`의 `stored_time`에 저장함
- Primary bottleneck: global readout보다 timestamp distribution/capture path임
- TIM-134 의미: 111,369-load high-fanout은 **clock net** warning임
- 오해 금지: `time_now` fanout이 111,369라는 의미가 아님

### Area hotspot

Hierarchical Area 해석은 다음과 같음.

1. 약 97.8%: 256 × bank packetizer replicas
2. 약 2.0%: global readout hierarchy
3. 나머지 약 0.2%: top/timebase 등

- Dominant hotspot: global arbiter 1개가 아니라 bank storage/packetization의 256회 반복임
- 절대 Area 판단 조건: 동일 tool/library/PVT/constraint reference가 필요함
- 직접 비교 금지: SAED32 DC Area와 GSCLIB045 45 nm Genus Area임

## 6. 최종 판단과 한계

| 판단 축 | V3 | V4 |
|---|---|---|
| Functional correctness | PASS | PASS |
| Transmission efficiency | UZH RAW 대비 28.45~33.24% 감소 | 별도 full UZH 결과 없음 |
| Latency / acceptance | accepted 증가, high-load P99 증가 | Dataset 수준 미평가 |
| Synthesis completion | Genus full flow 미완료 | SAED32 DC 46m16s 완료 |
| Area | N/A | DC Cell Area 2.359M, banks dominant |
| Timing | N/A | 100 MHz FAIL, WNS -18.27 ns |
| Power | N/A | N/A |
| Official 45 nm Genus PPA | N/A | 아직 없음 |

- Synthesis simplification: V3 대비 성공함
- 100 MHz timing: 추가 개선 필요함
- 보존 원칙: V4를 fallback/reference로 유지함
- 다음 검토 우선순위: timestamp distribution/capture path와 반복 bank structure임

## 7. Version provenance

| 의미 | Commit |
|---|---|
| Previous adaptive ROW/BANK RTL freeze | `f37ed04` |
| V3 SPARSE/ROW/BANK candidate | `41292b5` |
| V3 full UZH evaluation basis | `ad8fbd0` |
| V4 synthesis-ready checkpoint | `f713d16` |
| V4 Genus SystemVerilog parser alignment | `4e3b917` |
| SAED32 DC comparison handoff / 문서화 직전 HEAD | `1fd5da5` |

- 상세 provenance: `DATASET_EVALUATION.md`, `VERIFICATION.md`, `REFERENCE_VERSIONS.md` 참조함
- Synthesis handoff 조건: `GENUS_V4_HANDOFF.md`, `DC_SAED32_COMPARISON.md` 참조함
