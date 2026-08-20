# Cadence Handoff

Cadence tools are not executed in this phase. This document becomes actionable
only if the functional and dataset gate concludes `GO for Cadence`.

| Item | Candidate |
|---|---|
| Top module | `aer_top_128` |
| RTL filelist | `rtl/filelist.f` |
| Clock assumption | 100 MHz initial comparison clock |
| Public interface | 4096 tile valid/ready, 16384-bit ON/OFF buses, 16-bit output |
| Activity source | representative UZH canonical trace converted to RTL stimulus |
| Genus comparison | pinned fair RAW, pinned team design, current design |

Final recommended trace, constraints and GO evidence remain pending dataset evaluation.
