param(
    [string]$OutputRoot = "",
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir
$rtlDir = Join-Path $projectDir "rtl"
$simDir = Join-Path $projectDir "sim"

foreach ($tool in @("vlib", "vlog", "vsim")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Khong tim thay $tool trong PATH. Hay mo Questa Command Prompt hoac them Questa/ModelSim win64 vao PATH."
    }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputRoot = Join-Path $projectDir "reports\mmu-progress-$stamp"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$workDir = Join-Path $OutputRoot "questa-work"
New-Item -ItemType Directory -Force -Path $OutputRoot, $workDir | Out-Null

$tests = @(
    @{ File="tb_mmu_core.v";       Top="tb_mmu_core";       Marker="MMU_TB: PASS" },
    @{ File="tb_mmu_upgrade.v";    Top="tb_mmu_upgrade";    Marker="MMU_UPGRADE_TB: PASS" },
    @{ File="tb_mmu_policy.v";     Top="tb_mmu_policy";     Marker="MMU_POLICY_TB: PASS" },
    @{ File="tb_mmu_advanced.v";   Top="tb_mmu_advanced";   Marker="MMU_ADVANCED_TB: PASS" },
    @{ File="tb_mmu_sfence.v";     Top="tb_mmu_sfence";     Marker="MMU_SFENCE_TB: PASS" },
    @{ File="tb_mmu_context.v";    Top="tb_mmu_context";    Marker="MMU_CONTEXT_TB: PASS" },
    @{ File="tb_mmu_bus_error.v";  Top="tb_mmu_bus_error";  Marker="MMU_BUS_ERROR_TB: PASS" },
    @{ File="tb_csr_mmu_bits.v";   Top="tb_csr_mmu_bits";   Marker="CSR_MMU_BITS_TB: PASS" },
    @{ File="tb_csr_access_fault.v"; Top="tb_csr_access_fault"; Marker="CSR_ACCESS_FAULT_TB: PASS" }
)

$rtlFiles = Get-Content (Join-Path $rtlDir "files.f") |
    Where-Object { $_.Trim() -and -not $_.Trim().StartsWith("#") } |
    ForEach-Object { Join-Path $rtlDir $_.Trim() }

Push-Location $workDir
try {
    & vlib work | Out-Null
    & vlog -quiet -work work @rtlFiles 2>&1 | Tee-Object -FilePath (Join-Path $OutputRoot "compile-rtl.log")
    if ($LASTEXITCODE -ne 0) { throw "Compile RTL that bai. Xem compile-rtl.log." }

    $results = @()
    foreach ($test in $tests) {
        $tbPath = Join-Path $simDir $test.File
        $compileLog = Join-Path $OutputRoot ("compile-" + $test.Top + ".log")
        & vlog -quiet -work work $tbPath 2>&1 | Tee-Object -FilePath $compileLog
        $compileOk = ($LASTEXITCODE -eq 0)

        $runLog = Join-Path $OutputRoot ("run-" + $test.Top + ".log")
        if ($compileOk) {
            & vsim -c -quiet ("work." + $test.Top) -do "run -all; quit -f" 2>&1 |
                Tee-Object -FilePath $runLog
            $runText = Get-Content -Raw $runLog
            $passed = $runText.Contains($test.Marker) -and -not $runText.Contains(": FAIL")
        } else {
            $passed = $false
            "COMPILE FAILED" | Set-Content $runLog
        }
        $results += [pscustomobject]@{
            Test = $test.Top
            Result = if ($passed) { "PASS" } else { "FAIL" }
            Evidence = [System.IO.Path]::GetFileName($runLog)
        }
    }

    $results | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutputRoot "summary.csv")
    $passCount = @($results | Where-Object Result -eq "PASS").Count
    $lines = @(
        "# MMU weekly regression",
        "",
        "Run time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "",
        "Result: **$passCount/$($results.Count) PASS**",
        "",
        "| Test | Result | Log |",
        "|---|---:|---|"
    )
    foreach ($row in $results) { $lines += "| $($row.Test) | $($row.Result) | $($row.Evidence) |" }
    $lines += @(
        "",
        "> Pham vi nay chi la MMU + CSR lien quan truc tiep. tb_csr_priv khong nam trong mau so 9 test nay."
    )
    $lines | Set-Content -Encoding UTF8 (Join-Path $OutputRoot "summary.md")
    $results | Format-Table -AutoSize
    Write-Host "MMU RESULT: $passCount/$($results.Count) PASS"
    Write-Host "Evidence: $OutputRoot"
    if ($passCount -ne $results.Count) { exit 1 }
}
finally {
    Pop-Location
    if (-not $KeepWork -and (Test-Path $workDir)) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}
