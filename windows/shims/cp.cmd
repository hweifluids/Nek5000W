@echo off
if "%~2"=="" (
  echo Usage: cp source destination
  exit /b 2
)
copy /Y "%~1" "%~2" >nul
exit /b %ERRORLEVEL%
