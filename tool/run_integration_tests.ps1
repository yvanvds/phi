<#
.SYNOPSIS
    Drives every integration_test/*.dart file as its own `flutter test` run.

.DESCRIPTION
    On Windows a single `flutter test integration_test` invocation launches only
    the FIRST app in the folder and silently reports success for the rest, so the
    suite has to be driven file by file. This script does that, keeps going after
    a failure, prints the output of every file that failed, and exits non-zero if
    any file failed.

    The suite is engine-free: every file injects `FakeYseGateway`, so no
    `libyse.dll` and no `YSE_DLL_PATH` are required.

.PARAMETER Shard
    1-based index of this shard. Files are handed out round-robin over `Of`
    shards, so each shard gets an interleaved slice of similar weight.

.PARAMETER Of
    Total number of shards. Default 1 (run everything here).

.PARAMETER Filter
    Wildcard matched against the file name, e.g. `patcher_*`. Default `*`.

.PARAMETER Device
    Flutter device id. Default `windows`.

.PARAMETER TimeoutSeconds
    Wall-clock budget per file. A hung app is killed and counted as a failure
    instead of stalling an unattended nightly run. Default 900.

.EXAMPLE
    pwsh tool/run_integration_tests.ps1
    pwsh tool/run_integration_tests.ps1 -Filter 'patcher_*'
    pwsh tool/run_integration_tests.ps1 -Shard 2 -Of 4
#>
[CmdletBinding()]
param(
    [int]$Shard = 1,
    [int]$Of = 1,
    [string]$Filter = '*',
    [string]$Device = 'windows',
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'

if ($Of -lt 1) { throw "-Of must be >= 1 (got $Of)" }
if ($Shard -lt 1 -or $Shard -gt $Of) { throw "-Shard must be between 1 and $Of (got $Shard)" }

$repoRoot = Split-Path -Parent $PSScriptRoot
$testDir = Join-Path $repoRoot 'integration_test'
if (-not (Test-Path $testDir)) { throw "No integration_test/ folder at $testDir" }

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { throw 'flutter was not found on PATH.' }

$all = Get-ChildItem -Path $testDir -Filter '*.dart' |
    Where-Object { $_.Name -like $Filter } |
    Sort-Object Name

if ($all.Count -eq 0) { throw "No integration tests matched filter '$Filter'." }

# Round-robin so a shard never collects only the slow files.
$mine = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
for ($i = 0; $i -lt $all.Count; $i++) {
    if (($i % $Of) -eq ($Shard - 1)) { $mine.Add($all[$i]) }
}

Write-Host "Integration suite: $($all.Count) file(s) total, $($mine.Count) in shard $Shard/$Of."
Write-Host ''

$results = [System.Collections.Generic.List[object]]::new()
$logDir = Join-Path ([System.IO.Path]::GetTempPath()) "phi-integration-$PID"
New-Item -ItemType Directory -Force $logDir | Out-Null

$index = 0
foreach ($file in $mine) {
    $index++
    $relative = "integration_test/$($file.Name)"
    Write-Host "[$index/$($mine.Count)] $relative" -NoNewline

    $log = Join-Path $logDir "$($file.BaseName).log"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $flutter `
        -ArgumentList @('test', '-d', $Device, $relative) `
        -WorkingDirectory $repoRoot `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $log `
        -RedirectStandardError "$log.err"

    $timedOut = $false
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        try { $process.Kill($true) } catch { Write-Verbose "kill failed: $_" }
        $process.WaitForExit()
    }
    $watch.Stop()

    $ok = (-not $timedOut) -and ($process.ExitCode -eq 0)
    $seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
    $status = if ($ok) { 'PASS' } elseif ($timedOut) { 'TIMEOUT' } else { 'FAIL' }
    Write-Host "  $status (${seconds}s)"

    $results.Add([pscustomobject]@{
            File    = $relative
            Status  = $status
            Seconds = $seconds
            Log     = $log
        })
}

$failed = @($results | Where-Object { $_.Status -ne 'PASS' })

if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host '================ failing files ================'
    foreach ($failure in $failed) {
        Write-Host ''
        Write-Host "--- $($failure.File) [$($failure.Status)] ---"
        foreach ($path in @($failure.Log, "$($failure.Log).err")) {
            if ((Test-Path $path) -and (Get-Item $path).Length -gt 0) {
                Get-Content $path | Select-Object -Last 80 | ForEach-Object { Write-Host $_ }
            }
        }
    }
}

$total = [math]::Round(($results | Measure-Object -Property Seconds -Sum).Sum, 1)
Write-Host ''
Write-Host "Shard $Shard/${Of}: $($results.Count - $failed.Count)/$($results.Count) passed in ${total}s."

# Surface the outcome on the GitHub Actions run summary page.
if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @(
        "### Integration shard $Shard/$Of",
        '',
        "$($results.Count - $failed.Count)/$($results.Count) files passed in ${total}s.",
        ''
    )
    if ($failed.Count -gt 0) {
        $lines += '| File | Status |'
        $lines += '| --- | --- |'
        $lines += ($failed | ForEach-Object { "| ``$($_.File)`` | $($_.Status) |" })
    }
    $lines | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
