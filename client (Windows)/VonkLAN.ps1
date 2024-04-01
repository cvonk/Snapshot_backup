# Activate/deactivate WireGuard tunnel and rsync service
# (c) 2023, Coert Vonk, coert.vonk@gmail.com, https://coertvonk.com

# Place this file 'VonkLAN.ps1' in 'C:\Program Files\WireGuard\'
# Requires Powershell version >= 7.2.9
# When called from Windows Task Scheduler:
#   - General
#       User the following user account = SYSTEM
#       Run with the higest privileges
#   - Trigger 
#       Daily at 12:55 AM every day 
#   - Action
#       Program/Script = powershell.exe
#       Arguments = -ExecutionPolicy Bypass -File .\VonkLAN.ps1 start
#       Start in = C:\Program Files\WireGuard
#   - Conditions
#       Start the task only if the computer is on AC power = false
#       Wake the computer to run this task = true
#       Start only if the following network connection is available = any connection
#   - Settings
#       Stop the task if it runs longer than = 1 minutes
# Refer to 'VonkLAN.log' for transcript 
# If the task is stuck at 'running' in Task Scheduler, then press 'Refresh' in the right panel

param (
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet('start', 'stop', 'status')]
    [string] $Action
)

$wgDir = 'C:\Program Files\WireGuard'
$rsyncDir = 'C:\Program Files (x86)\rsyncd\bin'
$log = Join-Path -Path $wgDir -ChildPath '\VonkLAN.log'

[hashtable] $exe = @{
    wireguard = Join-Path -Path $wgdir -ChildPath 'wireguard.exe'
    rsync = Join-Path -Path $rsyncdir -ChildPath 'rsync.exe'
    cygrunsrv = Join-Path -Path $rsyncdir -ChildPath 'cygrunsrv.exe'  # wrapper for POSIX daemons to make them controllable as windows services
}

foreach ($key in $exe.Keys) {
    If (!(Test-Path $exe[$key])) {
        Write-Error ('File missing ({0})' -f $exe[$key])
    }
}

function Get-ServiceStatus() {

    param ([string] $serviceName)

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    if ($service.Length -gt 0) {
        return $service.Status
    } else {
        return 'Not installed'
    }
}

function Uninstall-Tunnel() {

    param([string] $serviceName,
          [string] $name)

    if ((Get-ServiceStatus $serviceName) -ne 'Not installed') {
        Write-Host 'WireGuard tunnel uninstalling ..'
        $arguments = '/uninstalltunnelservice ' + $name
        Start-Process -FilePath $exe.wireguard -ArgumentList $arguments -Wait -NoNewWindow
    } else {
        Write-Host 'WireGuard tunnel uninstalled'
    }
}

function Install-Tunnel {

    param([string] $serviceName,
          [string] $name,
          [string] $conf)

    Write-Host 'WireGuard tunnel installing ..'
    $arguments = '/installtunnelservice "' + $conf + '"' 
    Start-Process -FilePath $exe.wireguard -ArgumentList $arguments -Wait -NoNewWindow
    Set-NetConnectionProfile -InterfaceAlias $name -NetworkCategory Private
}

function Uninstall-RsyncService() {

    param( [string] $serviceName)

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    if ($service.Length -gt 0) {
        Write-Host "Uninstalling rsync service .."
        Remove-Service -Name $serviceName
    } else {
        Write-Host "Rsync service already uninstalled"
    }
}

function Start-Tunnel {

    param([string] $serviceName,
          [string] $name,
          [string] $conf)

    if ((Get-ServiceStatus $serviceName) -eq 'Not installed') {
        Install-Tunnel $serviceName $name $conf
    } 

    if ((Get-ServiceStatus $serviceName) -ne 'Running') {
        Write-Host 'WireGuard tunnel starting ..'
        Start-Service -Name $serviceName
    } else {
        Write-Host 'WireGuard tunnel already started'
    }
}

function Stop-Tunnel {

    param([string] $serviceName)

    if ((Get-ServiceStatus $serviceName) -eq 'Running') {
        Write-Host 'WireGuard tunnel stopping ..'
        Stop-Service -Name $serviceName
    } else {
        Write-Host 'WireGuard tunnel already stopped'
    }
}

function Install-RsyncService() {

    param( [string] $serviceName,
           [string] $userName,
           [string] $passwd )
           
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if ($service.Length -eq 0) {
        Write-Host "Installing rsync service .."
        $arg = @( ('--install ' + $serviceName),
                  ('--path "' + $exe.rsync + '"'),
                  ('--args "--config /rsyncd.conf --daemon --no-detach"'),
                  ('--dep tcpip'),
                  ('--user "' + $userName + '"'),
                  ('--passwd "' + $passwd + '"'),
                  ('--desc "Rsync - open source utility that provides fast incremental file transfer"'))
        Start-Process -FilePath $exe.cygRunSrv -ArgumentList $arg -Wait -NoNewWindow
        # stdout/stderr goes to Cygwin's /var/log/RsyncServer.log
    } else {
        Write-Host "Rsync service already installed"
    }
}

function Start-Rsync() {

    param( [string] $serviceName,
           [string] $userName,
           [string] $passwd )

    if ((Get-ServiceStatus $serviceName) -eq 'Not installed') {    
        Install-RsyncService $serviceName $userName $passwd
    }

    if ((Get-ServiceStatus $serviceName) -eq 'Stopped') {
        Write-Host 'Rsync starting ..'
        Start-Service -Name $serviceName
    } else {
        Write-Host 'Rsync service already started'
    }
}

function Stop-Rsync() {

    param( [string] $serviceName)

    if ((Get-ServiceStatus $serviceName) -eq 'Running') {
        Write-Host 'Rsync stopping ..'
        Stop-Service -Name $serviceName
    } else {
        Write-Host 'Rsync service already stopped'
    }
}

function Get-FirewallRuleStatus() {

    $rules = Get-NetFirewallRule
    if ($rules.DisplayName.Contains($firewallRuleDisplayName)) {
        return 'Present'
    } else {
        return 'Missing'
    }
}

function Add-FirewallRule() {

    param([string] $displayName)
    
    if ((Get-FirewallRuleStatus) -eq 'Missing') {
        $par = @{
            DisplayName = $displayName
            LocalPort = 873
            Direction = 'Inbound'
            Protocol = 'TCP'
            Profile = @('Domain', 'Private')
            Action = 'Allow'
            RemoteAddress = @('10.0.1.0/24', '10.0.1.4/32')
        }
        Write-Host 'Adding firewall rule ..'
        New-NetFirewallRule @par >$null
    } else {
        Write-Host 'Firewall rule already exists'
    }
}

function Remove-FirewallRule() {

    param([string] $displayName)
    
    if ((Get-FirewallRuleStatus) -eq 'Present') {
        Write-Host 'Removing firewall rule ..'
        Remove-NetFirewallRule -DisplayName $displayName
    } else {
        Write-Host 'Firewall rule already removed ..'
    }
}

Start-Transcript -Path $log -Force #-UseMinimalHeader

$tunnelName = 'VonkLAN'
$tunnelServiceName = 'WireGuardTunnel$' + $tunnelName
$tunnelConf = 'C:\Program Files\WireGuard\data\Configurations\VonkLAN.conf.dpapi'
$firewallRuleDisplayName = 'Rsync for backup' 
$rsyncServiceName = 'RsyncServer'

$windowsUserName = ${env:computername} + "\backup"
$windowsPasswd = "3S4kV6B3KdHYE8dLMWbp"

switch ($Action) {
    'start' { 
        Start-Tunnel $tunnelServiceName $tunnelName $tunnelConf
        Add-FirewallRule $firewallRuleDisplayName
        Start-Rsync $rsyncServiceName $windowsUserName $windowsPasswd
    }
    'stop'  { 
        Stop-Rsync $rsyncServiceName
        Remove-FirewallRule $firewallRuleDisplayName
        Stop-Tunnel $tunnelServiceName 
    }
    'status' {
        Write-Host ( 'WireGuard tunnel: ' + (Get-ServiceStatus $tunnelServiceName) )
        Write-Host ( 'Rsync service: ' + (Get-ServiceStatus $rsyncServiceName) )
        Write-Host ( 'Firewall rule: ' + (Get-FirewallRuleStatus) )
    }
}

Stop-Transcript

Exit $LASTEXITCODE