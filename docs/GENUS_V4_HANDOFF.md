# V4 Genus Full-Synthesis Handoff

## Fixed comparison condition

- Top: `aer_top_v4_128`
- RTL filelist: `rtl/filelist_v4.f`
- Genus baseline: documented V3 `23.14-s090_1`
- Technology: GSCLIB 45nm
- Library/PVT: `slow_vdd1v0_basicCells.lib`, `slow_vdd1v0`, 0.9V/125C
- Clock: 10ns / 100MHz
- Clock uncertainty: 0.2ns

The repository does not contain the competition server's V3 library path,
I/O constraints, synthesis effort/options, or verified power methodology.
Do not guess them. Create source-safe server fragments from the existing V3
flow and pass their paths through:

- `AER_GENUS_SERVER_SETUP_TCL`: library/PVT/search path and exact effort/options
- `AER_GENUS_V3_IO_CONSTRAINTS_TCL`: exact V3 I/O delay/drive/load constraints
- `AER_GENUS_V3_POWER_TCL`: optional exact V3 power methodology

The example hook files intentionally stop with an error until verified server
commands replace the placeholders.

## Output

Each invocation writes a separate UTC-tagged directory:

```text
results/genus_v4/<run_tag>/
├── logs/genus_console.log
├── reports/check_design.rpt
├── reports/area.rpt
├── reports/timing.rpt
├── reports/qor.rpt
├── reports/power.rpt
├── netlist/aer_top_v4_128_mapped.v
├── netlist/aer_top_v4_128_mapped.sdc
└── genus_v4_summary.txt
```

Stage runtime markers are `AER_STAGE_START` and `AER_STAGE_DONE`, with UTC,
epoch, and elapsed seconds. If no verified power hook is supplied, the log and
summary record `POWER_METHOD_REQUIRES_EXISTING_SERVER_SETUP`.

## Server execution

```bash
cd <EXISTING_SERVER_AER_REPO>
git fetch origin
git switch AER_hyeonho
git pull --ff-only origin AER_hyeonho
```

```bash
export AER_GENUS_SERVER_SETUP_TCL=<VERIFIED_V3_SERVER_SETUP_TCL>
export AER_GENUS_V3_IO_CONSTRAINTS_TCL=<VERIFIED_V3_IO_CONSTRAINTS_TCL>
export AER_GENUS_V3_POWER_TCL=<VERIFIED_V3_POWER_TCL>  # omit only if unavailable
bash scripts/genus/run_genus_v4.sh
```

For a non-Git transfer, the paths in
`scripts/genus/v4_handoff_manifest.txt` are the complete minimal handoff set.
