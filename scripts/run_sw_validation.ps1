param(
    [string]$OutputDirectory = "results"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    python -m unittest discover -s tests_sw -v
    if ($LASTEXITCODE -ne 0) {
        throw "Software unit tests failed with exit code $LASTEXITCODE"
    }

    $resultPath = Join-Path $OutputDirectory "synthetic.json"
    python -m sw.evaluate `
        --synthetic all `
        --cycles 2000 `
        --rate 0.5 `
        --window-cycles 8 `
        --fifo-words 8 `
        --json $resultPath
    if ($LASTEXITCODE -ne 0) {
        throw "Software evaluation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
