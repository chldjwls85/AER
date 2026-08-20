# Baseline Comparison

## Fixed designs

| Design | Exact RTL definition | Encoding |
|---|---|---|
| Fair RAW | pinned `aer_v1_top`, `ENABLE_BINNING=0` (`aer_v1_raw_top_128` wrapper) | ROW + RAW8 |
| Team second | pinned `aer_v1_top`, `ENABLE_BINNING=1` | ROW + RAW8/GROUP3/BIN4/BIN pair |
| Current | `aer_top_128` | adaptive lossless ROW/BANK |

All use 128x128 pixels, 2x2 ON/OFF tile input, 4x4 tiles/bank, one pending
slot/tile, 16-bit valid/ready/last output, 100 MHz and the same canonical trace.
The pinned reference RTL is exported, not merged into this branch.

## Quantitative answer

At ordinary timing all designs accept every event. Current reduces words by
only 194 of 278,066 (0.07%). At 1000x the model gives a 1.26% reduction in
words/accepted-event and 1.57% more accepted events, but P99 latency rises from
502 to 6,380 cycles. Actual dense-window XSim gives a stronger but still small
3.65% word-efficiency gain and 28.1% more accepted transactions. Sparse XSim is
exactly equal at 3 words/transaction, so there is no sparse penalty.

Team second equals Fair RAW on this UZH trace: GROUP3=0, BIN4=0 and BIN pair=0
in all representative XSim windows. This is not a general claim that bin
packing never helps; the pinned unit tests prove it helps full one-polarity
tiles, but those patterns do not occur here after cycle/tile canonicalization.

## Research questions

1. Multi-row bank activity is not frequent enough: BANK fraction is 0.21% at
   1x and peaks at 3.07% at 500x in the sweep.
2. BANK selection therefore remains a small minority of packets.
3. RAW reduction is 0.07% at 1x, 1.69% at 500x, and 1.26% at 1000x.
4. Team second is identical to RAW for this dataset, so the same percentages
   apply versus Team.
5. Sparse traffic has no measured overhead: 111 accepted, 333 words for all.
6. Dense/burst latency is not improved in the long-trace model; it is worse.
7. Backpressure begins between 10x and 100x for all designs; no clear
   saturation-onset shift is demonstrated.
8. The small traffic reduction does not justify Cadence PPA effort for this
   architecture hypothesis yet.
9. Only the provenance-confirmed UZH trace was evaluated, so cross-dataset
   generality is not established.
10. The practical gate is not met.

## Decision

**NO-GO / More architecture work required.** Functional correctness is strong,
but representative real-data efficiency is below 10%, the best actual RTL
window is 3.65%, and modeled P99 latency degrades under accelerated load.
Cadence tools were not run.
