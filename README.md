# V3 Reference: Lossless SPARSE/ROW/BANK Adaptive AER Packet Readout

> 문서 범위: 본 README는 V3 SPARSE/ROW/BANK frozen candidate 기준 설명임.
> V4 Lightweight SPARSE/ROW와 최종 synthesis 판단은
> [AER_V3_V4_DESIGN_EVOLUTION.md](docs/AER_V3_V4_DESIGN_EVOLUTION.md) 참조 필요함.

128×128 polarity-event sensor용 lossless AER packet readout RTL 및 검증 환경임.

- 입력 단위: 2×2 pixel tile, `ON[3:0]`, `OFF[3:0]`
- Bank 구성: 4×4 tiles, 8×8 pixels
- Packet mode: SPARSE / ROW / BANK
- 출력: 16-bit `valid/ready/last`
- 전역 readout: packet-locked round-robin
- 구현 언어: synthesizable Verilog-2001
- V3 RTL 기준: `AER_hyeonho` / `ad8fbd05b88e4645847dc438a5f3be668998882c`

## 한눈에 보는 현재 상태

| 항목 | 상태 | 핵심 결과 |
|---|---|---|
| 기능 regression | **PASS** | 5/5 self-checking XSim |
| Random round-trip | **PASS** | 2,050/2,050 |
| Dataset RTL | **PASS** | 9/9 sparse/dense/burst XSim |
| UZH full sweep | **완료** | 1/10/100/500/1000/2000/5000x |
| Unintended loss | **0** | accepted-to-decoded 기준 |
| RAW 대비 word 절감 | **28.45~33.24%** | 전체 7-speed sweep |
| Cadence Xcelium 호환성 | **PASS** | SPARSE, 128×128 smoke, dense dataset |
| V3 Full Genus PPA | **N/A** | `syn_generic` 장시간 진행 후 수동 중단함 |
| Innovus / P&R | **미수행** | 현재 작업 범위 아님 |

> `READY FOR CADENCE EVALUATION`은 기능·traffic gate 통과 의미임.
>
> Area/Timing/Power 우수성 확정 의미는 아님.

## 설계 목표

- RAW AER의 반복 address/timestamp metadata 감소
- 2×2 tile의 정확한 위치와 `ON/OFF` bitmap 보존
- accepted transaction의 좌표·polarity·timestamp 완전 복원
- sparse traffic과 multi-tile traffic을 동일 16-bit link에서 처리
- backpressure 중 `data/valid/last` 안정성 유지
- packet 종료 전 arbitration 대상 변경 금지
- binning, GROUP3, BIN4, lossy compression 미사용

## 설계 발전 과정

| 단계 | 핵심 아이디어 | 실제 UZH 결과 | 판단 |
|---|---|---|---|
| Fair RAW | tile event마다 ROW header/time/data 전송 | 약 3 words/event | 비교 기준 |
| Team second | RAW8/GROUP3/BIN4/BIN pair packing | 실제 trace에서 packing 기회가 거의 없음 | UZH 개선 미미 |
| Previous ROW/BANK | multi-row bank locality의 metadata 공유 | Dense XSim 3.65% 개선, BANK 0.2~3%, 1000x P99 6,380 cycles | **NO-GO** |
| V3 SPARSE/ROW/BANK | 흔한 singleton transaction을 2 words로 직접 전송 | RAW 대비 28.45~33.24% 절감 | **Functional/traffic PASS, synthesis NO-GO** |
| V4 Lightweight SPARSE/ROW | BANK와 bank-wide 분석 제거 | 별도 full UZH 결과 없음 | **DC synthesis 완료, timing 개선 필요** |

### SPARSE가 필요한 이유

- UZH canonical trace 대부분: 한 tile-cycle에 polarity bit 1개인 singleton transaction
- 기존 singleton ROW packet: `HEADER + TIME + DATA = 3 words`
- SPARSE packet: `ADDRESS + TIME = 2 words`
- singleton 1건 기준 word 감소: 약 33.3%
- 드문 BANK pattern보다 자주 발생하는 workload 직접 최적화

## 전체 구조

```text
128×128 pixels
  └─ 4096 × 2×2 tile input
       └─ ON[3:0], OFF[3:0], valid/ready
            └─ 256 × aer_bank_packetizer
                 └─ 4×4 tiles/bank = 8×8 pixels/bank
                      └─ SPARSE / ROW / BANK packet
                           └─ 16 × regional packet mux
                                └─ 2-entry elastic buffer
                                     └─ root packet mux
                                          └─ 16-bit valid/ready/last
```

### 핵심 module

| Module | 역할 |
|---|---|
| `aer_timebase` | 16-bit capture timestamp 생성 |
| `aer_bank_packetizer` | 16개 tile pending slot, mode 선택, packet 직렬화 |
| `aer_packet_rr_arbiter` | packet-locked look-ahead round-robin grant |
| `aer_packet_mux` | 선택 stream의 `valid/ready/last` routing |
| `aer_stream_buffer2` | 2-entry elastic word buffer |
| `aer_global_readout` | regional mux와 root mux 구성 |
| `aer_top_128` | 128×128 / 4096-tile top wrapper |

- 상세 계층 및 signal flow: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 참조함

## Packet mode

| Mode | 대상 | Word 구성 | 특징 |
|---|---|---|---|
| SPARSE | `ON/OFF` 전체에서 bit 1개만 set | `ADDRESS + TIME` | full 16-bit timestamp, 2 words |
| ROW | 한 row의 singleton/non-singleton 혼합 | `HEADER + TIME + DATA...` | 5-bit delta, exact ON/OFF bitmap |
| BANK | 두 row 이상 active, span ≤31, 실제 cost 절감 | `HEADER + MASK + TIME + DATA...` | 16-bit tile mask, tile ID 순서 보존 |

- 정확한 bit field: [docs/PACKET_FORMAT.md](docs/PACKET_FORMAT.md) 참조함

## Mode 선택 규칙

한 row에서 사용하는 기호는 다음과 같음.

- `S`: singleton tile 수
- `N`: non-singleton tile 수
- `P = S + N`

Word cost는 다음과 같음.

```text
ROW-only          = P + 2
SPARSE/ROW hybrid = 2*S + (N + 2, N>0일 때)
BANK              = total_P + 3
```

선택 순서는 다음과 같음.

1. Row별 `ROW-only`와 `SPARSE/ROW hybrid` 중 작은 cost 선택
2. 두 row 이상 active이며 전체 timestamp span ≤31인지 확인
3. BANK cost가 row별 최소 cost 합보다 **strictly cheaper**인지 확인
4. 조건 만족 시 BANK 선택
5. 동일 cost이면 packet lock이 짧은 SPARSE/ROW 우선
6. delta 범위 초과 시 값 절삭 없이 lossless fallback

## Lossless 정의

- 비교 기준: `tile_in_valid && tile_in_ready`로 accepted된 transaction임

```text
{tile_id, ON[3:0], OFF[3:0], timestamp}
                     ==
{decoded tile_id, decoded ON, decoded OFF, decoded timestamp}
```

- missing: 0
- extra: 0
- payload mismatch: 0
- timestamp mismatch: 0
- packet 순서 변경: arbitration 특성상 허용
- semantic record 변경·누락·중복: 불허
- `ready=0` 입력: loss가 아닌 source backpressure

## 검증 결과

### Functional regression

| Test | 검증 범위 | 결과 |
|---|---|---|
| `tb_aer_bank_packetizer` | SPARSE/ROW/BANK, pixel/polarity, timestamp 31/32, backpressure | PASS |
| `tb_aer_top` | multi-bank, packet lock, mixed payload | PASS |
| `tb_aer_top_128_smoke` | 4096 tiles / 256 banks elaboration, bank 0/255 | PASS |
| `tb_aer_protocol_stress` | reset, random stall, long contention, fairness | PASS |
| `tb_aer_roundtrip_random` | same-tile backpressure, 2,050건 semantic round-trip | PASS |

- 최종 결과: `TOTAL=5`, `PASS=5`, `FAIL=0`
- 필수 token: `AER_ALL_TESTS_PASS`
- 상세 기록: [docs/VERIFICATION.md](docs/VERIFICATION.md)
- 실행 요약: [results/logs/regression_summary.txt](results/logs/regression_summary.txt)

### UZH full sweep

Dataset 조건은 다음과 같음.

- Dataset: UZH Event-Camera Dataset `shapes_rotation`
- 입력: source event 앞 200,000개
- Crop: `x=56, y=26, width=128, height=128`
- Crop 후 event: 92,861개
- Clock: 100MHz
- Playback: 1/10/100/500/1000/2000/5000x

| Speed | RAW words/accepted | Current words/accepted | 감소율 | Accepted 증가 | RAW P99 | Current P99 |
|---:|---:|---:|---:|---:|---:|---:|
| 1x | 2.9944 | 1.9990 | 33.24% | 0.00% | 5 | 3 |
| 10x | 2.9944 | 1.9990 | 33.24% | 0.00% | 5 | 3 |
| 100x | 2.9944 | 1.9990 | 33.24% | 0.02% | 8 | 4 |
| 500x | 2.9727 | 1.9982 | 32.78% | 16.84% | 303 | 76 |
| 1000x | 2.9313 | 1.9960 | 31.90% | 36.15% | 502 | 2,577 |
| 2000x | 2.8855 | 1.9945 | 30.88% | 36.23% | 644 | 5,051 |
| 5000x | 2.7852 | 1.9928 | 28.45% | 36.53% | 832 | 4,710 |

결과 해석은 다음과 같음.

- 모든 속도에서 약 28~33% word-efficiency 개선
- 500x부터 RAW보다 많은 event 수용
- 1000x 이상에서 Current P99가 RAW보다 증가
- 원인: 더 많은 traffic 수용과 single global link queue 증가
- 결론: bandwidth/throughput 개선과 high-load tail-latency 간 trade-off
- unintended loss: 모든 조건에서 0

전체 수치: [results/summary.csv](results/summary.csv)

Dataset 조건 및 분석: [docs/DATASET_EVALUATION.md](docs/DATASET_EVALUATION.md)

### Actual RTL representative windows

| Window | RAW accepted / words / WPT | Current accepted / words / WPT | 감소율 | Current round-trip |
|---|---|---|---:|---|
| sparse | 111 / 333 / 3.0000 | 111 / 222 / 2.0000 | 33.33% | 111/111 |
| dense | 416 / 1,228 / 2.9519 | 649 / 1,298 / 2.0000 | 32.25% | 649/649 |
| burst | 423 / 1,237 / 2.9243 | 641 / 1,280 / 1.9969 | 31.71% | 641/641 |

V3 mode count는 다음과 같음.

- sparse window: `SPARSE/ROW/BANK = 111/0/0`
- dense window: `SPARSE/ROW/BANK = 639/2/2`
- burst window: `SPARSE/ROW/BANK = 628/4/1`
- 실제 workload에서 SPARSE가 지배적임

## 실행 방법

### Vivado 2019.1 XSim regression

```powershell
powershell -ExecutionPolicy Bypass -File scripts\regression\run_all_xsim.ps1
```

Vivado가 기본 위치에 없으면 다음과 같이 경로를 지정함.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\regression\run_all_xsim.ps1 `
  -VivadoPath "<Vivado 2019.1 vivado.bat 또는 bin 경로>"
```

### Dataset 전체 재현

```powershell
powershell -ExecutionPolicy Bypass -File scripts\dataset\run_all_dataset.ps1
```

- 원본 dataset: `data/` 아래 저장하며 Git에서 제외함
- Fair RAW/Team reference: pinned SHA에서 임시 export하며 현재 branch에 merge하지 않음
- 결과 위치: `results/summary.csv`, `results/metrics/`, `results/logs/`임

## Repository 구성

```text
rtl/                synthesizable Verilog-2001
  common/           timebase, arbiter, elastic buffer
  bank/             SPARSE/ROW/BANK packetizer
  fabric/           regional/root packet readout
tb/                 unit, regression, dataset self-checking testbench
scripts/            XSim, regression, dataset, reference 실행 script
sw/                 dataset loader, architecture model, decoder, visualization
docs/               구조, packet, 검증, dataset, 비교, Cadence handoff
results/            요약 CSV, 작은 metrics/log, 대표 figure/animation
```

### 문서 안내

| 문서 | 내용 |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | 전체 hierarchy, module, data flow |
| [PACKET_FORMAT.md](docs/PACKET_FORMAT.md) | SPARSE/ROW/BANK bit field와 decoder 규칙 |
| [VERIFICATION.md](docs/VERIFICATION.md) | self-checking regression 및 round-trip |
| [DATASET_EVALUATION.md](docs/DATASET_EVALUATION.md) | UZH provenance, canonicalization, 7-speed 평가 |
| [BASELINE_COMPARISON.md](docs/BASELINE_COMPARISON.md) | Fair RAW/Team/Current 정량 비교 |
| [REFERENCE_VERSIONS.md](docs/REFERENCE_VERSIONS.md) | branch, commit, dataset anchor |
| [CADENCE_HANDOFF.md](docs/CADENCE_HANDOFF.md) | Cadence 조건과 현재 진행 상태 |
| [AER_V3_V4_DESIGN_EVOLUTION.md](docs/AER_V3_V4_DESIGN_EVOLUTION.md) | Design Direction 2에서 V3/V4로 이어진 설계 변화와 최종 판단 |

## 비교 기준

| 구분 | 기준 |
|---|---|
| Fair RAW | `aer_v1_raw_top_128`, `ENABLE_BINNING=0` |
| Team second | `aer_v1_top_128`, `ENABLE_BINNING=1` |
| Team pinned SHA | `da686477ca054faada5f66d369f1fb253b2bf562` |
| V3 | `aer_top_128` |
| V3 RTL 기준 SHA | `ad8fbd05b88e4645847dc438a5f3be668998882c` |

세 구조의 공통 조건은 다음과 같음.

- 128×128 sensor
- 2×2 tile input
- 4×4 tiles/bank
- 16-bit output link
- 동일 canonical trace
- 동일 ready/backpressure 모델

## 알려진 한계

- Tile pending depth 1
- Same-tile 반복 event 수용을 위한 source-side ready 준수 필요
- 지속 처리량 1 word/clock인 single global link 제한
- ROW/BANK delta 범위 0~31 clocks
- 16-bit timestamp wrap-around grouping 별도 검증 필요
- 1000x 이상에서 높은 P99 latency
- UZH 단일 real dataset 중심 평가
- CIFAR10-DVS 기존 사용 provenance 미확인
- Formal verification 미수행
- V3 official Genus Area/Timing/Power: full synthesis 미완료로 N/A임
- V4 official competition 45 nm Genus PPA: 아직 없음

## 현재 판단과 후속 방향

V3 최종 판단은 다음과 같음.

- Functional correctness: PASS함
- Lossless round-trip: PASS함
- UZH word reduction: 28.45~33.24% 확보함
- High-load latency: tail-latency trade-off 존재함
- Genus synthesis feasibility: 제출 가능 시간 안에 완료되지 않아 NO-GO임
- Official 45 nm Genus PPA: N/A임

V4 후속 상태는 다음과 같음.

- BANK와 bank-wide 분석을 제거한 별도 RTL로 구현함
- Functional regression과 random round-trip PASS함
- Research-lab SAED32 DC full synthesis 완료함
- 100 MHz timing은 WNS -18.27 ns로 FAIL함
- V3/V4 상세 비교: `docs/AER_V3_V4_DESIGN_EVOLUTION.md` 참조 필요함
