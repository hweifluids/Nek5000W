[CmdletBinding()]
param(
    [string]$SourceDir = "",
    [string]$InstallDir = "",
    [string]$CCompiler = "cl",
    [string]$Librarian = "lib",
    [switch]$Mpi,
    [string]$MpiIncludePath = $env:MSMPI_INC,
    [string]$MpiLibraryPath = $env:MSMPI_LIB64,
    [string[]]$ExtraCFlags = @(),
    [switch]$Clean
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
        throw "Required command '$Name' was not found in PATH. Run from a Visual Studio x64 command prompt."
    }
    return $cmd.Source
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
$sourceRoot = Split-Path -Parent $scriptDir

if (-not $SourceDir) {
    $SourceDir = Join-Path $sourceRoot "3rd_party\gslib\gslib_v1.0.9"
}
if (-not $InstallDir) {
    if ($Mpi) {
        $InstallDir = Join-Path $sourceRoot "3rd_party\gslib_mpi"
    } else {
        $InstallDir = Join-Path $sourceRoot "3rd_party\gslib"
    }
}

$srcRoot = Get-FullPath $SourceDir
$installRoot = Get-FullPath $InstallDir
$srcDir = Join-Path $srcRoot "src"
$buildDirName = if ($Mpi) { "build_win_msmpi" } else { "build_win_serial" }
$buildDir = Join-Path $installRoot $buildDirName
$objDir = Join-Path $buildDir "obj"
$includeDir = Join-Path $installRoot "include"
$includeGslibDir = Join-Path $includeDir "gslib"
$libDir = Join-Path $installRoot "lib"
$configPath = Join-Path $srcDir "config.h"
$libPath = Join-Path $libDir "gs.lib"

if (-not (Test-Path -LiteralPath (Join-Path $srcDir "gslib.h") -PathType Leaf)) {
    throw "GSLIB source tree is invalid: $srcRoot"
}
if ($Mpi) {
    if (-not $MpiIncludePath) {
        throw "MS-MPI include path is required. Pass -MpiIncludePath or set MSMPI_INC."
    }
    if (-not $MpiLibraryPath) {
        throw "MS-MPI library path is required. Pass -MpiLibraryPath or set MSMPI_LIB64."
    }
    if (-not (Test-Path -LiteralPath $MpiIncludePath -PathType Container)) {
        throw "MS-MPI include path does not exist: $MpiIncludePath"
    }
    if (-not (Test-Path -LiteralPath $MpiLibraryPath -PathType Container)) {
        throw "MS-MPI library path does not exist: $MpiLibraryPath"
    }
    $MpiIncludePath = (Get-FullPath $MpiIncludePath).TrimEnd('\')
    $MpiLibraryPath = (Get-FullPath $MpiLibraryPath).TrimEnd('\')
}

$cPath = Require-Command $CCompiler
$libExe = Require-Command $Librarian
Write-Host "C compiler: $cPath"
Write-Host "Librarian:  $libExe"
if ($Mpi) {
    Write-Host "MS-MPI include: $MpiIncludePath"
    Write-Host "MS-MPI library: $MpiLibraryPath"
}

if ($Clean) {
    Remove-Item -LiteralPath $buildDir, $includeDir, $libDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $objDir, $includeGslibDir, $libDir | Out-Null

@(
    "#ifndef GSLIB_CONFIG_H",
    "#define GSLIB_CONFIG_H",
    "#define GSLIB_PREFIX gslib_",
    "#define GSLIB_FPREFIX fgslib_",
    "#define GSLIB_USE_GLOBAL_LONG_LONG",
    "#define GSLIB_USE_NAIVE_BLAS"
) + $(if ($Mpi) {
    @("#define GSLIB_USE_MPI")
} else {
    @()
}) + @(
    "#endif"
) | Set-Content -LiteralPath $configPath -Encoding ascii

$defines = @(
    "/DGSLIB_PREFIX=gslib_",
    "/DGSLIB_FPREFIX=fgslib_",
    "/DGSLIB_USE_GLOBAL_LONG_LONG",
    "/DGSLIB_USE_NAIVE_BLAS",
    "/D_CRT_SECURE_NO_WARNINGS"
)
if ($Mpi) {
    $defines += "/DGSLIB_USE_MPI"
}
$flags = @("/nologo", "/O2")
if ($Mpi) {
    $flags += "/I$MpiIncludePath"
}
$flags += @("/I$srcDir") + $defines + $ExtraCFlags

$sources = @(
    "gs.c",
    "sort.c",
    "sarray_transfer.c",
    "sarray_sort.c",
    "gs_local.c",
    "fail.c",
    "crystal.c",
    "comm.c",
    "tensor.c",
    "fcrystal.c",
    "findpts.c",
    "findpts_local.c",
    "obbox.c",
    "poly.c",
    "lob_bnd.c",
    "findpts_el_3.c",
    "findpts_el_2.c"
)

$objects = @()
foreach ($file in $sources) {
    $source = Join-Path $srcDir $file
    $object = Join-Path $objDir ([System.IO.Path]::GetFileNameWithoutExtension($file) + ".obj")
    Invoke-Logged -Program $CCompiler -Arguments (@("/c", "/Fo$object") + $flags + @($source))
    $objects += $object
}

Invoke-Logged -Program $Librarian -Arguments (@("/nologo", "/OUT:$libPath") + $objects)

Copy-Item -Path (Join-Path $srcDir "*.h") -Destination $includeGslibDir -Force
Copy-Item -LiteralPath $configPath -Destination (Join-Path $includeGslibDir "config.h") -Force
@(
    "// Automatically generated file",
    "#include ""gslib/gslib.h"""
) | Set-Content -LiteralPath (Join-Path $includeDir "gslib.h") -Encoding ascii

Write-Host ""
if ($Mpi) {
    Write-Host "GSLIB Windows MS-MPI build complete: $libPath"
} else {
    Write-Host "GSLIB Windows serial build complete: $libPath"
}
