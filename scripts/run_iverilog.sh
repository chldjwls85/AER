#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
output_dir="$project_root/build/sim"

mkdir -p "$output_dir"
cd "$project_root"

iverilog -g2001 -Wall -I rtl -s tb_aer_rr_arbiter \
  -o "$output_dir/tb_aer_rr_arbiter.vvp" \
  rtl/common/aer_rr_arbiter.v tb/tb_aer_rr_arbiter.v
vvp "$output_dir/tb_aer_rr_arbiter.vvp"

iverilog -g2001 -Wall -I rtl -s tb_aer_top \
  -o "$output_dir/tb_aer_top.vvp" \
  -f rtl/filelist.f tb/tb_aer_top.v
vvp "$output_dir/tb_aer_top.vvp"
