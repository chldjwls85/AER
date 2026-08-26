param(
    [string]$Dataset = 'data\cifar10_dvs\sample\cifar10_airplane_0.aedat',
    [double]$PlaybackSpeed = 1297.016861,
    [int]$MaxEvents = 178165,
    [int]$PixelFifoDepth = 2,
    [string]$Output = 'results\lossy_binning_sw\summary.json'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pythonCandidates = @(
    $env:AER_PYTHON,
    $(if ($env:USERPROFILE) {
        Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    }),
    (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$python = $pythonCandidates | Select-Object -First 1
if (-not $python) { throw 'Python was not found.' }

Push-Location $projectRoot
try {
    & $python -c 'import numpy'
    if ($LASTEXITCODE -ne 0) { throw "Python lacks NumPy: $python" }

    & $python -m unittest tests_sw.test_lossy_binning_model -v
    if ($LASTEXITCODE -ne 0) { throw 'Lossy-binning unit tests failed.' }

    & $python -m sw.lossy_binning_model `
        --dataset $Dataset `
        --clock-hz 100000000 200000000 `
        --playback-speed $PlaybackSpeed `
        --max-events $MaxEvents `
        --pixel-fifo-depth $PixelFifoDepth `
        --output $Output
    if ($LASTEXITCODE -ne 0) { throw 'Lossy-binning model failed.' }
} finally {
    Pop-Location
}

Write-Host "AER_LOSSY_BINNING_SW_DONE output=$Output"
