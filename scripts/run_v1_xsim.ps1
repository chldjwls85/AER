param(
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = if (-not $OutputRoot) {
    Join-Path $projectRoot 'build\xsim_v1'
} elseif ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot
} else {
    Join-Path $projectRoot $OutputRoot
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

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado simulation tool was not found: $tool"
    }
}

function Invoke-XsimTest {
    param(
        [Parameter(Mandatory = $true)][string]$Top,
        [Parameter(Mandatory = $true)][string[]]$Sources
    )

    $testDirectory = Join-Path $outputRoot $Top
    New-Item -ItemType Directory -Force -Path $testDirectory | Out-Null
    $absoluteSources = @(
        foreach ($source in $Sources) {
            Join-Path $projectRoot $source
        }
    )
    $snapshot = "${Top}_snapshot"

    Push-Location $testDirectory
    try {
        & $xvlog '--work' 'work' @absoluteSources
        if ($LASTEXITCODE -ne 0) {
            throw "xvlog failed for $Top with exit code $LASTEXITCODE."
        }

        & $xelab '--debug' 'typical' '--top' $Top '--snapshot' $snapshot
        if ($LASTEXITCODE -ne 0) {
            throw "xelab failed for $Top with exit code $LASTEXITCODE."
        }

        $simulationOutput = & $xsim $snapshot '--runall' 2>&1
        $simulationOutput | ForEach-Object { Write-Host $_ }
        if (($LASTEXITCODE -ne 0) -or
            ($simulationOutput -match '[A-Z0-9_]+_FAIL')) {
            throw "xsim failed for $Top with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

Invoke-XsimTest 'tb_aer_pixel_pending_array_depth2' @(
    'rtl\frontend\aer_pixel_pending_array.v',
    'tb\v1\tb_aer_pixel_pending_array_depth2.v'
)

Invoke-XsimTest 'tb_aer_tile_bitmap_encoder' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'tb\v1\tb_aer_tile_bitmap_encoder.v'
)

Invoke-XsimTest 'tb_aer_tile_bitmap_encoder_fair' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'tb\v1\tb_aer_tile_bitmap_encoder_fair.v'
)

Invoke-XsimTest 'tb_aer_global_bank_selector' @(
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_stream_fifo2.v',
    'rtl\v1\aer_balanced_selector_tree.v',
    'rtl\v1\aer_global_bank_selector.v',
    'tb\v1\tb_aer_global_bank_selector.v'
)

Invoke-XsimTest 'tb_aer_bank_row_reader' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'tb\v1\tb_aer_bank_row_reader.v'
)

Invoke-XsimTest 'tb_aer_bank_row_reader_extended' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'tb\v1\tb_aer_bank_row_reader_extended.v'
)

Invoke-XsimTest 'tb_aer_bank_fair_pair' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'tb\v1\tb_aer_bank_fair_pair.v'
)

Invoke-XsimTest 'tb_aer_bank_packing_compare' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'tb\v1\tb_aer_bank_packing_compare.v'
)

Invoke-XsimTest 'tb_aer_bank_row_fusion' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'tb\v1\tb_aer_bank_row_fusion.v'
)

Invoke-XsimTest 'tb_aer_bank_fusion' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'tb\v1\tb_aer_bank_fusion.v'
)

Invoke-XsimTest 'tb_aer_bank_lossy_mixed' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'tb\v1\tb_aer_bank_lossy_mixed.v'
)

Invoke-XsimTest 'tb_aer_v1_top_128' @(
    'rtl\frontend\aer_timebase.v',
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_stream_fifo2.v',
    'rtl\v1\aer_balanced_selector_tree.v',
    'rtl\v1\aer_bank_row_reader.v',
    'rtl\v1\aer_global_bank_selector.v',
    'rtl\v1\aer_v1_top_128.v',
    'tb\v1\tb_aer_v1_top_128.v'
)

Invoke-XsimTest 'tb_aer_v1_top_param' @(
    'rtl\frontend\aer_timebase.v',
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_stream_fifo2.v',
    'rtl\v1\aer_balanced_selector_tree.v',
    'rtl\v1\aer_bank_row_reader.v',
    'rtl\v1\aer_global_bank_selector.v',
    'rtl\v1\aer_v1_top_128.v',
    'tb\v1\tb_aer_v1_top_param.v'
)

Invoke-XsimTest 'tb_aer_v1_raw_top_128' @(
    'rtl\frontend\aer_timebase.v',
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_stream_fifo2.v',
    'rtl\v1\aer_balanced_selector_tree.v',
    'rtl\v1\aer_bank_row_reader.v',
    'rtl\v1\aer_global_bank_selector.v',
    'rtl\v1\aer_v1_top_128.v',
    'rtl\v1\aer_v1_raw_top_128.v',
    'tb\v1\tb_aer_v1_raw_top_128.v'
)
