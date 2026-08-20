param(
    [string]$VivadoPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$Runner = Join-Path $RootDir "scripts\xsim\run_xsim.ps1"
$Summary = Join-Path $RootDir "results\logs\regression_summary.txt"

$tests = @(
    @{ Top = "tb_aer_bank_packetizer"; Token = "AER_BANK_PACKETIZER_TB_PASS" },
    @{ Top = "tb_aer_top"; Token = "AER_ADAPTIVE_PACKET_TB_PASS" },
    @{ Top = "tb_aer_top_128_smoke"; Token = "AER_128_SMOKE_PASS" }
)

$lines = @(
    "AER XSim regression",
    "UTC=$([DateTime]::UtcNow.ToString('o'))",
    "TOTAL=$($tests.Count)"
)
$pass = 0
foreach ($test in $tests) {
    $arguments = @{
        Top = $test.Top
        ExpectedToken = $test.Token
    }
    if ($VivadoPath) { $arguments.VivadoPath = $VivadoPath }
    Write-Host "`n[AER] Running $($test.Top)"
    & $Runner @arguments
    if ($LASTEXITCODE -ne 0) { throw "Regression failed: $($test.Top)" }
    $pass += 1
    $lines += "PASS $($test.Top) $($test.Token)"
}

$lines += "PASS_COUNT=$pass"
$lines += "FAIL_COUNT=$($tests.Count - $pass)"
$lines += "AER_ALL_TESTS_PASS"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Summary) | Out-Null
Set-Content -LiteralPath $Summary -Value $lines -Encoding utf8
$lines | ForEach-Object { Write-Host $_ }
