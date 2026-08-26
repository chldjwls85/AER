# Cadence Handoff

## Status: READY FOR CADENCE EVALUATION

Cadence Xcelium, Genus and Innovus were not executed. Current
SPARSE/ROW/BANK는 7-speed UZH sweep에서 RAW 대비 28.45~33.24%의 일관된
words/accepted-event 감소를 보였고, 9/9 dataset RTL round-trip과 5/5 functional
regression을 통과했다. 따라서 다음 단계에서 PPA를 평가할 가치가 있다.

Candidate handoff:

| Item | Candidate |
|---|---|
| Top | `aer_top_128` |
| Synthesizable filelist | `rtl/filelist.f` |
| Initial clock | 100 MHz / 10 ns |
| Input | 4096 tile valid/ready, 16384-bit ON and OFF buses |
| Output | 16-bit valid/ready/last |
| Activity | UZH 1000x sparse/dense/burst vectors under `data/generated` |
| Comparisons | pinned Fair RAW, pinned Team second, Current |
| Functional evidence | 5/5 regression, 9/9 dataset XSim/round-trip, unintended loss 0 |
| RTL candidate basis | `41292b5ca307f18b8d6e5730f1cd0b3335757629` |

PPA 결과에서는 SPARSE cost-analysis logic의 area/timing/power overhead를 Fair RAW와
pinned Team reference에 대해 비교한다. 또한 1000x 이상에서 Current가 더 많은
event를 수용하지만 P99가 RAW보다 높은 throughput-latency trade-off를 숨기지
않는다. UZH 외 dataset generality와 timestamp wrap-around/formal 검증은 별도
후속 항목이다. 이 문서는 실행 조건만 정리하며 Cadence command를 실행하지 않는다.
