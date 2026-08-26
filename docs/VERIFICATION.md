# Verification

## Current freeze gate

| Test | Purpose | Expected token | Status |
|---|---|---|---|
| `tb_aer_bank_packetizer` | SPARSE ON/OFF/pixel/timestamp, delta 31/32, ROW/BANK, backpressure | `AER_BANK_PACKETIZER_TB_PASS` | PASS |
| `tb_aer_top` | 16×16 hierarchy, mixed payload, multi-bank packet lock | `AER_ADAPTIVE_PACKET_TB_PASS` | PASS |
| `tb_aer_top_128_smoke` | 128×128 elaboration and bank 0/255 connectivity | `AER_128_SMOKE_PASS` | PASS |
| `tb_aer_protocol_stress` | idle/mid-packet reset, random stalls, 4-bank long contention/fairness | `AER_PROTOCOL_STRESS_PASS` | PASS |
| `tb_aer_roundtrip_random` | same-tile backpressure and accepted-to-decoded semantic equality | `AER_ROUNDTRIP_RANDOM_PASS` | PASS |

Run:

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

Round-trip equality compares the multiset of accepted
`{tile_id, ON[3:0], OFF[3:0], timestamp}` records. Packet ordering may differ from
input ordering because rows and banks arbitrate, but no accepted record may be
missing, duplicated, or modified. A same-tile event presented while its pending
slot is occupied is not counted as loss: `tile_in_ready=0` tells the source to
hold it, and the test proves that the held transaction is later accepted.

## Execution record

2026-08-26 Windows native PowerShell에서
`C:\Xilinx\Vivado\2019.1\bin\vivado.bat` (Vivado v2019.1 build 2552052)를
사용했다. SPARSE 변경 후 각 top의 `xvlog`, `xelab`, `xsim`이 모두 성공했고 각 XSim log에서
PASS token을 직접 확인했다. 최종 summary는 `TOTAL=5`, `PASS_COUNT=5`,
`FAIL_COUNT=0`, `AER_ALL_TESTS_PASS`이다.

## Bugs found during verification

- 첫 runner는 `Tee-Object`의 UTF-16 append 때문에 콘솔 PASS를 UTF-8 log
  검색에서 찾지 못했다. 단일 UTF-8 append로 수정했다.
- 최초 stress monitor가 ready 재상승 handshake 뒤의 다음 word를 이전 stalled
  word와 비교해 41개 false failure를 냈다. handshake edge 직전 값 비교로
  수정했다.
- 두 문제 모두 verification infrastructure 오류이며 RTL 본체 변경은 없었다.

## Remaining verification limits

- random round-trip은 bank packetizer 단위이며 full 128×128 random trace는 dataset
  cross-check에서 수행한다.
- timestamp wrap-around 경계와 formal property proof는 아직 포함하지 않는다.
- reset은 pending transaction을 flush하는 현재 RTL 동작을 전제로 recovery를
  검증한다. reset 중 입력 보존은 외부 system 책임이다.

## Real-dataset RTL verification

`tb/dataset/tb_aer_dataset.v`는 동일한 1024-cycle sparse/dense/burst vectors를
pinned Fair RAW, pinned Team second, Current 128x128 top에 투입한다. 각 top은
Vivado 2019.1에서 별도 compile/elaboration되며 accepted input과 output word를
로그로 남긴다. Python decoder가 tile ID, ON/OFF bitmap, 16-bit timestamp와
transaction multiplicity를 비교한다.

| Scope | Total | PASS | FAIL |
|---|---:|---:|---:|
| Functional XSim tops | 5 | 5 | 0 |
| Dataset RTL windows | 9 | 9 | 0 |
| Dataset decoder round-trip | 9 | 9 | 0 |

Dataset tokens are `AER_DATASET_XSIM_PASS`,
`AER_DATASET_ROUNDTRIP_PASS`, and `AER_DATASET_XSIM_ALL_PASS`. Curated
summaries are under `results/logs`; raw word logs are ignored.

Previous ROW/BANK에서 packet-collection delay를 시험했으나 dense words를 줄이지
못하고 accepted transaction을 감소시켜 revert했다. 현재 SPARSE/ROW/BANK RTL은
그 이후 workload evidence에 따라 동결한 별도 candidate다.

## SPARSE full gate

1/10/100/500/1000/2000/5000x software sweep과 기존 deterministic 9개 RTL
window를 모두 재실행했다. Functional regression은 5/5, dataset XSim과 decoder
round-trip은 9/9 PASS다. Current sparse/dense/burst accepted-to-decoded 결과는
111/111, 649/649, 641/641이며 missing/extra/payload/timestamp mismatch는 모두
0이다. Dense mode count는 SPARSE/ROW/BANK = 639/2/2다. 상세 값은
`results/summary.csv`, `results/metrics/dataset_results.json`과
`results/metrics/xsim_current_adaptive_*.json`에 있다.
