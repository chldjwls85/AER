# Synopsys DC SAED32 V3/V4 comparison

This handoff is a supplemental relative comparison of V3 and V4 under the same
laboratory Synopsys Design Compiler and SAED32 conditions. It is not the
official competition Genus/PPA flow, and its absolute PPA must not be presented
as official competition results.

## Fixed comparison conditions

- Tool: Synopsys Design Compiler V-2023.12-SP4
- Library: `/home/KNUEEhdd1/idec/techfiles/saed28edk/saed32hvt_ff0p95v125c.db`
- Corner: SAED32 HVT FF, 0.95 V, 125 C
- Clock: 10.0 ns (100 MHz)
- Clock uncertainty: 0.2 ns
- Reset constraint: `set_false_path -from [get_ports rst_n]`
- HDL parser: `analyze -format sverilog`, followed by `elaborate` and `link`
- Optimization: basic `compile` for both versions
- V3 top/filelist: `aer_top_128`, `rtl/filelist.f`
- V4 top/filelist: `aer_top_v4_128`, `rtl/filelist_v4.f`

The shared `scripts/dc/dc_common.tcl` applies every library, constraint,
optimization, and reporting command identically. Only the top and RTL filelist
differ between the two wrappers.

## Server boundary and outputs

The repository root must be exactly:

`/home/KNUEEhdd1/kimdo904/02-dc/hyeonho`

Both Tcl and launcher scripts reject any other location. Do not modify or use
`/01-aes`, `/04-aer`, `/05-aer_ej`, or any other existing server workspace.

Generated files are separated under `dc_results/v3/` and `dc_results/v4/`.
Each run records the console log, start/end/elapsed time, pre/post-compile
`check_design`, QoR, hierarchical area, timing, mapped Verilog, and generated
SDC. `dc_results/` is intentionally ignored by Git.

## Run

From the repository root on the laboratory server:

```csh
chmod +x scripts/dc/run_dc_v3.csh scripts/dc/run_dc_v4.csh
./scripts/dc/run_dc_v3.csh
./scripts/dc/run_dc_v4.csh
```
