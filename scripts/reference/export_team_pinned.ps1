param(
    [string]$Commit = "da686477ca054faada5f66d369f1fb253b2bf562"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$BuildRoot = Join-Path $RootDir "build\reference"
$Target = Join-Path $BuildRoot "team_pinned"
$Archive = Join-Path $BuildRoot "team_pinned.zip"
$env:GIT_CONFIG_GLOBAL = "NUL"

New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
if (Test-Path -LiteralPath $Target) {
    $resolvedBuild = (Resolve-Path $BuildRoot).Path
    $resolvedTarget = (Resolve-Path $Target).Path
    if (-not $resolvedTarget.StartsWith($resolvedBuild, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove reference path outside build root: $resolvedTarget"
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
}
if (Test-Path -LiteralPath $Archive) {
    Remove-Item -LiteralPath $Archive -Force
}

Push-Location $RootDir
try {
    & git -c "safe.directory=$($RootDir.Replace('\','/'))" cat-file -e "$Commit^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "Pinned commit is unavailable: $Commit" }
    & git -c "safe.directory=$($RootDir.Replace('\','/'))" archive --format=zip "--output=$Archive" $Commit rtl/frontend/aer_timebase.v rtl/v1
    if ($LASTEXITCODE -ne 0) { throw "git archive failed for $Commit" }
} finally {
    Pop-Location
}
Expand-Archive -LiteralPath $Archive -DestinationPath $Target
Write-Host "AER_REFERENCE_EXPORT_PASS commit=$Commit path=$Target"
Write-Output $Target
