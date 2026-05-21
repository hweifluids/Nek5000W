[CmdletBinding()]
param(
    [string]$CaseName = ""
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

$caseDir = (Get-Location).Path
$case = Resolve-CaseName -CaseDirectory $caseDir -Requested $CaseName
$casePath = $caseDir.TrimEnd('\') + '\'
Set-Content -LiteralPath (Join-Path $caseDir "SESSION.NAME") -Encoding ASCII -Value @("1", $case, $casePath)

$exeCandidates = @(
    (Join-Path $caseDir "nek5000.exe"),
    (Join-Path $caseDir "obj_win_serial\nek5000.exe"),
    (Join-Path $caseDir "obj_win_msmpi\nek5000.exe")
)
$exe = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $exe) {
    throw "Cannot find nek5000.exe. Run makenek first."
}

& $exe
exit $LASTEXITCODE
