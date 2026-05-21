[CmdletBinding()]
param(
    [string]$NekSourceRoot = "",
    [string]$BuildDir = "",
    [string]$FortranCompiler = "ifx",
    [string]$CCompiler = "cl",
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
        throw "Required command '$Name' was not found in PATH. Run from an initialized Intel oneAPI x64 command prompt, or call bin\activate.cmd first."
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
$toolDir = Join-Path $sourceRoot "tools\gmsh2nek"
$coreDir = Join-Path $sourceRoot "core"
$winIncludeDir = Join-Path $sourceRoot "windows\include"

if (-not $BuildDir) {
    $BuildDir = Join-Path $toolDir "obj_win"
}
$buildRoot = Get-FullPath $BuildDir
$moduleDir = Join-Path $buildRoot "mod"

Require-File -Path (Join-Path $toolDir "mod_SIZE.f90") -Message "gmsh2nek module source is invalid."
Require-File -Path (Join-Path $toolDir "gmsh2nek.f90") -Message "gmsh2nek source is invalid."
Require-File -Path (Join-Path $toolDir "periodicity.f90") -Message "gmsh2nek periodicity source is invalid."
Require-File -Path (Join-Path $toolDir "non_right_hand_check.f90") -Message "gmsh2nek right-hand check source is invalid."
Require-File -Path (Join-Path $toolDir "mxm.f") -Message "gmsh2nek mxm source is invalid."
Require-File -Path (Join-Path $coreDir "speclib.f") -Message "Nek5000 speclib source is invalid."
Require-File -Path (Join-Path $coreDir "byte.c") -Message "Nek5000 byte.c source is invalid."

$fortranPath = Require-Command $FortranCompiler
$cPath = Require-Command $CCompiler
Write-Host "Fortran compiler: $fortranPath"
Write-Host "C compiler:       $cPath"
Write-Host "Nek source root:  $sourceRoot"
Write-Host "Build directory:  $buildRoot"

if ($CheckOnly) {
    Write-Host "CheckOnly succeeded."
    exit 0
}

if ($Clean -and (Test-Path -LiteralPath $buildRoot)) {
    $fullTool = [System.IO.Path]::GetFullPath($toolDir).TrimEnd('\')
    $fullBuild = [System.IO.Path]::GetFullPath($buildRoot).TrimEnd('\')
    if (-not $fullBuild.StartsWith($fullTool, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean build directory outside tools\gmsh2nek: $fullBuild"
    }
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
New-Item -ItemType Directory -Force -Path $moduleDir | Out-Null

$objects = @{
    modSize = Join-Path $buildRoot "mod_SIZE.obj"
    periodicity = Join-Path $buildRoot "periodicity.obj"
    rightHand = Join-Path $buildRoot "non_right_hand_check.obj"
    mxm = Join-Path $buildRoot "mxm.obj"
    speclib = Join-Path $buildRoot "speclib.obj"
    gmsh2nek = Join-Path $buildRoot "gmsh2nek.obj"
    byte = Join-Path $buildRoot "byte.obj"
}
$exe = Join-Path $buildRoot "gmsh2nek.exe"

$fFlags = @(
    "/nologo",
    "/fpp",
    "/real-size:64",
    "/fpconstant",
    "/names:lowercase",
    "/O2",
    "/module:$moduleDir",
    "/I$moduleDir",
    "/I$toolDir"
) + $ExtraFortranFlags

$fixedFlags = @(
    "/nologo",
    "/real-size:64",
    "/fpconstant",
    "/names:lowercase",
    "/O2",
    "/extend-source:132"
) + $ExtraFortranFlags

$cFlags = @(
    "/nologo",
    "/O2",
    "/D_CRT_SECURE_NO_WARNINGS",
    "/FI$winIncludeDir\msvc_compat.h",
    "/I$winIncludeDir",
    "/I$coreDir"
) + $ExtraCFlags

Invoke-Logged -Program $FortranCompiler -Arguments (@("/c") + $fFlags + @((Join-Path $toolDir "mod_SIZE.f90"), "/object:$($objects.modSize)"))
Invoke-Logged -Program $FortranCompiler -Arguments (@("/c") + $fFlags + @((Join-Path $toolDir "periodicity.f90"), "/object:$($objects.periodicity)"))
Invoke-Logged -Program $FortranCompiler -Arguments (@("/c") + $fFlags + @((Join-Path $toolDir "non_right_hand_check.f90"), "/object:$($objects.rightHand)"))
Invoke-Logged -Program $FortranCompiler -Arguments (@("/c") + $fixedFlags + @((Join-Path $toolDir "mxm.f"), "/object:$($objects.mxm)"))
Invoke-Logged -Program $FortranCompiler -Arguments (@("/c") + $fixedFlags + @((Join-Path $coreDir "speclib.f"), "/object:$($objects.speclib)"))
Invoke-Logged -Program $FortranCompiler -Arguments (@("/c") + $fFlags + @((Join-Path $toolDir "gmsh2nek.f90"), "/object:$($objects.gmsh2nek)"))
Invoke-Logged -Program $CCompiler -Arguments (@("/c", "/Fo$($objects.byte)") + $cFlags + @((Join-Path $coreDir "byte.c")))

$linkObjects = @(
    $objects.modSize,
    $objects.periodicity,
    $objects.rightHand,
    $objects.mxm,
    $objects.speclib,
    $objects.gmsh2nek,
    $objects.byte
)
Invoke-Logged -Program $FortranCompiler -Arguments (@("/nologo", "/exe:$exe") + $linkObjects + $ExtraLinkFlags)

Write-Host ""
Write-Host "Windows gmsh2nek build complete: $exe"
