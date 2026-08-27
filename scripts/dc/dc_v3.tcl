set script_dir [file dirname [file normalize [info script]]]
set flow_name "v3"
set top_name "aer_top_128"
set rtl_filelist [file normalize [file join $script_dir .. .. rtl filelist.f]]
source [file join $script_dir dc_common.tcl]
