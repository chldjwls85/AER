$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$testDirectory = Join-Path $projectRoot 'build\xsim_v1\tb_aer_v1_top_128'
$snapshot = 'tb_aer_v1_top_128_snapshot'
$snapshotDirectory = Join-Path $testDirectory "xsim.dir\$snapshot"
$waveScript = Join-Path $PSScriptRoot 'xsim_v1_wave.tcl'
$localWaveScript = Join-Path $testDirectory 'xsim_v1_wave.tcl'

$xsimCommand = Get-Command xsim -ErrorAction SilentlyContinue
if ($xsimCommand) {
    $xsim = $xsimCommand.Source
} else {
    $xsimCandidate = Get-ChildItem 'C:\Xilinx\Vivado\*\bin\xsim.bat' `
        -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $xsimCandidate) {
        throw 'Vivado xsim was not found in PATH or C:\Xilinx\Vivado.'
    }
    $xsim = $xsimCandidate.FullName
}

if (-not (Test-Path -LiteralPath $snapshotDirectory)) {
    & (Join-Path $PSScriptRoot 'run_v1_xsim.ps1')
}

if (-not (Test-Path -LiteralPath $snapshotDirectory)) {
    throw "XSim snapshot was not created: $snapshotDirectory"
}

# XSim's Windows launcher does not preserve quoted Korean paths reliably.
# Copy the Tcl file beside the snapshot and pass an ASCII relative path.
Copy-Item -LiteralPath $waveScript -Destination $localWaveScript -Force

$process = Start-Process -FilePath $xsim `
    -ArgumentList @(
        $snapshot,
        '--gui',
        '--onfinish', 'stop',
        '--tclbatch', 'xsim_v1_wave.tcl'
    ) `
    -WorkingDirectory $testDirectory `
    -PassThru

Write-Output "XSIM_GUI_PID=$($process.Id)"
Write-Output "XSIM_SNAPSHOT=$snapshot"
