@echo off
set "NEK_SOURCE_ROOT=%~dp0.."
set "PATH=%~dp0;%PATH%"
echo NEK_SOURCE_ROOT=%NEK_SOURCE_ROOT%
echo Added to PATH for this terminal: %~dp0
echo Available commands: makenek, nek, nekmpi, nekbmpi, genmap, genbox, gmsh2nek
