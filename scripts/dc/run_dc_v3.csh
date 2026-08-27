#!/bin/csh -f

set expected_root = "/home/KNUEEhdd1/kimdo904/02-dc/hyeonho"

if ( "$cwd" != "$expected_root" ) then
    echo "ERROR: V3 DC run is restricted to $expected_root (current: $cwd)"
    exit 2
endif

mkdir -p dc_results/v3/logs
dc_shell -f scripts/dc/dc_v3.tcl |& tee dc_results/v3/logs/dc_console.log
exit $status
