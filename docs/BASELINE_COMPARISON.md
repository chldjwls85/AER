# Baseline Comparison

## Fixed designs

| Design | Exact RTL definition | Encoding |
|---|---|---|
| Fair RAW | pinned `aer_v1_top`, `ENABLE_BINNING=0` (`aer_v1_raw_top_128` wrapper) | ROW + RAW8 |
| Team second | pinned `aer_v1_top`, `ENABLE_BINNING=1` | ROW + RAW8/GROUP3/BIN4/BIN pair |
| Current | `aer_top_128` | adaptive lossless SPARSE/ROW/BANK |

All use 128x128 pixels, 2x2 ON/OFF tile input, 4x4 tiles/bank, one pending
slot/tile, 16-bit valid/ready/last output, 100 MHz and the same canonical trace.
The pinned reference RTL is exported, not merged into this branch.

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

Quick result의 약 30% gain은 전체 sweep에서 유지됐다. 500x까지 Current P99가
RAW보다 낮지만, 1000x 이상에서는 더 많은 event를 수용하고 max pending이
194/338/529까지 커지면서 tail latency가 RAW보다 높다. 이는 숨겨진 loss가 아니라
single-link overload에서 나타난 throughput-latency trade-off다.

Team second equals Fair RAW on this UZH trace: GROUP3=0, BIN4=0 and BIN pair=0
in all representative XSim windows. This is not a general claim that bin
packing never helps; the pinned unit tests prove it helps full one-polarity
tiles, but those patterns do not occur here after cycle/tile canonicalization.

## Representative RTL answer

| Window | RAW accepted / words / words-per-transaction | Current accepted / words / words-per-transaction | Reduction |
|---|---|---|---:|
| sparse | 111 / 333 / 3.0000 | 111 / 222 / 2.0000 | 33.33% |
| dense | 416 / 1,228 / 2.9519 | 649 / 1,298 / 2.0000 | 32.25% |
| burst | 423 / 1,237 / 2.9243 | 641 / 1,280 / 1.9969 | 31.71% |

모든 Current accepted transaction이 exact decoder round-trip을 통과했다. Current
mode는 sparse/dense/burst에서 각각 `111/0/0`, `639/2/2`, `628/4/1`
(SPARSE/ROW/BANK)으로 SPARSE가 지배적이다.

## Previous ROW/BANK decision

**NO-GO / More architecture work required.** Functional correctness is strong,
but representative real-data efficiency is below 10%, the best actual RTL
window is 3.65%, and modeled P99 latency degrades under accelerated load.
Cadence tools were not run.

## Current decision

**READY FOR CADENCE EVALUATION.** Functional regression, full UZH sweep and
all representative RTL round-trips pass with unintended loss 0. Word reduction
is consistent and well above the 10% practical gate. Cadence evaluation should
measure whether the additional packet-cost logic is justified in area/timing,
and must report the 1000x+ P99 penalty alongside throughput gains. Cadence tools
were not executed here.
