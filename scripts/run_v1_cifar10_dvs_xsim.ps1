param(
    [string]$Dataset = 'data\cifar10_dvs\sample\cifar10_airplane_0.aedat',
    [int]$MaxEvents = 20000,
    [double]$PlaybackSpeed = 5000,
    [int]$ClockHz = 100000000,
    [double]$DensestWindowMs = 40,
    [int]$StartEvent = -1,
    [double]$TrailMs = 40,
    [string]$VisualizationDirectory = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot 'build\xsim_v1_cifar10_dvs'
$selectionTag = if ($StartEvent -ge 0) { "s$StartEvent-" } else { '' }
$runTag = "airplane0-$selectionTag$($MaxEvents)e-$('{0:g}' -f $PlaybackSpeed)x"
$runRoot = Join-Path $buildRoot $runTag
$visualRoot = Join-Path $projectRoot "results\cifar10_dvs_xsim\$runTag"
New-Item -ItemType Directory -Force -Path $buildRoot, $runRoot, $visualRoot | Out-Null

$datasetPath = if ([IO.Path]::IsPathRooted($Dataset)) {
    $Dataset
} else {
    Join-Path $projectRoot $Dataset
}
if (-not (Test-Path -LiteralPath $datasetPath)) {
    throw "CIFAR10-DVS sample was not found: $datasetPath"
}

$pythonCandidates = @(
    $env:AER_PYTHON,
    $(if ($env:USERPROFILE) {
        Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    }),
    (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$python = $pythonCandidates | Select-Object -First 1
if (-not $python) { throw 'Python was not found.' }
& $python -c 'import PIL, numpy' 2>$null
if ($LASTEXITCODE -ne 0) { throw "Python lacks Pillow or NumPy: $python" }

$xvlogCommand = Get-Command xvlog -ErrorAction SilentlyContinue
if ($xvlogCommand) {
    $vivadoBin = Split-Path -Parent $xvlogCommand.Source
} else {
    $xvlogCandidate = Get-ChildItem 'C:\Xilinx\Vivado\*\bin\xvlog.bat' `
        -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $xvlogCandidate) { throw 'Vivado XSim tools were not found.' }
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

Push-Location $projectRoot
try {
    $selectionArguments = if ($StartEvent -ge 0) {
        @('--start-event', $StartEvent, '--densest-window-ms', 0)
    } else {
        @('--densest-window-ms', $DensestWindowMs)
    }
    & $python -m sw.export_v1_aedat2_vectors `
        $datasetPath $vectorsPath $manifestPath `
        --max-events $MaxEvents `
        --clock-hz $ClockHz `
        --playback-speed $PlaybackSpeed @selectionArguments
    if ($LASTEXITCODE -ne 0) { throw 'CIFAR10-DVS vector generation failed.' }

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
            '--snapshot' 'tb_aer_v1_cifar10_dvs_snapshot'
        if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
        Copy-Item -LiteralPath $vectorsPath -Destination $defaultVectorsPath -Force
        & $xsim 'tb_aer_v1_cifar10_dvs_snapshot' '--runall'
        if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
        Copy-Item -LiteralPath $defaultRtlLogPath -Destination $rtlLogPath -Force
    } finally {
        Pop-Location
    }

    $htmlArguments = @()
    if ($VisualizationDirectory) {
        New-Item -ItemType Directory -Force -Path $VisualizationDirectory | Out-Null
        $fragmentPath = Join-Path $VisualizationDirectory 'cifar10-dvs-source-vs-xsim.html'
        $htmlArguments = @('--html-fragment', $fragmentPath)
    }
    & $python -m sw.render_v1_uzh_reconstruction `
        $manifestPath $rtlLogPath $visualRoot `
        --frames 36 --trail-ms $TrailMs @htmlArguments
    if ($LASTEXITCODE -ne 0) { throw 'CIFAR10-DVS reconstruction rendering failed.' }

    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ffmpeg) {
        & $ffmpeg.Source -hide_banner -loglevel error -y -framerate 10 `
            -i (Join-Path $visualRoot 'frames\frame_%03d.png') `
            -c:v libx264 -pix_fmt yuv420p `
            (Join-Path $visualRoot 'source_vs_aer.mp4')
        if ($LASTEXITCODE -ne 0) { throw 'MP4 generation failed.' }
    }

    Write-Host "AER_V1_CIFAR10_DVS_XSIM_DONE run=$runTag"
    Write-Host "Summary: $(Join-Path $visualRoot 'summary.json')"
    Write-Host "Comparison: $(Join-Path $visualRoot 'source_vs_aer.webp')"
} finally {
    Pop-Location
}
