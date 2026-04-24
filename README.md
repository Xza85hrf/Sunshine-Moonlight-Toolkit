# Sunshine-Moonlight-Toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue.svg)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.0%2B-blue.svg)](https://docs.microsoft.com/powershell/)

A complete Windows toolkit for optimizing game streaming with **Sunshine** (host) and **Moonlight** (client), with **Tailscale** VPN support for remote streaming.

## Features

- **One-click setup wizard** - Configure your network settings once
- **5 optimized streaming profiles** - From Performance to Ultra quality
- **Connection diagnostics** - Test latency, bandwidth, and port connectivity
- **Real-time monitoring** - Track stream quality during gameplay
- **Auto-configuration** - Firewall rules and network optimization
- **Tailscale support** - Stream remotely over VPN

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.0 or later (included in Windows)
- [Sunshine](https://github.com/LizardByte/Sunshine) installed on host PC
- [Moonlight](https://moonlight-stream.org/) installed on client PC
- [Tailscale](https://tailscale.com/) (optional, for remote streaming)

## Quick Start

### 1. Download

```bash
git clone https://github.com/Xza85hrf/Sunshine-Moonlight-Toolkit.git
```

Or download the ZIP and extract it.

### 2. First-Time Setup

Run the setup wizard to configure your network:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Setup-Toolkit.ps1"
```

Or double-click `Toolkit-Launcher.bat` and select **[0] Setup**.

### 3. Use the Toolkit

Double-click `Toolkit-Launcher.bat` to access all tools:

```
[0] Setup / Configure Toolkit
[1] Apply Moonlight Settings
[2] Test Connection
[3] Stream Monitor
[4] Full Diagnostics                (will prompt for host Tailscale IP)
[5] Optimize Sunshine Host (Admin)
[6] Fix Tailscale Stuck (Admin)
```

> **Note:** Option `[4] Full Diagnostics` invokes
> `Sunshine-Moonlight-Optimizer.ps1`, which declares `-HostTailscaleIP`
> as a mandatory parameter. When launched from the menu without that
> flag, PowerShell prompts for it interactively before the script
> continues. To skip the prompt, call the script directly:
> `powershell -ExecutionPolicy Bypass -File Sunshine-Moonlight-Optimizer.ps1 -HostTailscaleIP 100.x.x.x`.

## Scripts Included

| Script | Run On | Purpose |
|--------|--------|---------|
| `Setup-Toolkit.ps1` | Either | First-time configuration wizard |
| `Apply-OptimalSettings.ps1` | Client | Configure Moonlight with optimized profiles |
| `Test-Connection.ps1` | Client | Test connection quality to host |
| `Stream-Monitor.ps1` | Client | Real-time stream quality monitoring |
| `Sunshine-Moonlight-Optimizer.ps1` | Client | Comprehensive network diagnostics |
| `Optimize-SunshineHost.ps1` | Host | Configure firewall and network (Admin) |
| `Fix-Tailscale.ps1` | Either | Fix Tailscale stuck on "Starting..." (Admin) |

## Streaming Profiles

| Profile | Resolution | FPS | Bitrate | Best For |
|---------|------------|-----|---------|----------|
| **Performance** | 720p | 60 | 20 Mbps | Older hardware, testing |
| **Balanced** | 1080p | 60 | 50 Mbps | General gaming |
| **Quality** | 1080p | 60 | 80 Mbps | Visual quality priority |
| **Ultra** | 1080p | 120 | 100 Mbps | LAN connections (recommended) |
| **Competitive** | 1080p | 120 | 60 Mbps | FPS games, low latency |

## Network Requirements

### Ports Used by Sunshine

| Port | Protocol | Purpose |
|------|----------|---------|
| 47984 | TCP | HTTPS/API |
| 47989 | TCP | RTSP |
| 47990 | TCP | HTTP/WebUI |
| 47998 | UDP | Video Stream |
| 47999 | UDP | Audio Stream |
| 48000 | UDP | Control Input |
| 48010 | UDP | Alt Control |

### Recommended Bandwidth

| Quality | Minimum | Recommended |
|---------|---------|-------------|
| 720p/60fps | 15 Mbps | 20+ Mbps |
| 1080p/60fps | 30 Mbps | 50+ Mbps |
| 1080p/120fps | 50 Mbps | 80+ Mbps |
| 4K/60fps | 80 Mbps | 100+ Mbps |

## Usage Examples

### Apply Ultra Profile

```powershell
powershell -ExecutionPolicy Bypass -File ".\Apply-OptimalSettings.ps1" -Profile Ultra
```

### Test Connection to Specific IP

```powershell
powershell -ExecutionPolicy Bypass -File ".\Test-Connection.ps1" -HostIP "192.168.1.100"
```

### Run Full Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File ".\Sunshine-Moonlight-Optimizer.ps1" -HostTailscaleIP "100.x.x.x" -Detailed
```

## Troubleshooting

### "Slow connection" warning in Moonlight

This is often a false positive. If your actual streaming works fine, ignore it.

### Ports appear closed

1. Run `Optimize-SunshineHost.ps1` on the host PC (as Administrator)
2. Ensure Sunshine is running
3. Check Windows Firewall settings

### Tailscale stuck on "Starting..."

Run `Fix-Tailscale.ps1` as Administrator. You'll need to log in again.

### High latency when on LAN

Make sure you're connecting to the LAN IP, not the Tailscale IP.

### Can't reach host

1. Verify the host IP is correct in your config
2. Run `Test-Connection.ps1` to diagnose
3. Check that both devices are on the same network (for LAN)

## Configuration

Your settings are stored in `config.json`. You can edit this manually or run `Setup-Toolkit.ps1` again.

```json
{
  "host": {
    "lan_ip": "192.168.1.100",
    "tailscale_ip": "100.x.x.x",
    "name": "Gaming PC"
  },
  "preferences": {
    "default_profile": "Ultra"
  }
}
```

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Sunshine](https://github.com/LizardByte/Sunshine) - Open-source game streaming host
- [Moonlight](https://moonlight-stream.org/) - Open-source game streaming client
- [Tailscale](https://tailscale.com/) - Secure mesh VPN

## Support

- Open an [issue](../../issues) for bugs or feature requests
- Check [existing issues](../../issues) before creating a new one
- Star the repo if you find it useful!
