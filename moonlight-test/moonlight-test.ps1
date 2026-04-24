<#
.SYNOPSIS
    Moonlight/Sunshine LAN Streaming Diagnostics & Performance Test
.DESCRIPTION
    Tests network connectivity, adapter configuration, and Moonlight streaming
    performance between a client and a Sunshine host over LAN.
.PARAMETER HostIP
    IP address of the Sunshine host (default: auto-detect)
.PARAMETER Resolution
    Stream resolution: 720, 1080, 1440, 4K (default: 1080)
.PARAMETER FPS
    Target framerate (default: 144)
.PARAMETER Bitrate
    Video bitrate in Kbps (default: 150000)
.PARAMETER PacketSize
    Video packet size in bytes (default: 8192 for jumbo, 1024 for standard)
.PARAMETER Duration
    Test duration in seconds (default: 20)
.PARAMETER App
    Sunshine app to stream (default: Desktop)
.PARAMETER SkipStream
    Skip the Moonlight stream test and only run network diagnostics
.PARAMETER AdapterName
    Network adapter name to test (default: auto-detect 2.5G/10G adapter)
.EXAMPLE
    .\moonlight-test.ps1
    .\moonlight-test.ps1 -HostIP 192.168.50.2 -Resolution 4K -Bitrate 250000
    .\moonlight-test.ps1 -SkipStream
    .\moonlight-test.ps1 -AdapterName "Ethernet 2" -Duration 30
#>

param(
    [string]$HostIP,
    [ValidateSet("720", "1080", "1440", "4K")]
    [string]$Resolution = "1080",
    [int]$FPS = 144,
    [int]$Bitrate = 150000,
    [int]$PacketSize = 8192,
    [int]$Duration = 20,
    [string]$App = "Desktop",
    [switch]$SkipStream,
    [string]$AdapterName
)

$ErrorActionPreference = "SilentlyContinue"

# --- Helpers ---

function Write-Header($text) {
    Write-Host ""
    Write-Host "=== $text ===" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Pass($text) { Write-Host "  [PASS] $text" -ForegroundColor Green }
function Write-Fail($text) { Write-Host "  [FAIL] $text" -ForegroundColor Red }
function Write-Warn($text) { Write-Host "  [WARN] $text" -ForegroundColor Yellow }
function Write-Info($text) { Write-Host "  [INFO] $text" -ForegroundColor White }

function Test-Port($ip, $port) {
    $result = Test-NetConnection -ComputerName $ip -Port $port -WarningAction SilentlyContinue
    return $result.TcpTestSucceeded
}

# --- Find LAN Adapter ---

Write-Header "NETWORK ADAPTER DETECTION"

if ($AdapterName) {
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
} else {
    $adapter = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and
        $_.LinkSpeed -match "(2\.5|5|10) Gbps" -and
        $_.InterfaceDescription -notmatch "Virtual|Hyper-V|VPN|TAP|Tailscale|Bluetooth|OpenVPN"
    } | Select-Object -First 1

    if (-not $adapter) {
        $adapter = Get-NetAdapter | Where-Object {
            $_.Status -eq "Up" -and
            $_.InterfaceDescription -match "Ethernet|LAN|USB.*GbE|Realtek.*2\.5" -and
            $_.InterfaceDescription -notmatch "Virtual|Hyper-V|VPN|TAP|Tailscale|Bluetooth|OpenVPN"
        } | Select-Object -First 1
    }
}

if (-not $adapter) {
    Write-Fail "No suitable wired LAN adapter found. Use -AdapterName to specify one."
    Write-Host ""
    Write-Info "Available adapters:"
    Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed -AutoSize
    exit 1
}

$adapterName = $adapter.Name
$linkSpeed = $adapter.LinkSpeed
$adapterDesc = $adapter.InterfaceDescription

Write-Pass "Adapter: $adapterName ($adapterDesc)"
Write-Pass "Link Speed: $linkSpeed"
Write-Pass "Full Duplex: $($adapter.FullDuplex)"

# --- Get IP Config ---

$ipConfig = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4
$localIP = $ipConfig.IPAddress
$gateway = (Get-NetIPConfiguration -InterfaceAlias $adapterName).IPv4DefaultGateway.NextHop

Write-Info "Local IP: $localIP"
Write-Info "Gateway: $gateway"

# --- Auto-detect Host ---

Write-Header "HOST DETECTION"

if (-not $HostIP) {
    $neighbors = Get-NetNeighbor -InterfaceAlias $adapterName |
        Where-Object { $_.State -eq "Reachable" -and $_.IPAddress -match "^\d+\.\d+\.\d+\.\d+$" -and $_.IPAddress -ne $gateway }

    foreach ($neighbor in $neighbors) {
        $ip = $neighbor.IPAddress
        if (Test-Port $ip 47989) {
            $HostIP = $ip
            Write-Pass "Auto-detected Sunshine host: $HostIP"
            break
        }
    }

    if (-not $HostIP) {
        $subnet = ($localIP -replace "\.\d+$", "")
        Write-Info "Scanning $subnet.0/24 for Sunshine host..."
        for ($i = 1; $i -le 254; $i++) {
            $ip = "$subnet.$i"
            if ($ip -eq $localIP) { continue }
            $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds 1
            if ($ping -and (Test-Port $ip 47989)) {
                $HostIP = $ip
                Write-Pass "Found Sunshine host: $HostIP"
                break
            }
        }
    }

    if (-not $HostIP) {
        Write-Fail "Could not auto-detect Sunshine host. Use -HostIP to specify."
        exit 1
    }
} else {
    Write-Info "Using specified host: $HostIP"
}

# --- Adapter Advanced Settings ---

Write-Header "ADAPTER SETTINGS"

$advProps = Get-NetAdapterAdvancedProperty -Name $adapterName
$jumbo = ($advProps | Where-Object { $_.DisplayName -eq "Jumbo Frame" }).DisplayValue
$eee = ($advProps | Where-Object { $_.DisplayName -eq "Energy-Efficient Ethernet" }).DisplayValue
$flowCtrl = ($advProps | Where-Object { $_.DisplayName -eq "Flow Control" }).DisplayValue
$selectiveSuspend = ($advProps | Where-Object { $_.DisplayName -eq "Selective suspend" }).DisplayValue

if ($jumbo -match "Disabled|1514") { Write-Warn "Jumbo Frames: $jumbo (consider enabling 9014)" } else { Write-Pass "Jumbo Frames: $jumbo" }
if ($eee -match "Enabled") { Write-Warn "Energy-Efficient Ethernet: $eee (adds latency)" } else { Write-Pass "Energy-Efficient Ethernet: $eee" }
if ($selectiveSuspend -match "Enabled") { Write-Warn "Selective Suspend: $selectiveSuspend (can cause disconnects)" } else { Write-Pass "Selective Suspend: $selectiveSuspend" }
Write-Info "Flow Control: $flowCtrl"

# --- Interface Priority ---

Write-Header "ROUTING PRIORITY"

$interfaces = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.ConnectionState -eq "Connected" } | Sort-Object InterfaceMetric
$lanMetric = ($interfaces | Where-Object { $_.InterfaceAlias -eq $adapterName }).InterfaceMetric
$wifiMetric = ($interfaces | Where-Object { $_.InterfaceAlias -match "Wi-Fi|WiFi|Wireless" }).InterfaceMetric

Write-Info "$adapterName metric: $lanMetric"
if ($wifiMetric) {
    Write-Info "Wi-Fi metric: $wifiMetric"
    if ($lanMetric -lt $wifiMetric) {
        Write-Pass "LAN is preferred over Wi-Fi"
    } else {
        Write-Warn "Wi-Fi has higher priority than LAN - traffic may route over Wi-Fi"
    }
}

$routeTest = Test-NetConnection -ComputerName $HostIP -WarningAction SilentlyContinue
if ($routeTest.InterfaceAlias -eq $adapterName) {
    Write-Pass "Traffic to $HostIP routes through $adapterName"
} else {
    Write-Warn "Traffic to $HostIP routes through $($routeTest.InterfaceAlias) instead of $adapterName"
}

# --- Latency Test ---

Write-Header "LATENCY TEST (Gateway)"

$gwPing = Test-Connection -ComputerName $gateway -Count 10 -ErrorAction SilentlyContinue
if ($gwPing) {
    $gwAvg = [math]::Round(($gwPing | Measure-Object -Property Latency -Average).Average, 2)
    $gwMax = ($gwPing | Measure-Object -Property Latency -Maximum).Maximum
    $gwLoss = 10 - $gwPing.Count
    Write-Info "Gateway ($gateway): Avg ${gwAvg}ms, Max ${gwMax}ms, Loss $gwLoss/10"
} else {
    Write-Fail "Cannot reach gateway $gateway"
}

Write-Header "LATENCY TEST (Host - 50 packets)"

$hostPing = Test-Connection -ComputerName $HostIP -Count 50 -ErrorAction SilentlyContinue
if ($hostPing) {
    $hostAvg = [math]::Round(($hostPing | Measure-Object -Property Latency -Average).Average, 2)
    $hostMin = ($hostPing | Measure-Object -Property Latency -Minimum).Minimum
    $hostMax = ($hostPing | Measure-Object -Property Latency -Maximum).Maximum
    $hostLoss = 50 - $hostPing.Count
    $latencies = $hostPing | ForEach-Object { $_.Latency }
    $jitter = if ($latencies.Count -gt 1) {
        $diffs = for ($i = 1; $i -lt $latencies.Count; $i++) { [math]::Abs($latencies[$i] - $latencies[$i-1]) }
        [math]::Round(($diffs | Measure-Object -Average).Average, 2)
    } else { 0 }

    Write-Info "Host ($HostIP): Avg ${hostAvg}ms, Min ${hostMin}ms, Max ${hostMax}ms"
    Write-Info "Jitter: ${jitter}ms, Packet Loss: $hostLoss/50"

    if ($hostAvg -le 1) { Write-Pass "Latency: Excellent (<= 1ms)" }
    elseif ($hostAvg -le 5) { Write-Pass "Latency: Good (<= 5ms)" }
    elseif ($hostAvg -le 10) { Write-Warn "Latency: Acceptable (<= 10ms)" }
    else { Write-Fail "Latency: High (> 10ms) - may cause input lag" }

    if ($hostLoss -eq 0) { Write-Pass "Packet Loss: None" }
    elseif ($hostLoss -le 2) { Write-Warn "Packet Loss: Minor ($hostLoss/50)" }
    else { Write-Fail "Packet Loss: Significant ($hostLoss/50)" }
} else {
    Write-Fail "Cannot reach host $HostIP"
    exit 1
}

# --- MTU Test ---

Write-Header "MTU TEST"

$mtuSizes = @(
    @{ Name = "Standard (1500)"; Size = 1472 },
    @{ Name = "Jumbo (9000)"; Size = 8972 }
)

foreach ($mtu in $mtuSizes) {
    $result = ping -n 2 -l $mtu.Size -f $HostIP 2>&1
    if ($result -match "Reply from") {
        Write-Pass "$($mtu.Name): Working"
    } else {
        Write-Warn "$($mtu.Name): Not supported end-to-end"
    }
}

# --- Internet via LAN ---

Write-Header "INTERNET ROUTING TEST"

$inetResult = ping -n 2 -S $localIP 8.8.8.8 2>&1
if ($inetResult -match "Reply from 8.8.8.8") {
    $inetTime = [regex]::Match($inetResult, "time[=<](\d+)").Groups[1].Value
    Write-Pass "Internet via LAN: Working (${inetTime}ms)"
} else {
    Write-Warn "Internet via LAN: Not working (traffic uses another interface)"
}

# --- Sunshine Ports ---

Write-Header "SUNSHINE PORT CHECK"

$ports = @(
    @{ Port = 47984; Desc = "HTTPS/API" },
    @{ Port = 47989; Desc = "HTTP Discovery" },
    @{ Port = 47990; Desc = "Web UI" },
    @{ Port = 48010; Desc = "RTSP Control" }
)

foreach ($p in $ports) {
    if (Test-Port $HostIP $p.Port) {
        Write-Pass "Port $($p.Port) ($($p.Desc)): Open"
    } else {
        Write-Fail "Port $($p.Port) ($($p.Desc)): Closed"
    }
}

Write-Info "Ports 47998-48000 (Video/Audio/Control) are UDP - not testable via TCP"

# --- Moonlight Detection ---

Write-Header "MOONLIGHT CLIENT"

$moonlightPath = $null
$searchPaths = @(
    "C:\Program Files\Moonlight Game Streaming\Moonlight.exe",
    "C:\Program Files (x86)\Moonlight Game Streaming\Moonlight.exe",
    "$env:LOCALAPPDATA\Moonlight Game Streaming\Moonlight.exe"
)

foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        $moonlightPath = $path
        break
    }
}

if ($moonlightPath) {
    $version = & $moonlightPath --version 2>&1 | Select-String -Pattern "\d+\.\d+\.\d+"
    Write-Pass "Moonlight found: $moonlightPath"
    if ($version) { Write-Info "Version: $($version.Matches.Value)" }
} else {
    Write-Warn "Moonlight not found in standard locations"
    if (-not $SkipStream) {
        Write-Info "Skipping stream test. Install Moonlight or use -SkipStream"
        $SkipStream = $true
    }
}

# --- Moonlight Config ---

$configPath = "$env:LOCALAPPDATA\Moonlight Game Streaming\Moonlight Game Streaming.conf"
if (Test-Path $configPath) {
    Write-Info "Config: $configPath"
    $config = Get-Content $configPath
    foreach ($line in $config) {
        if ($line.Trim()) { Write-Info "  $line" }
    }
}

# --- Stream Test ---

if (-not $SkipStream) {
    Write-Header "MOONLIGHT STREAM TEST ($Resolution @ ${FPS}fps, ${Bitrate}kbps, ${Duration}s)"

    $resFlag = switch ($Resolution) {
        "720"  { "--720" }
        "1080" { "--1080" }
        "1440" { "--1440" }
        "4K"   { "--4K" }
    }

    $logFile = "$env:TEMP\moonlight-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    $args = @(
        "stream", $HostIP, "`"$App`"",
        $resFlag, "--fps", $FPS,
        "--bitrate", $Bitrate,
        "--packet-size", $PacketSize,
        "--performance-overlay",
        "--no-vsync",
        "--display-mode", "windowed",
        "--video-codec", "auto",
        "--video-decoder", "auto"
    )

    Write-Info "Launching Moonlight stream..."
    Write-Info "Log: $logFile"

    $process = Start-Process -FilePath $moonlightPath -ArgumentList $args -RedirectStandardError $logFile -PassThru -NoNewWindow
    Start-Sleep -Seconds $Duration

    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force 2>$null
        Start-Sleep -Seconds 2
    }

    if (Test-Path $logFile) {
        $log = Get-Content $logFile -Raw

        # Parse results
        $streamRes = [regex]::Match($log, "Video stream is (\d+x\d+x\d+)").Groups[1].Value
        $bitrateActual = [regex]::Match($log, "Video bitrate: (\d+) kbps").Groups[1].Value
        $firstVideo = [regex]::Match($log, "Received first video packet after (\d+) ms").Groups[1].Value
        $firstAudio = [regex]::Match($log, "Received first audio packet after (\d+) ms").Groups[1].Value
        $codec = if ($log -match "\[hevc") { "HEVC" } elseif ($log -match "\[h264") { "H.264" } elseif ($log -match "\[av1") { "AV1" } else { "Unknown" }
        $decoder = if ($log -match "D3D11VA") { "D3D11VA (Hardware)" } elseif ($log -match "CUDA") { "CUDA (Hardware)" } elseif ($log -match "software") { "Software" } else { "Unknown" }
        $rfiEvents = ([regex]::Matches($log, "Invalidate reference frame request sent \((\d+) to \1\)")).Count
        $packetSizeUsed = [regex]::Match($log, "packet size: (\d+) bytes").Groups[1].Value

        Write-Host ""
        Write-Host "  --- Stream Results ---" -ForegroundColor Cyan
        if ($streamRes) { Write-Info "Stream: $streamRes" }
        if ($bitrateActual) { Write-Info "Bitrate: ${bitrateActual} kbps" }
        if ($packetSizeUsed) { Write-Info "Packet Size: ${packetSizeUsed} bytes" }
        Write-Info "Codec: $codec | Decoder: $decoder"
        if ($firstVideo) { Write-Info "First Video Packet: ${firstVideo}ms" }
        if ($firstAudio) { Write-Info "First Audio Packet: ${firstAudio}ms" }
        Write-Info "RFI Events (frame recovery): $rfiEvents in ${Duration}s"

        if ($rfiEvents -eq 0) { Write-Pass "Stream Quality: Perfect - no frame recovery needed" }
        elseif ($rfiEvents -le 2) { Write-Pass "Stream Quality: Excellent - minimal frame recovery" }
        elseif ($rfiEvents -le 5) { Write-Warn "Stream Quality: Good - some frame recovery events" }
        else { Write-Fail "Stream Quality: Poor - frequent frame recovery ($rfiEvents events)" }

        if ($log -match "Network dropped") { Write-Fail "Network drops detected" }
        if ($log -match "frame loss") { Write-Warn "Frame loss detected" }

    } else {
        Write-Fail "No log output captured"
    }
}

# --- Summary ---

Write-Header "SUMMARY"

Write-Host "  Adapter:     $adapterDesc ($linkSpeed)" -ForegroundColor White
Write-Host "  Local IP:    $localIP" -ForegroundColor White
Write-Host "  Host IP:     $HostIP" -ForegroundColor White
Write-Host "  Latency:     ${hostAvg}ms avg, ${jitter}ms jitter" -ForegroundColor White
Write-Host "  Packet Loss: $hostLoss/50" -ForegroundColor White
Write-Host "  Jumbo MTU:   $jumbo" -ForegroundColor White
if (-not $SkipStream) {
    Write-Host "  Stream:      $streamRes @ ${bitrateActual}kbps ($codec/$decoder)" -ForegroundColor White
    Write-Host "  RFI Events:  $rfiEvents in ${Duration}s" -ForegroundColor White
}
Write-Host ""
