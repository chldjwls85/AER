# Verification

## Current freeze gate

| Test | Purpose | Expected token | Status |
|---|---|---|---|
| `tb_aer_bank_packetizer` | delta 31/32, ROW/BANK words, backpressure | `AER_BANK_PACKETIZER_TB_PASS` | PASS |
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

2026-08-21 Windows native PowerShell에서
`C:\Xilinx\Vivado\2019.1\bin\vivado.bat` (Vivado v2019.1 build 2552052)를
사용했다. 각 top의 `xvlog`, `xelab`, `xsim`이 모두 성공했고 각 XSim log에서
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
