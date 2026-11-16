param(
    [string]$ToolchainBin = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ToolchainBin)) {
    $ToolchainBin = Join-Path $ProjectDir ".tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectDir "build/workloads/quad_cache"
}

$Gcc = Join-Path $ToolchainBin "riscv-none-elf-gcc.exe"
$Objcopy = Join-Path $ToolchainBin "riscv-none-elf-objcopy.exe"
$Objdump = Join-Path $ToolchainBin "riscv-none-elf-objdump.exe"
$Size = Join-Path $ToolchainBin "riscv-none-elf-size.exe"
foreach ($Tool in @($Gcc, $Objcopy, $Objdump, $Size)) {
    if (-not (Test-Path -LiteralPath $Tool)) {
        throw "Missing RISC-V tool: $Tool"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$SourceDir = Join-Path $ProjectDir "sw/workloads"
$Elf = Join-Path $OutputDir "quad_cache_workload.elf"
$Mem = Join-Path $OutputDir "quad_cache_workload.mem"
$Dump = Join-Path $OutputDir "quad_cache_workload.objdump"
$Map = Join-Path $OutputDir "quad_cache_workload.map"

$CommonFlags = @(
    "-march=rv32ima_zicsr", "-mabi=ilp32", "-mcmodel=medlow",
    "-mno-relax", "-msmall-data-limit=0", "-O2",
    "-ffreestanding", "-fno-builtin", "-fno-pic", "-fno-pie",
    "-nostdlib", "-nostartfiles"
)

& $Gcc @CommonFlags `
    (Join-Path $SourceDir "quad_cache_crt0.S") `
    (Join-Path $SourceDir "quad_cache_workload.c") `
    "-T" (Join-Path $SourceDir "quad_cache_workload.ld") `
    "-Wl,--build-id=none" "-Wl,-Map=$Map" "-o" $Elf
if ($LASTEXITCODE -ne 0) { throw "RISC-V workload link failed" }

& $Objcopy -O verilog --verilog-data-width=4 $Elf $Mem
if ($LASTEXITCODE -ne 0) { throw "objcopy memory image failed" }

& $Objdump -d -S -M no-aliases,numeric $Elf | Set-Content -Encoding ascii $Dump
if ($LASTEXITCODE -ne 0) { throw "objdump failed" }

& $Size $Elf
Write-Output "WORKLOAD_ELF=$Elf"
Write-Output "WORKLOAD_MEM=$Mem"
Write-Output "WORKLOAD_OBJDUMP=$Dump"
