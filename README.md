# Lossless SPARSE/ROW/BANK Adaptive AER Packet Readout

이 저장소는 128×128 polarity-event sensor의 16-bit global link를 위한
SPARSE/ROW/BANK adaptive packetization RTL과 재현 가능한 검증·평가 환경이다.

현재 구조는 픽셀 정보를 버리지 않으면서 실제 workload에서 가장 흔한 singleton
tile transaction을 직접 줄이고, 나머지는 ROW/BANK format으로 보존한다.

## Why SPARSE / ROW / BANK?

1. **Fair RAW baseline.** event마다 spatial address와 timestamp metadata를
   반복하므로 dense traffic에서 16-bit link efficiency가 낮다.
2. **Team second/reference.** RAW8/GROUP3/BIN4와 BIN pair packing을 사용하지만,
   UZH `shapes_rotation`에서는 GROUP3/BIN4 opportunity가 거의 없어 실제 output
   word가 Fair RAW와 같았다.
3. **Previous ROW/BANK.** multi-row bank locality로 address/timestamp를 공유하려
   했지만 BANK fraction이 약 0.2~3%에 그쳤다. Dense XSim 개선은 3.65%였고
   1000x P99는 6,380 cycles까지 증가해 NO-GO였다.
4. **Workload observation.** canonical trace 대부분은 한 2×2 tile-cycle에 polarity
   bit가 하나뿐이었다. 드문 multi-row case보다 흔한 sparse case 최적화가 더
   중요하다고 판단했다.
5. **Current design.** singleton ROW의 3 words를 lossless SPARSE 2 words로 줄이고
   ROW/BANK fallback을 유지한다. SPARSE/ROW 대안과 BANK cost를 비교해 BANK가
   strictly cheaper일 때만 선택하며, 같은 cost면 짧은 packet을 우선한다.
6. **Lossless evidence.** bank ID, tile ID, pixel ID, polarity와 full 16-bit
   timestamp를 모두 보존한다. Functional random 2,050건과 sparse/dense/burst
   dataset RTL decoder round-trip이 모두 PASS했고 unintended loss는 0이다.
7. **Measured result.** Full 7-speed sweep에서 RAW 대비 words/accepted-event가
   28.45~33.24% 감소했고, 500x 이상에서는 accepted event도 16.84~36.53%
   증가했다. 대신 1000x 이상 P99는 RAW보다 높아 throughput-latency trade-off가
   남는다.

```text
128×128 pixels
  -> 2×2 tile: ON[3:0], OFF[3:0]
  -> 4×4 tiles / bank = 8×8 pixels
  -> lossless SPARSE, ROW or BANK packet
  -> 4×4-bank regional packet mux
  -> 2-entry elastic buffer
  -> root packet mux
  -> 16-bit valid / ready / last
```

## Adaptive rule

- ON/OFF 전체에서 polarity bit가 하나뿐인 tile은 2-word SPARSE 후보가 된다.
- 각 row의 ROW cost와 SPARSE/ROW 혼합 cost, 전체 BANK cost를 비교한다.
- BANK는 delta가 31 이하이고 혼합 대안보다 실제 word가 적을 때만 쓴다.
- 같은 cost면 packet lock이 짧은 SPARSE/ROW를 우선한다.
- BANK DATA는 tile ID 오름차순이며 16-bit tile mask가 위치를 복원한다.
- DATA word는 `delta[4:0]`, `ON[3:0]`, `OFF[3:0]`를 보존한다.
- binning, GROUP3, BIN4 또는 의도적 lossy compression은 사용하지 않는다.

비트 규약은 [PACKET_FORMAT.md](docs/PACKET_FORMAT.md), 전체 신호 흐름은
[ARCHITECTURE.md](docs/ARCHITECTURE.md)에 정리했다.

## Repository layout

```text
rtl/          synthesizable Verilog-2001
tb/           unit, regression, dataset self-checking testbenches
scripts/      XSim, regression, dataset, reference helpers
sw/           dataset loader, metrics, decoder, visualization
docs/         architecture, verification, evaluation, handoff documents
results/      curated summaries, metrics, figures, animations
```

## Vivado 2019.1 XSim

```powershell
powershell -ExecutionPolicy Bypass -File scripts\regression\run_all_xsim.ps1
```

기본 설치 경로가 아니면 `-VivadoPath`에 Vivado 2019.1의 `vivado.bat` 또는
`bin` directory를 지정한다. 모든 test는 compile/elaboration/simulation과 PASS
token을 확인하며 한 test라도 실패하면 non-zero로 종료한다.

현재 suite는 5개 self-checking top으로 구성되며 SPARSE/ROW/BANK format,
timestamp 31/32 boundary, 128×128 elaboration, reset recovery, random
backpressure, sustained four-bank contention, same-tile backpressure와 2,050건
decoder round-trip을 검사한다. 결과는 `results/logs/regression_summary.txt`에
남는다.

## Dataset evaluation

원본 dataset은 `data/` 아래에 두며 Git에 올리지 않는다. UZH
`shapes_rotation`을 canonical event trace로 변환한 뒤 동일 trace를 fair RAW,
팀 2차 설계, 현재 설계에 사용한다. 실행법과 provenance는
[DATASET_EVALUATION.md](docs/DATASET_EVALUATION.md)에 기록한다.

```powershell
# download/checksum + 7-speed software sweep + 3-design/3-window XSim
powershell -ExecutionPolicy Bypass -File scripts\dataset\run_all_dataset.ps1
```

공식 UZH ZIP의 SHA-256과 92,861-event crop을 자동 검증한다. XSim dataset
단계는 pinned team commit을 ignored build directory에 export하며 현재 branch로
merge하지 않는다.

## Measured status

- 기능 regression: 5/5 PASS
- random accepted-to-decoded round-trip: 2,050/2,050
- full UZH software sweep: 1/10/100/500/1000/2000/5000x 완료
- RAW 대비 words/accepted-event 감소: 28.45~33.24%
- 1000x: RAW 2.9313, Current 1.9960 words/accepted-event; accepted event +36.15%
- 1000x P99: RAW 502, Previous ROW/BANK 6,380, Current 2,577 cycles
- dataset RTL: 9/9 compile/elaboration/simulation/round-trip PASS
- dense XSim: RAW/Team 2.9519, Current 2.0000 words/transaction
- Current sparse/dense/burst round-trip: 111/111, 649/649, 641/641;
  missing/extra/payload/timestamp mismatch 모두 0
- unintended loss: 0 in all software and accepted RTL comparisons

결론은 **READY FOR CADENCE EVALUATION**이다. 이는 다음 단계에서 PPA를 평가할
가치가 있다는 뜻이며, 이 저장소 평가에서는 Cadence tool을 실행하지 않았다.

## Reproducibility anchors

- Repository: `https://github.com/chldjwls85/AER`
- Current branch: `AER_hyeonho`
- Team second design pinned commit:
  `da686477ca054faada5f66d369f1fb253b2bf562`
- Fair RAW top: `aer_v1_raw_top_128`, `ENABLE_BINNING=0`
- Team second design: `aer_v1_top_128`, `ENABLE_BINNING=1`
- Current top: `aer_top_128`

Exact SHA와 평가일은 [REFERENCE_VERSIONS.md](docs/REFERENCE_VERSIONS.md)에 둔다.

## Known limitations

- tile마다 pending slot이 하나이므로 source가 `tile_in_ready`를 지켜야 한다.
- output은 16-bit single global link라 지속적인 overload를 제거하지 못한다.
- BANK/ROW delta는 5-bit이며 31 clocks를 넘으면 다른 lossless packet으로 fallback한다.
- same-tile burst는 `ready=0` backpressure로 보존하지만 source-side queue가 필요하다.
- 16-bit timestamp wrap-around를 가로지르는 grouping은 아직 별도 검증하지 않았다.
- single global link와 얕은 pending storage 때문에 accelerated load에서 P99
  latency가 RAW보다 나빠질 수 있다.
- UZH 한 dataset만 provenance가 확인됐고 CIFAR10-DVS 기존 사용 증거는 없었다.
- PPA는 측정하지 않았으며 이번 단계에서 Cadence tool을 실행하지 않았다.

Full UZH gate는 통과했지만 dataset generality와 PPA는 아직 확인하지 않았다.
다음 단계에서는 이 RTL을 변경하지 않고 Cadence PPA와 추가 dataset robustness를
평가한다.
