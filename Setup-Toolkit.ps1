<#
.SYNOPSIS
    Sunshine-Moonlight-Toolkit Setup Wizard

.DESCRIPTION
    Interactive setup wizard to configure the toolkit for your network.
    Run this script before using other tools in the toolkit.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ".\Setup-Toolkit.ps1"
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$ConfigPath = Join-Path $PSScriptRoot "config.json"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Banner {
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host "       SUNSHINE-MOONLIGHT-TOOLKIT SETUP WIZARD                  " -ForegroundColor Cyan
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([int]$Step, [int]$Total, [string]$Title)
    Write-Host ""
    Write-Host "  Step $Step of $Total : $Title" -ForegroundColor Yellow
    Write-Host "  $("-" * 50)" -ForegroundColor Gray
}

function Test-ValidIP {
    param([string]$IP)

    if ([string]::IsNullOrWhiteSpace($IP)) {
        return $false
    }

    try {
        $result = [System.Net.IPAddress]::TryParse($IP, [ref]$null)
        return $result
    } catch {
        return $false
    }
}

function Get-UserIP {
    param(
        [string]$Prompt,
        [string]$Example,
        [bool]$Required = $true,
        [string]$Default = ""
    )

    while ($true) {
        Write-Host ""
        Write-Host "  $Prompt" -ForegroundColor White

        if ($Example) {
            Write-Host "  Example: $Example" -ForegroundColor Gray
        }

        if (-not $Required) {
            Write-Host "  (Press Enter to skip)" -ForegroundColor DarkGray
        }

        if ($Default) {
            $input = Read-Host "  Enter IP [$Default]"
            if ([string]::IsNullOrWhiteSpace($input)) {
                $input = $Default
            }
        } else {
            $input = Read-Host "  Enter IP"
        }

        if ([string]::IsNullOrWhiteSpace($input)) {
            if (-not $Required) {
                return ""
            }
            Write-Host "  [!] This field is required." -ForegroundColor Yellow
            continue
        }

        if (Test-ValidIP $input) {
            # Test connectivity
            Write-Host "  Testing connectivity..." -ForegroundColor Gray
            $reachable = Test-Connection -ComputerName $input -Count 1 -Quiet -ErrorAction SilentlyContinue

            if ($reachable) {
                Write-Host "  [OK] $input is reachable!" -ForegroundColor Green
            } else {
                Write-Host "  [!] $input is not reachable (this may be OK if the device is off)" -ForegroundColor Yellow
            }

            return $input
        } else {
            Write-Host "  [!] Invalid IP address format. Please try again." -ForegroundColor Red
        }
    }
}

function Get-NetworkInterfaces {
    $interfaces = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object Name, InterfaceDescription, MacAddress
    return $interfaces
}

# ============================================================================
# MAIN SETUP
# ============================================================================

Write-Banner

Write-Host "  Welcome! This wizard will help you configure the toolkit" -ForegroundColor White
Write-Host "  for your Sunshine + Moonlight streaming setup." -ForegroundColor White
Write-Host ""
Write-Host "  You will need:" -ForegroundColor Gray
Write-Host "    - Your Sunshine host PC's LAN IP address" -ForegroundColor Gray
Write-Host "    - Your Sunshine host PC's Tailscale IP (if using Tailscale)" -ForegroundColor Gray
Write-Host ""

$continue = Read-Host "  Press Enter to continue or 'Q' to quit"
if ($continue -eq "Q" -or $continue -eq "q") {
    exit 0
}

# Load existing config or create new
$config = $null
if (Test-Path $ConfigPath) {
    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-Host ""
        Write-Host "  [*] Found existing configuration. You can update it." -ForegroundColor Cyan
    } catch {
        $config = $null
    }
}

if (-not $config) {
    $config = [PSCustomObject]@{
        host = [PSCustomObject]@{
            lan_ip = ""
            tailscale_ip = ""
            name = "Desktop"
        }
        client = [PSCustomObject]@{
            lan_ip = ""
            name = "Laptop"
        }
        network = [PSCustomObject]@{
            interface_name = "Ethernet"
            description = ""
        }
        preferences = [PSCustomObject]@{
            default_profile = "Ultra"
            auto_detect_connection = $true
            enable_logging = $false
        }
        configured = $false
    }
}

$totalSteps = 5

# ============================================================================
# STEP 1: Host LAN IP
# ============================================================================

Write-Step -Step 1 -Total $totalSteps -Title "Sunshine Host LAN IP"

Write-Host ""
Write-Host "  Enter the LOCAL/LAN IP address of your Sunshine host PC." -ForegroundColor White
Write-Host "  This is typically something like 192.168.x.x or 10.0.x.x" -ForegroundColor Gray

# Try to detect current network
$localIPs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" }
if ($localIPs) {
    $subnet = ($localIPs | Select-Object -First 1).IPAddress -replace "\.\d+$", ".x"
    Write-Host "  Your network appears to be: $subnet" -ForegroundColor DarkGray
}

$defaultLAN = if ($config.host.lan_ip) { $config.host.lan_ip } else { "" }
$config.host.lan_ip = Get-UserIP -Prompt "Sunshine Host LAN IP:" -Example "192.168.1.100" -Required $true -Default $defaultLAN

# ============================================================================
# STEP 2: Host Tailscale IP (Optional)
# ============================================================================

Write-Step -Step 2 -Total $totalSteps -Title "Sunshine Host Tailscale IP (Optional)"

Write-Host ""
Write-Host "  If you use Tailscale for remote streaming, enter the" -ForegroundColor White
Write-Host "  Tailscale IP of your Sunshine host PC." -ForegroundColor White
Write-Host "  Tailscale IPs start with 100.x.x.x" -ForegroundColor Gray

# Check if Tailscale is installed
$tailscaleInstalled = Get-Command "tailscale" -ErrorAction SilentlyContinue
if ($tailscaleInstalled) {
    Write-Host "  [*] Tailscale detected on this machine" -ForegroundColor Cyan
}

$defaultTS = if ($config.host.tailscale_ip) { $config.host.tailscale_ip } else { "" }
$config.host.tailscale_ip = Get-UserIP -Prompt "Sunshine Host Tailscale IP:" -Example "100.64.0.1" -Required $false -Default $defaultTS

# ============================================================================
# STEP 3: Network Interface
# ============================================================================

Write-Step -Step 3 -Total $totalSteps -Title "Network Interface"

Write-Host ""
Write-Host "  Select your primary network interface for streaming." -ForegroundColor White
Write-Host ""

$interfaces = Get-NetworkInterfaces
$i = 1
$interfaceMap = @{}

foreach ($iface in $interfaces) {
    $interfaceMap[$i] = $iface.Name
    $marker = if ($iface.Name -eq "Ethernet") { " [Recommended]" } else { "" }
    Write-Host "    [$i] $($iface.Name)$marker" -ForegroundColor White
    Write-Host "        $($iface.InterfaceDescription)" -ForegroundColor Gray
    $i++
}

Write-Host ""
$defaultIdx = ($interfaceMap.GetEnumerator() | Where-Object { $_.Value -eq "Ethernet" } | Select-Object -First 1).Key
if (-not $defaultIdx) { $defaultIdx = 1 }

$choice = Read-Host "  Select interface (1-$($interfaces.Count)) [$defaultIdx]"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $defaultIdx }

if ($interfaceMap.ContainsKey([int]$choice)) {
    $config.network.interface_name = $interfaceMap[[int]$choice]
    Write-Host "  [OK] Selected: $($config.network.interface_name)" -ForegroundColor Green
} else {
    $config.network.interface_name = "Ethernet"
    Write-Host "  [*] Using default: Ethernet" -ForegroundColor Yellow
}

# ============================================================================
# STEP 4: Default Streaming Profile
# ============================================================================

Write-Step -Step 4 -Total $totalSteps -Title "Default Streaming Profile"

Write-Host ""
Write-Host "  Select your default streaming profile:" -ForegroundColor White
Write-Host ""
Write-Host "    [1] Performance  - 720p/60fps @ 20 Mbps (older hardware/testing)" -ForegroundColor White
Write-Host "    [2] Balanced     - 1080p/60fps @ 50 Mbps (general gaming)" -ForegroundColor White
Write-Host "    [3] Quality      - 1080p/60fps @ 80 Mbps (visual priority)" -ForegroundColor Green
Write-Host "    [4] Ultra        - 1080p/120fps @ 100 Mbps (LAN - best quality) [Recommended]" -ForegroundColor Green
Write-Host "    [5] Competitive  - 1080p/120fps @ 60 Mbps (FPS games, low latency)" -ForegroundColor White
Write-Host ""

$profileChoice = Read-Host "  Select profile (1-5) [4]"
if ([string]::IsNullOrWhiteSpace($profileChoice)) { $profileChoice = "4" }

$config.preferences.default_profile = switch ($profileChoice) {
    "1" { "Performance" }
    "2" { "Balanced" }
    "3" { "Quality" }
    "4" { "Ultra" }
    "5" { "Competitive" }
    default { "Ultra" }
}

Write-Host "  [OK] Default profile: $($config.preferences.default_profile)" -ForegroundColor Green

# ============================================================================
# STEP 5: Host Name (Optional)
# ============================================================================

Write-Step -Step 5 -Total $totalSteps -Title "Host PC Name (Optional)"

Write-Host ""
Write-Host "  Give your Sunshine host PC a friendly name (for display only)." -ForegroundColor White
Write-Host ""

$defaultName = if ($config.host.name) { $config.host.name } else { "Desktop" }
$hostName = Read-Host "  Host name [$defaultName]"
if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = $defaultName }
$config.host.name = $hostName

Write-Host "  [OK] Host name: $($config.host.name)" -ForegroundColor Green

# ============================================================================
# SAVE CONFIGURATION
# ============================================================================

Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host "       CONFIGURATION SUMMARY                                    " -ForegroundColor Cyan
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Host PC ($($config.host.name)):" -ForegroundColor White
Write-Host "    LAN IP      : $($config.host.lan_ip)" -ForegroundColor Cyan
if ($config.host.tailscale_ip) {
    Write-Host "    Tailscale IP: $($config.host.tailscale_ip)" -ForegroundColor Cyan
} else {
    Write-Host "    Tailscale IP: (not configured)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  Network:" -ForegroundColor White
Write-Host "    Interface   : $($config.network.interface_name)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Preferences:" -ForegroundColor White
Write-Host "    Profile     : $($config.preferences.default_profile)" -ForegroundColor Cyan
Write-Host ""

$save = Read-Host "  Save this configuration? (Y/N) [Y]"
if ([string]::IsNullOrWhiteSpace($save) -or $save -eq "Y" -or $save -eq "y") {
    $config.configured = $true

    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Force
        Write-Host ""
        Write-Host "  =============================================================" -ForegroundColor Green
        Write-Host "       SETUP COMPLETE!                                          " -ForegroundColor Green
        Write-Host "  =============================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Configuration saved to: config.json" -ForegroundColor White
        Write-Host ""
        Write-Host "  You can now use the toolkit!" -ForegroundColor White
        Write-Host ""
        Write-Host "  Quick Start:" -ForegroundColor Yellow
        Write-Host "    - Run Toolkit-Launcher.bat for the main menu" -ForegroundColor Gray
        Write-Host "    - Run Test-Connection.ps1 to verify connectivity" -ForegroundColor Gray
        Write-Host "    - Run Apply-OptimalSettings.ps1 to configure Moonlight" -ForegroundColor Gray
        Write-Host ""
    } catch {
        Write-Host ""
        Write-Host "  [ERROR] Failed to save configuration: $_" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "  [*] Configuration not saved. Run this script again to configure." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
