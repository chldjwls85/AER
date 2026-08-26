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
| Evaluation date | 2026-08-21 KST |

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

| Speed | Design | Accepted events | Backpressured | Output words | Words/accepted | Mean latency | P99 latency | BANK fraction |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1x | RAW / Team | 92,861 | 0 | 278,066 | 2.9944 | 2.13 | 5 | 0% |
| 1x | Current | 92,861 | 0 | 277,872 | 2.9923 | 2.13 | 5 | 0.21% |
| 500x | RAW / Team | 78,430 | 14,431 | 233,149 | 2.9727 | 51.39 | 303 | 0% |
| 500x | Current | 79,890 | 12,971 | 233,481 | 2.9225 | 95.73 | 898 | 3.07% |
| 1000x | RAW / Team | 46,610 | 46,251 | 136,626 | 2.9313 | 145.14 | 502 | 0% |
| 1000x | Current | 47,340 | 45,521 | 137,018 | 2.8943 | 353.93 | 6,380 | 1.86% |
| 5000x | RAW / Team | 12,572 | 80,289 | 35,015 | 2.7852 | 288.29 | 832 | 0% |
| 5000x | Current | 12,626 | 80,235 | 36,190 | 2.8663 | 899.72 | 7,399 | 1.18% |

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
| sparse | Current | 111 | 333 | 3.0000 | PASS |
| dense | Fair RAW | 416 | 1,228 | 2.9519 | PASS |
| dense | Team second | 416 | 1,228 | 2.9519 | PASS |
| dense | Current | 533 | 1,516 | 2.8443 | PASS |
| burst | Fair RAW | 423 | 1,237 | 2.9243 | PASS |
| burst | Team second | 423 | 1,237 | 2.9243 | PASS |
| burst | Current | 528 | 1,507 | 2.8542 | PASS |

All three tops were separately compiled and elaborated in Vivado 2019.1 XSim.
The current dense efficiency improvement is 3.65%, while it accepts 28.1% more
transactions. The burst efficiency improvement is 2.40%. These improvements
are real but below the practical 10% Cadence gate.

## Evidence-driven iteration

One limited iteration delayed `ST_ANALYZE` while the bank accepted another
tile. Full regression stayed PASS, but dense XSim remained 1,516 words and
accepted transactions fell from 533 to 531. Burst improved by only one word
and also accepted one fewer transaction. The change was rejected and reverted;
the final packetizer is byte-identical to the first freeze. No second
architecture iteration was attempted because the observed multi-row
opportunity was too small to justify more control logic.

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

## SPARSE/ROW/BANK quick evaluation (2026-08-26)

기존 provenance, crop, canonicalization을 그대로 재사용하고 전체 sweep/figure는
재생성하지 않았다.

| Speed | Design | Accepted events | Output words | Words/accepted event | Mean latency | P99 | SPARSE / ROW / BANK packets |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1x | Fair RAW | 92,861 | 278,066 | 2.9944 | 2.13 | 5 | 0 / 92,647 / 0 |
| 1x | Team second | 92,861 | 278,066 | 2.9944 | 2.13 | 5 | 0 / 92,647 / 0 |
| 1x | SPARSE/ROW/BANK | 92,861 | 185,633 | 1.9990 | 1.09 | 3 | 92,683 / 89 / 0 |
| 1000x | Fair RAW | 46,610 | 136,626 | 2.9313 | 145.14 | 502 | 0 / 45,058 / 0 |
| 1000x | SPARSE/ROW/BANK | 63,458 | 126,665 | 1.9960 | 149.38 | 2,577 | 62,825 / 198 / 39 |

1000x P99는 이전 ROW/BANK의 6,380 cycles보다 낮아졌지만 RAW의 502 cycles보다
여전히 높다. Dense representative RTL은 649 transactions, 1,298 words,
2.0000 words/transaction이며 round-trip 649/649 PASS다. 기존 pinned RAW/Team
dense 값은 각각 416 transactions, 1,228 words, 2.9519 words/transaction이다.
