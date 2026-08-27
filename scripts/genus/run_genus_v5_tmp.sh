#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

: "${AER_GENUS_SERVER_SETUP_TCL:?Set to the exact verified V4/V3 server setup fragment}"
: "${AER_GENUS_V3_IO_CONSTRAINTS_TCL:?Set to the exact verified V4/V3 I/O constraint fragment}"

genus_bin="${AER_GENUS_BIN:-genus}"
if ! command -v "${genus_bin}" >/dev/null 2>&1; then
    echo "Genus executable not found: ${genus_bin}" >&2
    exit 2
fi

run_user="${USER:-$(id -un)}"
if [[ ! "${run_user}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Unsafe user name for /tmp run directory: ${run_user}" >&2
    exit 2
fi

run_tag="${AER_GENUS_RUN_TAG:-$(date -u +%Y%m%d_%H%M%S)}"
default_run_dir="/tmp/${run_user}_aer_genus_v5_${run_tag}_$$"
run_dir="${AER_GENUS_RUN_DIR:-${default_run_dir}}"

case "${run_dir}" in
    "/tmp/${run_user}_aer_genus_v5_"*) ;;
    *)
        echo "Refusing run directory outside the user-specific V5 /tmp prefix: ${run_dir}" >&2
        exit 2
        ;;
esac

if [[ -e "${run_dir}" ]]; then
    echo "Refusing to reuse existing run directory: ${run_dir}" >&2
    exit 2
fi

umask 077
mkdir -m 700 "${run_dir}"
mkdir -p \
    "${run_dir}/scripts" \
    "${run_dir}/reports" \
    "${run_dir}/logs" \
    "${run_dir}/out" \
    "${run_dir}/work/tmp" \
    "${run_dir}/home"

cp "${repo_root}/scripts/genus/genus_v5_full.tcl" "${run_dir}/scripts/"

export AER_GENUS_RUN_TAG="${run_tag}"
export AER_GENUS_RUN_DIR="${run_dir}"
export HOME="${run_dir}/home"
export TMPDIR="${run_dir}/work/tmp"
export TMP="${TMPDIR}"
export TEMP="${TMPDIR}"

echo "AER_GENUS_V5_RUN_TAG ${run_tag}"
echo "AER_GENUS_V5_RUN_DIR ${run_dir}"
echo "AER_GENUS_V5_HOME ${HOME}"
echo "AER_GENUS_V5_TMPDIR ${TMPDIR}"

cd "${run_dir}/work"
"${genus_bin}" -f "${repo_root}/scripts/genus/genus_v5_full.tcl" 2>&1 |
    tee "${run_dir}/logs/genus_console.log"
exit "${PIPESTATUS[0]}"
