<#
.SYNOPSIS
    Fix Tailscale Stuck on "Starting..."
    
.DESCRIPTION
    Fixes the common issue where Tailscale shows "Starting..." but never connects.
    - Stops Tailscale service
    - Backs up and removes corrupted state
    - Restarts Tailscale
    - Launches for re-authentication
    
.NOTES
    MUST RUN AS ADMINISTRATOR!
    You will need to log in to Tailscale again after running this.
    
.EXAMPLE
    # Right-click PowerShell -> Run as Administrator, then:
    powershell -ExecutionPolicy Bypass -File ".\Fix-Tailscale.ps1"
#>

Clear-Host
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host "       TAILSCALE 'STARTING...' FIX                              " -ForegroundColor Cyan
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "  [ERROR] This script must run as ADMINISTRATOR!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  How to run:" -ForegroundColor Yellow
    Write-Host "    1. Right-click PowerShell" -ForegroundColor Gray
    Write-Host "    2. Select 'Run as Administrator'" -ForegroundColor Gray
    Write-Host "    3. Run this script again" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "  [OK] Running as Administrator" -ForegroundColor Green
Write-Host ""

$tailscaleDataPath = "C:\ProgramData\Tailscale"
$backupPath = "C:\ProgramData\Tailscale.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Step 1: Stop Tailscale
Write-Host "  [1/4] Stopping Tailscale..." -ForegroundColor Yellow

Get-Process -Name "tailscale*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$service = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -eq "Running") {
        Stop-Service -Name "Tailscale" -Force
        Write-Host "        Service stopped" -ForegroundColor Green
    } else {
        Write-Host "        Service was not running" -ForegroundColor Gray
    }
} else {
    Write-Host "  [ERROR] Tailscale service not found!" -ForegroundColor Red
    Write-Host "  Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Start-Sleep -Seconds 2

# Step 2: Backup state
Write-Host "  [2/4] Backing up Tailscale state..." -ForegroundColor Yellow

if (Test-Path $tailscaleDataPath) {
    try {
        Rename-Item -Path $tailscaleDataPath -NewName $backupPath -Force
        Write-Host "        Backed up to: $backupPath" -ForegroundColor Green
    } catch {
        Write-Host "        Trying to delete instead..." -ForegroundColor Yellow
        try {
            Remove-Item -Path $tailscaleDataPath -Recurse -Force
            Write-Host "        State folder removed" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Could not remove state folder" -ForegroundColor Red
            Write-Host "        Please manually delete: $tailscaleDataPath" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "        No state folder found (OK)" -ForegroundColor Gray
}

# Step 3: Start service
Write-Host "  [3/4] Starting Tailscale service..." -ForegroundColor Yellow

try {
    Start-Service -Name "Tailscale"
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name "Tailscale"
    if ($service.Status -eq "Running") {
        Write-Host "        Service started" -ForegroundColor Green
    } else {
        Write-Host "        Service status: $($service.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [ERROR] Could not start service: $_" -ForegroundColor Red
}

# Step 4: Launch Tailscale
Write-Host "  [4/4] Launching Tailscale..." -ForegroundColor Yellow

$tailscaleExe = "C:\Program Files\Tailscale\tailscale-ipn.exe"
if (Test-Path $tailscaleExe) {
    Start-Process -FilePath $tailscaleExe
    Write-Host "        Tailscale launched" -ForegroundColor Green
} else {
    Write-Host "        Please launch Tailscale manually" -ForegroundColor Yellow
}

# Done
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Green
Write-Host "       FIX COMPLETE!                                            " -ForegroundColor Green
Write-Host "  =============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "    1. A browser window should open for Tailscale login" -ForegroundColor White
Write-Host "    2. Log in to your Tailscale account" -ForegroundColor White
Write-Host "    3. Tailscale should now connect properly" -ForegroundColor White
Write-Host ""
Write-Host "  NOTE: You may need to remove the old device from:" -ForegroundColor Gray
Write-Host "        https://login.tailscale.com/admin/machines" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Backup saved to: $backupPath" -ForegroundColor Gray
Write-Host ""

Write-Host "  Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
