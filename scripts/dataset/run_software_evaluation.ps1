param(
    [string]$PythonPath = "C:\Users\AERO\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$Events = Join-Path $RootDir "data\uzh\events.txt"
$Archive = Join-Path $RootDir "data\uzh\shapes_rotation.zip"

foreach ($path in @($PythonPath, $Events, $Archive)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}

Push-Location $RootDir
try {
    & $PythonPath -u -m sw.dataset.run_evaluation --events $Events --archive $Archive
    if ($LASTEXITCODE -ne 0) {
        throw "Dataset software evaluation failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
