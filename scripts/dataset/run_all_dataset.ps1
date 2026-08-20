param(
    [string]$VivadoPath = "",
    [string]$PythonPath = "C:\Users\AERO\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $ScriptDir "download_uzh.ps1")
& (Join-Path $ScriptDir "run_software_evaluation.ps1") -PythonPath $PythonPath
$xsimArguments = @{ PythonPath = $PythonPath }
if ($VivadoPath) { $xsimArguments.VivadoPath = $VivadoPath }
& (Join-Path $ScriptDir "run_dataset_xsim.ps1") @xsimArguments
Write-Host "AER_DATASET_ALL_PASS"
