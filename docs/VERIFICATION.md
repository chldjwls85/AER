# Verification

> 문서 범위: 기본 5-test gate와 Dataset 9-window 결과는 V3 기준임.
> V4 4-test regression은 `results/logs/regression_v4_summary.txt` 참조 필요함.

## Current freeze gate

| Test | Purpose | Expected token | Status |
|---|---|---|---|
| `tb_aer_bank_packetizer` | SPARSE ON/OFF/pixel/timestamp, delta 31/32, ROW/BANK, backpressure | `AER_BANK_PACKETIZER_TB_PASS` | PASS |
| `tb_aer_top` | 16×16 hierarchy, mixed payload, multi-bank packet lock | `AER_ADAPTIVE_PACKET_TB_PASS` | PASS |
| `tb_aer_top_128_smoke` | 128×128 elaboration and bank 0/255 connectivity | `AER_128_SMOKE_PASS` | PASS |
| `tb_aer_protocol_stress` | idle/mid-packet reset, random stalls, 4-bank long contention/fairness | `AER_PROTOCOL_STRESS_PASS` | PASS |
| `tb_aer_roundtrip_random` | same-tile backpressure and accepted-to-decoded semantic equality | `AER_ROUNDTRIP_RANDOM_PASS` | PASS |

실행 명령은 다음과 같음.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\regression\run_all_xsim.ps1
```

## Coverage and expected behavior

| Requirement | Stimulus and check | Result |
|---|---|---|
| Basic ROW | one active row; exact header/time/payload/LAST | PASS |
| Basic BANK | two active rows; exact header/mask/base time/data order/LAST | PASS |
| Basic SPARSE | ON/OFF and local pixel 0/1/2/3; exact address/time/LAST | PASS |
| SPARSE backpressure | two-word packet stable while stalled | PASS |
| Consecutive SPARSE | same tile held by ready, accepted and decoded after release | PASS |
| Cost selection | SPARSE/ROW/BANK directed transitions and mixed payload exclusion | PASS |
| Mixed ON/OFF | independent 4-bit ON and OFF patterns | PASS |
| Multiple active tiles | full row plus multi-row mask/order checks | PASS |
| Timestamp boundary | delta 31 remains BANK; delta 32 falls back to ROW | PASS |
| Random backpressure | LFSR ready; valid/data/last stable through stalls | PASS |
| Multiple banks | concurrent bank streams cannot interleave before LAST | PASS |
| Long contention | four banks, 16 accepted/completed packets each | PASS |
| Reset | idle and stalled mid-packet reset; clean post-reset recovery | PASS |
| Consecutive same tile | second event held while ready=0, then accepted and decoded | PASS |
| Full hierarchy | 4,096 tiles/256 banks elaborate; banks 0 and 255 transmit | PASS |
| Decoder round-trip | 2 directed + 2,048 pseudo-random accepted records | PASS, 2,050/2,050 |

- Round-trip 비교 단위: accepted `{tile_id, ON[3:0], OFF[3:0], timestamp}` record의 multiset임
- Packet 순서: row/bank arbitration 때문에 입력 순서와 달라질 수 있음
- 금지 조건: accepted record의 missing/duplicate/payload change/timestamp change임
- Same-tile backpressure: pending slot 사용 중에는 `tile_in_ready=0`으로 source에 hold 요청함
- Loss 판정: hold된 transaction이 이후 accepted/decode되므로 internal loss로 집계하지 않음

## Execution record

- 실행일: 2026-08-26임
- 환경: Windows native PowerShell임
- Tool: `C:\Xilinx\Vivado\2019.1\bin\vivado.bat`, Vivado v2019.1 build 2552052임
- 단계 결과: 각 top의 `xvlog`, `xelab`, `xsim` 성공함
- 확인 방법: 각 XSim log의 PASS token을 직접 확인함
- 최종 summary: `TOTAL=5`, `PASS_COUNT=5`, `FAIL_COUNT=0`, `AER_ALL_TESTS_PASS`임

## Bugs found during verification

- Runner log encoding: `Tee-Object`의 UTF-16 append 때문에 UTF-8 PASS 검색이 실패함
- Runner 수정: 단일 UTF-8 append로 통일함
- Stress monitor: ready 재상승 handshake 이후 word를 이전 stalled word와 비교해 false failure 41개 발생함
- Monitor 수정: handshake edge 직전 값을 비교하도록 수정함
- RTL 영향: 두 문제 모두 verification infrastructure 오류이며 RTL 본체 변경 없음

## Remaining verification limits

- Random round-trip 범위: bank packetizer 단위임
- Full 128×128 random trace: dataset cross-check에서 수행함
- 미검증 항목: timestamp wrap-around 경계와 formal property proof임
- Reset 전제: pending transaction을 flush하는 현재 RTL 동작을 기준으로 recovery 검증함
- Reset 중 입력 보존: 외부 system 책임임

## Real-dataset RTL verification

- Testbench: `tb/dataset/tb_aer_dataset.v`임
- 입력: 동일한 1024-cycle sparse/dense/burst vector임
- 비교 top: pinned Fair RAW, pinned Team second, Current 128×128임
- Compile/elaboration: Vivado 2019.1에서 top별로 독립 수행함
- Log: accepted input과 output word를 기록함
- Decoder 비교: tile ID, ON/OFF bitmap, 16-bit timestamp, transaction multiplicity임

| Scope | Total | PASS | FAIL |
|---|---:|---:|---:|
| Functional XSim tops | 5 | 5 | 0 |
| Dataset RTL windows | 9 | 9 | 0 |
| Dataset decoder round-trip | 9 | 9 | 0 |

- Dataset PASS token: `AER_DATASET_XSIM_PASS`, `AER_DATASET_ROUNDTRIP_PASS`, `AER_DATASET_XSIM_ALL_PASS`임
- Curated summary 위치: `results/logs`임
- Raw word log: Git에서 제외함
- Previous ROW/BANK 시도: packet-collection delay를 적용했으나 dense word는 줄지 않고 accepted transaction이 감소함
- 판단: 해당 변경을 revert함
- Current candidate: workload evidence에 따라 SPARSE를 추가한 뒤 별도 freeze함

## SPARSE full gate

- Software sweep: 1/10/100/500/1000/2000/5000× 전체 수행함
- Deterministic RTL windows: 9개 전체 수행함
- Functional regression: 5/5 PASS함
- Dataset XSim/decoder round-trip: 9/9 PASS함
- Accepted-to-decoded: sparse 111/111, dense 649/649, burst 641/641임
- Mismatch: missing/extra/payload/timestamp 모두 0임
- Dense mode count: SPARSE/ROW/BANK = 639/2/2임
- 상세 결과: `results/summary.csv`, `results/metrics/dataset_results.json`, `results/metrics/xsim_current_adaptive_*.json`임
