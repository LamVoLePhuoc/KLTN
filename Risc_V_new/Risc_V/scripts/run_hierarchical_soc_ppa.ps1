param(
    [ValidateSet(0, 1)]
    [int]$MesiEnable = 1,
    [double]$PeriodNs = 4.000,
    [string]$Vivado = "D:\Xillinx\Vivado\2022.2\bin\vivado.bat"
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$PartitionDir = Join-Path $ProjectDir "build/hier-ppa-mesi$MesiEnable-$Stamp"
New-Item -ItemType Directory -Force -Path $PartitionDir | Out-Null

for ($Hart = 0; $Hart -lt 4; $Hart++) {
    & $Vivado -mode batch -nojournal -nolog `
        -source (Join-Path $PSScriptRoot "synth_hier_core_l1.tcl") `
        -tclargs $PartitionDir $Hart $MesiEnable $PeriodNs
    if ($LASTEXITCODE -ne 0) {
        throw "Hierarchical core/L1 synthesis failed for hart $Hart"
    }
}

& $Vivado -mode batch -nojournal -nolog `
    -source (Join-Path $PSScriptRoot "run_hierarchical_soc_ppa.tcl") `
    -tclargs $PartitionDir $PeriodNs $MesiEnable
if ($LASTEXITCODE -ne 0) {
    throw "Hierarchical full-SoC implementation failed"
}

Write-Output "HIER_PARTITION_DIR=$PartitionDir"
