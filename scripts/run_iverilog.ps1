$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build\sim'
$topSimulationImage = Join-Path $outputDirectory 'tb_aer_top.vvp'
$arbiterSimulationImage = Join-Path $outputDirectory 'tb_aer_rr_arbiter.vvp'

if (-not (Get-Command iverilog -ErrorAction SilentlyContinue)) {
    throw 'iverilog was not found in PATH.'
}

if (-not (Get-Command vvp -ErrorAction SilentlyContinue)) {
    throw 'vvp was not found in PATH.'
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Push-Location $projectRoot
try {
    & iverilog -g2001 -Wall -I rtl -s tb_aer_rr_arbiter -o $arbiterSimulationImage rtl/common/aer_rr_arbiter.v tb/tb_aer_rr_arbiter.v
    if ($LASTEXITCODE -ne 0) {
        throw "iverilog failed with exit code $LASTEXITCODE."
    }

    & vvp $arbiterSimulationImage
    if ($LASTEXITCODE -ne 0) {
        throw "vvp failed with exit code $LASTEXITCODE."
    }

    & iverilog -g2001 -Wall -I rtl -s tb_aer_top -o $topSimulationImage -f rtl/filelist.f tb/tb_aer_top.v
    if ($LASTEXITCODE -ne 0) {
        throw "iverilog failed with exit code $LASTEXITCODE."
    }

    & vvp $topSimulationImage
    if ($LASTEXITCODE -ne 0) {
        throw "vvp failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
