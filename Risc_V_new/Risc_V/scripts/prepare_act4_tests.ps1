param(
    [string]$Checkout = "",
    [string]$WorkDir = ""
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$PinnedCommit = "792e55702c6ffff5c8432670086f126f40b88c9e"
if ([string]::IsNullOrWhiteSpace($Checkout)) {
    $Checkout = Join-Path $ProjectDir "third_party/riscv-arch-test"
}
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path $ProjectDir "build/act4"
}

# ACT4's supported environment is Linux. Prefer the repository-pinned WSL
# bootstrap, which uses mise/Ruby/uv, GCC 15.2 and Sail 0.16 entirely inside
# WSL while leaving generated ELF files in the Windows workspace for XSIM.
$Wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
$WslScript = Join-Path $PSScriptRoot "prepare_act4_tests_wsl.sh"
if ($null -ne $Wsl -and (Test-Path -LiteralPath $WslScript)) {
    function ConvertTo-WslPath([string]$WindowsPath) {
        $FullPath = [System.IO.Path]::GetFullPath($WindowsPath)
        if ($FullPath -notmatch '^([A-Za-z]):\\(.*)$') {
            throw "ACT4 WSL runner requires a drive-qualified Windows path: $FullPath"
        }
        $Drive = $Matches[1].ToLowerInvariant()
        $Tail = $Matches[2].Replace('\', '/')
        return "/mnt/$Drive/$Tail"
    }

    $ProjectWsl = ConvertTo-WslPath $ProjectDir
    $CheckoutWsl = ConvertTo-WslPath $Checkout
    $WorkDirWsl = ConvertTo-WslPath $WorkDir
    $ScriptWsl = ConvertTo-WslPath $WslScript

    & wsl.exe bash $ScriptWsl $ProjectWsl $CheckoutWsl $WorkDirWsl
    if ($LASTEXITCODE -ne 0) {
        throw "ACT4 WSL generation failed with exit code $LASTEXITCODE"
    }
    exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $Checkout ".git"))) {
    throw "Missing official riscv-arch-test checkout at $Checkout"
}
$ActualCommit = (& git -C $Checkout rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualCommit -ne $PinnedCommit) {
    throw "ACT4 checkout must be pinned to $PinnedCommit; found $ActualCommit"
}

$ToolchainBin = Join-Path $ProjectDir ".tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
$Gcc = Join-Path $ToolchainBin "riscv-none-elf-gcc.exe"
$Objdump = Join-Path $ToolchainBin "riscv-none-elf-objdump.exe"
foreach ($Path in @($Gcc, $Objdump)) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing ACT compiler tool: $Path" }
}

$Missing = @()
foreach ($Command in @("make", "ruby", "bundle", "sail_riscv_sim")) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { $Missing += $Command }
}
if ($Missing.Count -ne 0) {
    throw "ACT4 dependency check failed. Missing: $($Missing -join ', '). Use WSL/Linux or install the official prerequisites before claiming an architectural-test result."
}
$GccVersion = (& $Gcc -dumpfullversion).Trim()
$SailVersion = ((& sail_riscv_sim --version) | Select-Object -First 1).Trim()
if ($GccVersion -ne "15.2.0") {
    throw "ACT4 requires GCC 15.2.0; found $GccVersion"
}
if ($SailVersion -ne "0.16") {
    throw "ACT4 requires Sail RISC-V 0.16; found $SailVersion"
}

$ConfigDir = Join-Path $WorkDir "config/kltn-rv32ima"
$ElfRoot = Join-Path $WorkDir "work"
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
New-Item -ItemType Directory -Force -Path $ElfRoot | Out-Null

$OfficialConfig = Join-Path $Checkout "config/sail/sail-RVI20U32"
Copy-Item -LiteralPath (Join-Path $ProjectDir "verification/arch_test/act4/kltn-rv32ima.yaml") -Destination (Join-Path $ConfigDir "kltn-rv32ima.yaml") -Force
$SailConfig = Join-Path $ConfigDir "sail.json"
Copy-Item -LiteralPath (Join-Path $OfficialConfig "sail.json") -Destination $SailConfig -Force
Copy-Item -LiteralPath (Join-Path $ProjectDir "verification/arch_test/act4/rvmodel_macros.h") -Destination $ConfigDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectDir "verification/arch_test/act4/link.ld") -Destination $ConfigDir -Force

# Match Sail's executable main-memory PMA to the DUT/testbench's 1 MiB map.
$SailText = Get-Content -Raw -LiteralPath $SailConfig
$RomMatch = [regex]::Match($SailText, '(?s)// ROM.*?"include_in_device_tree"\s*:\s*false')
if (-not $RomMatch.Success) { throw "Cannot locate the stock Sail ROM region" }
$RomBlock = $RomMatch.Value
$RomBlock = [regex]::Replace(
    $RomBlock,
    '(?s)("size"\s*:\s*\{.*?"value"\s*:\s*)"0x1000"',
    '${1}"0x000FF000"', 1)
$RomBlock = $RomBlock.Replace('"mem_type": "IOMemory"', '"mem_type": "MainMemory"')
$RomBlock = $RomBlock.Replace('"executable": false', '"executable": true')
$RomBlock = $RomBlock.Replace('"writable": false', '"writable": true')
$RomBlock = $RomBlock.Replace('"atomic_support": "AMONone"', '"atomic_support": "AMOCASQ"')
$RomBlock = $RomBlock.Replace('"reservability": "RsrvNone"', '"reservability": "RsrvEventual"')
foreach ($Expected in @('"value": "0x000FF000"', '"mem_type": "MainMemory"',
        '"executable": true', '"writable": true', '"atomic_support": "AMOCASQ"',
        '"reservability": "RsrvEventual"')) {
    if (-not $RomBlock.Contains($Expected)) {
        throw "Failed to specialize Sail memory map: missing $Expected"
    }
}
$SailText = $SailText.Remove($RomMatch.Index, $RomMatch.Length).Insert($RomMatch.Index, $RomBlock)
$SailText = $SailText.Replace(
    '"privileged_isa_version": "Privileged_ISA_1_12"',
    '"privileged_isa_version": "Privileged_ISA_1_11"')
if (-not $SailText.Contains('"privileged_isa_version": "Privileged_ISA_1_11"')) {
    throw "Failed to select Sail Privileged ISA 1.11"
}

# Keep the native-Windows fallback equivalent to prepare_act4_tests_wsl.sh.
# The stock RVI20U32 profile enables compressed and floating-point state which
# is absent from this RV32IMA DUT. In particular, Zca changes IALIGN from 32 to
# 16 and therefore changes the architectural value read back from xEPC[1].
function Set-SailExtensionField {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Extension,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][string]$OldValue,
        [Parameter(Mandatory = $true)][string]$NewValue
    )

    $ExtensionPattern = '(?ms)(^    "' + [regex]::Escape($Extension) +
        '"\s*:\s*\{\s*$)(.*?)(^    \},?\s*$)'
    $ExtensionMatch = [regex]::Match($Text, $ExtensionPattern)
    if (-not $ExtensionMatch.Success) {
        throw "Cannot locate Sail extension block $Extension"
    }

    $Block = $ExtensionMatch.Value
    $FieldPattern = '(?m)(^\s*"' + [regex]::Escape($Field) +
        '"\s*:\s*)' + [regex]::Escape($OldValue) + '(\s*,?\s*$)'
    if (-not [regex]::IsMatch($Block, $FieldPattern)) {
        throw "Cannot set Sail $Extension.$Field from $OldValue"
    }
    $Block = [regex]::Replace($Block, $FieldPattern, "`$1$NewValue`$2", 1)
    return $Text.Remove($ExtensionMatch.Index, $ExtensionMatch.Length).
        Insert($ExtensionMatch.Index, $Block)
}

foreach ($Extension in @("M", "A", "C")) {
    $SailText = Set-SailExtensionField $SailText $Extension `
        "mutable_misa" "true" "false"
}
foreach ($Extension in @("F", "D", "Zca", "Zcf", "Zcd")) {
    $SailText = Set-SailExtensionField $SailText $Extension `
        "supported" "true" "false"
}
$SailText = $SailText.Replace(
    '"fs_legal_states": "ExtContext_FourState"',
    '"fs_legal_states": "ExtContext_Off"')
if (-not $SailText.Contains('"fs_legal_states": "ExtContext_Off"')) {
    throw "Failed to make mstatus.FS read-only zero for the non-F DUT"
}
Set-Content -Encoding utf8 -NoNewline -LiteralPath $SailConfig -Value $SailText

$TestConfig = Join-Path $ConfigDir "test_config.yaml"
@"
name: kltn-rv32ima
compiler_exe: $($Gcc.Replace('\','/'))
objdump_exe: $($Objdump.Replace('\','/'))
ref_model_exe: sail_riscv_sim
udb_config: kltn-rv32ima.yaml
linker_script: link.ld
dut_include_dir: .
include_priv_tests: False
"@ | Set-Content -Encoding ascii -LiteralPath $TestConfig

# This is an official ACT4 subset run, not a certification declaration.  The
# selected suites match the currently implemented unprivileged RV32IMA/Zicsr/
# Zifencei decode. Privileged tests remain excluded pending an audited UDB file.
Push-Location $Checkout
try {
    & make "CONFIG_FILES=$TestConfig" "WORKDIR=$ElfRoot" `
        "EXTENSIONS=I,M,Zaamo,Zalrsc,Zicsr,Zifencei"
    if ($LASTEXITCODE -ne 0) { throw "ACT4 generation failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$ElfDir = Join-Path $ElfRoot "kltn-rv32ima/elfs"
if (-not (Test-Path -LiteralPath $ElfDir)) { throw "ACT4 did not produce $ElfDir" }
$Count = (Get-ChildItem -LiteralPath $ElfDir -Filter *.elf -File -Recurse).Count
if ($Count -eq 0) { throw "ACT4 produced no self-checking ELFs" }
$Manifest = Join-Path $WorkDir "act4-manifest.txt"
@(
    "ACT4_COMMIT=$ActualCommit"
    "ACT4_GCC_VERSION=$GccVersion"
    "ACT4_SAIL_VERSION=$SailVersion"
    "ACT4_ELF_DIR=$ElfDir"
    "ACT4_ELF_COUNT=$Count"
) | Set-Content -Encoding ascii -LiteralPath $Manifest
Get-Content -LiteralPath $Manifest
