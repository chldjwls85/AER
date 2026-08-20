param(
    [string]$VivadoPath = "",
    [string]$PythonPath = "C:\Users\AERO\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$BuildRoot = Join-Path $RootDir "build\dataset_xsim"
$StimulusRoot = Join-Path $RootDir "data\generated\uzh_1000x"
$RawRoot = Join-Path $RootDir "results\raw\dataset_xsim"
$MetricsRoot = Join-Path $RootDir "results\metrics"
$Summary = Join-Path $RootDir "results\logs\dataset_xsim_summary.txt"
$ReferenceExporter = Join-Path $RootDir "scripts\reference\export_team_pinned.ps1"
$Checker = Join-Path $RootDir "sw\decoder\check_xsim_roundtrip.py"
$Testbench = Join-Path $RootDir "tb\dataset\tb_aer_dataset.v"

if (-not $VivadoPath) {
    $VivadoPath = @(
        "C:\Xilinx\Vivado\2019.1\bin\vivado.bat",
        "C:\AMD\Vivado\2019.1\bin\vivado.bat"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $VivadoPath) {
    $command = Get-Command vivado -ErrorAction SilentlyContinue
    if ($command) { $VivadoPath = $command.Source }
}
if (-not $VivadoPath) { throw "Vivado 2019.1 not found" }
$VivadoExe = (Resolve-Path $VivadoPath).Path
$VivadoBin = Split-Path -Parent $VivadoExe
$version = (& $VivadoExe -version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $version -notmatch "2019\.1") {
    throw "Expected Vivado 2019.1, got:`n$version"
}
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"

foreach ($required in @($PythonPath,$StimulusRoot,$Checker,$Testbench,$xvlog,$xelab,$xsim)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required path missing: $required" }
}

$referenceOutput = & $ReferenceExporter
if ($LASTEXITCODE -ne 0) { throw "Pinned reference export failed" }
$ReferenceRoot = ($referenceOutput | Select-Object -Last 1).Trim()

$currentSources = Get-Content -LiteralPath (Join-Path $RootDir "rtl\filelist.f") |
    Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") } |
    ForEach-Object { Join-Path $RootDir $_ }
$referenceSources = @(
    "rtl\frontend\aer_timebase.v",
    "rtl\v1\aer_tile_bitmap_encoder.v",
    "rtl\v1\aer_locked_rr_arbiter.v",
    "rtl\v1\aer_stream_fifo2.v",
    "rtl\v1\aer_balanced_selector_tree.v",
    "rtl\v1\aer_bank_row_reader.v",
    "rtl\v1\aer_global_bank_selector.v",
    "rtl\v1\aer_v1_top_128.v",
    "rtl\v1\aer_v1_raw_top_128.v"
) | ForEach-Object { Join-Path $ReferenceRoot $_ }

$designs = @(
    @{ Name="raw_baseline"; Sources=$referenceSources; Defines=@() },
    @{ Name="team_second"; Sources=$referenceSources; Defines=@("TEAM_BINNING") },
    @{ Name="current_adaptive"; Sources=$currentSources; Defines=@("CURRENT_DESIGN") }
)
$windows = @("sparse","dense","burst")
$lines = @(
    "AER UZH representative-window XSim",
    "UTC=$([DateTime]::UtcNow.ToString('o'))",
    "VIVADO=$VivadoExe",
    "REFERENCE=da686477ca054faada5f66d369f1fb253b2bf562",
    "TOTAL=9"
)
$pass = 0
New-Item -ItemType Directory -Force -Path $BuildRoot,$RawRoot,$MetricsRoot,(Split-Path -Parent $Summary) | Out-Null

foreach ($design in $designs) {
    $testDir = Join-Path $BuildRoot $design.Name
    if (Test-Path -LiteralPath $testDir) {
        $resolvedBuild = (Resolve-Path $BuildRoot).Path
        $resolvedTest = (Resolve-Path $testDir).Path
        if (-not $resolvedTest.StartsWith($resolvedBuild, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove build path outside build root: $resolvedTest"
        }
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    Push-Location $testDir
    try {
        $compileArgs = @("--work","work")
        foreach ($define in $design.Defines) { $compileArgs += @("-d",$define) }
        $compileArgs += @($design.Sources) + @($Testbench)
        & $xvlog @compileArgs
        if ($LASTEXITCODE -ne 0) { throw "compile failed: $($design.Name)" }
        $snapshot = "dataset_$($design.Name)"
        & $xelab --debug typical --top tb_aer_dataset --snapshot $snapshot
        if ($LASTEXITCODE -ne 0) { throw "elaboration failed: $($design.Name)" }

        foreach ($window in $windows) {
            $windowRoot = Join-Path $StimulusRoot $window
            Copy-Item -LiteralPath (Join-Path $windowRoot "valid.hex") -Destination (Join-Path $testDir "valid.hex") -Force
            Copy-Item -LiteralPath (Join-Path $windowRoot "on.hex") -Destination (Join-Path $testDir "on.hex") -Force
            Copy-Item -LiteralPath (Join-Path $windowRoot "off.hex") -Destination (Join-Path $testDir "off.hex") -Force
            $simulationOutput = & $xsim $snapshot --runall 2>&1
            $simulationExit = $LASTEXITCODE
            $logPath = Join-Path $RawRoot "$($design.Name)_$window.log"
            Set-Content -LiteralPath $logPath -Value $simulationOutput -Encoding utf8
            $simulationOutput | ForEach-Object { Write-Host $_ }
            if ($simulationExit -ne 0 -or
                -not ($simulationOutput | Select-String -SimpleMatch "AER_DATASET_XSIM_PASS" -Quiet)) {
                throw "simulation failed: $($design.Name) $window; see $logPath"
            }
            $acceptedPath = Join-Path $RawRoot "$($design.Name)_${window}_accepted.log"
            $outputPath = Join-Path $RawRoot "$($design.Name)_${window}_output.log"
            Copy-Item -LiteralPath (Join-Path $testDir "accepted.log") -Destination $acceptedPath -Force
            Copy-Item -LiteralPath (Join-Path $testDir "output.log") -Destination $outputPath -Force
            $jsonPath = Join-Path $MetricsRoot "xsim_$($design.Name)_$window.json"
            & $PythonPath -u $Checker --design $design.Name --window $window --accepted $acceptedPath --output $outputPath --json $jsonPath
            if ($LASTEXITCODE -ne 0) { throw "round-trip failed: $($design.Name) $window" }
            $pass += 1
            $lines += "PASS $($design.Name) $window AER_DATASET_XSIM_PASS AER_DATASET_ROUNDTRIP_PASS"
        }
    } finally {
        Pop-Location
    }
}

$lines += "PASS_COUNT=$pass"
$lines += "FAIL_COUNT=$(9-$pass)"
$lines += "AER_DATASET_XSIM_ALL_PASS"
Set-Content -LiteralPath $Summary -Value $lines -Encoding utf8
$lines | ForEach-Object { Write-Host $_ }
