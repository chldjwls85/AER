# Full Genus synthesis driver for aer_top_v4_128.
# Server-specific library/PVT/effort and I/O constraints are sourced from
# existing V3 setup fragments supplied through environment variables.

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR [file normalize [file join $SCRIPT_DIR ".." ".."]]
set TOP aer_top_v4_128
set FILELIST [file join $ROOT_DIR "rtl" "filelist_v4.f"]
set CLOCK_SDC [file join $ROOT_DIR "constraints" "aer_v4_100mhz.sdc"]

proc require_env {name} {
    if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
        error "Required environment variable $name is not set"
    }
    return [file normalize $::env($name)]
}

proc utc_now {} {
    return [clock format [clock seconds] -gmt 1 -format "%Y-%m-%dT%H:%M:%SZ"]
}

array set STAGE_EPOCH {}
proc stage_start {name} {
    global STAGE_EPOCH
    set STAGE_EPOCH($name) [clock seconds]
    puts "AER_STAGE_START $name utc=[utc_now] epoch=$STAGE_EPOCH($name)"
    flush stdout
}

proc stage_done {name} {
    global STAGE_EPOCH
    set now [clock seconds]
    set elapsed [expr {$now - $STAGE_EPOCH($name)}]
    puts "AER_STAGE_DONE $name utc=[utc_now] epoch=$now elapsed_sec=$elapsed"
    flush stdout
}

if {
    [info exists ::env(AER_GENUS_RUN_TAG)] &&
    [string trim $::env(AER_GENUS_RUN_TAG)] ne ""
} {
    set RUN_TAG $::env(AER_GENUS_RUN_TAG)
} else {
    set RUN_TAG [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
}
set RUN_DIR [file join $ROOT_DIR "results" "genus_v4" $RUN_TAG]
set LOG_DIR [file join $RUN_DIR "logs"]
set REPORT_DIR [file join $RUN_DIR "reports"]
set NETLIST_DIR [file join $RUN_DIR "netlist"]
file mkdir $LOG_DIR $REPORT_DIR $NETLIST_DIR

set SERVER_SETUP_TCL [require_env AER_GENUS_SERVER_SETUP_TCL]
set V3_IO_TCL [require_env AER_GENUS_V3_IO_CONSTRAINTS_TCL]
if {![file isfile $SERVER_SETUP_TCL]} {
    error "Server setup Tcl not found: $SERVER_SETUP_TCL"
}
if {![file isfile $V3_IO_TCL]} {
    error "V3 I/O constraint Tcl not found: $V3_IO_TCL"
}

puts "AER_GENUS_V4_TOP $TOP"
puts "AER_GENUS_V4_RUN_DIR $RUN_DIR"
puts "AER_GENUS_SERVER_SETUP $SERVER_SETUP_TCL"
puts "AER_GENUS_V3_IO_CONSTRAINTS $V3_IO_TCL"

# Must contain exact V3 library path, slow_vdd1v0 PVT, effort, and options.
# It must not read, elaborate, synthesize, report, or exit.
source $SERVER_SETUP_TCL

set rtl_sources {}
set filelist_handle [open $FILELIST r]
while {[gets $filelist_handle line] >= 0} {
    set item [string trim $line]
    if {$item eq "" || [string match "#*" $item]} {
        continue
    }
    set source_file [file normalize [file join $ROOT_DIR $item]]
    if {![file isfile $source_file]} {
        close $filelist_handle
        error "RTL source from filelist not found: $source_file"
    }
    lappend rtl_sources $source_file
}
close $filelist_handle

stage_start read_hdl
read_hdl -sv $rtl_sources
stage_done read_hdl

stage_start elaborate
elaborate $TOP
stage_done elaborate

read_sdc $CLOCK_SDC
source $V3_IO_TCL

stage_start check_design
check_design -unresolved > [file join $REPORT_DIR "check_design.rpt"]
stage_done check_design

stage_start syn_generic
syn_generic
stage_done syn_generic

stage_start syn_map
syn_map
stage_done syn_map

stage_start syn_opt
syn_opt
stage_done syn_opt

set POWER_METHOD "POWER_METHOD_REQUIRES_EXISTING_SERVER_SETUP"
if {
    [info exists ::env(AER_GENUS_V3_POWER_TCL)] &&
    [string trim $::env(AER_GENUS_V3_POWER_TCL)] ne ""
} {
    set power_tcl [file normalize $::env(AER_GENUS_V3_POWER_TCL)]
    if {![file isfile $power_tcl]} {
        error "V3 power methodology Tcl not found: $power_tcl"
    }
    source $power_tcl
    set POWER_METHOD "EXISTING_V3_SERVER_SETUP:$power_tcl"
}
puts "AER_POWER_METHOD $POWER_METHOD"

stage_start report
report_area > [file join $REPORT_DIR "area.rpt"]
report_timing -max_paths 10 > [file join $REPORT_DIR "timing.rpt"]
report_qor > [file join $REPORT_DIR "qor.rpt"]
report_power > [file join $REPORT_DIR "power.rpt"]
write_hdl > [file join $NETLIST_DIR "aer_top_v4_128_mapped.v"]
write_sdc > [file join $NETLIST_DIR "aer_top_v4_128_mapped.sdc"]
stage_done report

set summary_path [file join $RUN_DIR "genus_v4_summary.txt"]
set summary [open $summary_path w]
puts $summary "AER V4 Genus full synthesis"
puts $summary "run_tag=$RUN_TAG"
puts $summary "top=$TOP"
puts $summary "technology=GSCLIB_45nm"
puts $summary "library=slow_vdd1v0_basicCells.lib / slow_vdd1v0"
puts $summary "pvt=0.9V_125C"
puts $summary "clock_period_ns=10.000"
puts $summary "clock_uncertainty_ns=0.200"
puts $summary "server_setup_tcl=$SERVER_SETUP_TCL"
puts $summary "v3_io_constraints_tcl=$V3_IO_TCL"
puts $summary "power_method=$POWER_METHOD"
puts $summary "area_report=[file join $REPORT_DIR area.rpt]"
puts $summary "timing_report=[file join $REPORT_DIR timing.rpt]"
puts $summary "qor_report=[file join $REPORT_DIR qor.rpt]"
puts $summary "power_report=[file join $REPORT_DIR power.rpt]"
puts $summary "netlist=[file join $NETLIST_DIR aer_top_v4_128_mapped.v]"
puts $summary "sdc=[file join $NETLIST_DIR aer_top_v4_128_mapped.sdc]"
puts $summary "AER_GENUS_V4_FULL_SYNTHESIS_DONE"
close $summary

puts "AER_GENUS_V4_FULL_SYNTHESIS_DONE summary=$summary_path"
flush stdout
