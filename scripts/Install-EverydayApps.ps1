#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DownloadRoot,
    [string]$UserProfileRoot = $env:USERPROFILE,
    [switch]$ForceDownload,
    [switch]$SkipValidation,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InstalledProgram {
    param(
        [string]$DisplayNamePattern
    )

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        $program = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $DisplayNamePattern } |
            Select-Object -First 1

        if ($program) {
            return $true
        }
    }

    return $false
}

function Install-ExePackage {
    param(
        [string]$Name,
        [string]$InstallerPath,
        [string[]]$ArgumentList
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "$Name installer was not found at $InstallerPath."
    }

    if ($PSCmdlet.ShouldProcess($Name, "Install EXE from $InstallerPath")) {
        $process = Start-Process -FilePath $InstallerPath -ArgumentList $ArgumentList -Wait -PassThru

        if ($process.ExitCode -notin @(0, 3010)) {
            throw "$Name installer failed with exit code $($process.ExitCode)."
        }
    }
}

function Register-SpotifyFirstLogonInstall {
    param(
        [string]$InstallerPath,
        [string]$ProfileRoot,
        [string]$TaskName = 'OSConfig-Install-Spotify'
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Spotify installer was not found at $InstallerPath."
    }

    $profile = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' -ErrorAction SilentlyContinue |
        Where-Object {
            $profilePath = [Environment]::ExpandEnvironmentVariables($_.ProfileImagePath)
            $profilePath.TrimEnd('\') -ieq $ProfileRoot.TrimEnd('\')
        } |
        Select-Object -First 1

    if (-not $profile) {
        throw "Unable to resolve the user SID for $ProfileRoot."
    }

    $profileSid = $profile.PSChildName
    $userId = ([Security.Principal.SecurityIdentifier]$profileSid).Translate([Security.Principal.NTAccount]).Value
    $deferredRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'OSConfig\Deferred\Spotify'
    $deferredInstaller = Join-Path $deferredRoot 'SpotifySetup.exe'
    $helperPath = Join-Path $deferredRoot 'Install-Spotify-FirstLogon.ps1'

    $helperContent = @'
#Requires -Version 5.1

param(
    [string]$InstallerPath,
    [string]$TaskName
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$logRoot = Join-Path $env:LOCALAPPDATA 'OSConfig'
$logPath = Join-Path $logRoot 'Spotify-FirstLogon.log'
$spotifyPath = Join-Path $env:APPDATA 'Spotify\Spotify.exe'
New-Item -Path $logRoot -ItemType Directory -Force | Out-Null

try {
    Add-Content -Path $logPath -Value "$(Get-Date -Format o) Starting deferred Spotify installation."

    if (-not (Test-Path -LiteralPath $spotifyPath)) {
        $process = Start-Process -FilePath $InstallerPath -ArgumentList '/silent' -PassThru
        $process.WaitForExit(300000)
        $deadline = (Get-Date).AddMinutes(5)

        while (-not (Test-Path -LiteralPath $spotifyPath) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
        }
    }

    if (-not (Test-Path -LiteralPath $spotifyPath)) {
        throw "Spotify was not found at $spotifyPath after installation."
    }

    Add-Content -Path $logPath -Value "$(Get-Date -Format o) Spotify installation completed."
    & schtasks.exe /Delete /TN $TaskName /F | Out-Null
} catch {
    Add-Content -Path $logPath -Value "$(Get-Date -Format o) Spotify installation failed: $($_.Exception.Message)"
    exit 1
}
'@

    if ($PSCmdlet.ShouldProcess($userId, 'Register deferred Spotify first-logon installer')) {
        New-Item -Path $deferredRoot -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $InstallerPath -Destination $deferredInstaller -Force
        Set-Content -Path $helperPath -Value $helperContent -Encoding ASCII
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

        $taskArgument = "-NoProfile -ExecutionPolicy Bypass -File `"$helperPath`" -InstallerPath `"$deferredInstaller`" -TaskName `"$TaskName`""
        $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $taskArgument
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $profileSid
        $principal = New-ScheduledTaskPrincipal -UserId $profileSid -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

        Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
        Write-Host "Spotify will install as $userId at the next interactive logon."
    }
}

function Invoke-EverydayAppValidation {
    param(
        [int]$TimeoutSeconds = 90
    )

    $expectedApps = @(
        @{
            Name = 'VLC media player'
            DisplayNamePattern = 'VLC media player*'
            ExecutablePaths = @(
                'C:\Program Files\VideoLAN\VLC\vlc.exe',
                'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe'
            )
        },
        @{
            Name = 'GIMP'
            DisplayNamePattern = 'GIMP*'
            ExecutablePaths = @(
                'C:\Program Files\GIMP 3\bin\gimp-3.0.exe',
                'C:\Program Files\GIMP 2\bin\gimp-2.10.exe'
            )
        }
    )

    foreach ($app in $expectedApps) {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $isInstalled = $false
        $executable = $null

        do {
            $isInstalled = Test-InstalledProgram -DisplayNamePattern $app.DisplayNamePattern
            $executable = $app.ExecutablePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

            if ($isInstalled -or $executable) {
                break
            }

            Start-Sleep -Seconds 2
        } while ((Get-Date) -lt $deadline)

        if (-not $isInstalled -and -not $executable) {
            throw "$($app.Name) was not found after installation."
        }

        if ($executable) {
            Write-Host "$($app.Name) executable found: $executable"
        } else {
            Write-Host "$($app.Name) is registered as installed."
        }
    }

    Write-Host 'Everyday apps validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-EverydayApps.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\EverydayApps'
}

$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)

$apps = @(
    @{
        Name = 'VLC media player'
        DisplayNamePattern = 'VLC media player*'
        Url = 'https://download.videolan.org/pub/videolan/vlc/3.0.21/win64/vlc-3.0.21-win64.exe'
        Path = Join-Path $DownloadRoot 'vlc-3.0.21-win64.exe'
        Arguments = @('/S')
    },
    @{
        Name = 'Spotify'
        DisplayNamePattern = 'Spotify*'
        Url = 'https://download.scdn.co/SpotifySetup.exe'
        Path = Join-Path $DownloadRoot 'SpotifySetup.exe'
        Arguments = @('/silent')
        DeferUntilUserLogon = $true
    },
    @{
        Name = 'GIMP'
        DisplayNamePattern = 'GIMP*'
        Url = 'https://download.gimp.org/gimp/v3.0/windows/gimp-3.0.4-setup.exe'
        Path = Join-Path $DownloadRoot 'gimp-3.0.4-setup.exe'
        Arguments = @('/VERYSILENT', '/ALLUSERS', '/NORESTART')
    }
)

if ($Uninstall) {
    Write-Warning 'Uninstall is not implemented for everyday apps yet.'
    return
}

Write-Host "Everyday apps installer download root: $DownloadRoot"
New-Item -Path $DownloadRoot -ItemType Directory -Force | Out-Null

foreach ($app in $apps) {
    $isInstalled = Test-InstalledProgram -DisplayNamePattern $app.DisplayNamePattern

    if ($isInstalled -and -not $ForceDownload) {
        Write-Host "$($app.Name) is already installed; skipping. Use -ForceDownload to refresh the installer and rerun installation."
        continue
    }

    if ($ForceDownload -or -not (Test-Path $app.Path)) {
        if ($PSCmdlet.ShouldProcess($app.Url, "Download to $($app.Path)")) {
            Invoke-WebRequest -Uri $app.Url -OutFile $app.Path
        }
    }

    if (-not (Test-Path $app.Path)) {
        throw "$($app.Name) download did not create the expected installer at $($app.Path)."
    }

    if ($isInstalled) {
        Write-Host "$($app.Name) is already installed; refreshing install with latest downloaded installer."
    }

    if ($app.DeferUntilUserLogon) {
        Register-SpotifyFirstLogonInstall -InstallerPath $app.Path -ProfileRoot $UserProfileRoot
    } else {
        Install-ExePackage -Name $app.Name -InstallerPath $app.Path -ArgumentList $app.Arguments
    }
}

if (-not $SkipValidation) {
    Invoke-EverydayAppValidation

    if (Get-ScheduledTask -TaskName 'OSConfig-Install-Spotify' -ErrorAction SilentlyContinue) {
        Write-Host 'Spotify deferred first-logon task is registered.'
    } else {
        $spotifyPath = Join-Path $UserProfileRoot 'AppData\Roaming\Spotify\Spotify.exe'

        if (-not (Test-Path -LiteralPath $spotifyPath)) {
            throw 'Spotify is not installed and its deferred first-logon task was not found.'
        }
    }
}
