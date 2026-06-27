# ==============================================================================
# bootstrap-win11.ps1
# ==============================================================================
#
# NSSA320 Lab 5 - Windows 11 Bootstrap Script
#
# Purpose:
#  - Configure the Windows 11 VM for Lab 5 Ansible management
#  - Set the hostname to win11
#  - Configure the static IPv4 network settings
#  - Write the Lab 5 managed hosts-file block
#  - Enable WinRM / PowerShell remoting for Ansible
#  - Configure local account remote admin behavior
#  - Create the local ansible service account
#  - Add ansible to the local Administrators group
#
# Design:
#  - Run locally on Windows 11 as Administrator.
#  - Idempotent: re-running should confirm or re-apply the same desired state.
#  - Does not require SSH or WinRM to already be working.
#
# Author:
#  - Jared Husson
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 5.0
# Date: 2026-06-27
#
# Changes:
#  - Added first Windows 11 bootstrap script for Lab 5.
#  - Added hostname, network, hosts file, WinRM, registry, firewall, and user setup.
#
# ==============================================================================


# ==============================================================================
# Desired Lab 5 Settings
# ==============================================================================

$Domain = "jh1528.com"

$DesiredHostname = "win11"

$Win11IP = "172.16.5.4"
$PrefixLength = 29
$Gateway = "172.16.5.6"
$DnsServers = @("8.8.8.8", "1.1.1.1")

$ControlIP = "172.16.5.5"
$Ansible1IP = "172.16.5.1"
$Ansible2IP = "172.16.5.2"
$UbuntuIP = "172.16.5.3"
$GatewayIP = "172.16.5.6"

$AnsibleUser = "ansible"
$AnsiblePassword = "Password1"

$HostsFile = "C:\Windows\System32\drivers\etc\hosts"

$BeginMarker = "# BEGIN NSSA320 LAB5 HOSTS"
$EndMarker = "# END NSSA320 LAB5 HOSTS"


# ==============================================================================
# Output Helpers
# ==============================================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}


# ==============================================================================
# Safety Checks
# ==============================================================================

function Test-IsAdministrator {
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    Write-Step "Checking Administrator privileges"

    if (-not (Test-IsAdministrator)) {
        Write-Fail "This script must be run from PowerShell as Administrator."
        exit 1
    }

    Write-Pass "Administrator privileges confirmed"
}


# ==============================================================================
# Network Helpers
# ==============================================================================

function Get-PrimaryAdapter {
    Write-Step "Detecting active network adapter"

    $Adapter = Get-NetAdapter |
        Where-Object { $_.Status -eq "Up" -and $_.HardwareInterface -eq $true } |
        Sort-Object -Property InterfaceMetric |
        Select-Object -First 1

    if (-not $Adapter) {
        Write-Fail "No active network adapter found."
        exit 1
    }

    Write-Pass "Active adapter detected: $($Adapter.Name)"
    return $Adapter
}

function Set-Lab5Network {
    param(
        [Parameter(Mandatory=$true)]
        $Adapter
    )

    Write-Step "Configuring static IPv4 network settings"

    $InterfaceAlias = $Adapter.Name

    Write-Info "Interface: $InterfaceAlias"
    Write-Info "Desired IP: $Win11IP/$PrefixLength"
    Write-Info "Desired Gateway: $Gateway"
    Write-Info "Desired DNS: $($DnsServers -join ', ')"

    $CurrentIPv4 = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne "127.0.0.1" }

    $CurrentDefaultRoute = Get-NetRoute -InterfaceAlias $InterfaceAlias -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue

    $NeedsIPChange = $true

    foreach ($Address in $CurrentIPv4) {
        if ($Address.IPAddress -eq $Win11IP -and $Address.PrefixLength -eq $PrefixLength) {
            $NeedsIPChange = $false
        }
    }

    if ($NeedsIPChange) {
        Write-Warn "IPv4 address is not in desired state. Reconfiguring adapter."

        foreach ($Address in $CurrentIPv4) {
            Write-Info "Removing old IPv4 address: $($Address.IPAddress)/$($Address.PrefixLength)"
            Remove-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $Address.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
        }

        foreach ($Route in $CurrentDefaultRoute) {
            Write-Info "Removing old default route through: $($Route.NextHop)"
            Remove-NetRoute -InterfaceAlias $InterfaceAlias -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
        }

        New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $Win11IP -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
        Write-Pass "Static IPv4 address configured"
    }
    else {
        Write-Pass "Static IPv4 address already configured correctly"
    }

    $CurrentDns = (Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).ServerAddresses

    if (($CurrentDns -join ",") -ne ($DnsServers -join ",")) {
        Write-Info "Updating DNS servers"
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServers
        Write-Pass "DNS servers configured"
    }
    else {
        Write-Pass "DNS servers already configured correctly"
    }
}

function Set-Lab5NetworkProfile {
    param(
        [Parameter(Mandatory=$true)]
        $Adapter
    )

    Write-Step "Setting network profile to Private"

    $Profile = Get-NetConnectionProfile -InterfaceAlias $Adapter.Name -ErrorAction SilentlyContinue

    if (-not $Profile) {
        Write-Warn "Could not find network profile for adapter: $($Adapter.Name)"
        return
    }

    if ($Profile.NetworkCategory -eq "Private") {
        Write-Pass "Network profile is already Private"
    }
    else {
        Write-Info "Changing network profile from $($Profile.NetworkCategory) to Private"
        Set-NetConnectionProfile -InterfaceAlias $Adapter.Name -NetworkCategory Private
        Write-Pass "Network profile set to Private"
    }
}


# ==============================================================================
# Hostname and Hosts File
# ==============================================================================

function Set-Lab5Hostname {
    Write-Step "Checking Windows hostname"

    $CurrentHostname = $env:COMPUTERNAME

    Write-Info "Current hostname: $CurrentHostname"
    Write-Info "Desired hostname: $DesiredHostname"

    if ($CurrentHostname.ToLower() -eq $DesiredHostname.ToLower()) {
        Write-Pass "Hostname is already correct"
        return $false
    }

    Write-Warn "Hostname will be changed. A reboot will be required."
    Rename-Computer -NewName $DesiredHostname -Force

    Write-Pass "Hostname rename requested"
    return $true
}

function Write-Lab5HostsFileBlock {
    Write-Step "Writing Lab 5 managed hosts-file block"

    $HostsBlock = @"

$BeginMarker
# Managed by Lab 5 Windows bootstrap script.
# Do not manually edit inside this block unless you also update bootstrap-win11.ps1.
$ControlIP control.$Domain control
$Ansible1IP ansible1.$Domain ansible1
$Ansible2IP ansible2.$Domain ansible2
$UbuntuIP ubuntu.$Domain ubuntu
$Win11IP win11.$Domain win11
$GatewayIP gateway.$Domain gateway
$EndMarker
"@

    $ExistingContent = ""
    if (Test-Path $HostsFile) {
        $ExistingContent = Get-Content $HostsFile -Raw
    }

    $Pattern = "(?s)\r?\n?$([regex]::Escape($BeginMarker)).*?$([regex]::Escape($EndMarker))\r?\n?"

    if ($ExistingContent -match [regex]::Escape($BeginMarker)) {
        Write-Info "Existing Lab 5 hosts block found. Replacing it."
        $NewContent = [regex]::Replace($ExistingContent, $Pattern, "`r`n$HostsBlock`r`n")
    }
    else {
        Write-Info "No existing Lab 5 hosts block found. Appending it."
        $NewContent = $ExistingContent.TrimEnd() + "`r`n" + $HostsBlock + "`r`n"
    }

    Set-Content -Path $HostsFile -Value $NewContent -Encoding ASCII

    Write-Pass "Lab 5 hosts-file block written"
}


# ==============================================================================
# WinRM / PowerShell Remoting
# ==============================================================================

function Enable-Lab5WinRM {
    Write-Step "Configuring WinRM and PowerShell remoting"

    Write-Info "Running winrm quickconfig"
    winrm quickconfig -quiet

    Write-Info "Enabling PowerShell remoting"
    Enable-PSRemoting -Force

    Write-Info "Allowing unencrypted WinRM traffic for lab HTTP/NTLM setup"
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true

    Write-Info "Enabling Basic and NTLM-compatible local authentication settings"
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -ErrorAction SilentlyContinue

    Write-Info "Configuring LocalAccountTokenFilterPolicy for local admin remote access"
    $PolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    New-ItemProperty -Path $PolicyPath -Name "LocalAccountTokenFilterPolicy" -Value 1 -PropertyType DWORD -Force | Out-Null

    Write-Info "Ensuring Windows firewall allows WinRM HTTP"
    Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue

    Write-Pass "WinRM configuration applied"
}


# ==============================================================================
# Local Ansible User
# ==============================================================================

function Ensure-Lab5AnsibleUser {
    Write-Step "Configuring local Ansible service account"

    $SecurePassword = ConvertTo-SecureString $AnsiblePassword -AsPlainText -Force
    $ExistingUser = Get-LocalUser -Name $AnsibleUser -ErrorAction SilentlyContinue

    if (-not $ExistingUser) {
        Write-Info "Creating local user: $AnsibleUser"
        New-LocalUser -Name $AnsibleUser -Password $SecurePassword -PasswordNeverExpires -AccountNeverExpires | Out-Null
        Write-Pass "Local user created: $AnsibleUser"
    }
    else {
        Write-Info "Local user already exists: $AnsibleUser"
        Write-Info "Resetting password to the Lab 5 desired value"
        Set-LocalUser -Name $AnsibleUser -Password $SecurePassword -PasswordNeverExpires $true
        Enable-LocalUser -Name $AnsibleUser
        Write-Pass "Local user confirmed and password reset: $AnsibleUser"
    }

    $AdminMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name

    $ExpectedLocalName = "$env:COMPUTERNAME\$AnsibleUser"

    if ($AdminMembers -contains $ExpectedLocalName -or $AdminMembers -contains $AnsibleUser) {
        Write-Pass "$AnsibleUser is already a member of Administrators"
    }
    else {
        Write-Info "Adding $AnsibleUser to Administrators"
        Add-LocalGroupMember -Group "Administrators" -Member $AnsibleUser
        Write-Pass "$AnsibleUser added to Administrators"
    }
}


# ==============================================================================
# Validation
# ==============================================================================

function Show-Lab5Validation {
    Write-Step "Final validation summary"

    Write-Info "Hostname:"
    hostname

    Write-Info "IPv4 configuration:"
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -like "172.16.5.*" } |
        Format-Table InterfaceAlias,IPAddress,PrefixLength -AutoSize

    Write-Info "Default route:"
    Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Format-Table InterfaceAlias,NextHop,RouteMetric -AutoSize

    Write-Info "DNS servers:"
    Get-DnsClientServerAddress -AddressFamily IPv4 |
        Format-Table InterfaceAlias,ServerAddresses -AutoSize

    Write-Info "Network profile:"
    Get-NetConnectionProfile |
        Format-Table InterfaceAlias,NetworkCategory -AutoSize

    Write-Info "WinRM listeners:"
    winrm enumerate winrm/config/listener

    Write-Info "WinRM service authentication:"
    winrm get winrm/config/service/auth

    Write-Info "WinRM service settings:"
    winrm get winrm/config/service

    Write-Info "Local ansible user:"
    Get-LocalUser -Name $AnsibleUser

    Write-Info "Administrators membership check:"
    Get-LocalGroupMember -Group "Administrators" |
        Where-Object { $_.Name -like "*\$AnsibleUser" -or $_.Name -eq $AnsibleUser }
}


# ==============================================================================
# Main
# ==============================================================================

function Main {
    $RebootNeeded = $false

    Require-Administrator

    $Adapter = Get-PrimaryAdapter

    Set-Lab5Network -Adapter $Adapter
    Set-Lab5NetworkProfile -Adapter $Adapter

    $HostnameChanged = Set-Lab5Hostname
    if ($HostnameChanged) {
        $RebootNeeded = $true
    }

    Write-Lab5HostsFileBlock
    Enable-Lab5WinRM
    Ensure-Lab5AnsibleUser
    Show-Lab5Validation

    Write-Step "Bootstrap result"

    if ($RebootNeeded) {
        Write-Warn "A reboot is required because the hostname was changed."
        Write-Info "Run this command when ready:"
        Write-Host "Restart-Computer" -ForegroundColor Yellow
    }
    else {
        Write-Pass "Bootstrap completed. No reboot required."
    }

    Write-Info "After reboot or completion, return to the control node and run:"
    Write-Host "cd ~/lab5" -ForegroundColor Cyan
    Write-Host "./scripts/lab5-act1-check.sh --win-only" -ForegroundColor Cyan
    Write-Host "date" -ForegroundColor Cyan
    Write-Host "ansible win11 -m win_ping" -ForegroundColor Cyan
}

Main
