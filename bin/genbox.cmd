@echo off
setlocal
set "NEK_SOURCE_ROOT=%~dp0.."
if not exist "%NEK_SOURCE_ROOT%\tools\genbox\obj_win\genbox.exe" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%NEK_SOURCE_ROOT%\windows\build-genbox.ps1"
  if errorlevel 1 exit /b %ERRORLEVEL%
)
"%NEK_SOURCE_ROOT%\tools\genbox\obj_win\genbox.exe" %*
exit /b %ERRORLEVEL%
