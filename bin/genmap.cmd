@echo off
setlocal
set "NEK_SOURCE_ROOT=%~dp0.."
if not exist "%NEK_SOURCE_ROOT%\tools\genmap\obj_win\genmap.exe" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%NEK_SOURCE_ROOT%\windows\build-genmap.ps1"
  if errorlevel 1 exit /b %ERRORLEVEL%
)
"%NEK_SOURCE_ROOT%\tools\genmap\obj_win\genmap.exe" %*
exit /b %ERRORLEVEL%
