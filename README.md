# AER Proposed Architecture: SPARSE/ROW + Hierarchical Readout + Regional Timebase

128×128 polarity-event sensor를 대상으로 Traditional AER의 event-by-event 반복 전송을 줄이고, 구현 단계의 timestamp fan-out 병목까지 완화한 lossless AER readout RTL임.

## 현재 기준

- Latest architecture: **V5**
- Top: `aer_top_v5_128`
- Input: 2×2 pixel tile, `ON[3:0]`, `OFF[3:0]`, `valid/ready`
- Bank: 8×8 pixels = 16 tiles
- Packet: **SPARSE / ROW**
- Readout: **Bank → Region → Root**
- Region: 4×4 banks, total 16 regions
- Timebase: **16 Regional 16-bit Timebases**
- Output: 16-bit `valid/ready/last`
- Lossless target: tile ID / ON-OFF / timestamp 보존함.

## 설계 발전

| 단계 | 핵심 변경 | 판단 |
|---|---|---|
| V3 | SPARSE/ROW/BANK adaptive packet | traffic 효율은 개선했으나 BANK complexity 대비 실효성이 낮음 |
| V4 | BANK 제거, Lightweight SPARSE/ROW | 구조 단순화 후 global timestamp fan-out bottleneck 확인함 |
| V5 | 1 global counter → 16 regional counters | timestamp worst path를 제거하고 대회 Genus 100 MHz timing MET 확인함 |

상세 과정: [docs/AER_V3_V5_DESIGN_EVOLUTION.md](docs/AER_V3_V5_DESIGN_EVOLUTION.md)

## Traffic 결과

UZH `shapes_rotation` 기반 평가에서 RAW 대비 word efficiency를 개선함.

| Speed | RAW words/accepted | Proposed words/accepted | 감소율 |
|---:|---:|---:|---:|
| 1× | 2.9944 | 1.9990 | 33.24% |
| 500× | 2.9727 | 1.9982 | 32.78% |
| 1000× | 2.9313 | 1.9960 | 31.90% |
| 5000× | 2.7852 | 1.9928 | 28.45% |

- 1000× accepted events는 46,610 → 63,458로 증가함.
- high-load에서는 더 많은 traffic을 수용하면서 P99 latency가 증가하는 trade-off가 존재함.
- 상세 결과: [docs/DATASET_EVALUATION.md](docs/DATASET_EVALUATION.md)

## V5 Verification

- `AER_V5_TIMEBASE_SANITY_PASS` 확인함.
- 16 Regional Timebases가 reset 후 lockstep +1로 동작함.
- 256 banks 전체 region mapping mismatch 0을 확인함.
- `AER_V4_V5_EQUIV_PASS` 확인함.
- SPARSE, ROW, simultaneous request, backpressure에서 output/ready mismatch 0을 확인함.
- V4→V5 변경은 timestamp distribution이며 packet behavior는 동일함.

상세: [docs/VERIFICATION.md](docs/VERIFICATION.md)

## 연구실 DC V4 → V5

동일 Synopsys DC / SAED32 / 10 ns 조건의 상대 비교임.

| 항목 | V4 | V5 |
|---|---:|---:|
| Critical Path | 28.05 ns | **25.26 ns** |
| WNS | -18.27 ns | **-15.49 ns** |
| TNS | -1.059M ns | **-0.770M ns** |
| Sequential Cells | 111,369 | **111,609** |
| Design Area | 3.511M | **3.502M** |

- global timestamp distribution이 worst path에서 제거됨.
- V5 worst path는 bank-local `pending_reg → sparse_pixel_reg`로 이동함.
- 상세: [docs/DC_SAED32_COMPARISON.md](docs/DC_SAED32_COMPARISON.md)
- 결과 근거: [results/synthesis/dc_v5/](results/synthesis/dc_v5/)

## 대회 Genus V5 최종 결과

실제 대회 서버 최종 report를 기준으로 결과를 확정함.

| 항목 | 결과 |
|---|---:|
| Target Clock | 100 MHz (10 ns) |
| Timing | **MET** |
| WNS | **+0.5819 ns** |
| TNS | **0 ns** |
| Violating Paths | **0** |
| Worst Data Path | 9.075 ns |
| Leaf Instances | 552,073 |
| Sequential Instances | 111,609 |
| Cell Area | **1,590,675.448** |
| Power Estimate | **43.84 mW** |
| Elapsed Runtime | 9,207 s |

- Worst setup path는 `pending_reg[0] → sparse_pixel_reg[0]`로 확인함.
- V4에서 문제였던 global timestamp distribution은 최종 worst path에 나타나지 않음.
- Area report에서 16개 Regional Timebase hierarchy가 유지됨을 확인함.
- Power 값은 synthesis-stage estimate이며 post-layout signoff power가 아님.
- 상세: [docs/GENUS_V5_RESULTS.md](docs/GENUS_V5_RESULTS.md)
- 결과 근거: [results/synthesis/genus_v5/](results/synthesis/genus_v5/)

## 주요 문서

- [Architecture](docs/ARCHITECTURE.md)
- [Packet Format](docs/PACKET_FORMAT.md)
- [Verification](docs/VERIFICATION.md)
- [Dataset Evaluation](docs/DATASET_EVALUATION.md)
- [V3→V5 Design Evolution](docs/AER_V3_V5_DESIGN_EVOLUTION.md)
- [DC V3/V4/V5 Comparison](docs/DC_SAED32_COMPARISON.md)
- [Genus V5 Results](docs/GENUS_V5_RESULTS.md)
- [Reference Versions](docs/REFERENCE_VERSIONS.md)

## 결과 해석 주의

- 연구실 DC와 대회 Genus의 절대 area/timing 수치는 직접 비교하지 않음.
- 서로 다른 library/technology/optimization flow를 사용하므로 각 환경 내부의 판단 기준으로 사용함.
- Innovus P&R, extracted RC, post-layout STA/power는 현재 범위에 포함하지 않음.
