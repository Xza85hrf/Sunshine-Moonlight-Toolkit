<#
.SYNOPSIS
    Sunshine Host Optimizer - Run on your DESKTOP (Host PC)
    
.DESCRIPTION
    Configures the Sunshine host for optimal streaming:
    - Sets Ethernet to Private network (fixes firewall issues)
    - Adds firewall rules for Sunshine
    - Shows optimal Sunshine settings
    
.NOTES
    MUST RUN AS ADMINISTRATOR!
    
.EXAMPLE
    # Right-click PowerShell -> Run as Administrator, then:
    powershell -ExecutionPolicy Bypass -File ".\Optimize-SunshineHost.ps1"
#>

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

try { Clear-Host } catch { }
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host "       SUNSHINE HOST OPTIMIZER                                  " -ForegroundColor Magenta
Write-Host "       Run on: Your Desktop (Host PC)                           " -ForegroundColor Magenta
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host ""

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

# ============================================================================
# 1. FIX NETWORK PROFILE
# ============================================================================

Write-Host "  Step 1: Checking Network Profile..." -ForegroundColor Yellow
Write-Host "  ------------------------------------" -ForegroundColor Gray

$ethernetProfile = Get-NetConnectionProfile -InterfaceAlias "Ethernet" -ErrorAction SilentlyContinue

if ($ethernetProfile) {
    Write-Host "    Current: $($ethernetProfile.NetworkCategory)" -ForegroundColor Gray
    
    if ($ethernetProfile.NetworkCategory -ne "Private") {
        Write-Host "    [!] Ethernet is set to '$($ethernetProfile.NetworkCategory)' - changing to Private..." -ForegroundColor Yellow
        
        try {
            Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
            Write-Host "    [OK] Ethernet set to Private" -ForegroundColor Green
        } catch {
            Write-Host "    [ERROR] Failed to change: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "    [OK] Ethernet already set to Private" -ForegroundColor Green
    }
} else {
    Write-Host "    [!] No 'Ethernet' adapter found, checking others..." -ForegroundColor Yellow
    
    Get-NetConnectionProfile | ForEach-Object {
        if ($_.InterfaceAlias -notlike "*Tailscale*" -and $_.InterfaceAlias -notlike "*Loopback*") {
            Write-Host "    Found: $($_.InterfaceAlias) = $($_.NetworkCategory)" -ForegroundColor Gray
            if ($_.NetworkCategory -eq "Public") {
                try {
                    Set-NetConnectionProfile -InterfaceAlias $_.InterfaceAlias -NetworkCategory Private
                    Write-Host "    [OK] $($_.InterfaceAlias) set to Private" -ForegroundColor Green
                } catch {
                    Write-Host "    [!] Could not change $($_.InterfaceAlias)" -ForegroundColor Yellow
                }
            }
        }
    }
}

Write-Host ""

# ============================================================================
# 2. FIREWALL RULES
# ============================================================================

Write-Host "  Step 2: Configuring Firewall Rules..." -ForegroundColor Yellow
Write-Host "  --------------------------------------" -ForegroundColor Gray

# Remove old rules first
$existingRules = Get-NetFirewallRule -DisplayName "Sunshine*" -ErrorAction SilentlyContinue
if ($existingRules) {
    Write-Host "    Removing old Sunshine rules..." -ForegroundColor Gray
    $existingRules | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

# Add TCP rule
try {
    New-NetFirewallRule -DisplayName "Sunshine TCP (HTTPS/RTSP/HTTP)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 47984,47989,47990 `
        -Action Allow `
        -Profile Any `
        -Description "Sunshine game streaming - TCP ports" | Out-Null
    Write-Host "    [OK] Sunshine TCP rule created (47984, 47989, 47990)" -ForegroundColor Green
} catch {
    Write-Host "    [ERROR] Failed to create TCP rule: $_" -ForegroundColor Red
}

# Add UDP rule
try {
    New-NetFirewallRule -DisplayName "Sunshine UDP (Video/Audio/Control)" `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort 47998,47999,48000,48010 `
        -Action Allow `
        -Profile Any `
        -Description "Sunshine game streaming - UDP ports" | Out-Null
    Write-Host "    [OK] Sunshine UDP rule created (47998-48010)" -ForegroundColor Green
} catch {
    Write-Host "    [ERROR] Failed to create UDP rule: $_" -ForegroundColor Red
}

Write-Host ""

# ============================================================================
# 3. SHOW IPs
# ============================================================================

Write-Host "  Step 3: Your Host IPs..." -ForegroundColor Yellow
Write-Host "  -------------------------" -ForegroundColor Gray

$lanIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.*" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress
$tailscaleIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "100.*" } | Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "    LAN IP (home use):      $lanIP" -ForegroundColor Cyan
Write-Host "    Tailscale IP (remote):  $tailscaleIP" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# 4. CHECK SUNSHINE STATUS
# ============================================================================

Write-Host "  Step 4: Sunshine Status..." -ForegroundColor Yellow
Write-Host "  ---------------------------" -ForegroundColor Gray

$sunshineProcess = Get-Process -Name "sunshine" -ErrorAction SilentlyContinue
if ($sunshineProcess) {
    Write-Host "    [OK] Sunshine is running" -ForegroundColor Green
} else {
    Write-Host "    [!] Sunshine is NOT running - start it!" -ForegroundColor Yellow
}

# Check ports
$port47984 = Get-NetTCPConnection -LocalPort 47984 -ErrorAction SilentlyContinue
$port47989 = Get-NetTCPConnection -LocalPort 47989 -ErrorAction SilentlyContinue

if ($port47984 -or $port47989) {
    Write-Host "    [OK] Sunshine ports are listening" -ForegroundColor Green
} else {
    Write-Host "    [!] Sunshine ports not detected - is Sunshine running?" -ForegroundColor Yellow
}

Write-Host ""

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "  =============================================================" -ForegroundColor Green
Write-Host "       OPTIMIZATION COMPLETE!                                   " -ForegroundColor Green
Write-Host "  =============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Changes made:" -ForegroundColor White
Write-Host "    [+] Ethernet network set to Private" -ForegroundColor Gray
Write-Host "    [+] Firewall rules added for Sunshine" -ForegroundColor Gray
Write-Host ""
Write-Host "  Moonlight clients should connect to:" -ForegroundColor Yellow
Write-Host "    Home/LAN:  $lanIP" -ForegroundColor Cyan
Write-Host "    Remote:    $tailscaleIP" -ForegroundColor Cyan
Write-Host ""
Write-Host "  If Sunshine isn't running, start it now!" -ForegroundColor Yellow
Write-Host ""

Write-Host "  Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
