# Moonlight/Sunshine LAN Streaming Diagnostics

A PowerShell script that tests network connectivity, adapter configuration, and Moonlight streaming performance between a client and a Sunshine host over LAN.

## Requirements

- Windows 10/11
- [Moonlight Game Streaming](https://moonlight-stream.org/) installed (optional — network tests run without it)
- [Sunshine](https://github.com/LizardByte/Sunshine) running on the host PC
- Wired LAN connection between client and host

## Quick Start

```powershell
# Run with defaults (auto-detects adapter and host)
.\moonlight-test.ps1

# If execution policy blocks it
powershell -ExecutionPolicy Bypass -File .\moonlight-test.ps1
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-HostIP` | auto-detect | IP address of the Sunshine host |
| `-Resolution` | `1080` | Stream resolution: `720`, `1080`, `1440`, `4K` |
| `-FPS` | `144` | Target framerate |
| `-Bitrate` | `150000` | Video bitrate in Kbps |
| `-PacketSize` | `8192` | Packet size in bytes (`1024` standard, `8192` jumbo) |
| `-Duration` | `20` | Stream test duration in seconds |
| `-App` | `Desktop` | Sunshine app to stream |
| `-SkipStream` | `false` | Skip stream test, only run network diagnostics |
| `-AdapterName` | auto-detect | Network adapter name to test |

## Usage Examples

```powershell
# 4K streaming test at 250 Mbps
.\moonlight-test.ps1 -Resolution 4K -Bitrate 250000

# Network diagnostics only (no Moonlight needed)
.\moonlight-test.ps1 -SkipStream

# Specify host and adapter manually
.\moonlight-test.ps1 -HostIP 192.168.1.100 -AdapterName "Ethernet"

# 1080p at 120fps with standard packet size
.\moonlight-test.ps1 -Resolution 1080 -FPS 120 -Bitrate 80000 -PacketSize 1024

# Longer test for stability analysis
.\moonlight-test.ps1 -Resolution 1440 -Duration 60

# Stream a specific app
.\moonlight-test.ps1 -App "Steam Big Picture"
```

## What It Tests

### Network Diagnostics
- **Adapter Detection** — auto-finds 2.5G/5G/10G wired adapters, shows link speed and duplex
- **Adapter Settings** — checks jumbo frames, energy-efficient ethernet, selective suspend, flow control
- **Routing Priority** — verifies LAN is preferred over Wi-Fi by comparing interface metrics
- **Latency** — 50-packet ping test with avg/min/max/jitter calculation
- **Packet Loss** — counts dropped packets over 50 pings
- **MTU** — tests standard (1500) and jumbo (9000) frame support end-to-end
- **Internet Routing** — confirms internet traffic flows through the LAN adapter

### Sunshine Host
- **Host Detection** — auto-discovers Sunshine host on the LAN via ARP + port scan
- **Port Check** — tests TCP ports 47984 (API), 47989 (HTTP), 47990 (Web UI), 48010 (RTSP)

### Moonlight Stream
- **Stream Setup** — resolution, FPS, bitrate, codec, decoder confirmation
- **Codec Detection** — identifies HEVC, H.264, or AV1
- **Hardware Decode** — confirms D3D11VA/CUDA hardware acceleration
- **First Packet Timing** — measures video and audio stream startup latency
- **Frame Recovery (RFI)** — counts frame recovery events during the test
- **Network Drops** — detects network-level packet drops during streaming

## Output

The script uses color-coded output:

- 🟢 `[PASS]` — test passed, optimal configuration
- 🟡 `[WARN]` — test passed but could be improved
- 🔴 `[FAIL]` — test failed, action needed
- ⚪ `[INFO]` — informational

Stream logs are saved to `%TEMP%\moonlight-test-<timestamp>.log` for further analysis.

## Sample Output

```
=== NETWORK ADAPTER DETECTION ===

  [PASS] Adapter: Ethernet 2 (Realtek Gaming USB 2.5GbE Family Controller)
  [PASS] Link Speed: 2.5 Gbps
  [PASS] Full Duplex: True
  [INFO] Local IP: 192.168.50.3
  [INFO] Gateway: 192.168.50.1

=== LATENCY TEST (Host - 50 packets) ===

  [INFO] Host (192.168.50.2): Avg 0ms, Min 0ms, Max 0ms
  [INFO] Jitter: 0ms, Packet Loss: 0/50
  [PASS] Latency: Excellent (<= 1ms)
  [PASS] Packet Loss: None

=== MOONLIGHT STREAM TEST (1440 @ 144fps, 150000kbps, 20s) ===

  --- Stream Results ---
  [INFO] Stream: 2560x1440x144
  [INFO] Bitrate: 150000 kbps
  [INFO] Codec: HEVC | Decoder: D3D11VA (Hardware)
  [INFO] RFI Events (frame recovery): 1 in 20s
  [PASS] Stream Quality: Excellent - minimal frame recovery

=== SUMMARY ===

  Adapter:     Realtek Gaming USB 2.5GbE Family Controller (2.5 Gbps)
  Latency:     0ms avg, 0ms jitter
  Packet Loss: 0/50
  Jumbo MTU:   9014 Bytes
  Stream:      2560x1440x144 @ 150000kbps (HEVC/D3D11VA (Hardware))
  RFI Events:  1 in 20s
```

## Recommended Settings by Resolution

| Resolution | FPS | Bitrate (Kbps) | Packet Size | Notes |
|------------|-----|----------------|-------------|-------|
| 720p | 120-144 | 30,000-50,000 | 1024 | Low bandwidth, works over 1G |
| 1080p | 120-144 | 80,000-100,000 | 8192 | Sweet spot for most setups |
| 1440p | 120-144 | 100,000-150,000 | 8192 | Needs 2.5G+ for high bitrate |
| 4K | 120-144 | 150,000-250,000 | 8192 | Needs 2.5G+, jumbo frames recommended |

## Optimizations

If the script reports warnings, here are the fixes (run as Administrator):

**Enable Jumbo Frames (both PCs):**
```powershell
Set-NetAdapterAdvancedProperty -Name "Ethernet" -DisplayName "Jumbo Frame" -DisplayValue "9014 Bytes"
```

**Disable Energy-Efficient Ethernet:**
```powershell
Set-NetAdapterAdvancedProperty -Name "Ethernet" -DisplayName "Energy-Efficient Ethernet" -DisplayValue "Disabled"
```

**Disable Selective Suspend (USB adapters):**
```powershell
Set-NetAdapterAdvancedProperty -Name "Ethernet" -DisplayName "Selective suspend" -DisplayValue "Disabled"
```

**Lower LAN metric to prioritize over Wi-Fi:**
```powershell
Set-NetIPInterface -InterfaceAlias "Ethernet" -InterfaceMetric 10
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| No adapter found | Script can't identify LAN adapter | Use `-AdapterName "Ethernet"` |
| No host found | Sunshine not running or wrong subnet | Use `-HostIP x.x.x.x` |
| Sunshine ports closed | Firewall blocking | Allow ports 47984-48010 in Windows Firewall |
| High latency (>5ms) | Bad cable, switch, or power saving | Check cable, disable EEE |
| Jumbo MTU fails | Not enabled on both ends + switch | Enable on both adapters and switch |
| RFI events >5 | Bitrate too low or encoder overloaded | Increase bitrate or lower resolution |
| Routes through Wi-Fi | LAN has higher metric | Lower LAN metric or disable Wi-Fi |

## License

Free to use and modify.
