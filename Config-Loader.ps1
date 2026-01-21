<#
.SYNOPSIS
    Configuration loader for Sunshine-Moonlight-Toolkit

.DESCRIPTION
    Provides functions to load and validate the toolkit configuration.
    This file is dot-sourced by other scripts in the toolkit.
#>

$script:ConfigPath = Join-Path $PSScriptRoot "config.json"

function Get-ToolkitConfig {
    <#
    .SYNOPSIS
        Loads the toolkit configuration from config.json
    #>

    if (-not (Test-Path $script:ConfigPath)) {
        return $null
    }

    try {
        $config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
        return $config
    } catch {
        Write-Host "  [ERROR] Failed to read config.json: $_" -ForegroundColor Red
        return $null
    }
}

function Test-ToolkitConfigured {
    <#
    .SYNOPSIS
        Checks if the toolkit has been configured
    #>

    $config = Get-ToolkitConfig

    if (-not $config) {
        return $false
    }

    return $config.configured -eq $true
}

function Get-HostIP {
    <#
    .SYNOPSIS
        Returns the appropriate host IP based on connection type
    .PARAMETER PreferLAN
        If true, tries LAN first, then Tailscale
    #>
    param(
        [switch]$PreferLAN = $true
    )

    $config = Get-ToolkitConfig

    if (-not $config -or -not $config.configured) {
        return $null
    }

    if ($PreferLAN -and $config.host.lan_ip) {
        # Test if LAN is reachable
        $lanReachable = Test-Connection -ComputerName $config.host.lan_ip -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($lanReachable) {
            return @{
                IP = $config.host.lan_ip
                Type = "LAN"
            }
        }
    }

    if ($config.host.tailscale_ip) {
        $tsReachable = Test-Connection -ComputerName $config.host.tailscale_ip -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($tsReachable) {
            return @{
                IP = $config.host.tailscale_ip
                Type = "Tailscale"
            }
        }
    }

    # Return LAN IP even if unreachable (let caller handle)
    if ($config.host.lan_ip) {
        return @{
            IP = $config.host.lan_ip
            Type = "LAN"
        }
    }

    return $null
}

function Save-ToolkitConfig {
    <#
    .SYNOPSIS
        Saves configuration to config.json
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    try {
        $Config | ConvertTo-Json -Depth 10 | Set-Content $script:ConfigPath -Force
        return $true
    } catch {
        Write-Host "  [ERROR] Failed to save config.json: $_" -ForegroundColor Red
        return $false
    }
}

function Show-ConfigurationRequired {
    <#
    .SYNOPSIS
        Displays a message that configuration is required
    #>

    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Yellow
    Write-Host "       CONFIGURATION REQUIRED                                   " -ForegroundColor Yellow
    Write-Host "  =============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  This toolkit needs to be configured before first use." -ForegroundColor White
    Write-Host ""
    Write-Host "  Please run: " -NoNewline -ForegroundColor White
    Write-Host "Setup-Toolkit.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Or use the launcher and select 'Setup/Configure'" -ForegroundColor Gray
    Write-Host ""
}

# Export functions
Export-ModuleMember -Function Get-ToolkitConfig, Test-ToolkitConfigured, Get-HostIP, Save-ToolkitConfig, Show-ConfigurationRequired -ErrorAction SilentlyContinue
