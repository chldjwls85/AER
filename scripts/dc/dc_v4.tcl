set script_dir [file dirname [file normalize [info script]]]
set flow_name "v4"
set top_name "aer_top_v4_128"
set rtl_filelist [file normalize [file join $script_dir .. .. rtl filelist_v4.f]]
source [file join $script_dir dc_common.tcl]
