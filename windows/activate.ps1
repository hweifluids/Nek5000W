[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceRoot = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $sourceRoot "bin"

$pathEntries = @($env:PATH -split ';' | Where-Object { $_ })
if (-not ($pathEntries | Where-Object { $_.TrimEnd('\') -ieq $binDir.TrimEnd('\') })) {
    $env:PATH = "$binDir;$env:PATH"
}
$env:NEK_SOURCE_ROOT = $sourceRoot

Write-Host "NEK_SOURCE_ROOT=$env:NEK_SOURCE_ROOT"
Write-Host "Added to PATH for this terminal: $binDir"
Write-Host "Available commands: makenek, nek, nekmpi, nekbmpi, genmap, genbox, gmsh2nek"
