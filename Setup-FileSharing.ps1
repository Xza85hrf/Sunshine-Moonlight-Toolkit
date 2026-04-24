<#
.SYNOPSIS
    File Sharing Setup - Run on your DESKTOP (Host PC)

.DESCRIPTION
    Configures Windows file sharing for Sunshine/Moonlight setups:
    - Fixes SMB configuration for cross-platform access
    - Handles Microsoft Account PIN authentication issues
    - Creates dedicated sharing user account
    - Sets up SMB shares with correct NTFS permissions
    - Enables File and Printer Sharing firewall rules

.NOTES
    MUST RUN AS ADMINISTRATOR!

.EXAMPLE
    # Right-click PowerShell -> Run as Administrator, then:
    powershell -ExecutionPolicy Bypass -File ".\Setup-FileSharing.ps1"
#>

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Clear-Host
Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host "       FILE SHARING SETUP                                       " -ForegroundColor Magenta
Write-Host "       Run on: Your Desktop (Host PC)                           " -ForegroundColor Magenta
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host ""

if (-not $isAdmin) {
    Write-Host "  [ERROR] This script must run as ADMINISTRATOR!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  How to run:" -ForegroundColor Yellow
    Write-Host "    1. Right-click PowerShell" -ForegroundColor Gray
    Write-Host "    2. Select 'Run as Administrator'" -ForegroundColor Gray
    Write-Host "    3. Run this script again" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "  [OK] Running as Administrator" -ForegroundColor Green
Write-Host ""

$sharingUser = $null
$createdShares = @()

# ============================================================================
# 1. CHECK NETWORK PROFILE
# ============================================================================

Write-Host "  Step 1: Checking Network Profile..." -ForegroundColor Yellow
Write-Host "  ------------------------------------" -ForegroundColor Gray

$ethernetProfile = Get-NetConnectionProfile -InterfaceAlias "Ethernet" -ErrorAction SilentlyContinue

if ($ethernetProfile) {
    Write-Host "    Current: $($ethernetProfile.NetworkCategory)" -ForegroundColor Gray

    if ($ethernetProfile.NetworkCategory -ne "Private") {
        Write-Host "    [!] Ethernet is set to '$($ethernetProfile.NetworkCategory)' - changing to Private..." -ForegroundColor Yellow

        try {
            Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
            Write-Host "    [OK] Ethernet set to Private" -ForegroundColor Green
        } catch {
            Write-Host "    [ERROR] Failed to change: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "    [OK] Ethernet already set to Private" -ForegroundColor Green
    }
} else {
    Write-Host "    [!] No 'Ethernet' adapter found, checking others..." -ForegroundColor Yellow

    Get-NetConnectionProfile | ForEach-Object {
        if ($_.InterfaceAlias -notlike "*Tailscale*" -and $_.InterfaceAlias -notlike "*Loopback*") {
            Write-Host "    Found: $($_.InterfaceAlias) = $($_.NetworkCategory)" -ForegroundColor Gray
            if ($_.NetworkCategory -eq "Public") {
                try {
                    Set-NetConnectionProfile -InterfaceAlias $_.InterfaceAlias -NetworkCategory Private
                    Write-Host "    [OK] $($_.InterfaceAlias) set to Private" -ForegroundColor Green
                } catch {
                    Write-Host "    [!] Could not change $($_.InterfaceAlias)" -ForegroundColor Yellow
                }
            }
        }
    }
}

Write-Host ""

# ============================================================================
# 2. CHECK SMB CONFIGURATION
# ============================================================================

Write-Host "  Step 2: Checking SMB Configuration..." -ForegroundColor Yellow
Write-Host "  --------------------------------------" -ForegroundColor Gray

try {
    $smbConfig = Get-SmbServerConfiguration

    if ($smbConfig.RejectUnencryptedAccess) {
        Write-Host "    [!] RejectUnencryptedAccess is ENABLED" -ForegroundColor Yellow
        Write-Host "        Older clients and Linux/macOS may fail to connect." -ForegroundColor Yellow
        $response = Read-Host "    Disable RejectUnencryptedAccess? (Y/n)"
        if ([string]::IsNullOrWhiteSpace($response) -or $response -match "^[Yy]$") {
            Set-SmbServerConfiguration -RejectUnencryptedAccess $false -Force -Confirm:$false
            Write-Host "    [OK] RejectUnencryptedAccess disabled" -ForegroundColor Green
        } else {
            Write-Host "    Skipped." -ForegroundColor Gray
        }
    } else {
        Write-Host "    [OK] RejectUnencryptedAccess is disabled" -ForegroundColor Green
    }

    if ($smbConfig.RequireSecuritySignature) {
        Write-Host "    [!] RequireSecuritySignature is ENABLED" -ForegroundColor Yellow
        Write-Host "        Some clients may fail to connect." -ForegroundColor Yellow
        $response = Read-Host "    Disable RequireSecuritySignature? (Y/n)"
        if ([string]::IsNullOrWhiteSpace($response) -or $response -match "^[Yy]$") {
            Set-SmbServerConfiguration -RequireSecuritySignature $false -Force -Confirm:$false
            Write-Host "    [OK] RequireSecuritySignature disabled" -ForegroundColor Green
        } else {
            Write-Host "    Skipped." -ForegroundColor Gray
        }
    } else {
        Write-Host "    [OK] RequireSecuritySignature is disabled" -ForegroundColor Green
    }
} catch {
    Write-Host "    [ERROR] Failed to check SMB configuration: $_" -ForegroundColor Red
}

Write-Host ""

# ============================================================================
# 3. DETECT MICROSOFT ACCOUNT
# ============================================================================

Write-Host "  Step 3: Checking Account Type..." -ForegroundColor Yellow
Write-Host "  ---------------------------------" -ForegroundColor Gray

try {
    $username = $env:USERNAME
    $localUser = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
    $isMicrosoftAccount = $false

    if ($localUser -and $localUser.PrincipalSource -eq "MicrosoftAccount") {
        $isMicrosoftAccount = $true
    }

    if ($isMicrosoftAccount) {
        Write-Host "    [!] Current user '$username' is a Microsoft Account" -ForegroundColor Yellow
        Write-Host "        Windows Hello PIN will NOT work for SMB authentication!" -ForegroundColor Yellow
        Write-Host "        You need your Microsoft Account password, or create a" -ForegroundColor Yellow
        Write-Host "        dedicated local sharing user (Step 4)." -ForegroundColor Yellow
    } else {
        Write-Host "    [OK] Current user '$username' is a Local Account" -ForegroundColor Green
    }
} catch {
    Write-Host "    [!] Could not determine account type" -ForegroundColor Yellow
}

Write-Host ""

# ============================================================================
# 4. CREATE LOCAL SHARING USER
# ============================================================================

Write-Host "  Step 4: Local Sharing User..." -ForegroundColor Yellow
Write-Host "  ------------------------------" -ForegroundColor Gray

$response = Read-Host "    Create a dedicated file sharing user? (Y/n)"
if ([string]::IsNullOrWhiteSpace($response) -or $response -match "^[Yy]$") {
    $defaultUsername = "shareuser"
    $inputUsername = Read-Host "    Enter username (default: $defaultUsername)"
    if ([string]::IsNullOrWhiteSpace($inputUsername)) {
        $inputUsername = $defaultUsername
    }

    $passwordSecure = Read-Host "    Enter password for '$inputUsername'" -AsSecureString

    try {
        New-LocalUser -Name $inputUsername -Password $passwordSecure `
            -FullName "File Sharing User" `
            -PasswordNeverExpires `
            -UserMayNotChangePassword -ErrorAction Stop | Out-Null
        Add-LocalGroupMember -Group "Users" -Member $inputUsername -ErrorAction SilentlyContinue
        Write-Host "    [OK] User '$inputUsername' created successfully" -ForegroundColor Green
        $sharingUser = $inputUsername
    } catch {
        if ($_.Exception.Message -like "*already exists*") {
            Write-Host "    [!] User '$inputUsername' already exists - will use it" -ForegroundColor Yellow
            $sharingUser = $inputUsername
        } else {
            Write-Host "    [ERROR] Failed to create user: $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "    Skipped user creation." -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# 5. LIST SMB SHARES & FIX PERMISSIONS
# ============================================================================

Write-Host "  Step 5: SMB Shares & Permissions..." -ForegroundColor Yellow
Write-Host "  ------------------------------------" -ForegroundColor Gray

try {
    $shares = Get-SmbShare | Where-Object { $_.Name -notmatch '^(C\$|ADMIN\$|IPC\$|print\$)$' }

    if ($shares -and $shares.Count -gt 0) {
        Write-Host "    Found $($shares.Count) non-system share(s):" -ForegroundColor Green
        Write-Host ""

        foreach ($share in $shares) {
            Write-Host "    Share: $($share.Name)" -ForegroundColor Cyan
            Write-Host "      Path: $($share.Path)" -ForegroundColor Gray
            if ($share.Description) {
                Write-Host "      Desc: $($share.Description)" -ForegroundColor Gray
            }

            if ($share.Path -and (Test-Path $share.Path)) {
                try {
                    $acl = Get-Acl -Path $share.Path
                    foreach ($access in $acl.Access) {
                        Write-Host "      NTFS: $($access.IdentityReference) = $($access.FileSystemRights)" -ForegroundColor Gray
                    }
                } catch {
                    Write-Host "      [!] Could not read NTFS permissions" -ForegroundColor Yellow
                }

                if ($sharingUser) {
                    $grantResponse = Read-Host "    Grant full access to '$sharingUser' on '$($share.Name)'? (Y/n)"
                    if ([string]::IsNullOrWhiteSpace($grantResponse) -or $grantResponse -match "^[Yy]$") {
                        icacls "$($share.Path)" /grant "${sharingUser}:(OI)(CI)F" /T | Out-Null
                        Write-Host "    [OK] NTFS permissions granted to '$sharingUser'" -ForegroundColor Green
                    }
                }
            }
            Write-Host ""
        }
    } else {
        Write-Host "    [!] No non-system SMB shares found" -ForegroundColor Yellow
        $createResponse = Read-Host "    Create a new share? (Y/n)"
        if ([string]::IsNullOrWhiteSpace($createResponse) -or $createResponse -match "^[Yy]$") {
            $sharePath = Read-Host "    Enter folder path to share"
            $shareName = Read-Host "    Enter share name"

            if (-not (Test-Path $sharePath)) {
                Write-Host "    [!] Path does not exist - creating folder..." -ForegroundColor Yellow
                New-Item -ItemType Directory -Path $sharePath -Force | Out-Null
            }

            try {
                if ($sharingUser) {
                    New-SmbShare -Name $shareName -Path $sharePath -FullAccess $sharingUser | Out-Null
                    icacls "$sharePath" /grant "${sharingUser}:(OI)(CI)F" /T | Out-Null
                    Write-Host "    [OK] Share '$shareName' created with access for '$sharingUser'" -ForegroundColor Green
                } else {
                    New-SmbShare -Name $shareName -Path $sharePath -FullAccess "Everyone" | Out-Null
                    Write-Host "    [OK] Share '$shareName' created with Everyone access" -ForegroundColor Green
                }
                $createdShares += $shareName
            } catch {
                Write-Host "    [ERROR] Failed to create share: $_" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "    [ERROR] Failed to list shares: $_" -ForegroundColor Red
}

Write-Host ""

# ============================================================================
# 6. CHECK FIREWALL RULES
# ============================================================================

Write-Host "  Step 6: Firewall Rules..." -ForegroundColor Yellow
Write-Host "  --------------------------" -ForegroundColor Gray

try {
    $firewallRules = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue

    if ($firewallRules) {
        $enabledCount = @($firewallRules | Where-Object { $_.Enabled -eq $true }).Count
        $disabledCount = @($firewallRules | Where-Object { $_.Enabled -eq $false }).Count

        Write-Host "    File and Printer Sharing rules: $enabledCount enabled, $disabledCount disabled" -ForegroundColor Gray

        if ($disabledCount -gt 0) {
            $enableResponse = Read-Host "    Enable all File and Printer Sharing rules? (Y/n)"
            if ([string]::IsNullOrWhiteSpace($enableResponse) -or $enableResponse -match "^[Yy]$") {
                Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
                Write-Host "    [OK] All File and Printer Sharing rules enabled" -ForegroundColor Green
            } else {
                Write-Host "    Skipped." -ForegroundColor Gray
            }
        } else {
            Write-Host "    [OK] All rules already enabled" -ForegroundColor Green
        }
    } else {
        Write-Host "    [!] No File and Printer Sharing rules found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    [ERROR] Failed to check firewall rules: $_" -ForegroundColor Red
}

Write-Host ""

# ============================================================================
# 7. CONNECTION INSTRUCTIONS
# ============================================================================

Write-Host "  Step 7: Connection Instructions..." -ForegroundColor Yellow
Write-Host "  ------------------------------------" -ForegroundColor Gray
Write-Host ""

$lanIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.*" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress
$tailscaleIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "100.*" } | Select-Object -First 1).IPAddress

# Collect all share names
$allShares = @()
$existingShares = Get-SmbShare | Where-Object { $_.Name -notmatch '^(C\$|ADMIN\$|IPC\$|print\$)$' }
if ($existingShares) { $allShares += $existingShares.Name }
$allShares += $createdShares
$allShares = $allShares | Select-Object -Unique

$connectUser = if ($sharingUser) { $sharingUser } else { $env:USERNAME }

if ($allShares.Count -gt 0) {
    $exampleShare = $allShares[0]

    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host "       HOW TO CONNECT FROM OTHER DEVICES                        " -ForegroundColor Cyan
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($lanIP) {
        Write-Host "  LAN Connection ($lanIP):" -ForegroundColor White
        Write-Host "    Windows Explorer:  \\$lanIP\$exampleShare" -ForegroundColor Cyan
        Write-Host "    Windows CMD:       net use Z: \\$lanIP\$exampleShare /user:$connectUser" -ForegroundColor Cyan
        Write-Host "    Linux:             smbclient //$lanIP/$exampleShare -U $connectUser" -ForegroundColor Cyan
        Write-Host "    macOS Finder:      smb://$lanIP/$exampleShare" -ForegroundColor Cyan
        Write-Host ""
    }

    if ($tailscaleIP) {
        Write-Host "  Remote via Tailscale ($tailscaleIP):" -ForegroundColor White
        Write-Host "    Windows Explorer:  \\$tailscaleIP\$exampleShare" -ForegroundColor Cyan
        Write-Host "    Windows CMD:       net use Z: \\$tailscaleIP\$exampleShare /user:$connectUser" -ForegroundColor Cyan
        Write-Host "    Linux:             smbclient //$tailscaleIP/$exampleShare -U $connectUser" -ForegroundColor Cyan
        Write-Host "    macOS Finder:      smb://$tailscaleIP/$exampleShare" -ForegroundColor Cyan
        Write-Host ""
    }

    if ($sharingUser) {
        Write-Host "  Credentials:" -ForegroundColor White
        Write-Host "    Username: $sharingUser" -ForegroundColor Cyan
        Write-Host "    Password: (as configured during setup)" -ForegroundColor Cyan
        Write-Host ""
    }

    if ($allShares.Count -gt 1) {
        Write-Host "  All available shares:" -ForegroundColor White
        foreach ($s in $allShares) {
            Write-Host "    - $s" -ForegroundColor Cyan
        }
        Write-Host ""
    }
} else {
    Write-Host "    [!] No shares configured. Re-run this script to create one." -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "  =============================================================" -ForegroundColor Green
Write-Host "       FILE SHARING SETUP COMPLETE!                             " -ForegroundColor Green
Write-Host "  =============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "  Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
