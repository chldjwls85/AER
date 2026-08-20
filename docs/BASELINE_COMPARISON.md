# Baseline Comparison

## Fixed designs

| Design | RTL definition | Intended difference |
|---|---|---|
| Fair RAW | pinned `aer_v1_raw_top_128`, `ENABLE_BINNING=0` | RAW8 only |
| Team second design | pinned `aer_v1_top_128`, `ENABLE_BINNING=1` | RAW8/GROUP3/BIN4 and BIN4 pair packing |
| Current design | `aer_top_128` | lossless ROW/BANK overhead sharing |

All use a 128×128 sensor view, 2×2 tile input, 4×4 tiles/bank, 16-bit
valid/ready/last output, one pending slot per tile, identical canonical trace,
clock assumption, ready policy and measurement interval. Any unavoidable
timestamp or hierarchy latency difference is reported with the metrics.

Measured tables are generated after dataset and representative RTL runs.
