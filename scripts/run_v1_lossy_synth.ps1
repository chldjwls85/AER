param(
    [string]$OutputRoot = 'build\synth_v1_lossy',
    [string]$Part = 'xc7z020clg484-1'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([IO.Path]::IsPathRooted($OutputRoot)) {
    throw 'OutputRoot must be relative to the repository for the Vivado path-safe mapping.'
}
$resolvedOutputRoot = Join-Path $projectRoot $OutputRoot

$vivadoCommand = Get-Command vivado -ErrorAction SilentlyContinue
$vivadoBin = if ($vivadoCommand) {
    Split-Path -Parent $vivadoCommand.Source
} else {
    $vivadoCandidate = Get-ChildItem 'C:\Xilinx\Vivado\*\bin\vivado.bat' `
        -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $vivadoCandidate) { throw 'Vivado was not found.' }
    Split-Path -Parent $vivadoCandidate.FullName
}
$vivado = Join-Path $vivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado executable was not found: $vivado"
}

New-Item -ItemType Directory -Force -Path $resolvedOutputRoot | Out-Null

$mappingName = @('Z', 'Y', 'X', 'W', 'V', 'U', 'T') |
    Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) } |
    Select-Object -First 1
if (-not $mappingName) { throw 'A free drive letter was not found for Vivado.' }
$mappingDrive = "${mappingName}:"
& subst.exe $mappingDrive $projectRoot
if ($LASTEXITCODE -ne 0) { throw 'Failed to create the Vivado path-safe drive mapping.' }
$mappedRoot = "${mappingDrive}\"
$mappedTclScript = Join-Path $mappedRoot 'scripts\synth_aer_v1_bank.tcl'

Push-Location $mappedRoot
try {
    foreach ($mode in @('raw', 'lossy')) {
        $modeRoot = Join-Path $resolvedOutputRoot $mode
        $modeArgument = Join-Path $OutputRoot $mode
        New-Item -ItemType Directory -Force -Path $modeRoot | Out-Null
        & $vivado -mode batch -nolog -nojournal -notrace `
            -source $mappedTclScript -tclargs $mode $modeArgument $Part
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado synthesis failed for mode=$mode"
        }
    }
} finally {
    Pop-Location
    & subst.exe $mappingDrive /d
}

Write-Host "AER_V1_LOSSY_SYNTH_DONE root=$resolvedOutputRoot"
Get-Content (Join-Path $resolvedOutputRoot 'raw\summary.txt')
Get-Content (Join-Path $resolvedOutputRoot 'lossy\summary.txt')
