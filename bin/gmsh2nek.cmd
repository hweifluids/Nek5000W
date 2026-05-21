@echo off
setlocal
set "NEK_SOURCE_ROOT=%~dp0.."
if not exist "%NEK_SOURCE_ROOT%\tools\gmsh2nek\obj_win\gmsh2nek.exe" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%NEK_SOURCE_ROOT%\windows\build-gmsh2nek.ps1"
  if errorlevel 1 exit /b %ERRORLEVEL%
)
set "PATH=%NEK_SOURCE_ROOT%\windows\shims;%PATH%"
"%NEK_SOURCE_ROOT%\tools\gmsh2nek\obj_win\gmsh2nek.exe" %*
exit /b %ERRORLEVEL%
