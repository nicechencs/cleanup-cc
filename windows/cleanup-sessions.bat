@echo off
REM ========================================
REM Claude Code Cache Cleanup Tool Launcher
REM ========================================
REM
REM Usage:
REM   Double-click this file to run
REM   All options will be selected interactively
REM
REM ========================================

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%cleanup-sessions.ps1"

if not exist "%PS_SCRIPT%" (
    echo Error: PowerShell script not found
    echo Path: %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

endlocal
