param(
    [Parameter(Mandatory = $true)]
    [string]$InputSaif,

    [Parameter(Mandatory = $true)]
    [string]$OutputSaif,

    [Parameter(Mandatory = $true)]
    [int]$SourcePeriodPs,

    [Parameter(Mandatory = $true)]
    [int]$TargetPeriodPs
)

$ErrorActionPreference = 'Stop'

if ($SourcePeriodPs -le 0 -or $TargetPeriodPs -le 0) {
    throw 'SourcePeriodPs and TargetPeriodPs must be positive.'
}

$inputPath = [System.IO.Path]::GetFullPath($InputSaif)
$outputPath = [System.IO.Path]::GetFullPath($OutputSaif)
if (-not [System.IO.File]::Exists($inputPath)) {
    throw "Input SAIF does not exist: $inputPath"
}
if ($inputPath -eq $outputPath) {
    throw 'InputSaif and OutputSaif must be different files.'
}

$outputDirectory = [System.IO.Path]::GetDirectoryName($outputPath)
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

$scalerSource = @'
using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

public static class SaifClockScaler
{
    private static readonly Regex DurationPattern = new Regex(
        @"\(DURATION\s+(\d+)\)", RegexOptions.Compiled);
    private static readonly Regex ActivityPattern = new Regex(
        @"\((T0|T1|TX|TZ|TB)\s+(\d+)\)", RegexOptions.Compiled);

    public static void Scale(string inputPath, string outputPath,
                             long sourcePeriodPs, long targetPeriodPs,
                             out long durationCount, out long activityCount)
    {
        long durations = 0;
        long activities = 0;
        Func<string, string> scaleValue = valueText => {
            long value = Int64.Parse(valueText);
            long numerator = checked(value * targetPeriodPs);
            if ((numerator % sourcePeriodPs) != 0)
                throw new InvalidDataException(
                    "SAIF time " + valueText + " cannot be scaled exactly by " +
                    targetPeriodPs + "/" + sourcePeriodPs + ".");
            return (numerator / sourcePeriodPs).ToString();
        };

        using (var reader = new StreamReader(inputPath, Encoding.ASCII,
                                             false, 4 * 1024 * 1024))
        using (var writer = new StreamWriter(outputPath, false, Encoding.ASCII,
                                             4 * 1024 * 1024))
        {
            string line;
            while ((line = reader.ReadLine()) != null)
            {
                line = DurationPattern.Replace(line, match => {
                    durations++;
                    return "(DURATION " + scaleValue(match.Groups[1].Value) + ")";
                });
                line = ActivityPattern.Replace(line, match => {
                    activities++;
                    return "(" + match.Groups[1].Value + " " +
                           scaleValue(match.Groups[2].Value) + ")";
                });
                writer.WriteLine(line);
            }
        }
        durationCount = durations;
        activityCount = activities;
    }
}
'@

Add-Type -TypeDefinition $scalerSource -Language CSharp
$durationCount = 0L
$activityCount = 0L
[SaifClockScaler]::Scale(
    $inputPath,
    $outputPath,
    $SourcePeriodPs,
    $TargetPeriodPs,
    [ref]$durationCount,
    [ref]$activityCount
)

if ($durationCount -ne 1 -or $activityCount -eq 0) {
    [System.IO.File]::Delete($outputPath)
    throw "Malformed SAIF: durations=$durationCount activity_fields=$activityCount"
}

$metadataPath = "$outputPath.scale.txt"
$metadata = @(
    "input=$inputPath"
    "output=$outputPath"
    "source_period_ps=$SourcePeriodPs"
    "target_period_ps=$TargetPeriodPs"
    "frequency_scale=$([double]$SourcePeriodPs / [double]$TargetPeriodPs)"
    "duration_fields=$durationCount"
    "activity_fields=$activityCount"
)
[System.IO.File]::WriteAllLines($metadataPath, $metadata)

Write-Host "Scaled SAIF clock activity: $SourcePeriodPs ps -> $TargetPeriodPs ps"
Write-Host "Output: $outputPath"
Write-Host "Activity fields: $activityCount"
