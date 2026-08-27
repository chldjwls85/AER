param(
    [string]$VivadoPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$Runner = Join-Path $RootDir "scripts\xsim\run_xsim.ps1"
$Summary = Join-Path $RootDir "results\logs\regression_v4_summary.txt"

$tests = @(
    @{ Top = "tb_aer_bank_packetizer_v4"; Token = "AER_BANK_PACKETIZER_V4_TB_PASS" },
    @{ Top = "tb_aer_top_128_smoke"; Token = "AER_128_SMOKE_PASS" },
    @{ Top = "tb_aer_protocol_stress"; Token = "AER_PROTOCOL_STRESS_PASS" },
    @{ Top = "tb_aer_roundtrip_random"; Token = "AER_ROUNDTRIP_RANDOM_PASS" }
)

$lines = @(
    "AER V4 XSim regression",
    "UTC=$([DateTime]::UtcNow.ToString('o'))",
    "TOTAL=$($tests.Count)"
)
$pass = 0
foreach ($test in $tests) {
    $arguments = @{
        Top = $test.Top
        ExpectedToken = $test.Token
        Design = "v4"
        Quiet = $true
    }
    if ($VivadoPath) { $arguments.VivadoPath = $VivadoPath }
    Write-Host "[AER V4] Running $($test.Top)"
    & $Runner @arguments
    if ($LASTEXITCODE -ne 0) { throw "V4 regression failed: $($test.Top)" }
    $pass += 1
    $lines += "PASS $($test.Top) $($test.Token)"
}

$lines += "PASS_COUNT=$pass"
$lines += "FAIL_COUNT=$($tests.Count - $pass)"
$lines += "AER_V4_ALL_TESTS_PASS"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Summary) | Out-Null
Set-Content -LiteralPath $Summary -Value $lines -Encoding utf8
$lines | ForEach-Object { Write-Host $_ }
