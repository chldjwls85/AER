# AER V3/V4 설계 진화와 최종 상태

이 문서는 `AER_hyeonho` branch에서 Design Direction 2의 ROW/BANK 구조가 V3
SPARSE/ROW/BANK를 거쳐 V4 Lightweight SPARSE/ROW로 바뀐 이유와 각 단계의 최종
상태를 기록한다. Functional correctness, transmission efficiency, latency,
synthesis feasibility, Area/Timing, official competition PPA를 서로 다른 판단 축으로
구분한다.

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

Previous ROW/BANK 구조는 128×128 sensor를 2×2 pixel tile로 나누고, 4×4 tiles
(8×8 pixels)를 한 bank로 묶어 총 256 banks를 구성했다. 같은 bank의 여러 row가
동시에 활성화되고 timestamp delta가 31 이내이면 BANK packet이 metadata를 공유해
dense/clustered traffic의 word 수를 크게 줄일 수 있다고 예상했다.

### 검증 결과

- Lossless ROW/BANK functional regression: 5/5 PASS
- Directed/random round-trip: 2050/2050 exact reconstruction PASS
- UZH workload BANK 사용률: 약 0.2~3%
- Dense RTL word-efficiency 개선: 약 3.65%
- 1000× P99 latency: 6,380 cycles
- 일부 고부하 구간에서는 RAW보다 words/accepted가 악화

### 판단

기능은 맞았지만 실제 UZH workload에서 multi-row BANK opportunity가 너무 드물었다.
희소한 경우를 위한 bank-wide 구조 복잡도와 긴 packet lock을 정당화할 만큼 전송
효율이 개선되지 않아 **NO-GO**로 판단했다.

## 2. V3: SPARSE/ROW/BANK

### 변경 원인

Previous ROW/BANK 결과 이후 UZH tile-cycle 분포를 다시 분석한 결과, 대부분의 2×2
tile transaction에서 `ON[3:0]`과 `OFF[3:0]` 전체 중 event bit 하나만 set된
singleton이 지배적이었다. V3는 드문 multi-row BANK를 더 최적화하는 대신 가장
자주 나타나는 singleton의 packet cost를 직접 줄였다.

### Architecture와 packet format

- 256 × `aer_bank_packetizer`, bank당 16 pending tiles
- lossless SPARSE / ROW / BANK 선택
- bank-wide 16-slot scan, multi-row timestamp/cost 분석
- packet-locked 2-stage hierarchical global readout
- pixel position, polarity, 16-bit timestamp 보존

기존 singleton ROW packet은 `HEADER + TIMESTAMP + DATA`의 3 words다. V3 SPARSE는
다음 2 words로 동일 정보를 lossless하게 표현한다.

| Word | 내용 |
|---|---|
| WORD0 | Bank / Tile / Pixel / Polarity |
| WORD1 | Full 16-bit Timestamp |

### Functional correctness

- Self-checking regression: 5/5 PASS
- Directed/random round-trip: 2050/2050 exact reconstruction PASS
- unintended loss: 0

이는 packet sequence가 짧아졌다는 사실과 별개로, accepted transaction의 pixel,
polarity, timestamp가 decoder에서 정확히 복원됐음을 의미한다.

### Transmission efficiency와 latency trade-off

아래 값은 **V3 full UZH evaluation 결과**이며 V4 결과가 아니다.

| Playback speed | RAW 대비 V3 word 감소 |
|---:|---:|
| 1× | 33.24% |
| 10× | 33.24% |
| 100× | 33.24% |
| 500× | 32.78% |
| 1000× | 31.90% |
| 2000× | 30.88% |
| 5000× | 28.45% |

1000×에서 accepted transaction은 RAW 46,610에서 V3 63,458로 36.15% 증가했다.
반면 P99 latency는 RAW 502 cycles에서 V3 2,577 cycles로 증가했고, 2000×와
5000×에서도 긴 tail latency가 관측됐다. 즉 link word efficiency와 accepted-event
수는 개선됐지만, 더 많은 traffic을 single global link가 수용하면서 high-load
queueing latency가 증가하는 trade-off가 있다.

## 3. V3 Genus synthesis 최종 상태

V3는 RTL 기능 오류로 synthesis가 실패한 것이 아니다. 실제 진행 순서는 다음과
같다.

1. 초기 Genus run에서 공유 `/home` storage 여유가 감소해 disk guard가 동작한
   이력이 있었다.
2. 이후 `/tmp` 중심 run 환경으로 정리해 다시 진행했다.
3. RTL read와 elaboration은 정상 완료됐다.
4. `syn_generic`의 Distributed Optimization까지 진입했다.
5. 재진행 run도 9시간 이상 진행했지만 `syn_generic`에서 완료되지 않았다.
6. 제출 일정 때문에 사용자가 최종적으로 수동 중단했다.
7. `syn_map`/`syn_opt`에는 도달하지 못했으며 최종 Area/Timing/Power report는 없다.

따라서 V3의 상태는 다음과 같이 분리해야 한다.

- Functional / transmission efficiency: **SUCCESS**
- Synthesis feasibility / completion time: **NO-GO**
- Official GSCLIB045 45 nm Genus PPA: **N/A**

### 장시간 synthesis의 가장 유력한 structural cause

`aer_bank_packetizer.v`는 각 bank에서 전체 16 tile pending scan, bank-wide
timestamp min/max와 delta 계산, multi-row cost 합산, SPARSE/ROW/BANK 3-way cost
비교, BANK snapshot 결정을 수행한다. 이 logic이 256 banks에 반복된다.

```text
bank-wide 16-slot analysis
  + multi-row timestamp / cost calculation
  + 3-mode decision
  × 256 banks
```

이 설명은 EDA tool 내부 원인에 대한 확정 진단이 아니다. RTL 구조와 장시간
`syn_generic` 진행을 종합할 때 optimization complexity를 키운 **가장 유력한
structural cause**로 판단한 것이다.

## 4. V4: Lightweight SPARSE/ROW

### 변경 원인과 목표

V3는 전송 효율이 좋아도 제출 가능한 시간 안에 합성이 끝나지 않으면 최종 hardware
candidate가 될 수 없다는 점을 보여줬다. 동시에 workload 개선의 대부분은 BANK가
아니라 SPARSE에서 발생했다. V4는 “V3의 useful path는 유지하고 rare-case
optimization은 제거”하는 synthesis-aware simplification이다.

### Architecture

- SPARSE / ROW only, BANK mode 제거
- lossless ON/OFF bitmap과 16-bit timestamp 보존
- 256 banks, 8×8 pixels/bank, 4×4 tiles/bank 유지
- 기존 packet-locked 2-stage global readout 재사용
- active row 하나를 선택하고 해당 row의 최대 4 tiles만 분석

V3 대비 BANK header/mask/timestamp serialization, bank-wide 16-tile min/max scan,
multi-row bank cost, SPARSE/ROW/BANK 3-way comparison을 제거했다. V4의 주요 RTL은
다음과 같으며 V3 파일을 덮어쓰지 않고 별도 보존된다.

- `rtl/bank/aer_bank_packetizer_v4.v`
- `rtl/aer_top_v4.v`
- `rtl/filelist_v4.f`
- synthesis top: `aer_top_v4_128`

선택 row에서 singleton 수를 `S`, non-singleton 수를 `N`, 전체 tile 수를
`P=S+N`이라 하면 V4는 `IndividualCost=2*S+3*N`, `RowCost=P+2`를 비교한다.
`RowCost`가 strictly smaller일 때만 ROW를 선택하고, 동률이면 packet lock이 짧은
individual SPARSE 또는 single-tile ROW fallback을 사용한다.

### Functional verification

- V4 regression: 4/4 PASS
- Random accepted-to-decoded round-trip: 2050/2050 exact reconstruction PASS
- reset, output wait, contention, backpressure test PASS
- pixel position, polarity, timestamp lossless reconstruction PASS

현재 repository에 tracked된 V4 결과는 `results/logs/regression_v4_summary.txt`의
functional regression summary다. V4 전용 full UZH sweep metric은 확인되지 않으므로
V3의 28.45~33.24% 수치를 V4 transmission result로 재사용하지 않는다.

## 5. V4 research-lab DC structural screening

이 결과는 V4의 synthesis feasibility와 구조적 hotspot을 보기 위한 연구실 보조
실험이다. **대회 공식 Genus/PPA 결과가 아니다.**

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

`Estimated Fmax`는 `1 / 28.05 ns`에 근거한 약 35 MHz의 pre-layout/pre-CTS DC
screening 추정치다. 최종 silicon 또는 signoff Fmax가 아니다. 10 ns constraint에서는
WNS -18.27 ns이므로 100 MHz timing을 만족하지 못한다.

### Timing root cause

worst setup path는 주로 다음 형태다.

```text
aer_timebase/time_now register
  -> top-level time_now distribution
  -> bank packetizer capture/mux logic
  -> stored_time register
```

`rtl/common/aer_timebase.v`의 `time_now`가 `rtl/aer_top_v4.v`에서 256 bank의
`time_now` 입력으로 배포되고, `rtl/bank/aer_bank_packetizer_v4.v`의 accepted tile
capture 경로에서 `stored_time`에 저장된다. 따라서 현재 primary bottleneck은 global
readout arbiter보다 timestamp distribution/capture path다.

TIM-134의 111,369-load high-fanout warning은 **clock net**에 대한 warning이다.
`time_now` fanout이 111,369이라는 뜻이 아니다.

### Area hotspot

hierarchical Area 해석은 다음과 같다.

1. 약 97.8%: 256 × bank packetizer replicas
2. 약 2.0%: global readout hierarchy
3. 나머지 약 0.2%: top/timebase 등

따라서 dominant hotspot은 global arbiter 하나가 아니라 bank storage와 packetization
logic이 256번 반복되는 구조다. 다만 절대 Area의 좋고 나쁨은 동일 tool/library/PVT/
constraint reference와 비교해야 한다. SAED32 DC Area와 대회 GSCLIB045 45 nm Genus
Area는 직접 비교할 수 없다.

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

V4는 V3보다 synthesis-friendly한 구조로 단순화하는 데 성공했지만 100 MHz timing은
추가 개선이 필요하다. 다음 candidate는 V4를 fallback/reference로 보존하면서
timestamp distribution/capture path와 반복 bank structure를 우선 검토해야 한다.

## 7. Version provenance

| 의미 | Commit |
|---|---|
| Previous adaptive ROW/BANK RTL freeze | `f37ed04` |
| V3 SPARSE/ROW/BANK candidate | `41292b5` |
| V3 full UZH evaluation basis | `ad8fbd0` |
| V4 synthesis-ready checkpoint | `f713d16` |
| V4 Genus SystemVerilog parser alignment | `4e3b917` |
| SAED32 DC comparison handoff / 문서화 직전 HEAD | `1fd5da5` |

각 수치의 상세 provenance는 `DATASET_EVALUATION.md`, `VERIFICATION.md`,
`REFERENCE_VERSIONS.md`, `GENUS_V4_HANDOFF.md`, `DC_SAED32_COMPARISON.md`를 함께
참조한다.
