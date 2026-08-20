param(
    [string]$Url = "https://rpg.ifi.uzh.ch/datasets/davis/shapes_rotation.zip"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$DataDir = Join-Path $RootDir "data\uzh"
$Archive = Join-Path $DataDir "shapes_rotation.zip"
$Events = Join-Path $DataDir "events.txt"
$ExpectedSha256 = "56aade6bf53dcf73e8fe40905ccac8385cd7606bc9a85103bf2c9f9045117551"

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) {
    Invoke-WebRequest -Uri $Url -OutFile $Archive
}
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLowerInvariant()
if ($actualHash -ne $ExpectedSha256) {
    throw "UZH archive checksum mismatch: expected=$ExpectedSha256 actual=$actualHash"
}
if (-not (Test-Path -LiteralPath $Events -PathType Leaf)) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $entry = $zip.GetEntry("events.txt")
        if (-not $entry) { throw "events.txt not found in archive" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $Events, $false)
    } finally {
        $zip.Dispose()
    }
}
Write-Host "AER_UZH_DATASET_READY archive_sha256=$actualHash events=$Events"
