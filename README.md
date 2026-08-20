# Lossless Adaptive AER Packet Readout

이 저장소는 128×128 polarity-event sensor의 16-bit global link를 위한
ROW/BANK adaptive packetization RTL과 재현 가능한 검증·평가 환경이다.

기존 RAW AER는 event마다 주소와 timestamp를 반복해 dense traffic에서 링크
효율이 낮다. 팀 2차 설계는 같은 계층에서 RAW8/GROUP3/BIN4를 선택하지만,
GROUP3와 단독 BIN4는 여전히 DATA word 하나를 사용하며 BIN4 두 개가 같은 row에
모일 때만 word 수가 감소한다. 현재 구조는 픽셀 정보를 버리지 않고 active row
수와 timestamp span에 따라 공유 overhead를 줄인다.

```text
128×128 pixels
  -> 2×2 tile: ON[3:0], OFF[3:0]
  -> 4×4 tiles / bank = 8×8 pixels
  -> lossless ROW or BANK packet
  -> 4×4-bank regional packet mux
  -> 2-entry elastic buffer
  -> root packet mux
  -> 16-bit valid / ready / last
```

## Adaptive rule

- 한 row만 active이거나 timestamp span이 31 clocks를 넘으면 ROW packet을 쓴다.
- 두 row 이상이 active이고 전체 span이 31 clocks 이하이면 BANK packet을 쓴다.
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

현재 suite는 5개 self-checking top으로 구성되며 기본 ROW/BANK format,
timestamp 31/32 boundary, 128×128 elaboration, reset recovery, random
backpressure, sustained four-bank contention, same-tile backpressure와 2,050건
decoder round-trip을 검사한다. 결과는 `results/logs/regression_summary.txt`에
남는다.

## Dataset evaluation

원본 dataset은 `data/` 아래에 두며 Git에 올리지 않는다. UZH
`shapes_rotation`을 canonical event trace로 변환한 뒤 동일 trace를 fair RAW,
팀 2차 설계, 현재 설계에 사용한다. 실행법과 provenance는
[DATASET_EVALUATION.md](docs/DATASET_EVALUATION.md)에 기록한다.

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
- BANK delta는 5-bit이며 31 clocks를 넘으면 ROW fallback한다.
- same-tile burst는 `ready=0` backpressure로 보존하지만 source-side queue가 필요하다.
- 16-bit timestamp wrap-around를 가로지르는 grouping은 아직 별도 검증하지 않았다.
- PPA는 아직 측정하지 않았으며 이번 단계에서는 Cadence tool을 실행하지 않는다.

Cadence 실험 가치가 정량적으로 확인될 때만 `GO for Cadence`로 동결하며,
그 전까지 PPA 개선을 주장하지 않는다.
