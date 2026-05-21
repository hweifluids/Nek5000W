[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-CaseName {
    param([Parameter(Mandatory=$true)][string]$CaseDirectory, [string]$Requested)
    if ($Requested) {
        return [System.IO.Path]::GetFileNameWithoutExtension($Requested)
    }
    $usrFiles = @(Get-ChildItem -LiteralPath $CaseDirectory -Filter "*.usr" -File)
    if ($usrFiles.Count -eq 1) {
        return [System.IO.Path]::GetFileNameWithoutExtension($usrFiles[0].Name)
    }
    throw "Pass a case name, or run from a directory with exactly one .usr file."
}

$rankText = ""
$caseName = ""
$logName = ""
foreach ($arg in $Arguments) {
    if (-not $rankText -and $arg -match '^\d+$') {
        $rankText = $arg
    } elseif (-not $caseName) {
        $caseName = $arg
    } elseif (-not $logName) {
        $logName = $arg
    } else {
        throw "Usage: nekbmpi <case> <ranks> [logfile] or nekbmpi <ranks> <case> [logfile]"
    }
}
if (-not $rankText) {
    if ($env:NP -and $env:NP -match '^\d+$') {
        $rankText = $env:NP
    } else {
        throw "Usage: nekbmpi <case> <ranks> [logfile] or set NP."
    }
}

$caseDir = (Get-Location).Path
$case = Resolve-CaseName -CaseDirectory $caseDir -Requested $caseName
$logPath = if ($logName) {
    if ([System.IO.Path]::IsPathRooted($logName)) {
        [System.IO.Path]::GetFullPath($logName)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $caseDir $logName))
    }
} else {
    Join-Path $caseDir "$case.log"
}

$sourceRoot = if ($env:NEK_SOURCE_ROOT) {
    [System.IO.Path]::GetFullPath($env:NEK_SOURCE_ROOT)
} else {
    Split-Path -Parent $PSScriptRoot
}
$nekmpiCmd = Join-Path $sourceRoot "bin\nekmpi.cmd"
if (-not (Test-Path -LiteralPath $nekmpiCmd -PathType Leaf)) {
    $cmd = Get-Command nekmpi -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Cannot find nekmpi. Add Nek5000 bin directory to PATH."
    }
    $nekmpiCmd = $cmd.Source
}

$cmdLine = 'cd /d "' + $caseDir + '" && "' + $nekmpiCmd + '" "' + $case + '" "' + $rankText + '" > "' + $logPath + '" 2>&1'
$process = Start-Process -FilePath $env:ComSpec -ArgumentList @("/d", "/s", "/c", $cmdLine) -WorkingDirectory $caseDir -WindowStyle Hidden -PassThru

Write-Host "Started Nek5000 background MPI run."
Write-Host "Case:  $case"
Write-Host "Ranks: $rankText"
Write-Host "PID:   $($process.Id)"
Write-Host "Log:   $logPath"
