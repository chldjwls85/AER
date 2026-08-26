# Lossless SPARSE/ROW/BANK Adaptive AER Packet Readout

이 저장소는 128×128 polarity-event sensor의 16-bit global link를 위한
SPARSE/ROW/BANK adaptive packetization RTL과 재현 가능한 검증·평가 환경이다.

기존 RAW AER는 event마다 주소와 timestamp를 반복해 dense traffic에서 링크
효율이 낮다. 팀 2차 설계는 같은 계층에서 RAW8/GROUP3/BIN4를 선택하지만,
GROUP3와 단독 BIN4는 여전히 DATA word 하나를 사용하며 BIN4 두 개가 같은 row에
모일 때만 word 수가 감소한다. 현재 구조는 픽셀 정보를 버리지 않고 active row
수와 timestamp span에 따라 공유 overhead를 줄인다.

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
- quick 1x software words/event: RAW/Team 2.9944, Current 1.9990
- quick 1000x software words/accepted-event: RAW/Team 2.9313, Current 1.9960
- quick 1000x P99: 이전 ROW/BANK 6,380, Current 2,577 cycles
- dense XSim: RAW/Team 2.9519 (기존 pinned 결과), Current 2.0000 words/transaction
- dense Current round-trip: 649/649, missing/extra 0/0

Quick gate 결론은 **PROMISING: proceed to full evaluation**이다. 전체 speed sweep과
추가 dataset 검증 전까지 Cadence handoff는 계속 보류하며 Cadence tool은 실행하지
않았다.

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

다음 구조 연구가 representative traffic에서 약 10% 이상 개선을 보인 뒤에만
Cadence handoff HOLD를 해제한다.
