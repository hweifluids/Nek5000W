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

function Resolve-MpiExec {
    if ($env:MSMPI_BIN) {
        $candidate = Join-Path $env:MSMPI_BIN "mpiexec.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    $cmd = Get-Command mpiexec -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    throw "Cannot find mpiexec. Set MSMPI_BIN or add MS-MPI to PATH."
}

$rankText = ""
$caseName = ""
foreach ($arg in $Arguments) {
    if (-not $rankText -and $arg -match '^\d+$') {
        $rankText = $arg
    } elseif (-not $caseName) {
        $caseName = $arg
    } else {
        throw "Usage: nekmpi <case> <ranks> or nekmpi <ranks> <case>"
    }
}
if (-not $rankText) {
    if ($env:NP -and $env:NP -match '^\d+$') {
        $rankText = $env:NP
    } else {
        throw "Usage: nekmpi <case> <ranks> or set NP."
    }
}

$caseDir = (Get-Location).Path
$case = Resolve-CaseName -CaseDirectory $caseDir -Requested $caseName
$casePath = $caseDir.TrimEnd('\') + '\'
Set-Content -LiteralPath (Join-Path $caseDir "SESSION.NAME") -Encoding ASCII -Value @("1", $case, $casePath)

$exeCandidates = @(
    (Join-Path $caseDir "obj_win_msmpi\nek5000.exe"),
    (Join-Path $caseDir "nek5000.exe")
)
$exe = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $exe) {
    throw "Cannot find an MPI nek5000.exe. Run makenek -mpi first."
}

$mpiExec = Resolve-MpiExec
& $mpiExec -n ([int]$rankText) $exe
exit $LASTEXITCODE
