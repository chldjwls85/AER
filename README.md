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
| V3 | SPARSE/ROW/BANK adaptive packet | traffic 효율 개선, BANK complexity 대비 실효성 낮음 |
| V4 | BANK 제거, Lightweight SPARSE/ROW | 기능/전송 구조 단순화, global timestamp fan-out bottleneck 확인 |
| V5 | 1 global counter → 16 regional counters | timestamp worst path 제거, 대회 Genus 100 MHz timing MET |

상세 과정: [docs/AER_V3_V5_DESIGN_EVOLUTION.md](docs/AER_V3_V5_DESIGN_EVOLUTION.md)

## Traffic 결과

UZH `shapes_rotation` 기반 평가에서 RAW 대비 word efficiency를 개선함.

| Speed | RAW words/accepted | Proposed words/accepted | 감소율 |
|---:|---:|---:|---:|
| 1× | 2.9944 | 1.9990 | 33.24% |
| 500× | 2.9727 | 1.9982 | 32.78% |
| 1000× | 2.9313 | 1.9960 | 31.90% |
| 5000× | 2.7852 | 1.9928 | 28.45% |

- 1000× accepted events: 46,610 → 63,458로 증가함.
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

동일 Synopsys DC/SAED32/10 ns 조건의 상대 비교임.

| 항목 | V4 | V5 |
|---|---:|---:|
| Critical Path | 28.05 ns | **25.26 ns** |
| WNS | -18.27 ns | **-15.49 ns** |
| TNS | -1.059M ns | **-0.770M ns** |
| Sequential Cells | 111,369 | **111,609** |
| Design Area | 3.511M | **3.502M** |

- global timestamp distribution이 worst path에서 제거됨.
- V5 worst path는 bank-local `pending_reg → sparse_pixel_reg`로 이동함.
- Reports: [results/synthesis/dc_v5/](results/synthesis/dc_v5/)
- 상세: [docs/DC_SAED32_COMPARISON.md](docs/DC_SAED32_COMPARISON.md)

## 대회 Genus V5 최종 결과

Cadence Genus 23.14-s090_1 / GSCLIB045 slow / 0.9 V / 125°C / 10 ns constraint에서 full synthesis 완료함.

| 항목 | 결과 |
|---|---:|
| Timing | **MET** |
| WNS | **+0.5819 ns** |
| TNS | **0 ns** |
| Violating Paths | **0** |
| Worst data path | 9.075 ns |
| Leaf Instances | 552,073 |
| Sequential Instances | 111,609 |
| Cell Area | 1,590,675.448 |
| Power estimate | 약 43.84 mW |
| Elapsed Runtime | 9,207 s |

- Genus worst path도 `pending_reg → sparse_pixel_reg`로 확인함.
- Power는 synthesis-stage vectorless/default-activity estimate이며 post-layout signoff 값이 아님.
- 상세: [docs/GENUS_V5_RESULTS.md](docs/GENUS_V5_RESULTS.md)
- Result summary: [results/synthesis/genus_v5/](results/synthesis/genus_v5/)

## 주요 RTL

```text
rtl/aer_top_v5.v
rtl/filelist_v5.f
rtl/bank/aer_bank_packetizer_v4.v
rtl/common/aer_timebase.v
rtl/common/aer_packet_rr_arbiter.v
rtl/common/aer_stream_buffer2.v
rtl/fabric/aer_packet_mux.v
rtl/fabric/aer_global_readout.v
```

## 문서

- [Architecture](docs/ARCHITECTURE.md)
- [Packet Format](docs/PACKET_FORMAT.md)
- [Verification](docs/VERIFICATION.md)
- [Dataset Evaluation](docs/DATASET_EVALUATION.md)
- [V3→V5 Design Evolution](docs/AER_V3_V5_DESIGN_EVOLUTION.md)
- [DC V3/V4/V5 Comparison](docs/DC_SAED32_COMPARISON.md)
- [Genus V5 Results](docs/GENUS_V5_RESULTS.md)
- [Reference Versions](docs/REFERENCE_VERSIONS.md)

## 주의

- 연구실 DC와 대회 Genus의 절대 area/timing 수치를 서로 직접 비교하지 않음.
- 서로 다른 library/technology/optimization flow를 사용하므로 각 환경 내부의 판단 기준으로 사용함.
- Innovus P&R, extracted RC, post-layout STA/power는 현재 범위에 포함하지 않음.
