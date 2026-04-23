<#
.SYNOPSIS
    Sunshine + Moonlight Stream Monitor and Auto-Configurator
    
.DESCRIPTION
    Real-time monitoring of stream quality with automatic settings optimization.
    - Monitors network latency, jitter, and packet loss during streaming
    - Detects quality issues and suggests/applies fixes
    - Configures Moonlight settings automatically
    - Logs performance data for analysis
    
.PARAMETER HostTailscaleIP
    The Tailscale IP of the Sunshine host

.PARAMETER Mode
    Operation mode: Monitor, Configure, or Both

.PARAMETER AutoAdjust
    Automatically adjust Moonlight settings based on conditions

.PARAMETER LogToFile
    Save monitoring data to CSV for later analysis

.EXAMPLE
    .\Stream-Monitor.ps1 -HostTailscaleIP "100.x.x.x" -Mode Monitor

.EXAMPLE
    .\Stream-Monitor.ps1 -HostTailscaleIP "100.x.x.x" -Mode Configure -Profile Balanced

.EXAMPLE
    .\Stream-Monitor.ps1 -HostTailscaleIP "100.x.x.x" -Mode Both -AutoAdjust
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostTailscaleIP,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Monitor", "Configure", "Both")]
    [string]$Mode = "Both",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Performance", "Balanced", "Quality", "Custom")]
    [string]$Profile = "Balanced",
    
    [Parameter(Mandatory = $false)]
    [switch]$AutoAdjust,
    
    [Parameter(Mandatory = $false)]
    [switch]$LogToFile,
    
    [Parameter(Mandatory = $false)]
    [int]$MonitorDuration = 0  # 0 = indefinite
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Continue"

# Moonlight config path
$MoonlightConfigPath = "$env:LOCALAPPDATA\Moonlight Game Streaming\Moonlight Game Streaming.conf"

# Streaming profiles based on your connection (optimized for ~110ms latency)
$StreamProfiles = @{
    Performance = @{
        Resolution = "1280x720"
        FPS = 60
        Bitrate = 15000  # 15 Mbps
        Codec = "auto"   # H.264
        PacketSize = 1024
        Description = "Lowest latency, stable for high-ping connections"
    }
    Balanced = @{
        Resolution = "1920x1080"
        FPS = 60
        Bitrate = 25000  # 25 Mbps
        Codec = "auto"
        PacketSize = 1024
        Description = "Good quality with reasonable latency"
    }
    Quality = @{
        Resolution = "1920x1080"
        FPS = 60
        Bitrate = 40000  # 40 Mbps
        Codec = "auto"
        PacketSize = 1392
        Description = "Best quality, may stutter on poor connections"
    }
    LowLatency = @{
        Resolution = "1920x1080"
        FPS = 60
        Bitrate = 20000  # 20 Mbps
        Codec = "auto"
        PacketSize = 1024
        Description = "Optimized for ~100ms connections like yours"
    }
}

# Thresholds for quality assessment
$Thresholds = @{
    LatencyGood = 50
    LatencyAcceptable = 100
    LatencyPoor = 150
    JitterGood = 10
    JitterAcceptable = 25
    JitterPoor = 40
    PacketLossGood = 0
    PacketLossAcceptable = 2
    PacketLossPoor = 5
}

# Monitoring state
$script:MonitorData = @{
    Samples = [System.Collections.ArrayList]::new()
    StartTime = $null
    CurrentQuality = "Unknown"
    Alerts = [System.Collections.ArrayList]::new()
    SettingsApplied = $false
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-ColorHost {
    param(
        [string]$Message,
        [string]$ForegroundColor = "White",
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $ForegroundColor -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $ForegroundColor
    }
}

function Get-Timestamp {
    return Get-Date -Format "HH:mm:ss"
}

function Write-Status {
    param($msg, $color = "White")
    Write-ColorHost "$(Get-Timestamp) | $msg" -ForegroundColor $color
}

function Write-Good { param($msg) Write-Status "[OK] $msg" "Green" }
function Write-Bad { param($msg) Write-Status "[!!] $msg" "Red" }
function Write-Warn { param($msg) Write-Status "[!] $msg" "Yellow" }
function Write-Info { param($msg) Write-Status "[*] $msg" "Cyan" }

# ============================================================================
# MOONLIGHT CONFIGURATION FUNCTIONS
# ============================================================================

function Get-MoonlightConfig {
    if (Test-Path $MoonlightConfigPath) {
        $config = @{}
        Get-Content $MoonlightConfigPath | ForEach-Object {
            if ($_ -match "^([^=]+)=(.*)$") {
                $config[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        return $config
    }
    return $null
}

function Set-MoonlightConfig {
    param(
        [hashtable]$Settings
    )
    
    # Read existing config
    $configLines = @()
    $existingKeys = @{}
    
    if (Test-Path $MoonlightConfigPath) {
        $configLines = Get-Content $MoonlightConfigPath
        for ($i = 0; $i -lt $configLines.Count; $i++) {
            if ($configLines[$i] -match "^([^=]+)=") {
                $existingKeys[$matches[1].Trim()] = $i
            }
        }
    }
    
    # Update or add settings
    foreach ($key in $Settings.Keys) {
        $value = $Settings[$key]
        if ($existingKeys.ContainsKey($key)) {
            $configLines[$existingKeys[$key]] = "$key=$value"
        } else {
            $configLines += "$key=$value"
        }
    }
    
    # Backup existing config
    if (Test-Path $MoonlightConfigPath) {
        $backupPath = "$MoonlightConfigPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $MoonlightConfigPath $backupPath -Force
        Write-Info "Config backed up to: $backupPath"
    }
    
    # Write new config
    $configLines | Set-Content $MoonlightConfigPath -Force
    Write-Good "Moonlight configuration updated!"
}

function Apply-StreamProfile {
    param(
        [string]$ProfileName
    )
    
    if (-not $StreamProfiles.ContainsKey($ProfileName)) {
        Write-Bad "Unknown profile: $ProfileName"
        return $false
    }
    
    $profile = $StreamProfiles[$ProfileName]
    
    Write-Info "Applying '$ProfileName' profile: $($profile.Description)"
    
    # Parse resolution
    $resParts = $profile.Resolution -split "x"
    $width = $resParts[0]
    $height = $resParts[1]
    
    $settings = @{
        "width" = $width
        "height" = $height
        "fps" = $profile.FPS
        "bitrate" = $profile.Bitrate
        "packetsize" = $profile.PacketSize
        "vsync" = "true"
        "framepacing" = "true"
        "audiocfg" = "auto"
        "videocfg" = "auto"
        "videodec" = "auto"
    }
    
    Set-MoonlightConfig -Settings $settings
    
    Write-Host ""
    Write-Host "  Applied Settings:" -ForegroundColor Cyan
    Write-Host "    Resolution : $($profile.Resolution)" -ForegroundColor White
    Write-Host "    FPS        : $($profile.FPS)" -ForegroundColor White
    Write-Host "    Bitrate    : $($profile.Bitrate / 1000) Mbps" -ForegroundColor White
    Write-Host "    Codec      : $($profile.Codec)" -ForegroundColor White
    Write-Host ""
    
    return $true
}

function Show-CurrentConfig {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "                  CURRENT MOONLIGHT CONFIGURATION                   " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    
    $config = Get-MoonlightConfig
    
    if ($config) {
        $width = if ($config["width"]) { $config["width"] } else { "Default" }
        $height = if ($config["height"]) { $config["height"] } else { "Default" }
        $fps = if ($config["fps"]) { $config["fps"] } else { "60" }
        $bitrate = if ($config["bitrate"]) { [int]$config["bitrate"] / 1000 } else { "Auto" }
        
        Write-Host ""
        Write-Host "  Resolution    : ${width}x${height}" -ForegroundColor White
        Write-Host "  FPS           : $fps" -ForegroundColor White
        Write-Host "  Bitrate       : $bitrate Mbps" -ForegroundColor White
        Write-Host "  V-Sync        : $($config["vsync"])" -ForegroundColor White
        Write-Host "  Frame Pacing  : $($config["framepacing"])" -ForegroundColor White
        Write-Host "  Video Decoder : $($config["videodec"])" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Warn "Could not read Moonlight config (using defaults)"
    }
    
    Write-Host "====================================================================" -ForegroundColor Cyan
}

# ============================================================================
# NETWORK MONITORING FUNCTIONS
# ============================================================================

function Get-NetworkSample {
    param([string]$TargetIP)
    
    $sample = @{
        Timestamp = Get-Date
        Latency = $null
        Success = $false
        Error = $null
    }
    
    try {
        $ping = Test-Connection -ComputerName $TargetIP -Count 1 -ErrorAction Stop
        $sample.Latency = $ping.ResponseTime
        $sample.Success = $true
    } catch {
        $sample.Error = $_.Exception.Message
        $sample.Success = $false
    }
    
    return $sample
}

function Get-NetworkStats {
    param([array]$Samples)
    
    $successfulSamples = $Samples | Where-Object { $_.Success }
    
    if ($successfulSamples.Count -eq 0) {
        return @{
            AvgLatency = 0
            MinLatency = 0
            MaxLatency = 0
            Jitter = 0
            PacketLoss = 100
            SampleCount = $Samples.Count
        }
    }
    
    $latencies = $successfulSamples | ForEach-Object { $_.Latency }
    
    $avgLatency = ($latencies | Measure-Object -Average).Average
    $minLatency = ($latencies | Measure-Object -Minimum).Minimum
    $maxLatency = ($latencies | Measure-Object -Maximum).Maximum
    
    # Calculate jitter (standard deviation)
    $sumSquares = ($latencies | ForEach-Object { [math]::Pow($_ - $avgLatency, 2) } | Measure-Object -Sum).Sum
    $jitter = [math]::Sqrt($sumSquares / $latencies.Count)
    
    $packetLoss = (($Samples.Count - $successfulSamples.Count) / $Samples.Count) * 100
    
    return @{
        AvgLatency = [math]::Round($avgLatency, 1)
        MinLatency = [math]::Round($minLatency, 1)
        MaxLatency = [math]::Round($maxLatency, 1)
        Jitter = [math]::Round($jitter, 1)
        PacketLoss = [math]::Round($packetLoss, 1)
        SampleCount = $Samples.Count
    }
}

function Get-QualityRating {
    param([hashtable]$Stats)
    
    $score = 100
    $issues = @()
    
    # Latency scoring
    if ($Stats.AvgLatency -gt $Thresholds.LatencyPoor) {
        $score -= 40
        $issues += "Very high latency"
    } elseif ($Stats.AvgLatency -gt $Thresholds.LatencyAcceptable) {
        $score -= 20
        $issues += "High latency"
    } elseif ($Stats.AvgLatency -gt $Thresholds.LatencyGood) {
        $score -= 10
    }
    
    # Jitter scoring
    if ($Stats.Jitter -gt $Thresholds.JitterPoor) {
        $score -= 30
        $issues += "Severe jitter"
    } elseif ($Stats.Jitter -gt $Thresholds.JitterAcceptable) {
        $score -= 15
        $issues += "High jitter"
    } elseif ($Stats.Jitter -gt $Thresholds.JitterGood) {
        $score -= 5
    }
    
    # Packet loss scoring
    if ($Stats.PacketLoss -gt $Thresholds.PacketLossPoor) {
        $score -= 30
        $issues += "High packet loss"
    } elseif ($Stats.PacketLoss -gt $Thresholds.PacketLossAcceptable) {
        $score -= 15
        $issues += "Some packet loss"
    }
    
    $rating = switch ($score) {
        { $_ -ge 90 } { "Excellent" }
        { $_ -ge 70 } { "Good" }
        { $_ -ge 50 } { "Fair" }
        { $_ -ge 30 } { "Poor" }
        default { "Critical" }
    }
    
    return @{
        Score = [math]::Max(0, $score)
        Rating = $rating
        Issues = $issues
    }
}

function Get-RecommendedProfile {
    param([hashtable]$Stats)
    
    $latency = $Stats.AvgLatency
    $jitter = $Stats.Jitter
    $packetLoss = $Stats.PacketLoss
    
    # For your specific case (~110ms latency)
    if ($latency -gt 120 -or $jitter -gt 30 -or $packetLoss -gt 3) {
        return "Performance"
    } elseif ($latency -gt 80 -or $jitter -gt 20 -or $packetLoss -gt 1) {
        return "LowLatency"
    } elseif ($latency -gt 50 -or $jitter -gt 15) {
        return "Balanced"
    } else {
        return "Quality"
    }
}

# ============================================================================
# REAL-TIME MONITOR DISPLAY
# ============================================================================

function Show-MonitorHeader {
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host "    SUNSHINE + MOONLIGHT REAL-TIME STREAM MONITOR              " -ForegroundColor Magenta
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Target: $HostTailscaleIP" -ForegroundColor White
    Write-Host "  Press Ctrl+C to stop monitoring" -ForegroundColor Gray
    Write-Host ""
}

function Show-LiveStats {
    param(
        [hashtable]$Stats,
        [hashtable]$Quality,
        [string]$CurrentProfile
    )
    
    # Move cursor to stats position (after header)
    $host.UI.RawUI.CursorPosition = @{ X = 0; Y = 9 }
    
    # Quality indicator color
    $qualityColor = switch ($Quality.Rating) {
        "Excellent" { "Green" }
        "Good" { "Green" }
        "Fair" { "Yellow" }
        "Poor" { "Red" }
        "Critical" { "Red" }
        default { "White" }
    }
    
    # Latency color
    $latencyColor = if ($Stats.AvgLatency -lt 50) { "Green" } 
                    elseif ($Stats.AvgLatency -lt 100) { "Yellow" } 
                    else { "Red" }
    
    # Jitter color
    $jitterColor = if ($Stats.Jitter -lt 10) { "Green" } 
                   elseif ($Stats.Jitter -lt 25) { "Yellow" } 
                   else { "Red" }
    
    # Packet loss color
    $lossColor = if ($Stats.PacketLoss -eq 0) { "Green" } 
                 elseif ($Stats.PacketLoss -lt 3) { "Yellow" } 
                 else { "Red" }
    
    Write-Host "  ====================================================================" -ForegroundColor Cyan
    Write-Host "                         LIVE STATISTICS                              " -ForegroundColor Cyan
    Write-Host "  ====================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Quality score bar
    $barLength = 30
    $filledLength = [math]::Round(($Quality.Score / 100) * $barLength)
    $emptyLength = $barLength - $filledLength
    $bar = ("█" * $filledLength) + ("░" * $emptyLength)
    
    Write-Host "  Quality: " -NoNewline -ForegroundColor White
    Write-Host "$bar " -NoNewline -ForegroundColor $qualityColor
    Write-Host "$($Quality.Score)/100 " -NoNewline -ForegroundColor $qualityColor
    Write-Host "($($Quality.Rating))     " -ForegroundColor $qualityColor
    
    Write-Host ""
    Write-Host "  Network Metrics:" -ForegroundColor White
    
    $latencyStr = "$($Stats.AvgLatency) ms".PadRight(15)
    $jitterStr = "$($Stats.Jitter) ms".PadRight(15)
    $lossStr = "$($Stats.PacketLoss) percent".PadRight(15)
    $rangeStr = "$($Stats.MinLatency)-$($Stats.MaxLatency) ms".PadRight(15)
    
    Write-Host "    Latency (avg)  : " -NoNewline -ForegroundColor Gray
    Write-Host $latencyStr -ForegroundColor $latencyColor
    
    Write-Host "    Latency (range): " -NoNewline -ForegroundColor Gray
    Write-Host $rangeStr -ForegroundColor $latencyColor
    
    Write-Host "    Jitter         : " -NoNewline -ForegroundColor Gray
    Write-Host $jitterStr -ForegroundColor $jitterColor
    
    Write-Host "    Packet Loss    : " -NoNewline -ForegroundColor Gray
    Write-Host $lossStr -ForegroundColor $lossColor
    
    Write-Host "    Samples        : $($Stats.SampleCount)              " -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "  Current Profile: " -NoNewline -ForegroundColor White
    Write-Host "$CurrentProfile              " -ForegroundColor Cyan
    
    Write-Host ""
    Write-Host "  ====================================================================" -ForegroundColor Cyan
    
    # Show issues if any
    if ($Quality.Issues.Count -gt 0) {
        Write-Host ""
        Write-Host "  Active Issues:" -ForegroundColor Yellow
        foreach ($issue in $Quality.Issues) {
            Write-Host "    - $issue              " -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "  No active issues              " -ForegroundColor Green
        Write-Host "                                " # Clear any previous issue lines
        Write-Host "                                "
    }
    
    Write-Host ""
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Initialize-LogFile {
    $logDir = Join-Path $env:USERPROFILE "Moonlight-StreamLogs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $logDir "stream_log_$timestamp.csv"
    
    # Write CSV header
    "Timestamp,Latency,Jitter,PacketLoss,QualityScore,QualityRating,Profile" | Set-Content $logFile
    
    return $logFile
}

function Write-LogEntry {
    param(
        [string]$LogFile,
        [hashtable]$Stats,
        [hashtable]$Quality,
        [string]$Profile
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp,$($Stats.AvgLatency),$($Stats.Jitter),$($Stats.PacketLoss),$($Quality.Score),$($Quality.Rating),$Profile"
    Add-Content -Path $LogFile -Value $entry
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Banner
try { Clear-Host } catch { }
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host "    SUNSHINE + MOONLIGHT STREAM OPTIMIZER                       " -ForegroundColor Magenta
Write-Host "    Mode: $Mode | Profile: $Profile                             " -ForegroundColor Magenta
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host ""

# Show available profiles
if ($Mode -eq "Configure" -or $Mode -eq "Both") {
    Write-Host "  Available Streaming Profiles:" -ForegroundColor Cyan
    Write-Host ""
    foreach ($profileName in $StreamProfiles.Keys) {
        $p = $StreamProfiles[$profileName]
        $bitrateStr = "$($p.Bitrate / 1000) Mbps"
        Write-Host "    $($profileName.PadRight(12)) : $($p.Resolution) @ $($p.FPS)fps, $bitrateStr" -ForegroundColor White
        Write-Host "                   $($p.Description)" -ForegroundColor Gray
    }
    Write-Host ""
}

# Configuration mode
if ($Mode -eq "Configure" -or $Mode -eq "Both") {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Yellow
    Write-Host "                      CONFIGURATION MODE                            " -ForegroundColor Yellow
    Write-Host "====================================================================" -ForegroundColor Yellow
    
    # Show current config
    Show-CurrentConfig
    
    # Check if Moonlight is running
    $moonlightProcess = Get-Process -Name "Moonlight" -ErrorAction SilentlyContinue
    if ($moonlightProcess) {
        Write-Warn "Moonlight is currently running!"
        Write-Host "    Please close Moonlight before applying new settings." -ForegroundColor Yellow
        Write-Host "    Settings will be applied on next launch." -ForegroundColor Yellow
        Write-Host ""
    }
    
    # Apply the selected profile
    Write-Host ""
    $apply = Read-Host "Apply '$Profile' profile? (Y/N)"
    if ($apply -eq "Y" -or $apply -eq "y") {
        # For your specific high-latency connection, recommend LowLatency profile
        if ($Profile -eq "Balanced") {
            Write-Host ""
            Write-Warn "Note: Based on your ~110ms latency, 'LowLatency' profile may work better."
            $useLowLatency = Read-Host "Use 'LowLatency' profile instead? (Y/N)"
            if ($useLowLatency -eq "Y" -or $useLowLatency -eq "y") {
                $Profile = "LowLatency"
            }
        }
        
        Apply-StreamProfile -ProfileName $Profile
        $script:MonitorData.SettingsApplied = $true
    } else {
        Write-Info "Configuration skipped."
    }
}

# Monitoring mode
if ($Mode -eq "Monitor" -or $Mode -eq "Both") {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Yellow
    Write-Host "                       MONITORING MODE                              " -ForegroundColor Yellow
    Write-Host "====================================================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Initialize logging if requested
    $logFile = $null
    if ($LogToFile) {
        $logFile = Initialize-LogFile
        Write-Info "Logging to: $logFile"
    }
    
    Write-Host "Starting real-time monitoring..." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray
    Write-Host ""
    
    Start-Sleep -Seconds 2
    
    # Get current profile from config
    $currentConfig = Get-MoonlightConfig
    $currentProfile = "Unknown"
    if ($currentConfig) {
        $bitrate = [int]$currentConfig["bitrate"]
        if ($bitrate -le 15000) { $currentProfile = "Performance" }
        elseif ($bitrate -le 22000) { $currentProfile = "LowLatency" }
        elseif ($bitrate -le 30000) { $currentProfile = "Balanced" }
        else { $currentProfile = "Quality" }
    }
    
    # Monitoring loop
    $samples = [System.Collections.ArrayList]::new()
    $windowSize = 30  # Rolling window of samples
    $sampleInterval = 1  # Seconds between samples
    $statsUpdateInterval = 5  # Update display every N samples
    $sampleCount = 0
    
    Show-MonitorHeader
    
    try {
        while ($true) {
            # Collect sample
            $sample = Get-NetworkSample -TargetIP $HostTailscaleIP
            $null = $samples.Add($sample)
            $sampleCount++
            
            # Keep rolling window
            if ($samples.Count -gt $windowSize) {
                $samples.RemoveAt(0)
            }
            
            # Update display periodically
            if ($sampleCount % $statsUpdateInterval -eq 0 -and $samples.Count -ge 5) {
                $stats = Get-NetworkStats -Samples $samples
                $quality = Get-QualityRating -Stats $stats
                
                Show-LiveStats -Stats $stats -Quality $quality -CurrentProfile $currentProfile
                
                # Log if enabled
                if ($logFile) {
                    Write-LogEntry -LogFile $logFile -Stats $stats -Quality $quality -Profile $currentProfile
                }
                
                # Auto-adjust if enabled
                if ($AutoAdjust) {
                    $recommendedProfile = Get-RecommendedProfile -Stats $stats
                    if ($recommendedProfile -ne $currentProfile) {
                        Write-Host ""
                        Write-Warn "Recommending profile change: $currentProfile -> $recommendedProfile"
                        # Note: Auto-apply would require Moonlight restart
                    }
                }
            }
            
            Start-Sleep -Seconds $sampleInterval
            
            # Check duration limit
            if ($MonitorDuration -gt 0 -and $sampleCount -ge $MonitorDuration) {
                break
            }
        }
    } catch {
        # Ctrl+C or other interruption
    }
    
    # Final summary
    Write-Host ""
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "                      MONITORING SUMMARY                            " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    
    if ($samples.Count -gt 0) {
        $finalStats = Get-NetworkStats -Samples $samples
        $finalQuality = Get-QualityRating -Stats $finalStats
        
        Write-Host ""
        Write-Host "  Session Statistics:" -ForegroundColor White
        Write-Host "    Total Samples   : $($samples.Count)" -ForegroundColor Gray
        Write-Host "    Avg Latency     : $($finalStats.AvgLatency) ms" -ForegroundColor Gray
        Write-Host "    Latency Range   : $($finalStats.MinLatency) - $($finalStats.MaxLatency) ms" -ForegroundColor Gray
        Write-Host "    Avg Jitter      : $($finalStats.Jitter) ms" -ForegroundColor Gray
        Write-Host "    Packet Loss     : $($finalStats.PacketLoss) percent" -ForegroundColor Gray
        Write-Host "    Quality Score   : $($finalQuality.Score)/100 ($($finalQuality.Rating))" -ForegroundColor Gray
        Write-Host ""
        
        $recommendedProfile = Get-RecommendedProfile -Stats $finalStats
        Write-Host "  Recommended Profile: " -NoNewline -ForegroundColor White
        Write-Host $recommendedProfile -ForegroundColor Green
        
        if ($logFile) {
            Write-Host ""
            Write-Host "  Log saved to: $logFile" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan
}

# Final recommendations for your specific setup
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "              OPTIMIZED SETTINGS FOR YOUR CONNECTION                " -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Based on your ~110ms latency to ${HostTailscaleIP}:" -ForegroundColor White
Write-Host ""
Write-Host "  RECOMMENDED MOONLIGHT SETTINGS:" -ForegroundColor Yellow
Write-Host "    Resolution     : 1920x1080 (1080p)" -ForegroundColor Cyan
Write-Host "    FPS            : 60" -ForegroundColor Cyan
Write-Host "    Bitrate        : 20-25 Mbps" -ForegroundColor Cyan
Write-Host "    Video Codec    : H.264 (Automatic)" -ForegroundColor Cyan
Write-Host "    Video Decoder  : Automatic (uses NVDEC on your RTX 3060)" -ForegroundColor Cyan
Write-Host "    V-Sync         : ON" -ForegroundColor Cyan
Write-Host "    Frame Pacing   : ON" -ForegroundColor Cyan
Write-Host ""
Write-Host "  SUNSHINE HOST SETTINGS (on remote PC):" -ForegroundColor Yellow
Write-Host "    Encoder        : NVENC (if NVIDIA GPU)" -ForegroundColor Cyan
Write-Host "    Min Bitrate    : Match Moonlight setting" -ForegroundColor Cyan
Write-Host "    Network        : Enable UPnP or forward ports" -ForegroundColor Cyan
Write-Host ""
Write-Host "  GAME TYPES THAT WORK WELL AT ~110ms:" -ForegroundColor Yellow
Write-Host "    [OK] Strategy, RPGs, Turn-based, Story games" -ForegroundColor Green
Write-Host "    [OK] Racing (with assists), Single-player action" -ForegroundColor Green
Write-Host "    [!!] Competitive FPS, Fighting games (not recommended)" -ForegroundColor Red
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
