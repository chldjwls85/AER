# V4 clock constraint shared with the documented V3 Genus condition.
create_clock -name clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks clk]

# Input/output delay, drive, and load constraints are server-flow specific.
# genus_v4_full.tcl requires AER_GENUS_V3_IO_CONSTRAINTS_TCL so the exact
# existing V3 constraints are reused instead of guessed here.
