#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DownloadRoot,
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

function Install-CurrentUserExePackage {
    param(
        [string]$Name,
        [string]$InstallerPath,
        [string[]]$ArgumentList,
        [int]$TimeoutSeconds = 300
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "$Name installer was not found at $InstallerPath."
    }

    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskName = "OSConfig-Install-$($Name -replace '[^A-Za-z0-9]', '')"
    $escapedArguments = ($ArgumentList | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $taskArgument = "-NoProfile -ExecutionPolicy Bypass -Command `"Start-Process -FilePath '$InstallerPath' -ArgumentList '$escapedArguments' -Wait`""

    if ($PSCmdlet.ShouldProcess($Name, "Install as current user $currentIdentity from $InstallerPath")) {
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

            $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $taskArgument
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
            $principal = New-ScheduledTaskPrincipal -UserId $currentIdentity -LogonType Interactive -RunLevel Limited
            $settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
            Start-ScheduledTask -TaskName $taskName

            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

            do {
                Start-Sleep -Seconds 2
                $scheduledTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

                if ($scheduledTask -and $scheduledTask.State -ne 'Running') {
                    break
                }
            } while ((Get-Date) -lt $deadline)

            if ((Get-Date) -ge $deadline) {
                throw "$Name current-user installer did not finish within $TimeoutSeconds seconds."
            }

            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue

            if ($taskInfo -and $taskInfo.LastTaskResult -ne 0) {
                throw "$Name current-user installer failed with scheduled task result $($taskInfo.LastTaskResult)."
            }
        } finally {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
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
            Name = 'Spotify'
            DisplayNamePattern = 'Spotify*'
            ExecutablePaths = @(
                "$env:APPDATA\Spotify\Spotify.exe",
                "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe"
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
        InstallAsCurrentUser = $true
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

    if ($app.InstallAsCurrentUser) {
        Install-CurrentUserExePackage -Name $app.Name -InstallerPath $app.Path -ArgumentList $app.Arguments
    } else {
        Install-ExePackage -Name $app.Name -InstallerPath $app.Path -ArgumentList $app.Arguments
    }
}

if (-not $SkipValidation) {
    Invoke-EverydayAppValidation
}
