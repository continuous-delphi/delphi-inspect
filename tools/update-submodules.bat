@echo off
cls
setlocal EnableExtensions EnableDelayedExpansion

pushd "%~dp0..\"

set "MODE=%~1"

if /I "%MODE%"==""        set "MODE=latest"
if /I "%MODE%"=="--help"  goto :usage
if /I "%MODE%"=="/?"      goto :usage

if /I not "%MODE%"=="pinned" if /I not "%MODE%"=="latest" (
    echo.
    echo ERROR: Invalid mode "%MODE%"
    goto :usage_error
)

echo.
echo  ============================================
echo  Updating git submodules v1.0
echo  Mode: %MODE%
echo  ============================================
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: git.exe was not found in PATH
    goto :failed
)

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: This script must be run from inside a git working tree
    goto :failed
)

echo Syncing submodule URLs from .gitmodules...
git submodule sync --recursive
if errorlevel 1 (
    echo.
    echo ERROR: git submodule sync failed
    goto :failed
)

if /I "%MODE%"=="pinned" goto :mode_pinned
if /I "%MODE%"=="latest" goto :mode_latest

goto :usage_error

:mode_pinned
echo.
echo Checking out submodules to commits recorded by the parent repository...
git submodule update --init --recursive
if errorlevel 1 (
    echo.
    echo ERROR: pinned submodule update failed
    goto :failed
)

echo.
echo Submodules are now checked out to the commits recorded by the parent repository.
goto :show_status

:mode_latest
echo.
echo Fetching latest commits for tracked submodule branches...
git submodule update --init --recursive --remote
if errorlevel 1 (
    echo.
    echo ERROR: remote submodule update failed
    goto :failed
)

echo.
echo Submodules were advanced to the latest commit on their tracked remote branches.
echo NOTE: If any submodule SHA changed, commit the updated submodule pointers in the parent repository.
goto :show_status

:show_status
echo.
echo Current submodule status:
git submodule status --recursive
if errorlevel 1 (
    echo.
    echo WARNING: Unable to display submodule status
)

goto :success

:usage
echo.
echo Usage:
echo   updatesubmodules.bat [latest^pinned]
echo.
echo Modes:
echo   pinned   Checkout each submodule to the exact commit recorded by the parent repo
echo   latest   Update each submodule to the latest commit on its tracked remote branch
echo.
echo Examples:
echo   updatesubmodules.bat
echo   updatesubmodules.bat latest
echo   updatesubmodules.bat pinned
echo.
popd
endlocal
exit /b 0

:usage_error
echo.
echo Usage:
echo   updatesubmodules.bat [pinned^|latest]
echo.
popd
endlocal
pause
exit /b 1

:failed
popd
endlocal
echo.
echo  -----------------------------------------------
echo  -         Update finished WITH ERRORS         -
echo  -----------------------------------------------
pause
exit /b 1

:success
popd
endlocal
echo.
echo  ------------------------------------------------
echo  -      Submodule operation completed OK       -
echo  ------------------------------------------------
pause
exit /b 0