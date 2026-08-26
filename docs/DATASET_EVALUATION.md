# Dataset Evaluation

## Provenance

| Item | Recorded value |
|---|---|
| Dataset | UZH Event-Camera Dataset `shapes_rotation` |
| Official URL | `https://rpg.ifi.uzh.ch/datasets/davis/shapes_rotation.zip` |
| ZIP SHA-256 | `56aade6bf53dcf73e8fe40905ccac8385cd7606bc9a85103bf2c9f9045117551` |
| ZIP / `events.txt` size | 157,446,920 / 509,907,771 bytes |
| Source rows read | first 200,000 |
| Crop | `x=56, y=26, width=128, height=128` |
| Cropped events | 92,861 (pinned result reproduced exactly) |
| Clock | 100 MHz |
| Full evaluation date | 2026-08-26 KST |

CIFAR10-DVS, `cifar10dvs`, `CIFAR10`, `cifar`, and `.aedat` were searched in
all Git refs/history and under the local `C:\Project_V2\AI-semi` tree. No
script, result, dataset, or commit proved prior use, so **CIFAR10-DVS use is not
confirmed in the existing team GitHub/local material**. It is not labelled a
team reproduction dataset.

Raw data and generated wide RTL vectors are under ignored `data/`. Reproduce
the complete flow with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\dataset\run_all_dataset.ps1
```

## Canonical trace and loss accounting

The loader follows the pinned order: read 200,000 rows, quantize from the first
source timestamp, crop, then rebase coordinates. Each event becomes
`event_id,timestamp,cycle,x,y,polarity`. Events sharing a `{cycle, 2x2 tile}`
are OR-reduced into one transaction with `tile_id, ON[3:0], OFF[3:0]`.

The 1000x trace has 92,669 tile transactions and 92,861 canonical polarity
bits. There are no source-to-interface duplicate losses in this trace: its
92,861 cropped source events remain 92,861 canonical bits. A transaction not
accepted because `ready=0` is reported as input backpressure, not internal
loss. Every accepted RTL transaction is decoded and compared; unintended loss
is zero in all nine XSim runs.

## Software sweep

The software model uses one 16-bit word/cycle link, packet-locked bank round
robin, one pending slot/tile, exact packet costs and format-selection rules.
It is used for the long sweep; its latency is an architecture/link model, not
post-layout timing. Sparse/dense/burst windows are cross-checked in actual RTL
XSim to bound model risk.

| Speed | Design | Accepted events/transactions | Backpressured events/transactions | Output words | Words/input | Words/accepted | Bits/accepted | Mean | P99 | Throughput | Max pending | S/R/B packets | Loss |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1x | RAW / Team | 92,861 / 92,772 | 0 / 0 | 278,066 | 2.9944 | 2.9944 | 47.91 | 2.13 | 5 | 0.000495 | 4 | 0/92,647/0 | 0 |
| 1x | Current | 92,861 / 92,772 | 0 / 0 | 185,633 | 1.9990 | 1.9990 | 31.98 | 1.09 | 3 | 0.000495 | 4 | 92,683/89/0 | 0 |
| 10x | RAW / Team | 92,861 / 92,772 | 0 / 0 | 278,066 | 2.9944 | 2.9944 | 47.91 | 2.13 | 5 | 0.004950 | 4 | 0/92,647/0 | 0 |
| 10x | Current | 92,861 / 92,772 | 0 / 0 | 185,633 | 1.9990 | 1.9990 | 31.98 | 1.09 | 3 | 0.004950 | 4 | 92,683/89/0 | 0 |
| 100x | RAW / Team | 92,791 / 92,702 | 70 / 69 | 277,858 | 2.9922 | 2.9944 | 47.91 | 2.56 | 8 | 0.049460 | 15 | 0/92,578/0 | 0 |
| 100x | Current | 92,806 / 92,717 | 55 / 54 | 185,523 | 1.9979 | 1.9990 | 31.98 | 1.25 | 4 | 0.049468 | 13 | 92,628/89/0 | 0 |
| 500x | RAW / Team | 78,430 / 78,307 | 14,431 / 14,411 | 233,149 | 2.5107 | 2.9727 | 47.56 | 51.39 | 303 | 0.208966 | 71 | 0/77,421/0 | 0 |
| 500x | Current | 91,636 / 91,493 | 1,225 / 1,225 | 183,106 | 1.9718 | 1.9982 | 31.97 | 8.35 | 76 | 0.244211 | 49 | 91,272/145/17 | 0 |
| 1000x | RAW / Team | 46,610 / 46,510 | 46,251 / 46,159 | 136,626 | 1.4713 | 2.9313 | 46.90 | 145.14 | 502 | 0.248127 | 111 | 0/45,058/0 | 0 |
| 1000x | Current | 63,458 / 63,327 | 29,403 / 29,342 | 126,665 | 1.3640 | 1.9960 | 31.94 | 149.38 | 2,577 | 0.337756 | 194 | 62,825/198/39 | 0 |
| 2000x | RAW / Team | 26,629 / 26,563 | 66,232 / 66,006 | 76,837 | 0.8274 | 2.8855 | 46.17 | 208.42 | 644 | 0.282893 | 143 | 0/25,137/0 | 0 |
| 2000x | Current | 36,277 / 36,174 | 56,584 / 56,395 | 72,354 | 0.7792 | 1.9945 | 31.91 | 320.48 | 5,051 | 0.384596 | 338 | 35,801/182/5 | 0 |
| 5000x | RAW / Team | 12,572 / 12,503 | 80,289 / 79,678 | 35,015 | 0.3771 | 2.7852 | 44.56 | 288.29 | 832 | 0.331426 | 205 | 0/11,256/0 | 0 |
| 5000x | Current | 17,165 / 17,093 | 75,696 / 75,088 | 34,207 | 0.3684 | 1.9928 | 31.89 | 504.79 | 4,710 | 0.447938 | 529 | 16,888/110/2 | 0 |

The complete 21-row table is `results/summary.csv`. RAW and Team word counts
are identical for this trace. The long sweep selects one GROUP3 token at each
of 500x, 1000x, and 2000x, but this does not change total word cost; all other
accepted Team tokens are RAW8 and no BIN4/pair token is selected. The real data
is overwhelmingly one polarity bit per tile-cycle.

## Actual RTL XSim windows

At 1000x, deterministic windows are selected from all non-overlapping bins:
the 25th-percentile occupied bin (`sparse`), maximum 1024-cycle bin (`dense`),
and the maximum 128-cycle burst centered in 1024 cycles (`burst`). This avoids
manual cherry-picking.

| Window | Design | Accepted transactions | Output words | Words/accepted | Round-trip |
|---|---|---:|---:|---:|---|
| sparse | Fair RAW | 111 | 333 | 3.0000 | PASS |
| sparse | Team second | 111 | 333 | 3.0000 | PASS |
| sparse | Current | 111 | 222 | 2.0000 | PASS |
| dense | Fair RAW | 416 | 1,228 | 2.9519 | PASS |
| dense | Team second | 416 | 1,228 | 2.9519 | PASS |
| dense | Current | 649 | 1,298 | 2.0000 | PASS |
| burst | Fair RAW | 423 | 1,237 | 2.9243 | PASS |
| burst | Team second | 423 | 1,237 | 2.9243 | PASS |
| burst | Current | 641 | 1,280 | 1.9969 | PASS |

All three tops were separately compiled and elaborated in Vivado 2019.1 XSim.
Current의 sparse/dense/burst word-efficiency 개선은 각각 33.33%, 32.25%,
31.71%이며 dense/burst accepted transaction도 크게 증가했다. 모든 Current
decoder result는 missing/extra/payload/timestamp mismatch 0이다.

## Evidence-driven iteration

Previous ROW/BANK에서 한 limited iteration으로 `ST_ANALYZE`를 지연했다. Full
regression은 PASS했지만 dense XSim은 1,516 words로 같았고 accepted transaction은
533에서 531로 감소했다. Burst도 한 word만 줄면서 accepted transaction이 하나
감소해 해당 변경을 revert했다. 이후 workload evidence에 따라 singleton용
SPARSE format을 한 번 추가했고, 이 SPARSE/ROW/BANK candidate는 추가 redesign
없이 full gate를 통과했다.

## Visual QA

- `results/figures/uzh_dense_event_comparison.png`: original and all decoded
  event maps; x grows right, y grows down, ON red and OFF blue.
- `results/figures/uzh_activity_mode_map.png`: bank activity and multi-row
  opportunity distribution.
- `results/figures/uzh_performance_comparison.png`: efficiency, latency,
  throughput, backpressure and mode fraction.
- `results/animations/uzh_shapes_rotation_compare.gif`: 24 nonempty frames,
  800x440, original versus current accepted/decoded events.

The PNGs and first/last animation frames were opened after generation. No
empty/corrupt image, coordinate inversion, or single-frame animation was found.

## SPARSE/ROW/BANK full-evaluation conclusion (2026-08-26)

기존 provenance, crop, canonicalization을 그대로 재사용해 7-speed sweep과 9개
RTL window를 모두 재실행했다. RAW 대비 words/accepted-event 개선은 모든 속도에서
28.45~33.24%이며 SPARSE fraction은 Current에서 99.34% 이상이다. 500x부터
accepted event가 뚜렷하게 증가하지만 1000x 이상 P99는 RAW보다 높다. 더 많은
traffic을 수용하면서 single global link queue가 길어지는 trade-off이며 unintended
loss는 0이다. 결과는 `results/summary.csv`와 `results/metrics/dataset_results.json`
에 기록했다.
