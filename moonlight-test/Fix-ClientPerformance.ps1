<#
.SYNOPSIS
    Fix slow Moonlight streaming on the CLIENT laptop

.DESCRIPTION
    Fixes common causes of slow Moonlight connections:
    - Switches to High Performance power plan
    - Disables NIC power saving features (Green Ethernet, Power Saving Mode)
    - Fixes NIC link speed settings
    - Disables OS NIC power management

.NOTES
    MUST RUN AS ADMINISTRATOR!
    Run this on your LAPTOP (Moonlight client)

.EXAMPLE
    # Right-click PowerShell -> Run as Administrator, then:
    powershell -ExecutionPolicy Bypass -File ".\Fix-ClientPerformance.ps1"
#>

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Clear-Host
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host "       MOONLIGHT CLIENT PERFORMANCE FIX                         " -ForegroundColor Cyan
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $isAdmin) {
    Write-Host "  [ERROR] This script must run as ADMINISTRATOR!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  How to run:" -ForegroundColor Yellow
    Write-Host "    1. Right-click PowerShell -> 'Run as Administrator'" -ForegroundColor Gray
    Write-Host "    2. Run this script again" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "  [OK] Running as Administrator" -ForegroundColor Green
Write-Host ""

$fixCount = 0
$errorCount = 0

# ============================================================================
# 1. HIGH PERFORMANCE POWER PLAN
# ============================================================================

Write-Host "  Step 1: Power Plan..." -ForegroundColor Yellow
Write-Host "  ---------------------" -ForegroundColor Gray

try {
    $currentPlan = powercfg /getactivescheme
    Write-Host "    Current: $currentPlan" -ForegroundColor Gray

    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    Write-Host "    [OK] Switched to High Performance" -ForegroundColor Green
    $fixCount++
} catch {
    Write-Host "    [ERROR] Failed to change power plan: $_" -ForegroundColor Red
    $errorCount++
}

Write-Host ""

# ============================================================================
# 2. DISABLE NIC POWER SAVING FEATURES
# ============================================================================

Write-Host "  Step 2: Network Adapter Optimization..." -ForegroundColor Yellow
Write-Host "  -----------------------------------------" -ForegroundColor Gray

# Find the primary network adapter (not virtual, not Tailscale)
$primaryAdapter = Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and
    $_.Name -notlike '*WSL*' -and
    $_.Name -notlike '*vEthernet*' -and
    $_.Name -notlike '*Tailscale*' -and
    $_.Name -notlike '*Loopback*'
} | Select-Object -First 1

if ($primaryAdapter) {
    $adapterName = $primaryAdapter.Name
    Write-Host "    Found adapter: $adapterName ($($primaryAdapter.InterfaceDescription))" -ForegroundColor Gray
    Write-Host "    Link Speed: $($primaryAdapter.LinkSpeed)" -ForegroundColor Gray
    Write-Host ""

    # Disable Green Ethernet
    try {
        Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Green Ethernet" -DisplayValue "Disabled" -ErrorAction Stop
        Write-Host "    [OK] Green Ethernet -> Disabled" -ForegroundColor Green
        $fixCount++
    } catch {
        Write-Host "    [SKIP] Green Ethernet (not available or already disabled)" -ForegroundColor Gray
    }

    # Disable Power Saving Mode
    try {
        Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Power Saving Mode" -DisplayValue "Disabled" -ErrorAction Stop
        Write-Host "    [OK] Power Saving Mode -> Disabled" -ForegroundColor Green
        $fixCount++
    } catch {
        Write-Host "    [SKIP] Power Saving Mode (not available or already disabled)" -ForegroundColor Gray
    }

    # Fix WOL Shutdown Link Speed
    try {
        Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "WOL & Shutdown Link Speed" -DisplayValue "Not Speed Down" -ErrorAction Stop
        Write-Host "    [OK] WOL & Shutdown Link Speed -> Not Speed Down" -ForegroundColor Green
        $fixCount++
    } catch {
        Write-Host "    [SKIP] WOL & Shutdown Link Speed (not available)" -ForegroundColor Gray
    }

    # Disable Energy-Efficient Ethernet (if not already)
    try {
        $eee = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Energy-Efficient Ethernet" -ErrorAction SilentlyContinue
        if ($eee -and $eee.DisplayValue -ne "Disabled") {
            Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Energy-Efficient Ethernet" -DisplayValue "Disabled" -ErrorAction Stop
            Write-Host "    [OK] Energy-Efficient Ethernet -> Disabled" -ForegroundColor Green
            $fixCount++
        } else {
            Write-Host "    [OK] Energy-Efficient Ethernet already Disabled" -ForegroundColor Green
        }
    } catch {
        Write-Host "    [SKIP] Energy-Efficient Ethernet (not available)" -ForegroundColor Gray
    }

    # Disable Advanced EEE (if not already)
    try {
        $aeee = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Advanced EEE" -ErrorAction SilentlyContinue
        if ($aeee -and $aeee.DisplayValue -ne "Disabled") {
            Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Advanced EEE" -DisplayValue "Disabled" -ErrorAction Stop
            Write-Host "    [OK] Advanced EEE -> Disabled" -ForegroundColor Green
            $fixCount++
        } else {
            Write-Host "    [OK] Advanced EEE already Disabled" -ForegroundColor Green
        }
    } catch {
        Write-Host "    [SKIP] Advanced EEE (not available)" -ForegroundColor Gray
    }

    # Disable interrupt moderation for lower latency (optional but helps streaming)
    try {
        $im = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Interrupt Moderation" -ErrorAction SilentlyContinue
        if ($im) {
            Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Interrupt Moderation" -DisplayValue "Disabled" -ErrorAction Stop
            Write-Host "    [OK] Interrupt Moderation -> Disabled (lower latency)" -ForegroundColor Green
            $fixCount++
        }
    } catch {
        Write-Host "    [SKIP] Interrupt Moderation (not available)" -ForegroundColor Gray
    }

} else {
    Write-Host "    [!] No primary network adapter found" -ForegroundColor Yellow
    $errorCount++
}

Write-Host ""

# ============================================================================
# 3. DISABLE OS NIC POWER MANAGEMENT
# ============================================================================

Write-Host "  Step 3: OS Power Management for NIC..." -ForegroundColor Yellow
Write-Host "  ----------------------------------------" -ForegroundColor Gray

if ($primaryAdapter) {
    try {
        # Disable "Allow the computer to turn off this device to save power"
        $adapterClass = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
        Get-ChildItem $adapterClass -ErrorAction SilentlyContinue | ForEach-Object {
            $driverDesc = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DriverDesc
            if ($driverDesc -eq $primaryAdapter.InterfaceDescription) {
                Set-ItemProperty $_.PSPath -Name "PnPCapabilities" -Value 24 -Type DWord -ErrorAction Stop
                Write-Host "    [OK] Disabled 'Allow computer to turn off NIC to save power'" -ForegroundColor Green
                $fixCount++
            }
        }
    } catch {
        Write-Host "    [!] Could not modify registry: $_" -ForegroundColor Yellow
    }
}

Write-Host ""

# ============================================================================
# 4. DISABLE NAGLE'S ALGORITHM (reduces input lag)
# ============================================================================

Write-Host "  Step 4: TCP Optimization (Nagle's Algorithm)..." -ForegroundColor Yellow
Write-Host "  -------------------------------------------------" -ForegroundColor Gray

try {
    $tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    Get-ChildItem $tcpParams -ErrorAction SilentlyContinue | ForEach-Object {
        $ipAddr = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).IPAddress
        $dhcpAddr = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DhcpIPAddress
        if ($ipAddr -or $dhcpAddr) {
            Set-ItemProperty $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    Write-Host "    [OK] Nagle's Algorithm disabled (reduces input lag)" -ForegroundColor Green
    $fixCount++
} catch {
    Write-Host "    [!] Could not modify TCP settings: $_" -ForegroundColor Yellow
}

Write-Host ""

# ============================================================================
# 5. CHECK FOR COMMON ISSUES
# ============================================================================

Write-Host "  Step 5: Checking for common issues..." -ForegroundColor Yellow
Write-Host "  ----------------------------------------" -ForegroundColor Gray

# Check if WiFi is also connected (dual-homing can cause issues)
$wifiAdapter = Get-NetAdapter | Where-Object { $_.Name -like '*Wi-Fi*' -and $_.Status -eq 'Up' }
if ($wifiAdapter) {
    Write-Host "    [!] WiFi is also active!" -ForegroundColor Yellow
    Write-Host "        If on Ethernet, disable WiFi for better streaming" -ForegroundColor Yellow
    Write-Host ""
}

# Check for VPN software that might interfere
$vpnProcesses = Get-Process -Name "*vpn*","*wireguard*","*openvpn*" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "Tailscale" }
if ($vpnProcesses) {
    Write-Host "    [!] VPN software detected: $($vpnProcesses.Name -join ', ')" -ForegroundColor Yellow
    Write-Host "        VPNs can add latency to your stream" -ForegroundColor Yellow
    Write-Host ""
}

# Check DNS resolution speed
try {
    $dnsStart = Get-Date
    [System.Net.Dns]::GetHostEntry("google.com") | Out-Null
    $dnsTime = ((Get-Date) - $dnsStart).TotalMilliseconds
    if ($dnsTime -gt 100) {
        Write-Host "    [!] DNS resolution slow: ${dnsTime}ms" -ForegroundColor Yellow
    } else {
        Write-Host "    [OK] DNS resolution: ${dnsTime}ms" -ForegroundColor Green
    }
} catch {
    Write-Host "    [!] DNS resolution failed" -ForegroundColor Red
}

Write-Host ""

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "  =============================================================" -ForegroundColor Green
Write-Host "       OPTIMIZATION COMPLETE!                                   " -ForegroundColor Green
Write-Host "  =============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Changes applied: $fixCount" -ForegroundColor White
if ($errorCount -gt 0) {
    Write-Host "  Errors: $errorCount" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  IMPORTANT: A REBOOT is recommended for all changes to take effect!" -ForegroundColor Yellow
Write-Host ""
Write-Host "  ALSO FIX YOUR HOST (Desktop):" -ForegroundColor Cyan
Write-Host "    1. Run these same optimizations on the Sunshine host PC" -ForegroundColor White
Write-Host "    2. Run 'Optimize-SunshineHost.ps1' as Admin on the host" -ForegroundColor White
Write-Host "    3. Make sure Sunshine is using NVENC encoder" -ForegroundColor White
Write-Host ""
Write-Host "  MOONLIGHT SETTINGS TO CHECK:" -ForegroundColor Cyan
Write-Host "    - If on LAN: Use H.265/HEVC, 60fps, 50-80 Mbps bitrate" -ForegroundColor White
Write-Host "    - If on Tailscale: Use H.264, 60fps, 20-30 Mbps bitrate" -ForegroundColor White
Write-Host "    - Enable V-Sync and Frame Pacing" -ForegroundColor White
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Gray
Write-Host ""

Write-Host "  Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
