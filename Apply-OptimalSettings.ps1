<#
.SYNOPSIS
    Moonlight Quick Setup - Apply Optimal Settings
    
.DESCRIPTION
    One-click script to configure Moonlight with optimized settings.
    Profiles optimized for LAN connections (100+ Mbps available).
    
.PARAMETER Profile
    Choose preset: Performance, Balanced, Quality, Ultra, or Competitive
    
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ".\Apply-OptimalSettings.ps1"
    powershell -ExecutionPolicy Bypass -File ".\Apply-OptimalSettings.ps1" -Profile Ultra
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Performance", "Balanced", "Quality", "Ultra", "Competitive")]
    [string]$Profile = ""
)

$MoonlightConfigPath = "$env:LOCALAPPDATA\Moonlight Game Streaming\Moonlight Game Streaming.conf"

# Profiles optimized for LAN (100+ Mbps available)
$Profiles = @{
    Performance = @{
        width = 1280
        height = 720
        fps = 60
        bitrate = 20000
        packetsize = 1024
        vsync = "true"
        framepacing = "true"
        videodec = "auto"
        audiocfg = "auto"
        Description = "720p/60fps at 20 Mbps"
        BestFor = "Older hardware or testing"
    }
    Balanced = @{
        width = 1920
        height = 1080
        fps = 60
        bitrate = 50000
        packetsize = 1392
        vsync = "true"
        framepacing = "true"
        videodec = "auto"
        audiocfg = "auto"
        Description = "1080p/60fps at 50 Mbps"
        BestFor = "Most games, good balance"
    }
    Quality = @{
        width = 1920
        height = 1080
        fps = 60
        bitrate = 80000
        packetsize = 1392
        vsync = "true"
        framepacing = "true"
        videodec = "auto"
        audiocfg = "auto"
        Description = "1080p/60fps at 80 Mbps"
        BestFor = "Story games, visual quality priority"
    }
    Ultra = @{
        width = 1920
        height = 1080
        fps = 120
        bitrate = 100000
        packetsize = 1392
        vsync = "true"
        framepacing = "true"
        videodec = "auto"
        audiocfg = "auto"
        Description = "1080p/120fps at 100 Mbps"
        BestFor = "LAN connections, 120Hz displays"
    }
    Competitive = @{
        width = 1920
        height = 1080
        fps = 120
        bitrate = 60000
        packetsize = 1024
        vsync = "false"
        framepacing = "false"
        videodec = "auto"
        audiocfg = "auto"
        Description = "1080p/120fps at 60 Mbps (V-Sync OFF)"
        BestFor = "FPS games, lowest input lag"
    }
}

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host "       MOONLIGHT QUICK SETUP - LAN OPTIMIZED                    " -ForegroundColor Cyan
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-CurrentSettings {
    Write-Host "  Current Moonlight Settings:" -ForegroundColor White
    Write-Host "  ----------------------------" -ForegroundColor Gray
    
    if (Test-Path $MoonlightConfigPath) {
        $config = @{}
        Get-Content $MoonlightConfigPath | ForEach-Object {
            if ($_ -match "^([^=]+)=(.*)$") {
                $config[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        
        if ($config.Count -gt 0) {
            $width = if ($config["width"]) { $config["width"] } else { "1920" }
            $height = if ($config["height"]) { $config["height"] } else { "1080" }
            $fps = if ($config["fps"]) { $config["fps"] } else { "60" }
            $bitrate = if ($config["bitrate"]) { [int]$config["bitrate"] / 1000 } else { "Auto" }
            
            Write-Host "    Resolution   : ${width}x${height}" -ForegroundColor Gray
            Write-Host "    FPS          : $fps" -ForegroundColor Gray
            Write-Host "    Bitrate      : $bitrate Mbps" -ForegroundColor Gray
        } else {
            Write-Host "    Using Moonlight defaults" -ForegroundColor Gray
        }
    } else {
        Write-Host "    No config file found (using defaults)" -ForegroundColor Gray
    }
    Write-Host ""
}

function Show-ProfileMenu {
    Write-Host "  Available Profiles:" -ForegroundColor Yellow
    Write-Host ""
    
    $i = 1
    foreach ($name in @("Performance", "Balanced", "Quality", "Ultra", "Competitive")) {
        $p = $Profiles[$name]
        $bitrateMbps = $p.bitrate / 1000
        
        $color = if ($name -eq "Ultra") { "Green" } else { "White" }
        $marker = if ($name -eq "Ultra") { " [RECOMMENDED FOR LAN]" } else { "" }
        
        Write-Host "    [$i] $name$marker" -ForegroundColor $color
        Write-Host "        $($p.Description)" -ForegroundColor Gray
        Write-Host "        Best for: $($p.BestFor)" -ForegroundColor DarkGray
        Write-Host ""
        $i++
    }
}

function Apply-Profile {
    param([string]$ProfileName)
    
    $profileData = $Profiles[$ProfileName]
    
    # Check if Moonlight is running
    $moonlightRunning = Get-Process -Name "Moonlight" -ErrorAction SilentlyContinue
    if ($moonlightRunning) {
        Write-Host ""
        Write-Host "  [!] Moonlight is running - close it and reopen after applying settings" -ForegroundColor Yellow
        Write-Host ""
    }
    
    # Ensure config directory exists
    $configDir = Split-Path $MoonlightConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    # Backup existing config
    if (Test-Path $MoonlightConfigPath) {
        $backupDir = Join-Path $configDir "Backups"
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        Copy-Item $MoonlightConfigPath (Join-Path $backupDir "backup_$timestamp.conf") -Force
        Write-Host "  [OK] Config backed up" -ForegroundColor Green
    }
    
    # Read existing config
    $config = @{}
    if (Test-Path $MoonlightConfigPath) {
        Get-Content $MoonlightConfigPath | ForEach-Object {
            if ($_ -match "^([^=]+)=(.*)$") {
                $config[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }
    
    # Apply profile settings
    foreach ($key in $profileData.Keys) {
        if ($key -eq "Description" -or $key -eq "BestFor") { continue }
        $config[$key] = $profileData[$key]
    }
    
    # Write config
    $config.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Set-Content $MoonlightConfigPath -Force
    
    return $true
}

# ============================================================================
# MAIN
# ============================================================================

Show-Banner
Show-CurrentSettings

if (-not $Profile) {
    Show-ProfileMenu
    
    Write-Host "  Your LAN supports 100+ Mbps - use Ultra for best quality!" -ForegroundColor Cyan
    Write-Host ""
    
    $choice = Read-Host "  Select profile (1-5) or Enter for Ultra"
    
    $Profile = switch ($choice) {
        "1" { "Performance" }
        "2" { "Balanced" }
        "3" { "Quality" }
        "4" { "Ultra" }
        "5" { "Competitive" }
        default { "Ultra" }
    }
}

Write-Host ""
Write-Host "  Applying '$Profile' profile..." -ForegroundColor Cyan

if (Apply-Profile -ProfileName $Profile) {
    $p = $Profiles[$Profile]
    $bitrateMbps = $p.bitrate / 1000
    
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Green
    Write-Host "       SETTINGS APPLIED!                                        " -ForegroundColor Green
    Write-Host "  =============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "    Resolution : $($p.width)x$($p.height)" -ForegroundColor White
    Write-Host "    FPS        : $($p.fps)" -ForegroundColor White
    Write-Host "    Bitrate    : $bitrateMbps Mbps" -ForegroundColor White
    Write-Host "    V-Sync     : $($p.vsync)" -ForegroundColor White
    Write-Host ""
    Write-Host "  NEXT: Close and reopen Moonlight, then connect to your host:" -ForegroundColor Yellow
    Write-Host "        LAN IP: Your host's local IP (when at home)" -ForegroundColor Cyan
    Write-Host "        Tailscale: Your host's Tailscale IP (when remote)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  NOTE: Ignore 'slow connection' warnings - your LAN is fine!" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
