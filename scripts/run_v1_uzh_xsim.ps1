param(
    [string]$Dataset = 'data\uzh\shapes_rotation\events.txt',
    [int]$MaxEvents = 5000,
    [double]$PlaybackSpeed = 5000,
    [int]$ClockHz = 100000000,
    [double]$DensestWindowMs = 0,
    [int]$ScanInputEvents = 200000,
    [double]$TrailMs = 2,
    [string]$VisualizationDirectory = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot 'build\xsim_v1_uzh'
$datasetTag = [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($Dataset))
if (-not $datasetTag) { $datasetTag = 'uzh' }
$datasetTag = $datasetTag -replace '[^A-Za-z0-9_-]', '_'
$speedTag = ('{0:g}x' -f $PlaybackSpeed).Replace('.', '_')
$clockTag = ('{0:g}mhz' -f ($ClockHz / 1000000.0)).Replace('.', '_')
$runTag = if ($DensestWindowMs -gt 0) {
    $windowTag = ('{0:g}ms' -f $DensestWindowMs).Replace('.', '_')
    "dense-$windowTag-$speedTag"
} else {
    $speedTag
}
$tag = "$datasetTag-$runTag-$clockTag"
$runRoot = Join-Path $buildRoot $tag
$visualRoot = Join-Path $runRoot 'visuals'
New-Item -ItemType Directory -Force -Path $buildRoot, $runRoot, $visualRoot | Out-Null

$datasetPath = if ([IO.Path]::IsPathRooted($Dataset)) {
    $Dataset
} else {
    Join-Path $projectRoot $Dataset
}
if (-not (Test-Path -LiteralPath $datasetPath)) {
    throw "Dataset was not found: $datasetPath"
}

$pythonCandidates = @(
    $env:AER_PYTHON,
    $(if ($env:USERPROFILE) {
        Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    }),
    (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$python = $pythonCandidates | Select-Object -First 1
if (-not $python) {
    throw 'Python was not found. Set AER_PYTHON to a Python executable with Pillow and NumPy.'
}
& $python -c 'import PIL, numpy' 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Python does not provide Pillow and NumPy: $python"
}

$xvlogCommand = Get-Command xvlog -ErrorAction SilentlyContinue
if ($xvlogCommand) {
    $vivadoBin = Split-Path -Parent $xvlogCommand.Source
} else {
    $xvlogCandidate = Get-ChildItem 'C:\Xilinx\Vivado\*\bin\xvlog.bat' `
        -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $xvlogCandidate) {
        throw 'Vivado xvlog was not found in PATH or C:\Xilinx\Vivado.'
    }
    $vivadoBin = Split-Path -Parent $xvlogCandidate.FullName
}
$xvlog = Join-Path $vivadoBin 'xvlog.bat'
$xelab = Join-Path $vivadoBin 'xelab.bat'
$xsim = Join-Path $vivadoBin 'xsim.bat'

$vectorsPath = Join-Path $runRoot 'vectors.txt'
$manifestPath = Join-Path $runRoot 'manifest.json'
$rtlLogPath = Join-Path $runRoot 'rtl_events.log'
$defaultVectorsPath = Join-Path $buildRoot 'vectors.txt'
$defaultRtlLogPath = Join-Path $buildRoot 'rtl_events.log'
$clockHalfPeriodNs = [int][Math]::Round(500000000.0 / $ClockHz)
if ($clockHalfPeriodNs -le 0 -or
    [Math]::Abs(($clockHalfPeriodNs * 2.0 * $ClockHz) - 1000000000.0) -gt 0.5) {
    throw "ClockHz must have an integer half-period in nanoseconds: $ClockHz"
}
$clockGeneric = '"CLK_HALF_PERIOD_NS={0}"' -f $clockHalfPeriodNs

Push-Location $projectRoot
try {
    $exportArguments = @(
        $datasetPath, $vectorsPath, $manifestPath,
        '--max-events', $MaxEvents,
        '--clock-hz', $ClockHz,
        '--playback-speed', $PlaybackSpeed,
        '--crop', 56, 26, 128, 128
    )
    if ($DensestWindowMs -gt 0) {
        $exportArguments += @(
            '--densest-window-ms', $DensestWindowMs,
            '--scan-input-events', $ScanInputEvents
        )
    }
    & $python -m sw.export_v1_uzh_vectors @exportArguments
    if ($LASTEXITCODE -ne 0) { throw 'UZH vector generation failed.' }

    $sources = @(
        'rtl\frontend\aer_timebase.v',
        'rtl\v1\aer_tile_bitmap_encoder.v',
        'rtl\v1\aer_locked_rr_arbiter.v',
        'rtl\v1\aer_bank_row_reader.v',
        'rtl\v1\aer_global_bank_selector.v',
        'rtl\v1\aer_v1_top_128.v',
        'tb\v1\tb_aer_v1_uzh.v'
    ) | ForEach-Object { Join-Path $projectRoot $_ }

    Push-Location $buildRoot
    try {
        & $xvlog '--work' 'work' @sources
        if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
        & $xelab '--debug' 'typical' '--top' 'tb_aer_v1_uzh' `
            '--generic_top' $clockGeneric `
            '--snapshot' 'tb_aer_v1_uzh_snapshot'
        if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
        Copy-Item -LiteralPath $vectorsPath -Destination $defaultVectorsPath -Force
        & $xsim 'tb_aer_v1_uzh_snapshot' '--runall'
        if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
        Copy-Item -LiteralPath $defaultRtlLogPath -Destination $rtlLogPath -Force
    } finally {
        Pop-Location
    }

    $htmlArguments = @()
    if ($VisualizationDirectory) {
        $fragmentPath = Join-Path $VisualizationDirectory "aer-real-trace-$tag.html"
        $htmlArguments = @('--html-fragment', $fragmentPath)
    }
    & $python -m sw.render_v1_uzh_reconstruction `
        $manifestPath $rtlLogPath $visualRoot `
        --frames 36 --trail-ms $TrailMs @htmlArguments
    if ($LASTEXITCODE -ne 0) { throw 'RTL reconstruction rendering failed.' }

    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ffmpeg) {
        & $ffmpeg.Source -hide_banner -loglevel error -y -framerate 10 `
            -i (Join-Path $visualRoot 'frames\frame_%03d.png') `
            -c:v libx264 -pix_fmt yuv420p `
            (Join-Path $visualRoot 'source_vs_aer.mp4')
        if ($LASTEXITCODE -ne 0) { throw 'MP4 generation failed.' }
    }

    Write-Host "AER_V1_UZH_XSIM_DONE tag=$tag"
    Write-Host "Summary: $(Join-Path $visualRoot 'summary.json')"
    Write-Host "Animation: $(Join-Path $visualRoot 'source_vs_aer.webp')"
} finally {
    Pop-Location
}
