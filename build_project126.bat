@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "BUILD_RESULT=0"

echo.
echo ================================================================
echo PROJECT 126 - NeoGS / Intel 8086 core build
echo ================================================================
echo.
echo [BUILD] Starting Project126 assembly...
echo [DEBUG] Build script: tools\build_project126.ps1
echo [DEBUG] Listing: build\NEOGS.lst
echo [DEBUG] Symbol map: build\NEOGS.map
echo [DEBUG] Binary: build\x86_cpu_state.bin
echo.

if not exist "tools\build_project126.ps1" (
    echo ERROR: tools\build_project126.ps1 is missing.
    set "BUILD_RESULT=1"
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "tools\build_project126.ps1"
if errorlevel 1 (
    set "BUILD_RESULT=%ERRORLEVEL%"
    if "%BUILD_RESULT%"=="0" set "BUILD_RESULT=1"
    goto :failed
)

if not exist "build\NEOGS.lst" (
    echo ERROR: build\NEOGS.lst was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)
if not exist "build\NEOGS.map" (
    echo ERROR: build\NEOGS.map was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)
if not exist "build\x86_cpu_state.bin" (
    echo ERROR: build\x86_cpu_state.bin was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)

echo.
echo BUILD COMPLETED.
dir "build\NEOGS.lst" "build\NEOGS.map" "build\x86_cpu_state.bin"
goto :finish

:failed
echo.
echo BUILD FAILED. Exit code: %BUILD_RESULT%

:finish
echo.
echo ================================================================
echo BUILD SCRIPT FINISHED. Exit code: %BUILD_RESULT%
echo The window will remain open. Press any key to close it.
echo ================================================================
pause >nul
exit /b %BUILD_RESULT%
