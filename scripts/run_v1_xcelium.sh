#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
output_root="$project_root/build/xcelium_v1"

if ! command -v xrun >/dev/null 2>&1; then
    echo "xrun was not found in PATH." >&2
    exit 1
fi

run_test() {
    test_top=$1
    testbench=$2
    test_directory="$output_root/$test_top"
    mkdir -p "$test_directory"

    (
        cd "$project_root"
        run_status=0
        xrun -64bit -sv \
            -top "$test_top" \
            -xmlibdirname "$test_directory/xcelium.d" \
            -l "$test_directory/xrun.log" \
            -f rtl/filelist_v1.f \
            "$testbench" || run_status=$?

        # Each test is independently compiled.  Keep the small text log, but
        # release the reproducible Xcelium work library before the next test.
        xrun -64bit -clean \
            -xmlibdirname "$test_directory/xcelium.d" \
            -nolog -nohistory >/dev/null 2>&1 || true

        return "$run_status"
    )
}

run_test tb_aer_tile_bitmap_encoder tb/v1/tb_aer_tile_bitmap_encoder.v
run_test tb_aer_tile_bitmap_encoder_fair tb/v1/tb_aer_tile_bitmap_encoder_fair.v
run_test tb_aer_bank_row_reader tb/v1/tb_aer_bank_row_reader.v
run_test tb_aer_bank_row_reader_extended tb/v1/tb_aer_bank_row_reader_extended.v
run_test tb_aer_bank_fair_pair tb/v1/tb_aer_bank_fair_pair.v
run_test tb_aer_bank_packing_compare tb/v1/tb_aer_bank_packing_compare.v
run_test tb_aer_global_bank_selector tb/v1/tb_aer_global_bank_selector.v
run_test tb_aer_v1_top_param tb/v1/tb_aer_v1_top_param.v
run_test tb_aer_v1_top_128 tb/v1/tb_aer_v1_top_128.v
run_test tb_aer_v1_raw_top_128 tb/v1/tb_aer_v1_raw_top_128.v
