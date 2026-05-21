[CmdletBinding()]
param(
    [string]$CaseDir = ".",
    [string]$CaseName = "",
    [string]$NekSourceRoot = "",
    [string]$BuildDir = "",
    [string]$FortranCompiler = "ifx",
    [string]$CCompiler = "cl",
    [string]$Librarian = "lib",
    [switch]$Mpi,
    [string]$MpiIncludePath = $env:MSMPI_INC,
    [string]$MpiLibraryPath = $env:MSMPI_LIB64,
    [string]$MpiExec = "",
    [string[]]$MpiLibraries = @("msmpi.lib", "msmpifec.lib"),
    [switch]$EnableMpiIo,
    [string]$GslibInclude = "",
    [string]$GslibLib = "",
    [string]$BlasLib = "",
    [string[]]$ExtraFortranFlags = @(),
    [string[]]$ExtraCFlags = @(),
    [string[]]$ExtraLinkFlags = @(),
    [switch]$EmitLinkMap,
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

function Require-Directory {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Message)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Message Missing directory: $Path"
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

function Test-FileRegex {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Pattern)
    return [bool](Select-String -LiteralPath $Path -Pattern $Pattern -CaseSensitive:$false -Quiet)
}

function Add-BlockIfMissing {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [Parameter(Mandatory=$true)][string[]]$Lines
    )
    if (-not (Test-FileRegex -Path $Path -Pattern $Pattern)) {
        Add-Content -LiteralPath $Path -Value ""
        Add-Content -LiteralPath $Path -Value $Lines
    }
}

function Resolve-CaseName {
    param([Parameter(Mandatory=$true)][string]$Directory, [string]$Requested)
    if ($Requested) {
        return $Requested
    }
    $usrFiles = @(Get-ChildItem -LiteralPath $Directory -Filter "*.usr" -File)
    if ($usrFiles.Count -eq 0) {
        throw "No .usr file found in case directory: $Directory"
    }
    if ($usrFiles.Count -gt 1) {
        $names = ($usrFiles | ForEach-Object { $_.Name }) -join ", "
        throw "Multiple .usr files found in case directory. Pass -CaseName explicitly. Files: $names"
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($usrFiles[0].Name)
}

function Copy-CaseSize {
    param(
        [Parameter(Mandatory=$true)][string]$CaseDirectory,
        [Parameter(Mandatory=$true)][string]$SourceRoot,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    $candidates = @(
        (Join-Path $CaseDirectory "SIZE"),
        (Join-Path $CaseDirectory "SIZEu"),
        (Join-Path $CaseDirectory "SIZE.legacy"),
        (Join-Path $SourceRoot "core\SIZE.template")
    )
    $source = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $source) {
        throw "Cannot find SIZE, SIZEu, SIZE.legacy, or core\SIZE.template for this case."
    }

    Copy-Item -LiteralPath $source -Destination $Destination -Force

    Add-BlockIfMissing -Path $Destination -Pattern "\blelr\b" -Lines @(
        "c automatically added by windows build",
        "      integer lelr",
        "      parameter (lelr=lelt) ! max number of local elements per restart file"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "\bldimt_proj\b" -Lines @(
        "c automatically added by windows build",
        "      integer ldimt_proj",
        "      parameter(ldimt_proj=1) ! max auxiliary fields residual projection"
    )

    if (-not (Test-FileRegex -Path $Destination -Pattern "SIZE\.inc")) {
        Add-BlockIfMissing -Path $Destination -Pattern "\boptlevel\b" -Lines @(
            "c automatically added by windows build",
            "      integer optlevel,loglevel",
            "      common /lolevels/ optlevel,loglevel"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\blxo\b" -Lines @(
            "c automatically added by windows build",
            "      integer lxo",
            "      parameter(lxo   = lx1) ! max output grid size (lxo>=lx1)"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\bax1\b" -Lines @(
            "c automatically added by windows build",
            "      integer ax1,ay1,az1,ax2,ay2,az2",
            "      parameter (ax1=lx1,ay1=ly1,az1=lz1,ax2=lx2,ay2=ly2,az2=lz2) ! running averages"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\blxs\b" -Lines @(
            "c automatically added by windows build",
            "      integer lxs,lys,lzs",
            "      parameter (lxs=1,lys=lxs,lzs=(lxs-1)*(ldim-2)+1) ! New Pressure Preconditioner"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\blcvx1\b" -Lines @(
            "c automatically added by windows build",
            "      integer lcvx1,lcvy1,lcvz1,lcvelt",
            "      parameter (lcvx1=1,lcvy1=1,lcvz1=1,lcvelt=1) ! cvode arrays"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\blfdm\b" -Lines @(
            "c automatically added by windows build",
            "      integer lfdm",
            "      parameter (lfdm=0)  ! == 1 for fast diagonalization method"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\bnsessmax\b" -Lines @(
            "c automatically added by windows build",
            "      integer nsessmax",
            "      parameter (nsessmax=1)  ! max sessions to NEKNEK"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\bnmaxl_nn\b" -Lines @(
            "c automatically added by windows build",
            "      integer nmaxl_nn",
            "      parameter (nmaxl_nn=",
            "     $          min(1+(nsessmax-1)*2*ldim*lxz*lelt,2*ldim*lxz*lelt))"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\bnfldmax_nn\b" -Lines @(
            "c automatically added by windows build",
            "      integer nfldmax_nn",
            "      parameter (nfldmax_nn=",
            "     $          min(1+(nsessmax-1)*(ldim+1+ldimt),ldim+1+ldimt))"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\bnio\b" -Lines @(
            "c automatically added by windows build",
            "      integer nio",
            "      common/IOFLAG/nio  ! for logfile verbosity control"
        )
        Add-BlockIfMissing -Path $Destination -Pattern "\blhref\b" -Lines @(
            "c automatically added by windows build",
            "      integer lhref",
            "      parameter (lhref=10)"
        )
    }
}

function New-UserFortranFile {
    param(
        [Parameter(Mandatory=$true)][string]$UsrFile,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    Copy-Item -LiteralPath $UsrFile -Destination $Destination -Force
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+uservp" -Lines @(
        "c automatically added by windows build",
        "      subroutine uservp(ix,iy,iz,eg)",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+userf" -Lines @(
        "c automatically added by windows build",
        "      subroutine userf(ix,iy,iz,eg)",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+userq" -Lines @(
        "c automatically added by windows build",
        "      subroutine userq(ix,iy,iz,eg)",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+useric" -Lines @(
        "c automatically added by windows build",
        "      subroutine useric(ix,iy,iz,eg)",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+userbc" -Lines @(
        "c automatically added by windows build",
        "      subroutine userbc(ix,iy,iz,iside,eg)",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+userchk" -Lines @(
        "c automatically added by windows build",
        "      subroutine userchk()",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+usrdat0" -Lines @(
        "c automatically added by windows build",
        "      subroutine usrdat0()",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "^\s*subroutine\s+usrdat\s*(\(|!|$)" -Lines @(
        "c automatically added by windows build",
        "      subroutine usrdat()",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+usrdat2" -Lines @(
        "c automatically added by windows build",
        "      subroutine usrdat2()",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+usrdat3" -Lines @(
        "c automatically added by windows build",
        "      subroutine usrdat3",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+usrsetvert" -Lines @(
        "c automatically added by windows build",
        "      subroutine usrsetvert(glo_num,nel,nx,ny,nz)",
        "      integer*8 glo_num(1)",
        "      return",
        "      end"
    )
    Add-BlockIfMissing -Path $Destination -Pattern "subroutine\s+userqtl" -Lines @(
        "c automatically added by windows build",
        "      subroutine userqtl",
        "      call userqtl_scig",
        "      return",
        "      end"
    )
}

function Compile-Fortran {
    param([string]$Source, [string]$Object, [string[]]$Flags, [string[]]$Includes, [string[]]$Defines)
    $args = @("/c") + $Flags + $Defines + $Includes + @($Source, "/object:$Object")
    Invoke-Logged -Program $FortranCompiler -Arguments $args
}

function Compile-C {
    param([string]$Source, [string]$Object, [string[]]$Flags, [string[]]$Includes, [string[]]$Defines)
    $args = @("/c", "/Fo$Object") + $Flags + $Defines + $Includes + @($Source)
    Invoke-Logged -Program $CCompiler -Arguments $args
}

$scriptDir = Split-Path -Parent $PSCommandPath
if (-not $NekSourceRoot) {
    $NekSourceRoot = Split-Path -Parent $scriptDir
}
$sourceRoot = Get-FullPath $NekSourceRoot
$caseDirectory = Get-FullPath $CaseDir
$case = Resolve-CaseName -Directory $caseDirectory -Requested $CaseName
if (-not $BuildDir) {
    if ($Mpi) {
        $BuildDir = Join-Path $caseDirectory "obj_win_msmpi"
    } else {
        $BuildDir = Join-Path $caseDirectory "obj_win_serial"
    }
}
$buildRoot = Get-FullPath $BuildDir
$objDir = Join-Path $buildRoot "obj"
$blasObjDir = Join-Path $buildRoot "blas_obj"
$caseUsr = Join-Path $caseDirectory "$case.usr"
$generatedUsr = Join-Path $buildRoot "$case.f"
$generatedSize = Join-Path $buildRoot "SIZE"
$generatedParallel = Join-Path $buildRoot "PARALLEL"
$generatedMpif = Join-Path $buildRoot "mpif.h"

Require-File -Path (Join-Path $sourceRoot "core\drive.f") -Message "Nek5000 source root is invalid."
Require-File -Path $caseUsr -Message "Case source is invalid."

$fortranPath = Require-Command $FortranCompiler
$cPath = Require-Command $CCompiler
$libPath = Require-Command $Librarian
Write-Host "Fortran compiler: $fortranPath"
Write-Host "C compiler:       $cPath"
Write-Host "Librarian:        $libPath"
$mpiIncludeDirs = @()
if ($Mpi) {
    if (-not $MpiIncludePath) {
        throw "MS-MPI include path is required. Pass -MpiIncludePath or set MSMPI_INC."
    }
    if (-not $MpiLibraryPath) {
        throw "MS-MPI library path is required. Pass -MpiLibraryPath or set MSMPI_LIB64."
    }
    Require-Directory -Path $MpiIncludePath -Message "MS-MPI include path is invalid."
    Require-Directory -Path $MpiLibraryPath -Message "MS-MPI library path is invalid."
    $MpiIncludePath = (Get-FullPath $MpiIncludePath).TrimEnd('\')
    $MpiLibraryPath = (Get-FullPath $MpiLibraryPath).TrimEnd('\')
    $mpiIncludeDirs = @($MpiIncludePath)
    $mpiPtrIncludePath = Join-Path $MpiIncludePath "x64"
    if (Test-Path -LiteralPath (Join-Path $mpiPtrIncludePath "mpifptr.h") -PathType Leaf) {
        $mpiIncludeDirs += $mpiPtrIncludePath
    }
    foreach ($mpiLibName in $MpiLibraries) {
        Require-File -Path (Join-Path $MpiLibraryPath $mpiLibName) -Message "MS-MPI library is required."
    }
    if (-not $MpiExec) {
        if ($env:MSMPI_BIN) {
            $MpiExec = Join-Path $env:MSMPI_BIN "mpiexec.exe"
        } else {
            $mpiexecCmd = Get-Command mpiexec -ErrorAction SilentlyContinue
            if ($mpiexecCmd) {
                $MpiExec = $mpiexecCmd.Source
            }
        }
    }
    if ($MpiExec) {
        if (Test-Path -LiteralPath $MpiExec -PathType Leaf) {
            $MpiExec = Get-FullPath $MpiExec
        } else {
            $mpiexecCmd = Get-Command $MpiExec -ErrorAction SilentlyContinue
            if (-not $mpiexecCmd) {
                throw "MS-MPI mpiexec is invalid. Pass -MpiExec with a file path or command name."
            }
            $MpiExec = $mpiexecCmd.Source
        }
    }
    Write-Host "MS-MPI include:   $MpiIncludePath"
    if ($mpiIncludeDirs.Count -gt 1) {
        Write-Host "MS-MPI include+:  $($mpiIncludeDirs[1..($mpiIncludeDirs.Count - 1)] -join '; ')"
    }
    Write-Host "MS-MPI library:   $MpiLibraryPath"
    if ($MpiExec) {
        Write-Host "MS-MPI mpiexec:   $MpiExec"
    }
}

if (-not $GslibInclude) {
    if ($Mpi) {
        $GslibInclude = Join-Path $sourceRoot "3rd_party\gslib_mpi\include"
    } else {
        $GslibInclude = Join-Path $sourceRoot "3rd_party\gslib\include"
    }
}
if (-not $GslibLib) {
    if ($Mpi) {
        $candidates = @(
            (Join-Path $sourceRoot "3rd_party\gslib_mpi\lib\gs.lib"),
            (Join-Path $sourceRoot "3rd_party\gslib_mpi\lib\libgs.lib")
        )
    } else {
        $candidates = @(
            (Join-Path $sourceRoot "3rd_party\gslib\lib\gs.lib"),
            (Join-Path $sourceRoot "3rd_party\gslib\lib\libgs.lib")
        )
    }
    $GslibLib = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
Require-Directory -Path $GslibInclude -Message "A Windows-native GSLIB include directory is required."
if (-not $GslibLib) {
    if ($Mpi) {
        throw "A Windows-native MS-MPI GSLIB .lib is required. Pass -GslibLib or run windows\build-gslib.ps1 -Mpi."
    }
    throw "A Windows-native serial GSLIB .lib is required. Pass -GslibLib or build 3rd_party\gslib\lib\gs.lib."
}
Require-File -Path $GslibLib -Message "A Windows-native GSLIB library is required."

if ($CheckOnly) {
    Write-Host "CheckOnly succeeded."
    exit 0
}

if ($Clean -and (Test-Path -LiteralPath $buildRoot)) {
    $fullCase = [System.IO.Path]::GetFullPath($caseDirectory).TrimEnd('\')
    $fullBuild = [System.IO.Path]::GetFullPath($buildRoot).TrimEnd('\')
    if (-not $fullBuild.StartsWith($fullCase, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean build directory outside the case directory: $fullBuild"
    }
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $buildRoot, $objDir, $blasObjDir | Out-Null
Copy-CaseSize -CaseDirectory $caseDirectory -SourceRoot $sourceRoot -Destination $generatedSize
New-UserFortranFile -UsrFile $caseUsr -Destination $generatedUsr
Copy-Item -LiteralPath (Join-Path $sourceRoot "core\PARALLEL.default") -Destination $generatedParallel -Force
if (-not $Mpi) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot "core\mpi_dummy.h") -Destination $generatedMpif -Force
} elseif (Test-Path -LiteralPath $generatedMpif -PathType Leaf) {
    Remove-Item -LiteralPath $generatedMpif -Force
}

$coreDir = Join-Path $sourceRoot "core"
$winDir = Join-Path $sourceRoot "windows"
$winIncludeDir = Join-Path $winDir "include"
$experimentalDir = Join-Path $coreDir "experimental"

$fIncludes = @(
    "/I$buildRoot",
    "/I$caseDirectory",
    "/I$coreDir",
    "/I$experimentalDir"
)
if ($Mpi) {
    $fIncludes = @($mpiIncludeDirs | ForEach-Object { "/I$_" }) + $fIncludes
}
$cIncludes = @(
    "/I$winIncludeDir",
    "/I$buildRoot",
    "/I$caseDirectory",
    "/I$coreDir",
    "/I$experimentalDir",
    "/I$GslibInclude"
)
if ($Mpi) {
    $cIncludes = @($mpiIncludeDirs | ForEach-Object { "/I$_" }) + $cIncludes
}

$fDefines = @("/DTIMER")
$cDefines = @("/DWIN32", "/D_WINDOWS", "/DTIMER", "/DCOMM_H", "/D_CRT_SECURE_NO_WARNINGS")
if ($Mpi) {
    $fDefines += "/DMPI"
    $cDefines += "/DMPI"
} else {
    $fDefines += "/DNOMPIIO"
    $cDefines += "/DNOMPIIO"
}
if ($Mpi -and -not $EnableMpiIo) {
    $fDefines += "/DNOMPIIO"
    $cDefines += "/DNOMPIIO"
}

$dynComBlocks = 'vptsol,gmre1,gmre2,gmres,spltprec,gxyz,giso1,giso2,gisod,gmfact,gsurf,gvolm,mass,solnd,bqcb,vptmsk,cbm2,diverg,input5,input6,input8,input9,inputmi,cbout_mask'
$fDynCom = @("/Qdyncom`"$dynComBlocks`"")
Write-Host "Dynamic COMMON:   $dynComBlocks"

$fBaseFlags = @("/nologo", "/fpp", "/real-size:64", "/fpconstant", "/names:lowercase")
$fFlagsO2 = $fBaseFlags + @("/O2") + $fDynCom + $ExtraFortranFlags
$fFlagsO3 = $fBaseFlags + @("/O3") + $fDynCom + $ExtraFortranFlags
$fFlagsO0 = $fBaseFlags + @("/Od") + $fDynCom + $ExtraFortranFlags
$cFlagsO2 = @("/nologo", "/O2", "/FI$winIncludeDir\msvc_compat.h") + $ExtraCFlags

if (-not $BlasLib) {
    $BlasLib = Join-Path $buildRoot "blasLapack.lib"
    $blasSources = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot "3rd_party\blasLapack") -Filter "*.f" -File)
    $blasObjects = @()
    foreach ($src in $blasSources) {
        $obj = Join-Path $blasObjDir ([System.IO.Path]::GetFileNameWithoutExtension($src.Name) + ".obj")
        Compile-Fortran -Source $src.FullName -Object $obj -Flags $fFlagsO0 -Includes @() -Defines @()
        $blasObjects += $obj
    }
    Invoke-Logged -Program $Librarian -Arguments (@("/nologo", "/OUT:$BlasLib") + $blasObjects)
}
Require-File -Path $BlasLib -Message "BLAS/LAPACK library is required."

$fortranO2 = @(
    "drive1.f", "drive2.f", "comm_mpi.f", "plan5.f", "plan4.f", "bdry.f", "coef.f",
    "conduct.f", "connect1.f", "connect2.f", "dssum.f", "eigsolv.f",
    "gauss.f", "genxyz.f", "navier1.f", "makeq.f", "navier0.f",
    "navier2.f", "navier3.f", "navier4.f", "prepost.f", "speclib.f",
    "map2.f", "mvmesh.f", "ic.f", "gfldr.f", "ssolv.f", "planx.f",
    "hmholtz.f", "subs1.f", "subs2.f", "gmres.f", "hsmg.f", "convect.f",
    "induct.f", "perturb.f", "navier5.f", "navier6.f", "navier7.f",
    "navier8.f", "fast3d.f", "fasts.f", "calcz.f", "byte_mpi.f",
    "postpro.f", "interp.f", "cvode_driver.f", "multimesh.f", "vprops.f",
    "makeq_aux.f", "papi.f", "hpf.f", "hrefine.f",
    "reader_rea.f", "reader_par.f", "reader_re2.f", "dprocmap.f",
    "mpi_dummy.f", "mxm_wrapper.f", "mxm_std.f",
    "3rd_party\nek_in_situ.f"
)
if ($Mpi) {
    $fortranO2 = @($fortranO2 | Where-Object { $_ -ne "mpi_dummy.f" })
}
$fortranO0 = @("convect2.f")
$fortranO3 = @("math.f")

$cO2 = @(
    "byte.c",
    "fcrs.c",
    "crs_xxt.c",
    "crs_amg.c",
    "experimental\fem_amg_preco.c",
    "experimental\crs_hypre.c",
    "partitioner.c",
    "nekio.c",
    "3rd_party\finiparser.c",
    "3rd_party\iniparser.c",
    "3rd_party\dictionary.c"
)
$winC = @(
    (Join-Path $winDir "chelpers_win.c")
)
if (-not $Mpi) {
    $winC += (Join-Path $winDir "mpi_dummy_win.c")
}

$objects = @()
foreach ($file in $fortranO2) {
    $src = Join-Path $coreDir $file
    $obj = Join-Path $objDir ([System.IO.Path]::GetFileNameWithoutExtension($file) + ".obj")
    Compile-Fortran -Source $src -Object $obj -Flags $fFlagsO2 -Includes $fIncludes -Defines $fDefines
    $objects += $obj
}
foreach ($file in $fortranO0) {
    $src = Join-Path $coreDir $file
    $obj = Join-Path $objDir ([System.IO.Path]::GetFileNameWithoutExtension($file) + ".obj")
    Compile-Fortran -Source $src -Object $obj -Flags $fFlagsO0 -Includes $fIncludes -Defines $fDefines
    $objects += $obj
}
foreach ($file in $fortranO3) {
    $src = Join-Path $coreDir $file
    $obj = Join-Path $objDir ([System.IO.Path]::GetFileNameWithoutExtension($file) + ".obj")
    Compile-Fortran -Source $src -Object $obj -Flags $fFlagsO3 -Includes $fIncludes -Defines $fDefines
    $objects += $obj
}
foreach ($file in $cO2) {
    $src = Join-Path $coreDir $file
    $obj = Join-Path $objDir ([System.IO.Path]::GetFileNameWithoutExtension($file) + ".obj")
    Compile-C -Source $src -Object $obj -Flags $cFlagsO2 -Includes $cIncludes -Defines $cDefines
    $objects += $obj
}
foreach ($src in $winC) {
    $obj = Join-Path $objDir ([System.IO.Path]::GetFileNameWithoutExtension($src) + ".obj")
    Compile-C -Source $src -Object $obj -Flags $cFlagsO2 -Includes $cIncludes -Defines $cDefines
    $objects += $obj
}

$libNek = Join-Path $buildRoot "nek5000_core.lib"
Invoke-Logged -Program $Librarian -Arguments (@("/nologo", "/OUT:$libNek") + $objects)

$usrObj = Join-Path $objDir "$case.obj"
Compile-Fortran -Source $generatedUsr -Object $usrObj -Flags $fFlagsO2 -Includes $fIncludes -Defines $fDefines

$driveObj = Join-Path $objDir "drive.obj"
Compile-Fortran -Source (Join-Path $coreDir "drive.f") -Object $driveObj -Flags $fFlagsO2 -Includes $fIncludes -Defines $fDefines

$exe = Join-Path $buildRoot "nek5000.exe"
$mpiLinkLibs = @()
if ($Mpi) {
    foreach ($mpiLibName in $MpiLibraries) {
        $mpiLinkLibs += (Join-Path $MpiLibraryPath $mpiLibName)
    }
}
$linkArgs = @("/nologo", "/exe:$exe", $driveObj, $usrObj, $libNek, $GslibLib, $BlasLib) + $mpiLinkLibs + @("Psapi.lib") + $ExtraLinkFlags
if ($EmitLinkMap) {
    $mapFile = Join-Path $buildRoot "nek5000.map"
    $linkArgs += @("/link", "/MAP:$mapFile")
    Write-Host "Link map:         $mapFile"
}
Invoke-Logged -Program $FortranCompiler -Arguments $linkArgs

Write-Host ""
if ($Mpi) {
    Write-Host "Windows MS-MPI build complete: $exe"
} else {
    Write-Host "Windows serial build complete: $exe"
}
