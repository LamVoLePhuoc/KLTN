param(
    [string]$ReportDirectory = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$rtlDirectory = Join-Path $projectRoot "rtl"
$simDirectory = Join-Path $projectRoot "sim"
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $ReportDirectory = Join-Path $projectRoot "reports\full-regression-latest"
}
elseif (-not [IO.Path]::IsPathRooted($ReportDirectory)) {
    $ReportDirectory = Join-Path $projectRoot $ReportDirectory
}

$vlog = Get-Command vlog -ErrorAction Stop
$vsim = Get-Command vsim -ErrorAction Stop
$vlib = Get-Command vlib -ErrorAction Stop
$testFiles = @(Get-ChildItem -LiteralPath $simDirectory -Filter "tb_*.v" | Sort-Object Name)
if ($testFiles.Count -eq 0) {
    throw "No self-checking testbenches found in $simDirectory"
}

New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$questaWorkName = ".questa-work-" + [guid]::NewGuid().ToString("N")
$questaWork = Join-Path (Join-Path $projectRoot "reports") $questaWorkName
$questaWorkArgument = "../reports/$questaWorkName"
New-Item -ItemType Directory -Path $questaWork | Out-Null

$results = @()
try {
    & $vlib.Source $questaWork | Out-Null
    Push-Location $rtlDirectory
    try {
        $compileLog = Join-Path $ReportDirectory "compile.log"
        # Questa 10.2c on Windows cannot load an absolute path through
        # vsim -lib reliably. Both tools run from rtl/, so use the same
        # short relative library path for compile and simulation.
        & $vlog.Source -work $questaWorkArgument -l $compileLog -f files.f $testFiles.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "RTL/testbench compilation failed; see $compileLog"
        }

        foreach ($test in $testFiles) {
            $top = $test.BaseName
            $logName = "run-$top.log"
            $logPath = Join-Path $ReportDirectory $logName
            $output = @(& $vsim.Source -c -quiet -lib $questaWorkArgument $top -l $logPath -do "run -all; quit -f" 2>&1)
            $joined = $output -join "`n"
            $passed = ($LASTEXITCODE -eq 0) -and
                      ($joined -match "_TB: PASS") -and
                      ($joined -notmatch "_TB: FAIL")
            $results += [pscustomobject]@{
                Test = $top
                Result = if ($passed) { "PASS" } else { "FAIL" }
                Log = $logName
            }
            Write-Host ("{0,-32} {1}" -f $top, $results[-1].Result)
        }
    }
    finally {
        Pop-Location
    }

    $results | Export-Csv -LiteralPath (Join-Path $ReportDirectory "summary.csv") -NoTypeInformation
    $passCount = @($results | Where-Object Result -eq "PASS").Count
    $summary = @(
        "# Full RTL regression",
        "",
        "Result: **$passCount/$($results.Count) PASS**",
        "",
        "| Test | Result | Log |",
        "|---|---:|---|"
    )
    foreach ($result in $results) {
        $summary += "| $($result.Test) | $($result.Result) | $($result.Log) |"
    }
    Set-Content -LiteralPath (Join-Path $ReportDirectory "summary.md") -Value $summary

    if ($passCount -ne $results.Count) {
        throw "Regression failed: $passCount/$($results.Count) PASS"
    }
    Write-Host "Regression complete: $passCount/$($results.Count) PASS"
}
finally {
    if (Test-Path -LiteralPath $questaWork) {
        $resolvedTemp = (Resolve-Path -LiteralPath $questaWork).Path
        $reportRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot "reports"))
        if (-not $resolvedTemp.StartsWith($reportRoot + [IO.Path]::DirectorySeparatorChar,
                                          [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove simulator work library outside project reports: $resolvedTemp"
        }
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
