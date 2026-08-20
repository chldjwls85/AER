param(
    [Parameter(Mandatory = $true)][string]$Top,
    [Parameter(Mandatory = $true)][string]$ExpectedToken,
    [string]$VivadoPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$BuildRoot = Join-Path $RootDir "build\xsim"
$LogRoot = Join-Path $RootDir "results\logs\xsim"

if (-not $VivadoPath) {
    $preferred = @(
        "C:\Xilinx\Vivado\2019.1\bin\vivado.bat",
        "C:\AMD\Vivado\2019.1\bin\vivado.bat"
    )
    $VivadoPath = $preferred | Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}
if (-not $VivadoPath) {
    $command = Get-Command vivado -ErrorAction SilentlyContinue
    if ($command) { $VivadoPath = $command.Source }
}
if (-not $VivadoPath) {
    throw "Vivado 2019.1 was not found. Pass -VivadoPath explicitly."
}

if ((Get-Item -LiteralPath $VivadoPath).PSIsContainer) {
    $VivadoBin = (Resolve-Path $VivadoPath).Path
    $VivadoExe = Join-Path $VivadoBin "vivado.bat"
} else {
    $VivadoExe = (Resolve-Path $VivadoPath).Path
    $VivadoBin = Split-Path -Parent $VivadoExe
}

$version = (& $VivadoExe -version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $version -notmatch "2019\.1") {
    throw "Expected Vivado 2019.1 at '$VivadoExe', reported:`n$version"
}

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing XSim tool: $tool"
    }
}

$testbench = switch ($Top) {
    "tb_aer_bank_packetizer" { "tb\unit\tb_aer_bank_packetizer.v" }
    "tb_aer_top" { "tb\regression\tb_aer_top.v" }
    "tb_aer_top_128_smoke" { "tb\regression\tb_aer_top_128_smoke.v" }
    default { throw "No testbench path registered for top '$Top'." }
}

$rtlSources = Get-Content -LiteralPath (Join-Path $RootDir "rtl\filelist.f") |
    Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") } |
    ForEach-Object { Join-Path $RootDir $_ }
$sources = @($rtlSources) + @(Join-Path $RootDir $testbench)

$testDir = Join-Path $BuildRoot $Top
$log = Join-Path $LogRoot ("xsim_" + $Top + ".log")
New-Item -ItemType Directory -Force -Path $BuildRoot,$LogRoot | Out-Null
if (Test-Path -LiteralPath $testDir) {
    $resolvedBuild = (Resolve-Path $BuildRoot).Path
    $resolvedTest = (Resolve-Path $testDir).Path
    if (-not $resolvedTest.StartsWith($resolvedBuild, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove build directory outside build root: $resolvedTest"
    }
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
Set-Content -LiteralPath $log -Value "TOP=$Top`nVIVADO=$VivadoExe`n" -Encoding utf8

function Invoke-LoggedTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][object[]]$Arguments
    )
    $heading = "===== $Name ====="
    Write-Host $heading
    Add-Content -LiteralPath $log -Value $heading -Encoding utf8
    $output = & $Command @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    Add-Content -LiteralPath $log -Value $output -Encoding utf8
    if ($exitCode -ne 0) {
        throw "$Name failed for $Top with exit code $exitCode. See $log"
    }
    $marker = "${Name}_PASS"
    Write-Host $marker
    Add-Content -LiteralPath $log -Value $marker -Encoding utf8
}

Push-Location $testDir
try {
    Invoke-LoggedTool -Name "COMPILE" -Command $xvlog -Arguments (@("--work", "work") + $sources)
    $snapshot = "${Top}_snapshot"
    Invoke-LoggedTool -Name "ELABORATION" -Command $xelab -Arguments @("--debug", "typical", "--top", $Top, "--snapshot", $snapshot)
    Invoke-LoggedTool -Name "SIMULATION" -Command $xsim -Arguments @($snapshot, "--runall")
} finally {
    Pop-Location
}

if (-not (Select-String -LiteralPath $log -SimpleMatch $ExpectedToken -Quiet)) {
    throw "Required PASS token '$ExpectedToken' was not found in $log"
}

Write-Host "[PASS] $Top : $ExpectedToken"
Write-Host "[LOG ] $log"
