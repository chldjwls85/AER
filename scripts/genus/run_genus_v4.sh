#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

: "${AER_GENUS_SERVER_SETUP_TCL:?Set to a source-safe fragment from the existing V3 Genus setup}"
: "${AER_GENUS_V3_IO_CONSTRAINTS_TCL:?Set to the exact existing V3 I/O constraint fragment}"

genus_bin="${AER_GENUS_BIN:-genus}"
if ! command -v "${genus_bin}" >/dev/null 2>&1; then
    echo "Genus executable not found: ${genus_bin}" >&2
    exit 2
fi

run_tag="${AER_GENUS_RUN_TAG:-$(date -u +%Y%m%d_%H%M%S)}"
run_dir="${repo_root}/results/genus_v4/${run_tag}"
mkdir -p "${run_dir}/logs" "${run_dir}/reports" "${run_dir}/netlist"
export AER_GENUS_RUN_TAG="${run_tag}"

cd "${repo_root}"
echo "AER_GENUS_V4_RUN_TAG ${run_tag}"
echo "AER_GENUS_V4_RUN_DIR ${run_dir}"
"${genus_bin}" -f scripts/genus/genus_v4_full.tcl 2>&1 |
    tee "${run_dir}/logs/genus_console.log"
exit "${PIPESTATUS[0]}"
