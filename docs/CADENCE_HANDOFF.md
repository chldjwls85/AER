# Cadence Handoff

## Status: HOLD — quick gate PROMISING, full evaluation pending

Cadence Xcelium, Genus and Innovus were not executed. The real-data gate did
not justify PPA work: 1000x software efficiency improved 1.26%, dense RTL XSim
improved 3.65%, and accelerated-load P99 latency worsened.

If later architecture work clears the gate, the candidate handoff is:

| Item | Candidate |
|---|---|
| Top | `aer_top_128` |
| Synthesizable filelist | `rtl/filelist.f` |
| Initial clock | 100 MHz / 10 ns |
| Input | 4096 tile valid/ready, 16384-bit ON and OFF buses |
| Output | 16-bit valid/ready/last |
| Activity | UZH 1000x dense and burst vectors under `data/generated` |
| Comparisons | pinned Fair RAW, pinned Team second, Current |
| Functional prerequisites | 5/5 regression and 9/9 dataset XSim round-trip |

Before lifting HOLD, demonstrate at least ~10% representative word/bit
reduction without the observed latency penalty, preferably on more than one
provenance-controlled dataset.
