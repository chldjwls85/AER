$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $projectRoot 'build\xsim_v1'

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

        & $xsim $snapshot '--runall'
        if ($LASTEXITCODE -ne 0) {
            throw "xsim failed for $Top with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

Invoke-XsimTest 'tb_aer_tile_bitmap_encoder' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'tb\v1\tb_aer_tile_bitmap_encoder.v'
)

Invoke-XsimTest 'tb_aer_global_bank_selector' @(
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_global_bank_selector.v',
    'tb\v1\tb_aer_global_bank_selector.v'
)

Invoke-XsimTest 'tb_aer_bank_row_reader' @(
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'tb\v1\tb_aer_bank_row_reader.v'
)

Invoke-XsimTest 'tb_aer_v1_top_128' @(
    'rtl\frontend\aer_timebase.v',
    'rtl\v1\aer_tile_bitmap_encoder.v',
    'rtl\v1\aer_locked_rr_arbiter.v',
    'rtl\v1\aer_bank_row_reader.v',
    'rtl\v1\aer_global_bank_selector.v',
    'rtl\v1\aer_v1_top_128.v',
    'tb\v1\tb_aer_v1_top_128.v'
)
