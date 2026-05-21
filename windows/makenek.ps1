[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host @"
Usage:
  makenek [case]              Build the case. Defaults to MPI, matching Nek5000's Unix makenek.
  makenek -serial [case]      Build a serial Windows executable.
  makenek -mpi [case]         Build an MS-MPI Windows executable.
  makenek clean               Remove Windows build outputs in the current case directory.
  makenek -build-dep          Build Windows dependency libraries for the selected mode.

Environment:
  MPI=0                       Select serial mode.
  MPI=1 or unset              Select MS-MPI mode.
  FC, CC                      Override ifx/cl command names.
  MSMPI_INC, MSMPI_LIB64      MS-MPI SDK include/library roots.
  NEK_WIN_LINK_MAP=1          Emit a linker map into the Windows build directory.
"@
}

function Resolve-CaseName {
    param([Parameter(Mandatory=$true)][string]$CaseDirectory, [string]$Requested)
    if ($Requested) {
        return [System.IO.Path]::GetFileNameWithoutExtension($Requested)
    }
    $usrFiles = @(Get-ChildItem -LiteralPath $CaseDirectory -Filter "*.usr" -File)
    if ($usrFiles.Count -eq 0) {
        throw "No .usr file found in current directory. Pass a case name."
    }
    if ($usrFiles.Count -gt 1) {
        $names = ($usrFiles | ForEach-Object { $_.Name }) -join ", "
        throw "Multiple .usr files found. Pass a case name. Files: $names"
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($usrFiles[0].Name)
}

function Invoke-Script {
    param([Parameter(Mandatory=$true)][string]$Script, [Parameter(Mandatory=$true)][hashtable]$Parameters)
    $displayArgs = ($Parameters.GetEnumerator() | Sort-Object Name | ForEach-Object {
        if ($_.Value -is [switch] -or $_.Value -is [bool]) {
            if ($_.Value) { "-$($_.Name)" } else { "" }
        } else {
            "-$($_.Name) $($_.Value)"
        }
    }) -join ' '
    Write-Host ">> powershell -File $Script $displayArgs"
    & $Script @Parameters
    if (-not $?) {
        throw "Command failed: $Script $displayArgs"
    }
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$caseDir = (Get-Location).Path
$caseName = ""
$mode = ""
$clean = $false
$buildDepOnly = $false
$showHelp = $false

foreach ($arg in $Arguments) {
    switch -Regex ($arg) {
        '^(clean|distclean)$' { $clean = $true; continue }
        '^(-h|--help|/h|/\?)$' { $showHelp = $true; continue }
        '^(-serial|--serial|/serial|-nompi|--nompi)$' { $mode = "serial"; continue }
        '^(-mpi|--mpi|/mpi)$' { $mode = "mpi"; continue }
        '^-build-dep$' { $buildDepOnly = $true; continue }
        default {
            if ($arg.StartsWith("-") -or $arg.StartsWith("/")) {
                throw "Unsupported makenek option: $arg"
            }
            if ($caseName) {
                throw "Only one case name is supported. Got '$caseName' and '$arg'."
            }
            $caseName = $arg
        }
    }
}

if ($showHelp) {
    Show-Help
    exit 0
}

if (-not $mode) {
    if ($env:MPI -eq "0") {
        $mode = "serial"
    } else {
        $mode = "mpi"
    }
}

if ($clean) {
    $targets = @(
        (Join-Path $caseDir "obj_win_serial"),
        (Join-Path $caseDir "obj_win_msmpi"),
        (Join-Path $caseDir "nek5000.exe"),
        (Join-Path $caseDir "build.log")
    )
    foreach ($target in $targets) {
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Windows Nek5000 build outputs removed from $caseDir"
    exit 0
}

$fortranCompiler = if ($env:FC) { $env:FC } else { "ifx" }
$cCompiler = if ($env:CC) { $env:CC } else { "cl" }

if ($mode -eq "mpi") {
    $gslibLib = Join-Path $sourceRoot "3rd_party\gslib_mpi\lib\gs.lib"
    if (-not (Test-Path -LiteralPath $gslibLib -PathType Leaf)) {
        $depParams = @{ Mpi = $true; CCompiler = $cCompiler }
        if ($env:MSMPI_INC) { $depParams.MpiIncludePath = $env:MSMPI_INC }
        if ($env:MSMPI_LIB64) { $depParams.MpiLibraryPath = $env:MSMPI_LIB64 }
        Invoke-Script -Script (Join-Path $sourceRoot "windows\build-gslib.ps1") -Parameters $depParams
    }
} else {
    $gslibLib = Join-Path $sourceRoot "3rd_party\gslib\lib\gs.lib"
    if (-not (Test-Path -LiteralPath $gslibLib -PathType Leaf)) {
        $depParams = @{ CCompiler = $cCompiler }
        Invoke-Script -Script (Join-Path $sourceRoot "windows\build-gslib.ps1") -Parameters $depParams
    }
}

if ($buildDepOnly) {
    Write-Host "Dependency build completed for mode: $mode"
    exit 0
}

$caseName = Resolve-CaseName -CaseDirectory $caseDir -Requested $caseName
$buildScript = Join-Path $sourceRoot "windows\build-serial.ps1"
$buildParams = @{
    CaseDir = $caseDir
    CaseName = $caseName
    FortranCompiler = $fortranCompiler
    CCompiler = $cCompiler
}
if ($mode -eq "mpi") {
    $buildParams.Mpi = $true
}
if ($env:NEK_WIN_LINK_MAP -and $env:NEK_WIN_LINK_MAP -ne "0") {
    $buildParams.EmitLinkMap = $true
}
$buildDirName = if ($mode -eq "mpi") { "obj_win_msmpi" } else { "obj_win_serial" }
$blasCandidate = Join-Path $caseDir "$buildDirName\blasLapack.lib"
if (Test-Path -LiteralPath $blasCandidate -PathType Leaf) {
    $buildParams.BlasLib = $blasCandidate
}

Invoke-Script -Script $buildScript -Parameters $buildParams

$builtExe = Join-Path $caseDir "$buildDirName\nek5000.exe"
$caseExe = Join-Path $caseDir "nek5000.exe"
if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
    throw "Build finished but executable is missing: $builtExe"
}
Copy-Item -LiteralPath $builtExe -Destination $caseExe -Force

Write-Host ""
Write-Host "Nek5000 Windows $mode executable ready: $caseExe"
