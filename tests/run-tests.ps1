# Runs the Account Queue test suite. Requires AutoHotkey v2.
# Each test is a self-contained .ahk that #Includes the real app against
# a sandbox Logins folder created next to this script.
#
#   .\run-tests.ps1            everything (~12s; steals the mouse briefly)
#   .\run-tests.ps1 -Fast      logic + layout only (~3s, hands off the mouse)
#   .\run-tests.ps1 -Only rout run just the files matching "rout"
#   .\run-tests.ps1 -Quiet     one line unless something fails
#
# WHEN TO USE WHICH: iterate with -Fast; run the full suite once before
# shipping a version. -Fast covers every pure-logic check (data, routines,
# search, session math); it skips the two files that drive real input:
# macro-test (moves the mouse, 7s) and resize-stress (flashes a window).

param(
    [switch]$Fast,
    [string]$Only = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# Find AutoHotkey v2 wherever it happens to be installed. Set AHK_PATH to
# override. (This used to be one hardcoded path, which worked on exactly one
# machine.)
$ahk = $env:AHK_PATH
if (-not $ahk) {
    foreach ($candidate in @(
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\AutoHotkey64.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")) {
        if ($candidate -and (Test-Path $candidate)) { $ahk = $candidate; break }
    }
}
if (-not $ahk) {
    try { $ahk = (Get-ItemProperty "HKLM:\SOFTWARE\AutoHotkey" -ErrorAction Stop).InstallDir + "\v2\AutoHotkey64.exe" } catch {}
}
if (-not $ahk -or -not (Test-Path $ahk)) {
    $onPath = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($onPath) { $ahk = $onPath.Source }
}
if (-not $ahk -or -not (Test-Path $ahk)) {
    Write-Host "AutoHotkey v2 not found. Install it from https://www.autohotkey.com/"
    Write-Host "or point AHK_PATH at AutoHotkey64.exe:  $env:AHK_PATH = 'C:\path\to\AutoHotkey64.exe'"
    exit 1
}

$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root "AccountQueue.ahk"

# 1. Load-time syntax validation of the app itself
$p = Start-Process -FilePath $ahk -ArgumentList "/ErrorStdOut", "/validate", "`"$script`"" -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { Write-Host "VALIDATE: FAIL (exit $($p.ExitCode))"; exit 1 }
if (-not $Quiet) { Write-Host "VALIDATE: PASS" }

# 2. Test scripts. Slow = drives real input (mouse/resize), skipped by -Fast.
$suite = @(
    @{ Test = "test-runner.ahk";   Results = "test-results.txt";   Slow = $false },
    @{ Test = "macro-test.ahk";    Results = "macro-results.txt";  Slow = $true  },
    @{ Test = "layout-audit.ahk";  Results = "audit-results.txt";  Slow = $false },
    @{ Test = "resize-stress.ahk"; Results = "stress-results.txt"; Slow = $true  }
)
if ($Fast) { $suite = $suite | Where-Object { -not $_.Slow } }
if ($Only) { $suite = $suite | Where-Object { $_.Test -like "*$Only*" } }
if (-not $suite) { Write-Host "No test files matched '$Only'"; exit 1 }
$skipped = 0
if ($Fast) { $skipped = 2 }

$totalPass = 0
$totalFail = 0
foreach ($item in $suite) {
    $resultsPath = Join-Path $PSScriptRoot $item.Results
    Remove-Item $resultsPath -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $ahk -ArgumentList "/ErrorStdOut", "`"$(Join-Path $PSScriptRoot $item.Test)`"" -PassThru -NoNewWindow
    if (-not $proc.WaitForExit(120000)) {
        Stop-Process -Id $proc.Id -Force
        Write-Host "$($item.Test): TIMED OUT"
        $totalFail++
        continue
    }
    $lines = @()
    if (Test-Path $resultsPath) { $lines = Get-Content $resultsPath }
    # Tests end lines in "PASS"/"FAIL"/"TUNE" (some with ":", some "=>");
    # errors start the line. Anchored so labels containing "fail" don't
    # false-positive.
    $pass = @($lines | Select-String " PASS$").Count
    $fail = @($lines | Select-String "^ERROR| FAIL$| TUNE$").Count
    $totalPass += $pass
    $totalFail += $fail
    # Zero checks means the script died before it could assert anything
    # (a stray ExitApp, a crash outside the error handler). That MUST be
    # a failure - it once reported "all passed" while running nothing.
    if ($pass -eq 0) {
        $totalFail++
        Write-Host "$($item.Test): NO CHECKS PRODUCED - crashed or exited early"
        if (-not (Test-Path $resultsPath)) { Write-Host "  (no results file was written)" }
    }
    if ($fail -gt 0 -or $pass -eq 0) {
        Write-Host "$($item.Test): $pass pass, $fail FAIL"
        $lines | Select-String "^ERROR| FAIL$| TUNE$" | ForEach-Object { Write-Host "  $_" }
    } elseif (-not $Quiet) {
        Write-Host "$($item.Test): $pass pass"
    }
}

if ($totalFail -gt 0) {
    Write-Host ""
    Write-Host "RESULT: $totalFail FAILURE(S), $totalPass passed"
    exit 1
}
$note = if ($skipped) { " (fast: skipped $skipped input-driving files)" } else { "" }
Write-Host "RESULT: all $totalPass checks passed$note"
exit 0
