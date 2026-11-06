@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "BUILD_RESULT=0"

echo.
echo ================================================================
echo PROJECT 126 - ATM / NeoGS / TR-DOS disk build
echo ================================================================
echo.
echo [BUILD] Starting complete Project126 build...
echo [DEBUG] Build script: tools\build_project126.ps1
echo [DEBUG] TR-DOS image: disk_A.trd
echo [DEBUG] Build copy: build\disk_A.trd
echo.

if not exist "tools\build_project126.ps1" (
    echo ERROR: tools\build_project126.ps1 is missing.
    set "BUILD_RESULT=1"
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "tools\build_project126.ps1"
if errorlevel 1 goto :failed

for %%F in ("build\NEOGS.lst" "build\NEOGS.map" "build\x86_cpu_state.bin" "build\ATM.lst" "build\ATM.map" "build\ATM_IPC.bin" "build\ATM_DISK.lst" "build\ATM_DISK.map" "disk_A.trd" "build\disk_A.trd") do (
    if not exist "%%~F" (
        echo ERROR: Required build output missing: %%~F
        set "BUILD_RESULT=1"
        goto :finish
    )
)

echo.
echo BUILD COMPLETED.
dir "disk_A.trd" "build\disk_A.trd" "build\ATM_DISK.lst" "build\ATM_DISK.map"
goto :finish

:failed
set "BUILD_RESULT=%ERRORLEVEL%"
if "%BUILD_RESULT%"=="0" set "BUILD_RESULT=1"
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
