if {$argc < 2} {
    puts "usage: vivado -mode batch -source synth_aer_v1_bank.tcl -tclargs <raw|lossy|combined|combined_opt> <output_dir> ?part?"
    exit 2
}

set mode [lindex $argv 0]
set output_dir [file normalize [lindex $argv 1]]
set part [expr {$argc >= 3 ? [lindex $argv 2] : "xc7z020clg484-1"}]
set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname $script_dir]

if {$mode eq "raw"} {
    set generic_list {
        ENABLE_BINNING=0
        ENABLE_ROW_FUSION=0
        ENABLE_BANK_FUSION=0
        ENABLE_LOSSY_BINNING=0
        ENABLE_SPARSE=0
        EXTERNAL_RX_TIMESTAMP=1
    }
} elseif {$mode eq "lossy"} {
    set generic_list {
        ENABLE_BINNING=1
        ENABLE_ROW_FUSION=0
        ENABLE_BANK_FUSION=1
        ENABLE_LOSSY_BINNING=1
        ENABLE_SPARSE=0
        EXTERNAL_RX_TIMESTAMP=1
    }
} elseif {$mode eq "combined"} {
    set generic_list {
        ENABLE_BINNING=1
        ENABLE_ROW_FUSION=0
        ENABLE_BANK_FUSION=1
        ENABLE_LOSSY_BINNING=1
        ENABLE_SPARSE=1
        EXTERNAL_RX_TIMESTAMP=1
    }
} elseif {$mode eq "combined_opt"} {
    set generic_list {}
} else {
    puts "unsupported synthesis mode: $mode"
    exit 2
}

file mkdir $output_dir
read_verilog [file join $project_root rtl v1 aer_tile_bitmap_encoder.v]
read_verilog [file join $project_root rtl v1 aer_tile_combined_classifier.v]
read_verilog [file join $project_root rtl v1 aer_locked_rr_arbiter.v]
read_verilog [file join $project_root rtl v1 aer_bank_row_reader.v]
read_verilog [file join $project_root rtl v1 aer_bank_row_reader_combined_opt.v]

if {$mode eq "combined_opt"} {
    synth_design \
        -top aer_bank_row_reader_combined_opt \
        -part $part \
        -mode out_of_context \
        -flatten_hierarchy rebuilt
} else {
    synth_design \
        -top aer_bank_row_reader \
        -part $part \
        -mode out_of_context \
        -flatten_hierarchy rebuilt \
        -generic $generic_list
}

create_clock -name clk -period 5.000 [get_ports clk]
set_false_path -from [get_ports rst_n]

report_utilization -file [file join $output_dir utilization.rpt]
report_timing_summary \
    -delay_type max \
    -max_paths 10 \
    -file [file join $output_dir timing_summary.rpt]
write_checkpoint -force [file join $output_dir aer_bank_row_reader_${mode}.dcp]

set primitive_cells [get_cells -hierarchical -filter {IS_PRIMITIVE}]
set lut_cells [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]
set ff_cells [get_cells -hierarchical -filter {REF_NAME =~ FD*}]
set mux_cells [get_cells -hierarchical -filter {REF_NAME =~ MUXF*}]
set timing_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
set worst_slack "NA"
set data_path_delay "NA"
if {[llength $timing_path] > 0} {
    set worst_slack [get_property SLACK $timing_path]
    set data_path_delay [get_property DATAPATH_DELAY $timing_path]
}

set summary_file [open [file join $output_dir summary.txt] w]
puts $summary_file "mode=$mode"
puts $summary_file "part=$part"
puts $summary_file "clock_period_ns=5.000"
puts $summary_file "primitive_cells=[llength $primitive_cells]"
puts $summary_file "luts=[llength $lut_cells]"
puts $summary_file "ffs=[llength $ff_cells]"
puts $summary_file "muxf=[llength $mux_cells]"
puts $summary_file "worst_slack_ns=$worst_slack"
puts $summary_file "data_path_delay_ns=$data_path_delay"
close $summary_file

puts "AER_V1_BANK_SYNTH_DONE mode=$mode output=$output_dir"
