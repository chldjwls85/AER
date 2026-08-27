# Shared Synopsys Design Compiler flow for the V3/V4 SAED32 comparison.
# The wrapper must define flow_name, top_name, and rtl_filelist before sourcing.

foreach required_var {flow_name top_name rtl_filelist} {
    if {![info exists $required_var]} {
        error "Required variable '$required_var' is not defined"
    }
}

set allowed_repo_root "/home/KNUEEhdd1/kimdo904/02-dc/hyeonho"
set repo_root [file normalize [file join $script_dir .. ..]]
if {$repo_root ne $allowed_repo_root} {
    error "Run only from repository root $allowed_repo_root (resolved: $repo_root)"
}

set library_db "/home/KNUEEhdd1/idec/techfiles/saed28edk/saed32hvt_ff0p95v125c.db"
if {![file exists $library_db]} {
    error "SAED32 library not found: $library_db"
}
if {![file exists $rtl_filelist]} {
    error "RTL filelist not found: $rtl_filelist"
}

set run_dir [file join $repo_root dc_results $flow_name]
set work_dir [file join $run_dir work]
set report_dir [file join $run_dir reports]
set netlist_dir [file join $run_dir netlist]
set constraint_dir [file join $run_dir constraints]
set log_dir [file join $run_dir logs]
foreach dir [list $run_dir $work_dir $report_dir $netlist_dir $constraint_dir $log_dir] {
    file mkdir $dir
}

set start_epoch [clock seconds]
set start_text [clock format $start_epoch -format "%Y-%m-%d %H:%M:%S %Z"]
puts "AER_DC_RUN_START flow=$flow_name top=$top_name timestamp={$start_text} epoch=$start_epoch"

set_app_var search_path [concat [list . [file dirname $library_db]] $search_path]
set_app_var target_library [list $library_db]
set_app_var link_library [concat "*" $target_library]

define_design_lib WORK -path $work_dir

set rtl_sources {}
set filelist_handle [open $rtl_filelist r]
while {[gets $filelist_handle line] >= 0} {
    set entry [string trim $line]
    if {$entry eq "" || [string match "#*" $entry]} {
        continue
    }
    set source_path [file normalize [file join $repo_root $entry]]
    if {![file exists $source_path]} {
        close $filelist_handle
        error "RTL source not found: $source_path"
    }
    lappend rtl_sources $source_path
}
close $filelist_handle

puts "AER_DC_STAGE_START analyze epoch=[clock seconds]"
analyze -format sverilog -library WORK $rtl_sources
puts "AER_DC_STAGE_END analyze epoch=[clock seconds]"

puts "AER_DC_STAGE_START elaborate epoch=[clock seconds]"
elaborate $top_name -library WORK
current_design $top_name
link
puts "AER_DC_STAGE_END elaborate epoch=[clock seconds]"

create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]
set_false_path -from [get_ports rst_n]

redirect -file [file join $report_dir check_design.rpt] {check_design}

puts "AER_DC_STAGE_START compile epoch=[clock seconds]"
compile
puts "AER_DC_STAGE_END compile epoch=[clock seconds]"

redirect -file [file join $report_dir qor.rpt] {report_qor}
redirect -file [file join $report_dir area.rpt] {report_area -hierarchy}
redirect -file [file join $report_dir timing.rpt] {
    report_timing -delay_type max -max_paths 10 -nworst 1
}
redirect -file [file join $report_dir check_design_post_compile.rpt] {check_design}

write -format verilog -hierarchy -output [file join $netlist_dir ${top_name}_mapped.v]
write_sdc [file join $constraint_dir ${top_name}_mapped.sdc]

set end_epoch [clock seconds]
set end_text [clock format $end_epoch -format "%Y-%m-%d %H:%M:%S %Z"]
set elapsed_seconds [expr {$end_epoch - $start_epoch}]
set summary_path [file join $report_dir run_summary.txt]
set summary_handle [open $summary_path w]
puts $summary_handle "flow=$flow_name"
puts $summary_handle "top=$top_name"
puts $summary_handle "tool=Synopsys Design Compiler V-2023.12-SP4"
puts $summary_handle "library=$library_db"
puts $summary_handle "corner=SAED32 HVT FF 0.95V 125C"
puts $summary_handle "clock_period_ns=10.0"
puts $summary_handle "clock_uncertainty_ns=0.2"
puts $summary_handle "compile_command=compile"
puts $summary_handle "start_timestamp=$start_text"
puts $summary_handle "end_timestamp=$end_text"
puts $summary_handle "elapsed_seconds=$elapsed_seconds"
close $summary_handle

puts "AER_DC_RUN_END flow=$flow_name top=$top_name timestamp={$end_text} epoch=$end_epoch elapsed_seconds=$elapsed_seconds"
exit
