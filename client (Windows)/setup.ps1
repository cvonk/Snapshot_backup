#Requires -RunAsAdministrator

# Prior: install cygwin from https://www.cygwin.com/index.html
#   install to 'C:\Program Files (x86)\rsyncd' (ignore the spaces in path warning)
#   include the latest rsync (Net) and cygrunsrv (Admin) packages
# don't forget to put a rsyncd.conf and rsyncd.secrets in your install dir.
#
# MUST be run elevated (as Administrator)
# To uninstall both, add the command line option 'remove'
#
# (c) 2024 by Coert Vonk

<#
.Synopsis
  creates a backup user and installs the rsync daemon as a service.
.Parameter option
  Either --create or --remove, to respectively create the user and
  service or remove those.
.Example
  Usage:
  .\regsrv.ps1 --create
#>

param (
    [string]$option = '--create'
 )

$user = "backup"
$group = "Administrators"
$fullname = "Rsync daemon user"
$serviceName = "rsync daemon"
$serviceDir = "C:\Program Files (x86)\rsyncd"
$serviceDesc = "Open source utility that provides fast incremental file transfer"
$servicePath = (Join-Path $serviceDir -ChildPath 'bin\rsync.exe')
$cygrunsrvPath = (Join-Path $serviceDir -ChildPath 'bin\cygrunsrv.exe')
[SecureString] $password = $(Read-Host "Password for the local backup account" -AsSecureString)

# https://github.com/PowerShell/PowerShell/issues/18624#issuecomment-1649261124
Import-Module microsoft.powershell.localaccounts -UseWindowsPowerShell

# triggers: WARNING: Module microsoft.powershell.localaccounts is ...
# https://stackoverflow.com/questions/313831/using-powershell-how-do-i-grant-log-on-as-service-to-an-account
Function Grant-LogonAsService {

    [string] $Username = "$env:COMPUTERNAME\$user"
    [string] $Right = 'SeServiceLogonRight'

    $tmp = New-TemporaryFile
    $TempConfigFile = "$tmp.inf"
    $TempDbFile = "$tmp.sdb"

    Write-Host "Getting current policy"
    secedit /export /cfg $TempConfigFile
    $sid = ((New-Object System.Security.Principal.NTAccount($Username)).Translate([System.Security.Principal.SecurityIdentifier])).Value
    $currentConfig = Get-Content -Encoding ascii $TempConfigFile

    $newConfig = $null
    if ($currentConfig | Select-String -Pattern "^$Right = ") {
        if ($currentConfig | Select-String -Pattern "^$Right .*$sid.*$") {
            Write-Host "Already has right"
        } else {
            Write-Host "Adding $Right to $Username"
            $newConfig = $currentConfig -replace "^$Right .+", "`$0,*$sid"
        }
    } else {
        Write-Host "Right $Right did not exist in config. Adding $Right to $Username."
        $newConfig = $currentConfig -replace "^\[Privilege Rights\]$", "`$0`n$Right = *$sid"
    }

    if ($newConfig) {
        Set-Content -Path $TempConfigFile -Encoding ascii -Value $newConfig
        $validationResult = secedit /validate $TempConfigFile
        if ($validationResult | Select-String '.*invalid.*') {
            throw $validationResult;
        }
        secedit /import /cfg $TempConfigFile /db $TempDbFile
        secedit /configure /db $TempDbFile /cfg $TempConfigFile
        gpupdate /force

        Remove-Item $tmp* -ea 0
    }
}

Function New-User {
    process {
        try {
            New-LocalUser "$user" -Password $password -FullName "$user" -Description "$fullname" -ErrorAction stop
            Add-LocalGroupMember -Group "$group" -Member "$user" -ErrorAction stop
        } catch {
            Write-Error "Failed to create $user"
        }
    }    
}

Function Remove-User {
    process {
        try {
            Remove-LocalUser -Name "$user" -ErrorAction SilentlyContinue
        } catch {
            Write-Error "Failed to remove user $user"
        }
    }    
}

Function New-Service {
    process {
        try {
            # using cygrunsrv instead of the native Powershell API, because
            # it provides some additional housekeeping for CygWin apps.
            $plainPasswd = ConvertFrom-SecureString -SecureString $password -AsPlainText
            $arguments = @( '--install', ('"' + $serviceName + '"'),
                            '--desc', ('"' + $serviceDesc + '"'),
                            '--path', ('"' + $servicePath + '"'), 
                            '--chdir', ('"' + $serviceDir + '"'),
                            '--args', '"--config=rsyncd.conf --daemon --no-detach"',
                            '--dep', 'tcpip',
                            '--env', 'CYGWIN="nontsec binmode"',
                            '--shutdown',
                            '--user', ('"' + $user + '"'),
                            '--passwd', ('"' + $plainPasswd + '"') )
            Start-Process -FilePath "$cygrunsrvPath" -ArgumentList $arguments -Wait -NoNewWindow 
            # should now show up with `bin\cygrunsrv.exe -V --list`
        } catch {
            Write-Error "Failed to create service $serviceName"
        }
    }
}

Function Start-Service {
    process {
        try {
            $arguments = @( '--start', ('"' + $serviceName + '"') )
            Start-Process -FilePath "$cygrunsrvPath" -ArgumentList $arguments -Wait -NoNewWindow 
            # should now show up in Services panel, or as Started in `bin\cygrunsrv.exe -V --list`
            # consult /var/log/'rsync daemon'.log for details
        } catch {
            Write-Error "Failed to start service $serviceName"
        }
    }
}

Function Stop-Service {
    process {
        try {
            $arguments = @( '--stop', ('"' + $serviceName + '"') )
            Start-Process -FilePath "$cygrunsrvPath" -ArgumentList $arguments -Wait -NoNewWindow 
            # should now show up in Services panel, or as Started in `bin\cygrunsrv.exe -V --list`
            # consult /var/log/'rsync daemon'.log for details
        } catch {
            Write-Error "Failed to stop service $serviceName"
        }
    }
}

Function Remove-Service {
    process {
        try {
            $arguments = @( '--remove', ('"' + $serviceName + '"') )
            Start-Process -FilePath "$cygrunsrvPath" -ArgumentList $arguments -Wait -NoNewWindow 
            # should now show up with `bin\cygrunsrv.exe -V --list`
        } catch {
            Write-Error "Failed to remove service $serviceName"
        }
    }
}

#
# main()
#

switch($option) {
    '--create' {
        if (-Not ((Get-LocalGroupMember "$group").Name -contains "$env:COMPUTERNAME\$user")) {
            New-User
            Grant-LogonAsService
        }
        
        if (-Not (Get-Service $serviceName -ErrorAction SilentlyContinue)) {
            New-Service
            Start-Service
        }
    }
    '--remove' {
        if (Get-LocalUser $user -ErrorAction SilentlyContinue) {
            Remove-User
        }
        if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
            # might defer when e.g. services panel is open
            Stop-Service
            Remove-Service
        }
    }
}