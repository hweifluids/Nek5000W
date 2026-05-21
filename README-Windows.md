# Windows Native Build

by Huanxia Wei at University of Manchester

This variant is Windows-native only. The user-facing commands live in
`bin\*.cmd` and forward to the PowerShell build/run scripts in `windows\`.
The old POSIX/GNU make entry points have been removed.

Supported command-line tools:

- `makenek`
- `nek`
- `nekmpi`
- `nekbmpi`
- `genmap`
- `genbox`
- `gmsh2nek`

## Terminal Setup

Use an x64 Visual Studio + Intel oneAPI command prompt, or initialize a normal
`cmd.exe` terminal like this:

```bat
cd /d C:\1_Development\Nek5000W
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64
call "C:\Program Files (x86)\Intel\oneAPI\setvars.bat" intel64
bin\activate.cmd
```

For PowerShell after the compiler environment is already initialized:

```powershell
Set-Location C:\1_Development\Nek5000W
.\windows\activate.ps1
```

MS-MPI is discovered from these variables or from `PATH`:

```bat
set MSMPI_INC=C:\Program Files (x86)\Microsoft SDKs\MPI\Include\
set MSMPI_LIB64=C:\Program Files (x86)\Microsoft SDKs\MPI\Lib\x64\
set MSMPI_BIN=C:\Program Files\Microsoft MPI\Bin\
```

## Serial Case

```bat
cd /d C:\1_Development\Nek5000W\short_tests\eddy
makenek -serial eddy_uv
echo -1>ioinfo
nek eddy_uv
```

`makenek -serial` builds `obj_win_serial\nek5000.exe` and copies it to
`nek5000.exe` in the case directory. `echo -1>ioinfo` is optional; it limits
this smoke case to one time step.

## MS-MPI Case

`makenek` defaults to MS-MPI, matching the usual parallel-oriented Nek5000
workflow. Use `-serial` or `set MPI=0` for a serial build.

```bat
cd /d C:\1_Development\Nek5000W\short_tests\eddy
makenek eddy_uv
echo -1>ioinfo
nekmpi eddy_uv 2
```

80-rank smoke:

```bat
echo -1>ioinfo
nekmpi eddy_uv 80
```

## Mesh Tools

`genmap` reads the case name and tolerance from stdin:

```bat
cd /d C:\1_Development\Nek5000W\short_tests\eddy
(echo eddy_uv& echo 0.5) | genmap
```

`genbox` prompts for the `.box` file name. Pipe the file name, not the file
contents:

```bat
cd /d C:\1_Development\Nek5000W\examples\phill
echo phill.box | genbox
```

`gmsh2nek` reads interactive answers from stdin and writes a `.re2` file:

```bat
cd /d C:\1_Development\Nek5000W\short_tests\bcid_test\3D
(echo 3& echo pipe& echo 0& echo 0& echo pipe_win) | gmsh2nek
```

For a 2D fluid+solid mesh:

```bat
cd /d C:\1_Development\Nek5000W\short_tests\bcid_test\2D
(echo 2& echo fluid& echo 1& echo solid& echo 0& echo 0& echo cht2d_win) | gmsh2nek
```

## Build Scripts

The command wrappers are the preferred interface, but the lower-level scripts
remain available:

- `windows\build-gslib.ps1`
- `windows\build-genmap.ps1`
- `windows\build-genbox.ps1`
- `windows\build-gmsh2nek.ps1`
- `windows\build-serial.ps1`

Configuration variables are exposed as script parameters: `-FortranCompiler`,
`-CCompiler`, `-Librarian`, `-MpiIncludePath`, `-MpiLibraryPath`, `-MpiExec`,
`-GslibInclude`, `-GslibLib`, `-BlasLib`, and `-BuildDir`.
Set `NEK_WIN_LINK_MAP=1` before `makenek` to emit an optional Windows linker
map in the build directory for image-size diagnostics.

Expected Windows artifacts:

- `3rd_party\gslib\lib\gs.lib`
- `3rd_party\gslib_mpi\lib\gs.lib`
- `tools\genmap\obj_win\genmap.exe`
- `tools\genbox\obj_win\genbox.exe`
- `tools\gmsh2nek\obj_win\gmsh2nek.exe`
- `short_tests\eddy\obj_win_serial\nek5000.exe`
- `short_tests\eddy\obj_win_msmpi\nek5000.exe`
