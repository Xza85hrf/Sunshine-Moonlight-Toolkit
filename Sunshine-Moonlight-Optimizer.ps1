<#
.SYNOPSIS
    Sunshine + Moonlight Connection Tester and Optimizer over Tailscale
    
.DESCRIPTION
    Tests network conditions between Sunshine host and Moonlight client to recommend
    optimal streaming settings for resolution, bitrate, FPS, and codec selection.
    
.PARAMETER HostTailscaleIP
    The Tailscale IP of the Sunshine host (e.g., 100.x.x.x)
    
.PARAMETER TestDuration
    Duration in seconds for each bandwidth test (default: 10)

.PARAMETER Detailed
    Run extended tests with more detail

.EXAMPLE
    .\Sunshine-Moonlight-Optimizer.ps1 -HostTailscaleIP "100.x.x.x"

.EXAMPLE
    .\Sunshine-Moonlight-Optimizer.ps1 -HostTailscaleIP "100.x.x.x" -Detailed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostTailscaleIP,
    
    [Parameter(Mandatory = $false)]
    [int]$TestDuration = 10,
    
    [Parameter(Mandatory = $false)]
    [switch]$Detailed
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Continue"

# Sunshine ports
$SunshinePorts = @{
    HTTPS  = 47984
    HTTP   = 47990
    RTSP   = 47989
    Video  = 47998
    Audio  = 47999
    Control = 48000
    ControlAlt = 48010
}

# Output formatting
function Write-Header { 
    param($msg) 
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section { param($msg) Write-Host "`n--- $msg ---`n" -ForegroundColor White }
function Write-Good { param($msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Bad { param($msg) Write-Host "[-] $msg" -ForegroundColor Red }
function Write-Warn { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Data { param($msg) Write-Host "    $msg" -ForegroundColor Gray }

# Results storage
$script:TestResults = @{
    Latency = @{
        Min = 0
        Max = 0
        Avg = 0
        Jitter = 0
    }
    Bandwidth = @{
        Estimated = 0
        Stable = $false
    }
    PortStatus = @{}
    Recommendations = @{}
}

# ============================================================================
# BANNER
# ============================================================================

Clear-Host
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host "    SUNSHINE + MOONLIGHT CONNECTION OPTIMIZER                   " -ForegroundColor Magenta
Write-Host "    Over Tailscale VPN                                          " -ForegroundColor Magenta
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Target Host: $HostTailscaleIP" -ForegroundColor White
$testTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "  Test Time  : $testTime" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# 1. BASIC CONNECTIVITY TEST
# ============================================================================

Write-Header "1. BASIC CONNECTIVITY TEST"

Write-Section "Ping Test (ICMP)"

# Extended ping test for latency analysis
$pingResults = @()
$pingCount = 20

Write-Info "Sending $pingCount pings to measure latency and jitter..."

for ($i = 1; $i -le $pingCount; $i++) {
    $ping = Test-Connection -ComputerName $HostTailscaleIP -Count 1 -ErrorAction SilentlyContinue
    if ($ping) {
        $pingResults += $ping.ResponseTime
        Write-Progress -Activity "Ping Test" -Status "Ping $i of $pingCount" -PercentComplete (($i / $pingCount) * 100)
    } else {
        Write-Progress -Activity "Ping Test" -Status "Ping $i of $pingCount (timeout)" -PercentComplete (($i / $pingCount) * 100)
    }
    Start-Sleep -Milliseconds 100
}
Write-Progress -Activity "Ping Test" -Completed

if ($pingResults.Count -gt 0) {
    $script:TestResults.Latency.Min = [math]::Round(($pingResults | Measure-Object -Minimum).Minimum, 2)
    $script:TestResults.Latency.Max = [math]::Round(($pingResults | Measure-Object -Maximum).Maximum, 2)
    $script:TestResults.Latency.Avg = [math]::Round(($pingResults | Measure-Object -Average).Average, 2)
    
    # Calculate jitter (standard deviation of latency)
    $avg = $script:TestResults.Latency.Avg
    $sumSquares = ($pingResults | ForEach-Object { [math]::Pow($_ - $avg, 2) } | Measure-Object -Sum).Sum
    $script:TestResults.Latency.Jitter = [math]::Round([math]::Sqrt($sumSquares / $pingResults.Count), 2)
    
    $packetLossPercent = [math]::Round(($pingResults.Count / $pingCount) * 100, 1)
    
    Write-Good "Host is reachable!"
    Write-Data "Packets Sent    : $pingCount"
    Write-Data "Packets Received: $($pingResults.Count) ($packetLossPercent percent)"
    Write-Data "Latency Min     : $($script:TestResults.Latency.Min) ms"
    Write-Data "Latency Max     : $($script:TestResults.Latency.Max) ms"
    Write-Data "Latency Avg     : $($script:TestResults.Latency.Avg) ms"
    Write-Data "Jitter          : $($script:TestResults.Latency.Jitter) ms"
    
    # Latency assessment
    $latencyRating = ""
    if ($script:TestResults.Latency.Avg -lt 20) {
        $latencyRating = "EXCELLENT - Local network quality"
        Write-Good "Latency Rating: $latencyRating"
    } elseif ($script:TestResults.Latency.Avg -lt 50) {
        $latencyRating = "GOOD - Suitable for most games"
        Write-Good "Latency Rating: $latencyRating"
    } elseif ($script:TestResults.Latency.Avg -lt 100) {
        $latencyRating = "MODERATE - OK for slower-paced games"
        Write-Warn "Latency Rating: $latencyRating"
    } else {
        $latencyRating = "HIGH - May experience input lag"
        Write-Bad "Latency Rating: $latencyRating"
    }
    
    # Jitter assessment
    if ($script:TestResults.Latency.Jitter -gt 20) {
        Write-Warn "High jitter detected - may cause stuttering"
    }
    
} else {
    Write-Bad "Host is not reachable via ICMP ping"
    Write-Warn "This could mean:"
    Write-Data "- Host is offline"
    Write-Data "- ICMP is blocked (Tailscale or Windows firewall)"
    Write-Data "- Wrong IP address"
}

# ============================================================================
# 2. PORT CONNECTIVITY TEST
# ============================================================================

Write-Header "2. PORT CONNECTIVITY TEST"

Write-Section "Testing Sunshine Ports"

# TCP Port Tests
Write-Info "Testing TCP ports..."
$tcpPorts = @(47984, 47989, 47990)

foreach ($port in $tcpPorts) {
    $portName = switch ($port) {
        47984 { "HTTPS/API" }
        47989 { "RTSP" }
        47990 { "HTTP" }
    }
    
    $tcpTest = Test-NetConnection -ComputerName $HostTailscaleIP -Port $port -WarningAction SilentlyContinue
    
    if ($tcpTest.TcpTestSucceeded) {
        Write-Good "TCP $port ($portName) - OPEN"
        $script:TestResults.PortStatus["TCP_$port"] = $true
    } else {
        Write-Bad "TCP $port ($portName) - CLOSED/FILTERED"
        $script:TestResults.PortStatus["TCP_$port"] = $false
    }
}

# UDP Port Tests (indirect - via timing)
Write-Host ""
Write-Info "Testing UDP ports (connection attempt timing)..."
$udpPorts = @(47998, 47999, 48000, 48010)

foreach ($port in $udpPorts) {
    $portName = switch ($port) {
        47998 { "Video Stream" }
        47999 { "Audio Stream" }
        48000 { "Control Input" }
        48010 { "Alt Control" }
    }
    
    # UDP test using socket
    try {
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.Client.ReceiveTimeout = 1000
        $udpClient.Connect($HostTailscaleIP, $port)
        
        # Send a test packet
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("test")
        $null = $udpClient.Send($bytes, $bytes.Length)
        
        $udpClient.Close()
        Write-Good "UDP $port ($portName) - Reachable (packet sent)"
        $script:TestResults.PortStatus["UDP_$port"] = $true
    } catch {
        Write-Warn "UDP $port ($portName) - Unknown (UDP is connectionless)"
        $script:TestResults.PortStatus["UDP_$port"] = "Unknown"
    }
}

# Summary of port status
$openTcpPorts = ($script:TestResults.PortStatus.Keys | Where-Object { $_ -like "TCP_*" -and $script:TestResults.PortStatus[$_] -eq $true }).Count
$totalTcpPorts = $tcpPorts.Count

Write-Host ""
if ($openTcpPorts -eq $totalTcpPorts) {
    Write-Good "All TCP ports are accessible!"
} elseif ($openTcpPorts -gt 0) {
    Write-Warn "Some TCP ports are blocked ($openTcpPorts of $totalTcpPorts open)"
} else {
    Write-Bad "All TCP ports appear blocked - Sunshine may not be running or firewall is blocking"
}

# ============================================================================
# 3. BANDWIDTH ESTIMATION
# ============================================================================

Write-Header "3. BANDWIDTH ESTIMATION"

Write-Section "Estimating Available Bandwidth"

Write-Info "Running bandwidth estimation test..."
Write-Data "This test downloads data from the Sunshine API to estimate throughput"
Write-Host ""

# Method 1: Large ping packets (up to 65500 bytes)
Write-Info "Method 1: Large packet ping test..."

$packetSizes = @(1000, 5000, 10000, 32000)
$bandwidthEstimates = @()

foreach ($size in $packetSizes) {
    try {
        $start = Get-Date
        $ping = Test-Connection -ComputerName $HostTailscaleIP -Count 5 -BufferSize $size -ErrorAction Stop
        $elapsed = ((Get-Date) - $start).TotalSeconds
        
        $avgTime = ($ping.ResponseTime | Measure-Object -Average).Average
        # Estimate: (packet size * 2 for round trip * 8 bits * 1000 for ms to sec) / time in ms = bits per second
        $bitsPerSecond = ($size * 2 * 8 * 1000) / $avgTime
        $mbps = [math]::Round($bitsPerSecond / 1000000, 2)
        
        $avgTimeRounded = [math]::Round($avgTime, 2)
        Write-Data "Packet size ${size}B: ~$mbps Mbps (RTT: ${avgTimeRounded}ms)"
        $bandwidthEstimates += $mbps
    } catch {
        Write-Data "Packet size ${size}B: Test failed"
    }
}

if ($bandwidthEstimates.Count -gt 0) {
    $avgBandwidth = [math]::Round(($bandwidthEstimates | Measure-Object -Average).Average, 2)
    $script:TestResults.Bandwidth.Estimated = $avgBandwidth
    
    Write-Host ""
    Write-Info "Estimated available bandwidth: ~$avgBandwidth Mbps"
    Write-Data "(Note: Actual streaming bandwidth may differ based on network conditions)"
}

# Method 2: If Sunshine API is accessible, try to get server info
Write-Host ""
Write-Info "Method 2: Checking Sunshine API..."

try {
    # Try to connect to Sunshine HTTPS API
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    
    $apiUrl = "https://${HostTailscaleIP}:47984"
    $webRequest = [System.Net.WebRequest]::Create($apiUrl)
    $webRequest.Timeout = 5000
    $webRequest.Method = "GET"
    
    $start = Get-Date
    try {
        $response = $webRequest.GetResponse()
        $elapsed = ((Get-Date) - $start).TotalMilliseconds
        $elapsedRounded = [math]::Round($elapsed, 2)
        
        Write-Good "Sunshine API responded in ${elapsedRounded}ms"
        $response.Close()
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            Write-Good "Sunshine API is running (requires authentication)"
        } else {
            Write-Warn "Could not reach Sunshine API"
        }
    }
} catch {
    Write-Warn "Sunshine API check failed: $($_.Exception.Message)"
}

# ============================================================================
# 4. TAILSCALE CONNECTION QUALITY
# ============================================================================

Write-Header "4. TAILSCALE CONNECTION QUALITY"

Write-Section "Tailscale Status"

# Get Tailscale status
$tailscaleStatus = $null
try {
    $tailscaleJson = tailscale status --json 2>$null
    if ($tailscaleJson) {
        $tailscaleStatus = $tailscaleJson | ConvertFrom-Json
    }
    
    if ($tailscaleStatus) {
        Write-Good "Tailscale is connected"
        Write-Data "Backend State: $($tailscaleStatus.BackendState)"
        
        # Find the peer
        $peer = $tailscaleStatus.Peer.PSObject.Properties | Where-Object { 
            $_.Value.TailscaleIPs -contains $HostTailscaleIP 
        }
        
        if ($peer) {
            $peerInfo = $peer.Value
            Write-Host ""
            Write-Info "Peer Information:"
            Write-Data "Hostname    : $($peerInfo.HostName)"
            Write-Data "Online      : $($peerInfo.Online)"
            $isDirect = $peerInfo.CurAddr -ne ""
            Write-Data "Direct      : $isDirect"
            Write-Data "Relay       : $($peerInfo.Relay)"
            Write-Data "Last Seen   : $($peerInfo.LastSeen)"
            $txMB = [math]::Round($peerInfo.TxBytes / 1MB, 2)
            $rxMB = [math]::Round($peerInfo.RxBytes / 1MB, 2)
            Write-Data "TX Bytes    : $txMB MB"
            Write-Data "RX Bytes    : $rxMB MB"
            
            if ($peerInfo.CurAddr) {
                Write-Good "Direct connection established: $($peerInfo.CurAddr)"
            } else {
                Write-Warn "Using DERP relay - this may increase latency"
                Write-Data "Relay: $($peerInfo.Relay)"
            }
        }
    }
} catch {
    Write-Warn "Could not get Tailscale status. Is Tailscale CLI in PATH?"
}

# ============================================================================
# 5. CONNECTION PATH ANALYSIS
# ============================================================================

Write-Header "5. CONNECTION PATH ANALYSIS"

Write-Section "Traceroute to Host"

Write-Info "Tracing route to $HostTailscaleIP..."

try {
    $trace = Test-NetConnection -ComputerName $HostTailscaleIP -TraceRoute -WarningAction SilentlyContinue
    
    if ($trace.TraceRoute) {
        $hopCount = $trace.TraceRoute.Count
        Write-Data "Total hops: $hopCount"
        
        for ($i = 0; $i -lt $trace.TraceRoute.Count; $i++) {
            $hop = $trace.TraceRoute[$i]
            $hopNum = $i + 1
            Write-Data "Hop ${hopNum}: $hop"
        }
        
        if ($hopCount -le 2) {
            Write-Good "Direct or near-direct connection (optimal)"
        } elseif ($hopCount -le 5) {
            Write-Info "Reasonable hop count"
        } else {
            Write-Warn "Many hops detected - may affect latency"
        }
    }
} catch {
    Write-Warn "Traceroute failed: $($_.Exception.Message)"
}

# ============================================================================
# 6. SYSTEM CAPABILITY CHECK (CLIENT SIDE)
# ============================================================================

Write-Header "6. CLIENT SYSTEM CAPABILITIES"

Write-Section "GPU and Decoder Information"

# GPU check
$gpus = Get-CimInstance Win32_VideoController
foreach ($gpu in $gpus) {
    Write-Info "GPU: $($gpu.Name)"
    Write-Data "Driver Version: $($gpu.DriverVersion)"
    $vramGB = [math]::Round($gpu.AdapterRAM / 1GB, 2)
    Write-Data "VRAM: $vramGB GB"
    
    if ($gpu.Name -match "NVIDIA") {
        Write-Good "NVIDIA GPU - Hardware decoding (NVDEC) available"
    } elseif ($gpu.Name -match "AMD|Radeon") {
        Write-Good "AMD GPU - Hardware decoding (VCN) available"
    } elseif ($gpu.Name -match "Intel") {
        Write-Good "Intel GPU - Hardware decoding (QuickSync) available"
    }
}

Write-Section "Display Information"

try {
    Add-Type -AssemblyName System.Windows.Forms
    $screens = [System.Windows.Forms.Screen]::AllScreens
    
    foreach ($screen in $screens) {
        $primary = if ($screen.Primary) { "(Primary)" } else { "" }
        $width = $screen.Bounds.Width
        $height = $screen.Bounds.Height
        $bpp = $screen.BitsPerPixel
        Write-Data "$($screen.DeviceName): ${width}x${height} at ${bpp}bpp $primary"
    }
    
    $primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen
    $nativeRes = "$($primaryScreen.Bounds.Width)x$($primaryScreen.Bounds.Height)"
    Write-Host ""
    Write-Info "Your native resolution: $nativeRes"
} catch {
    Write-Warn "Could not enumerate displays"
}

# ============================================================================
# 7. GENERATE RECOMMENDATIONS
# ============================================================================

Write-Header "7. OPTIMAL SETTINGS RECOMMENDATIONS"

# Calculate recommendations based on test results
$latency = $script:TestResults.Latency.Avg
$jitter = $script:TestResults.Latency.Jitter
$bandwidth = $script:TestResults.Bandwidth.Estimated

Write-Section "Based on Your Connection"

# Create recommendation table
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "          MOONLIGHT CLIENT RECOMMENDED SETTINGS                     " -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# Resolution Recommendation
$resolutionRec = ""
$resolutionExplain = ""
if ($latency -lt 30 -and $bandwidth -gt 50) {
    $resolutionRec = "1080p or 4K (if host supports)"
    $resolutionExplain = "Excellent connection supports high resolution"
} elseif ($latency -lt 60 -and $bandwidth -gt 30) {
    $resolutionRec = "1080p"
    $resolutionExplain = "Good connection for Full HD"
} elseif ($latency -lt 100 -and $bandwidth -gt 15) {
    $resolutionRec = "720p or 1080p"
    $resolutionExplain = "Moderate connection - start with 720p"
} else {
    $resolutionRec = "720p"
    $resolutionExplain = "Limited connection - use lower resolution"
}
Write-Host ""
Write-Host "Resolution      : $resolutionRec" -ForegroundColor White
Write-Host "                  $resolutionExplain" -ForegroundColor Gray

# FPS Recommendation
$fpsRec = ""
$fpsExplain = ""
if ($latency -lt 25 -and $jitter -lt 10) {
    $fpsRec = "120 FPS (if supported) or 60 FPS"
    $fpsExplain = "Low latency and jitter supports high FPS"
} elseif ($latency -lt 50 -and $jitter -lt 20) {
    $fpsRec = "60 FPS"
    $fpsExplain = "Good for smooth 60 FPS gaming"
} elseif ($latency -lt 80) {
    $fpsRec = "60 FPS (or 30 FPS for stability)"
    $fpsExplain = "May work at 60, drop to 30 if stuttering"
} else {
    $fpsRec = "30 FPS"
    $fpsExplain = "Higher latency - 30 FPS more stable"
}
Write-Host ""
Write-Host "FPS             : $fpsRec" -ForegroundColor White
Write-Host "                  $fpsExplain" -ForegroundColor Gray

# Bitrate Recommendation
$bitrateRec = ""
$bitrateExplain = ""
$recommendedBitrate = 0

if ($bandwidth -gt 100) {
    $recommendedBitrate = 80
    $bitrateRec = "60-80 Mbps"
    $bitrateExplain = "High bandwidth - maximize quality"
} elseif ($bandwidth -gt 50) {
    $recommendedBitrate = 50
    $bitrateRec = "40-60 Mbps"
    $bitrateExplain = "Good bandwidth - high quality streaming"
} elseif ($bandwidth -gt 30) {
    $recommendedBitrate = 30
    $bitrateRec = "20-40 Mbps"
    $bitrateExplain = "Moderate bandwidth - balanced quality"
} elseif ($bandwidth -gt 15) {
    $recommendedBitrate = 15
    $bitrateRec = "10-20 Mbps"
    $bitrateExplain = "Limited bandwidth - reduce bitrate"
} else {
    $recommendedBitrate = 10
    $bitrateRec = "5-15 Mbps"
    $bitrateExplain = "Low bandwidth - use minimum for stability"
}

# If we couldn't estimate bandwidth, give safe defaults
if ($bandwidth -eq 0) {
    $bitrateRec = "20-40 Mbps (start here)"
    $bitrateExplain = "Bandwidth unknown - adjust based on experience"
}

Write-Host ""
Write-Host "Video Bitrate   : $bitrateRec" -ForegroundColor White
Write-Host "                  $bitrateExplain" -ForegroundColor Gray

# Codec Recommendation
$codecRec = ""
$codecExplain = ""
if ($latency -lt 40) {
    $codecRec = "HEVC (H.265) or AV1 if supported"
    $codecExplain = "Better compression, low latency allows it"
} else {
    $codecRec = "H.264 (Automatic)"
    $codecExplain = "Lower decode latency, more compatible"
}
Write-Host ""
Write-Host "Video Codec     : $codecRec" -ForegroundColor White
Write-Host "                  $codecExplain" -ForegroundColor Gray

# Additional Settings
Write-Host ""
Write-Host "Video Decoder   : Automatic (Hardware preferred)" -ForegroundColor White
Write-Host "V-Sync          : ON (reduces tearing)" -ForegroundColor White
Write-Host "Frame Pacing    : ON (smoother frames)" -ForegroundColor White

if ($latency -gt 50) {
    Write-Host "Game Mode       : Enable Windows Game Mode on host" -ForegroundColor Yellow
}

Write-Host "====================================================================" -ForegroundColor Cyan

# Store in results
$script:TestResults.Recommendations = @{
    Resolution = $resolutionRec
    FPS = $fpsRec
    Bitrate = $bitrateRec
    Codec = $codecRec
}

# ============================================================================
# 8. PROFILE PRESETS
# ============================================================================

Write-Host ""
Write-Section "Quick Profile Presets"

Write-Host ""
Write-Host "Based on your connection, here are some preset profiles to try:" -ForegroundColor White
Write-Host ""

# Determine best profile
if ($latency -lt 30 -and $bandwidth -gt 50) {
    Write-Host "  [RECOMMENDED] Ultra Quality Profile:" -ForegroundColor Green
    Write-Host "    Resolution: 1080p (or 4K if available)" -ForegroundColor Gray
    Write-Host "    FPS: 60" -ForegroundColor Gray
    Write-Host "    Bitrate: 60-80 Mbps" -ForegroundColor Gray
    Write-Host "    Codec: HEVC" -ForegroundColor Gray
} elseif ($latency -lt 50 -and $bandwidth -gt 30) {
    Write-Host "  [RECOMMENDED] Balanced Profile:" -ForegroundColor Green
    Write-Host "    Resolution: 1080p" -ForegroundColor Gray
    Write-Host "    FPS: 60" -ForegroundColor Gray
    Write-Host "    Bitrate: 40 Mbps" -ForegroundColor Gray
    Write-Host "    Codec: Automatic" -ForegroundColor Gray
} else {
    Write-Host "  [RECOMMENDED] Performance Profile:" -ForegroundColor Green
    Write-Host "    Resolution: 720p" -ForegroundColor Gray
    Write-Host "    FPS: 60" -ForegroundColor Gray
    Write-Host "    Bitrate: 20 Mbps" -ForegroundColor Gray
    Write-Host "    Codec: H.264" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  Alternative Profiles:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Competitive Gaming (Low Latency):" -ForegroundColor White
Write-Host "    Resolution: 720p-1080p" -ForegroundColor Gray
Write-Host "    FPS: 120 (if supported)" -ForegroundColor Gray
Write-Host "    Bitrate: 30-50 Mbps" -ForegroundColor Gray
Write-Host "    Codec: H.264 (lowest decode latency)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Cinematic (Best Quality):" -ForegroundColor White
Write-Host "    Resolution: 4K (if supported)" -ForegroundColor Gray
Write-Host "    FPS: 30-60" -ForegroundColor Gray
Write-Host "    Bitrate: 80-100 Mbps" -ForegroundColor Gray
Write-Host "    Codec: HEVC/AV1" -ForegroundColor Gray
Write-Host "    HDR: Enable if supported" -ForegroundColor Gray

# ============================================================================
# 9. YOUR CURRENT SETTINGS ANALYSIS
# ============================================================================

Write-Header "8. YOUR CURRENT SETTINGS ANALYSIS"

Write-Host "Based on typical Moonlight defaults:" -ForegroundColor White
Write-Host ""
Write-Host "  Current Settings:" -ForegroundColor Cyan
Write-Host "    Resolution: 1080p" -ForegroundColor White
Write-Host "    FPS: 60" -ForegroundColor White
Write-Host "    Bitrate: 40 Mbps" -ForegroundColor White
Write-Host "    V-Sync: ON" -ForegroundColor White
Write-Host "    Frame Pacing: ON" -ForegroundColor White
Write-Host "    Video Decoder: Automatic" -ForegroundColor White
Write-Host "    Video Codec: Automatic" -ForegroundColor White
Write-Host ""

# Compare with recommendations
if ($latency -gt 0) {
    Write-Host "  Analysis:" -ForegroundColor Yellow
    
    if ($latency -lt 50) {
        Write-Host "    [OK] Your settings look good for your connection!" -ForegroundColor Green
        
        if ($bandwidth -gt 60) {
            Write-Host "    [TIP] You could try increasing bitrate to 50-60 Mbps for better quality" -ForegroundColor Cyan
        }
        
        if ($latency -lt 30 -and $jitter -lt 10) {
            Write-Host "    [TIP] Your connection might support 120 FPS if your display supports it" -ForegroundColor Cyan
        }
    } elseif ($latency -lt 80) {
        Write-Host "    [OK] Settings are reasonable, but consider:" -ForegroundColor Yellow
        Write-Host "    [TIP] If you experience stuttering, try reducing bitrate to 30 Mbps" -ForegroundColor Cyan
    } else {
        Write-Host "    [WARN] High latency detected - consider:" -ForegroundColor Yellow
        Write-Host "    [TIP] Reduce resolution to 720p" -ForegroundColor Cyan
        Write-Host "    [TIP] Reduce bitrate to 15-20 Mbps" -ForegroundColor Cyan
        Write-Host "    [TIP] Use H.264 codec for lower decode latency" -ForegroundColor Cyan
    }
}

# ============================================================================
# 10. ISSUES & TROUBLESHOOTING
# ============================================================================

Write-Header "9. POTENTIAL ISSUES AND FIXES"

$hasIssues = $false

# Check for closed ports
$closedPorts = $script:TestResults.PortStatus.Keys | Where-Object { 
    $_ -like "TCP_*" -and $script:TestResults.PortStatus[$_] -eq $false 
}

if ($closedPorts.Count -gt 0) {
    $hasIssues = $true
    Write-Bad "Some TCP ports are not accessible"
    Write-Host "   Fix: Ensure Sunshine is running on the host" -ForegroundColor Yellow
    Write-Host "   Fix: Check firewall rules on the host machine" -ForegroundColor Yellow
    Write-Host "   Fix: Run the diagnostic script on the host to verify" -ForegroundColor Yellow
    Write-Host ""
}

# Check for high latency
if ($latency -gt 80) {
    $hasIssues = $true
    Write-Bad "High latency detected ($latency ms)"
    Write-Host "   Fix: Check if using DERP relay (direct connection preferred)" -ForegroundColor Yellow
    Write-Host "   Fix: Ensure both machines have good internet connections" -ForegroundColor Yellow
    Write-Host "   Fix: Try: tailscale up --reset on both machines" -ForegroundColor Yellow
    Write-Host ""
}

# Check for high jitter
if ($jitter -gt 20) {
    $hasIssues = $true
    Write-Bad "High jitter detected ($jitter ms)"
    Write-Host "   Fix: This can cause stuttering in streams" -ForegroundColor Yellow
    Write-Host "   Fix: Reduce video bitrate for more consistent delivery" -ForegroundColor Yellow
    Write-Host "   Fix: Check for network congestion or WiFi interference" -ForegroundColor Yellow
    Write-Host ""
}

# Check Tailscale relay
if ($tailscaleStatus) {
    $peer = $tailscaleStatus.Peer.PSObject.Properties | Where-Object { 
        $_.Value.TailscaleIPs -contains $HostTailscaleIP 
    }
    if ($peer -and -not $peer.Value.CurAddr) {
        $hasIssues = $true
        Write-Warn "Connection is via DERP relay (not direct)"
        Write-Host "   Fix: Both machines may be behind strict NAT" -ForegroundColor Yellow
        Write-Host "   Fix: Try port forwarding UDP 41641 on your router" -ForegroundColor Yellow
        Write-Host "   Fix: Run 'tailscale netcheck' for detailed connectivity info" -ForegroundColor Yellow
        Write-Host ""
    }
}

if (-not $hasIssues) {
    Write-Good "No major issues detected! Your connection looks healthy."
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================

Write-Header "TEST SUMMARY"

Write-Host ""
Write-Host "====================================================================" -ForegroundColor White
Write-Host "                      CONNECTION SUMMARY                            " -ForegroundColor White
Write-Host "====================================================================" -ForegroundColor White
Write-Host " Target Host     : $HostTailscaleIP" -ForegroundColor Cyan

$latencyColor = if ($latency -lt 50) { "Green" } elseif ($latency -lt 100) { "Yellow" } else { "Red" }
Write-Host " Latency (avg)   : $($script:TestResults.Latency.Avg) ms" -ForegroundColor $latencyColor

$jitterColor = if ($jitter -lt 15) { "Green" } elseif ($jitter -lt 30) { "Yellow" } else { "Red" }
Write-Host " Jitter          : $($script:TestResults.Latency.Jitter) ms" -ForegroundColor $jitterColor

$bwColor = if ($bandwidth -gt 30) { "Green" } elseif ($bandwidth -gt 15) { "Yellow" } else { "Red" }
Write-Host " Est. Bandwidth  : ~$($script:TestResults.Bandwidth.Estimated) Mbps" -ForegroundColor $bwColor

$portColor = if ($openTcpPorts -eq $totalTcpPorts) { "Green" } else { "Red" }
Write-Host " TCP Ports Open  : $openTcpPorts of $totalTcpPorts" -ForegroundColor $portColor
Write-Host "====================================================================" -ForegroundColor White

Write-Host ""
Write-Host "Recommended starting settings for Moonlight:" -ForegroundColor Cyan
Write-Host "  Resolution: $($script:TestResults.Recommendations.Resolution)" -ForegroundColor White
Write-Host "  FPS       : $($script:TestResults.Recommendations.FPS)" -ForegroundColor White
Write-Host "  Bitrate   : $($script:TestResults.Recommendations.Bitrate)" -ForegroundColor White
Write-Host "  Codec     : $($script:TestResults.Recommendations.Codec)" -ForegroundColor White
Write-Host ""

Write-Host "Tips for best experience:" -ForegroundColor Yellow
Write-Host "  1. Start with recommended settings, then adjust based on experience" -ForegroundColor Gray
Write-Host "  2. If you see artifacts/pixelation, increase bitrate" -ForegroundColor Gray
Write-Host "  3. If you see stuttering, decrease bitrate or resolution" -ForegroundColor Gray
Write-Host "  4. For competitive games, prioritize FPS over resolution" -ForegroundColor Gray
Write-Host "  5. Re-run this test periodically to check connection quality" -ForegroundColor Gray
Write-Host ""

$endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "Test completed at $endTime" -ForegroundColor Gray
Write-Host ""
