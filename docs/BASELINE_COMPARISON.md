# Baseline Comparison

> 명칭 주의: 본 문서의 `Current`는 V3 SPARSE/ROW/BANK candidate를 의미함.
> V4 Dataset 결과를 의미하지 않음.

## Fixed designs

| Design | Exact RTL definition | Encoding |
|---|---|---|
| Fair RAW | pinned `aer_v1_top`, `ENABLE_BINNING=0` (`aer_v1_raw_top_128` wrapper) | ROW + RAW8 |
| Team second | pinned `aer_v1_top`, `ENABLE_BINNING=1` | ROW + RAW8/GROUP3/BIN4/BIN pair |
| Current | `aer_top_128` | adaptive lossless SPARSE/ROW/BANK |

공통 비교 조건은 다음과 같음.

- Sensor: 128×128 pixels임
- 입력: 2×2 ON/OFF tile임
- Bank: 4×4 tiles/bank임
- Pending: tile당 1 slot임
- 출력: 16-bit `valid/ready/last`임
- Clock/model 조건: 100 MHz와 동일 canonical trace 사용함
- Reference RTL: pinned commit에서 export하며 현재 branch에 merge하지 않음

## Full quantitative answer

| Speed | RAW words/accepted | Current words/accepted | Reduction | Accepted gain | RAW P99 | Current P99 |
|---:|---:|---:|---:|---:|---:|---:|
| 1x | 2.9944 | 1.9990 | 33.24% | 0.00% | 5 | 3 |
| 10x | 2.9944 | 1.9990 | 33.24% | 0.00% | 5 | 3 |
| 100x | 2.9944 | 1.9990 | 33.24% | 0.02% | 8 | 4 |
| 500x | 2.9727 | 1.9982 | 32.78% | 16.84% | 303 | 76 |
| 1000x | 2.9313 | 1.9960 | 31.90% | 36.15% | 502 | 2,577 |
| 2000x | 2.8855 | 1.9945 | 30.88% | 36.23% | 644 | 5,051 |
| 5000x | 2.7852 | 1.9928 | 28.45% | 36.53% | 832 | 4,710 |

- Word efficiency: quick result의 약 30% gain이 full sweep에서도 유지됨
- 500× 이하: Current P99가 RAW보다 낮음
- 1000× 이상: accepted event와 max pending이 함께 증가해 tail latency가 RAW보다 높아짐
- 해석: hidden loss가 아니라 single-link overload의 throughput-latency trade-off임
- Team second: 대표 XSim window에서 GROUP3/BIN4/BIN pair 사용 횟수가 모두 0임
- 주의: bin packing이 항상 무효라는 뜻은 아님. UZH canonical trace에 해당 pattern이 거의 없다는 뜻임

## Representative RTL answer

| Window | RAW accepted / words / words-per-transaction | Current accepted / words / words-per-transaction | Reduction |
|---|---|---|---:|
| sparse | 111 / 333 / 3.0000 | 111 / 222 / 2.0000 | 33.33% |
| dense | 416 / 1,228 / 2.9519 | 649 / 1,298 / 2.0000 | 32.25% |
| burst | 423 / 1,237 / 2.9243 | 641 / 1,280 / 1.9969 | 31.71% |

- Exact round-trip: 모든 Current accepted transaction이 PASS함
- Mode count: sparse/dense/burst에서 각각 `111/0/0`, `639/2/2`, `628/4/1`임
- 해석: 세 window 모두 SPARSE가 지배적임

## Previous ROW/BANK decision

- 판단: **NO-GO / More architecture work required**임
- Functional correctness: 확보함
- Real-data efficiency: 대표 결과 10% 미만임
- Best actual RTL window: 3.65% 개선에 그침
- Latency: accelerated load에서 modeled P99가 악화됨
- Cadence tools: 이 단계에서 실행하지 않음

## Current decision

- 당시 판단: **READY FOR CADENCE EVALUATION**임
- Gate 결과: functional regression, full UZH sweep, 대표 RTL round-trip 모두 PASS함
- Unintended loss: 0임
- Word reduction: 10% practical gate를 일관되게 초과함
- 후속 확인 항목: packet-cost logic의 Area/Timing overhead임
- 보고 시 필수 병기: 1000× 이상 P99 penalty와 throughput gain임
- Cadence tools: 이 문서의 평가 단계에서는 실행하지 않음
- 이후 V3/V4 최종 판단: `AER_V3_V4_DESIGN_EVOLUTION.md` 참조 필요함
