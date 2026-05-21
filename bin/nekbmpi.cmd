@echo off
setlocal
set "NEK_SOURCE_ROOT=%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%NEK_SOURCE_ROOT%\windows\nekbmpi.ps1" %*
exit /b %ERRORLEVEL%
