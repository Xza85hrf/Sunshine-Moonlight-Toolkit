<#
.SYNOPSIS
    Sunshine + Moonlight Connection Tester
    
.DESCRIPTION
    Tests your connection to the Sunshine host and recommends optimal settings.
    Run this on your LAPTOP/CLIENT.
    
.PARAMETER HostIP
    IP address of your Sunshine host (default: auto-detect)
    
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ".\Test-Connection.ps1"
    powershell -ExecutionPolicy Bypass -File ".\Test-Connection.ps1" -HostIP "192.168.1.100"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$HostIP = ""
)

# Load configuration
$ConfigPath = Join-Path $PSScriptRoot "config.json"
$config = $null
if (Test-Path $ConfigPath) {
    try { $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { $config = $null }
}

Clear-Host
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host "       SUNSHINE CONNECTION TESTER                               " -ForegroundColor Cyan
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host ""

# Auto-detect host IP if not provided
if (-not $HostIP) {
    # Load IPs from config if available
    if ($config -and $config.configured) {
        $lanIP = $config.host.lan_ip
        $tailscaleIP = $config.host.tailscale_ip
        Write-Host "  Using configuration from config.json..." -ForegroundColor Gray
    } else {
        Write-Host "  [!] No config found. Run Setup-Toolkit.ps1 or specify -HostIP" -ForegroundColor Yellow
        $HostIP = Read-Host "  Enter host IP"
        if (-not $HostIP) { exit 1 }
    }

    if (-not $HostIP -and $lanIP) {
        Write-Host "  Checking connectivity..." -ForegroundColor Gray

        # Test LAN first
        $lanTest = Test-Connection -ComputerName $lanIP -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($lanTest) {
            $HostIP = $lanIP
            Write-Host "  [OK] Found host on LAN: $lanIP" -ForegroundColor Green
        } elseif ($tailscaleIP) {
            # Try Tailscale
            $tsTest = Test-Connection -ComputerName $tailscaleIP -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($tsTest) {
                $HostIP = $tailscaleIP
                Write-Host "  [OK] Found host via Tailscale: $tailscaleIP" -ForegroundColor Green
            } else {
                Write-Host "  [!] Host not reachable, using LAN IP anyway" -ForegroundColor Yellow
                $HostIP = $lanIP
            }
        } else {
            $HostIP = $lanIP
        }
    }
}

Write-Host ""
Write-Host "  Testing connection to: $HostIP" -ForegroundColor White
Write-Host "  =============================================================" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# 1. PING TEST
# ============================================================================

Write-Host "  [1] Latency Test (Ping)..." -ForegroundColor Yellow

$pingResults = @()
for ($i = 1; $i -le 10; $i++) {
    $ping = Test-Connection -ComputerName $HostIP -Count 1 -ErrorAction SilentlyContinue
    if ($ping) {
        $pingResults += $ping.ResponseTime
    }
    Write-Progress -Activity "Ping Test" -PercentComplete ($i * 10)
}
Write-Progress -Activity "Ping Test" -Completed

if ($pingResults.Count -gt 0) {
    $avgLatency = [math]::Round(($pingResults | Measure-Object -Average).Average, 1)
    $minLatency = ($pingResults | Measure-Object -Minimum).Minimum
    $maxLatency = ($pingResults | Measure-Object -Maximum).Maximum
    
    $latencyColor = if ($avgLatency -lt 5) { "Green" } elseif ($avgLatency -lt 50) { "Yellow" } else { "Red" }
    
    Write-Host "      Average: $avgLatency ms" -ForegroundColor $latencyColor
    Write-Host "      Range:   $minLatency - $maxLatency ms" -ForegroundColor Gray
    
    if ($avgLatency -lt 5) {
        Write-Host "      Rating:  EXCELLENT (LAN)" -ForegroundColor Green
        $connectionType = "LAN"
    } elseif ($avgLatency -lt 50) {
        Write-Host "      Rating:  GOOD" -ForegroundColor Green
        $connectionType = "Good"
    } elseif ($avgLatency -lt 100) {
        Write-Host "      Rating:  MODERATE" -ForegroundColor Yellow
        $connectionType = "Moderate"
    } else {
        Write-Host "      Rating:  HIGH LATENCY" -ForegroundColor Red
        $connectionType = "Remote"
    }
} else {
    Write-Host "      [ERROR] Host not reachable!" -ForegroundColor Red
    $connectionType = "Failed"
}

Write-Host ""

# ============================================================================
# 2. PORT TEST
# ============================================================================

Write-Host "  [2] Port Connectivity..." -ForegroundColor Yellow

$ports = @(
    @{ Port = 47984; Name = "HTTPS/API" },
    @{ Port = 47989; Name = "RTSP" },
    @{ Port = 47990; Name = "HTTP/WebUI" }
)

$allPortsOpen = $true
foreach ($p in $ports) {
    $test = Test-NetConnection -ComputerName $HostIP -Port $p.Port -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($test) {
        Write-Host "      TCP $($p.Port) ($($p.Name)): OPEN" -ForegroundColor Green
    } else {
        Write-Host "      TCP $($p.Port) ($($p.Name)): CLOSED" -ForegroundColor Red
        $allPortsOpen = $false
    }
}

Write-Host ""

# ============================================================================
# 3. BANDWIDTH TEST
# ============================================================================

Write-Host "  [3] Bandwidth Estimation..." -ForegroundColor Yellow

try {
    $testData = New-Object byte[] 10MB
    $client = New-Object System.Net.Sockets.TcpClient
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    $client.Connect($HostIP, 47990)
    $stream = $client.GetStream()
    $stream.Write($testData, 0, $testData.Length)
    $stopwatch.Stop()
    
    $bandwidth = [math]::Round(($testData.Length * 8 / $stopwatch.Elapsed.TotalSeconds) / 1000000, 1)
    
    $bwColor = if ($bandwidth -gt 80) { "Green" } elseif ($bandwidth -gt 40) { "Yellow" } else { "Red" }
    Write-Host "      Estimated: $bandwidth Mbps" -ForegroundColor $bwColor
    
    $client.Close()
} catch {
    Write-Host "      Could not measure bandwidth" -ForegroundColor Yellow
    $bandwidth = 50  # Assume reasonable
}

Write-Host ""

# ============================================================================
# 4. RECOMMENDATIONS
# ============================================================================

Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host "       RECOMMENDED SETTINGS                                     " -ForegroundColor Cyan
Write-Host "  =============================================================" -ForegroundColor Cyan
Write-Host ""

if ($connectionType -eq "LAN" -and $bandwidth -gt 80) {
    Write-Host "  Connection: LOCAL NETWORK (Excellent!)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Recommended Profile: ULTRA" -ForegroundColor Cyan
    Write-Host "    Resolution: 1080p (or 4K if supported)" -ForegroundColor White
    Write-Host "    FPS:        120 (or 60)" -ForegroundColor White
    Write-Host "    Bitrate:    80-100 Mbps" -ForegroundColor White
    Write-Host "    Codec:      HEVC (H.265)" -ForegroundColor White
} elseif ($connectionType -eq "Good" -or $bandwidth -gt 40) {
    Write-Host "  Connection: GOOD" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Recommended Profile: QUALITY" -ForegroundColor Cyan
    Write-Host "    Resolution: 1080p" -ForegroundColor White
    Write-Host "    FPS:        60" -ForegroundColor White
    Write-Host "    Bitrate:    50-70 Mbps" -ForegroundColor White
    Write-Host "    Codec:      HEVC or H.264" -ForegroundColor White
} elseif ($connectionType -eq "Moderate") {
    Write-Host "  Connection: MODERATE (Remote/Tailscale)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Recommended Profile: BALANCED" -ForegroundColor Cyan
    Write-Host "    Resolution: 1080p" -ForegroundColor White
    Write-Host "    FPS:        60" -ForegroundColor White
    Write-Host "    Bitrate:    20-40 Mbps" -ForegroundColor White
    Write-Host "    Codec:      H.264" -ForegroundColor White
} else {
    Write-Host "  Connection: LIMITED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Recommended Profile: PERFORMANCE" -ForegroundColor Cyan
    Write-Host "    Resolution: 720p" -ForegroundColor White
    Write-Host "    FPS:        60 (or 30)" -ForegroundColor White
    Write-Host "    Bitrate:    10-20 Mbps" -ForegroundColor White
    Write-Host "    Codec:      H.264" -ForegroundColor White
}

Write-Host ""

# Issues
if (-not $allPortsOpen) {
    Write-Host "  [!] ISSUE: Some ports are closed!" -ForegroundColor Red
    Write-Host "      Run 'Optimize-SunshineHost.ps1' on the host PC" -ForegroundColor Yellow
    Write-Host ""
}

if ($HostIP -like "100.*") {
    Write-Host "  [TIP] You're using Tailscale IP ($HostIP)" -ForegroundColor Yellow
    Write-Host "        If you're at home, use your host's LAN IP for better speed!" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  =============================================================" -ForegroundColor Gray
Write-Host ""

Write-Host "  Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
