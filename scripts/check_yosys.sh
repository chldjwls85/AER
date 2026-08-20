#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
output_dir="$project_root/build/yosys"
log_file="$output_dir/check.log"

mkdir -p "$output_dir"
cd "$project_root"

rtl_files=$(tr '\n' ' ' < rtl/filelist.f)
yosys -Q -l "$log_file" -p \
  "read_verilog -I rtl $rtl_files; hierarchy -check -top aer_top; proc; opt; check; stat"
