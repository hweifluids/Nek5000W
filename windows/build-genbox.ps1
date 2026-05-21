[CmdletBinding()]
param(
    [string]$NekSourceRoot = "",
    [string]$BuildDir = "",
    [string]$FortranCompiler = "ifx",
    [string]$CCompiler = "cl",
    [int]$MaxElements = 150000,
    [string[]]$ExtraFortranFlags = @(),
    [string[]]$ExtraCFlags = @(),
    [string[]]$ExtraLinkFlags = @(),
    [switch]$Clean,
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FullPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Require-Command {
    param([Parameter(Mandatory=$true)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Required command '$Name' was not found in PATH. Run from an Intel oneAPI x64 command prompt with Visual Studio tools initialized."
    }
    return $cmd.Source
}

function Require-File {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Message)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Message Missing file: $Path"
    }
}

function Invoke-Logged {
    param([Parameter(Mandatory=$true)][string]$Program, [Parameter(Mandatory=$true)][string[]]$Arguments)
    Write-Host ">> $Program $($Arguments -join ' ')"
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $Program $($Arguments -join ' ')"
    }
}

$scriptDir = Split-Path -Parent $PSCommandPath
if (-not $NekSourceRoot) {
    $NekSourceRoot = Split-Path -Parent $scriptDir
}
$sourceRoot = Get-FullPath $NekSourceRoot
$toolDir = Join-Path $sourceRoot "tools\genbox"
if (-not $BuildDir) {
    $BuildDir = Join-Path $toolDir "obj_win"
}
$buildRoot = Get-FullPath $BuildDir
$winIncludeDir = Join-Path $sourceRoot "windows\include"

Require-File -Path (Join-Path $toolDir "genbox.f") -Message "genbox source is invalid."
Require-File -Path (Join-Path $toolDir "SIZE") -Message "genbox SIZE include is invalid."
Require-File -Path (Join-Path $toolDir "byte.c") -Message "genbox byte.c source is invalid."

$fortranPath = Require-Command $FortranCompiler
$cPath = Require-Command $CCompiler
Write-Host "Fortran compiler: $fortranPath"
Write-Host "C compiler:       $cPath"

if ($CheckOnly) {
    Write-Host "CheckOnly succeeded."
    exit 0
}

if ($Clean -and (Test-Path -LiteralPath $buildRoot)) {
    $fullTool = [System.IO.Path]::GetFullPath($toolDir).TrimEnd('\')
    $fullBuild = [System.IO.Path]::GetFullPath($buildRoot).TrimEnd('\')
    if (-not $fullBuild.StartsWith($fullTool, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean build directory outside tools\genbox: $fullBuild"
    }
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

$genboxObj = Join-Path $buildRoot "genbox.obj"
$byteObj = Join-Path $buildRoot "byte.obj"
$exe = Join-Path $buildRoot "genbox.exe"

$fFlags = @(
    "/nologo",
    "/fpp",
    "/real-size:64",
    "/fpconstant",
    "/names:lowercase",
    "/O2",
    "/DMAXNEL=$MaxElements",
    "/I$toolDir"
) + $ExtraFortranFlags

$cFlags = @(
    "/nologo",
    "/O2",
    "/D_CRT_SECURE_NO_WARNINGS",
    "/FI$winIncludeDir\msvc_compat.h",
    "/I$winIncludeDir",
    "/I$toolDir"
) + $ExtraCFlags

Invoke-Logged -Program $FortranCompiler -Arguments (@("/c") + $fFlags + @((Join-Path $toolDir "genbox.f"), "/object:$genboxObj"))
Invoke-Logged -Program $CCompiler -Arguments (@("/c", "/Fo$byteObj") + $cFlags + @((Join-Path $toolDir "byte.c")))
Invoke-Logged -Program $FortranCompiler -Arguments (@("/nologo", "/exe:$exe", $genboxObj, $byteObj) + $ExtraLinkFlags)

Write-Host ""
Write-Host "Windows genbox build complete: $exe"
