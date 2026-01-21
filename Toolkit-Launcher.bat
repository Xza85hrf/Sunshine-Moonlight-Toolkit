@echo off
title Sunshine + Moonlight Toolkit
color 0B

:menu
cls
echo.
echo  =============================================================
echo       SUNSHINE + MOONLIGHT + TAILSCALE TOOLKIT
echo  =============================================================
echo.

REM Check if configured
if not exist "%~dp0config.json" (
    echo  [!] First time? Run Setup first to configure your IPs
    echo.
)

echo  Select an option:
echo.
echo    [0] Setup / Configure Toolkit (FIRST TIME SETUP)
echo.
echo    [1] Apply Moonlight Settings (run on LAPTOP)
echo    [2] Test Connection (run on LAPTOP)
echo    [3] Stream Monitor (run on LAPTOP)
echo    [4] Full Diagnostics (run on LAPTOP)
echo.
echo    [5] Optimize Sunshine Host (run on DESKTOP - needs Admin)
echo    [6] Fix Tailscale Stuck (needs Admin)
echo.
echo    [7] Exit
echo.
set /p choice="  Enter choice (0-7): "

if "%choice%"=="0" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Setup-Toolkit.ps1"
    goto menu
)
if "%choice%"=="1" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Apply-OptimalSettings.ps1"
    goto menu
)
if "%choice%"=="2" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Test-Connection.ps1"
    goto menu
)
if "%choice%"=="3" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Stream-Monitor.ps1"
    goto menu
)
if "%choice%"=="4" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Sunshine-Moonlight-Optimizer.ps1"
    goto menu
)
if "%choice%"=="5" (
    echo.
    echo  This requires Administrator privileges!
    echo  Right-click this script and "Run as Administrator"
    echo.
    powershell -ExecutionPolicy Bypass -File "%~dp0Optimize-SunshineHost.ps1"
    goto menu
)
if "%choice%"=="6" (
    echo.
    echo  This requires Administrator privileges!
    echo  Right-click this script and "Run as Administrator"
    echo.
    powershell -ExecutionPolicy Bypass -File "%~dp0Fix-Tailscale.ps1"
    goto menu
)
if "%choice%"=="7" (
    exit
)

echo.
echo  Invalid choice. Please try again.
pause
goto menu
