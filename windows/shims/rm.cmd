@echo off
if "%~1"=="" exit /b 0
:again
if "%~1"=="" exit /b 0
del /Q "%~1" >nul 2>nul
if errorlevel 1 exit /b %ERRORLEVEL%
shift
goto again
