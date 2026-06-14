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

function Install-MsiPackage {
    param(
        [string]$Name,
        [string]$InstallerPath
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "$Name installer was not found at $InstallerPath."
    }

    if ($PSCmdlet.ShouldProcess($Name, "Install MSI from $InstallerPath")) {
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $InstallerPath, '/qn', '/norestart') -Wait -PassThru

        if ($process.ExitCode -notin @(0, 3010, 1638)) {
            throw "$Name installer failed with exit code $($process.ExitCode)."
        }
    }
}

function Invoke-CommunicationValidation {
    param(
        [int]$TimeoutSeconds = 90
    )

    $expectedApps = @(
        @{
            Name = 'Discord'
            DisplayNamePattern = 'Discord*'
            ExecutablePaths = @(
                "$env:LOCALAPPDATA\Discord\Update.exe",
                "$env:LOCALAPPDATA\Discord\app-*\Discord.exe"
            )
        },
        @{
            Name = 'Zoom'
            DisplayNamePattern = 'Zoom*'
            ExecutablePaths = @(
                'C:\Program Files\Zoom\bin\Zoom.exe',
                'C:\Program Files (x86)\Zoom\bin\Zoom.exe'
            )
        },
        @{
            Name = 'Slack'
            DisplayNamePattern = 'Slack*'
            ExecutablePaths = @(
                "$env:LOCALAPPDATA\slack\slack.exe",
                "$env:LOCALAPPDATA\slack\app-*\slack.exe",
                'C:\Program Files\Slack\slack.exe'
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

    Write-Host 'Communication apps validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Communication.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\Communication'
}

$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)

$apps = @(
    @{
        Name = 'Discord'
        DisplayNamePattern = 'Discord*'
        Url = 'https://discord.com/api/download?platform=win'
        Path = Join-Path $DownloadRoot 'DiscordSetup.exe'
        Type = 'Exe'
        Arguments = @('-s')
    },
    @{
        Name = 'Zoom'
        DisplayNamePattern = 'Zoom*'
        Url = 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64'
        Path = Join-Path $DownloadRoot 'ZoomInstallerFull-x64.msi'
        Type = 'Msi'
    },
    @{
        Name = 'Slack'
        DisplayNamePattern = 'Slack*'
        Url = 'https://slack.com/ssb/download-win64'
        Path = Join-Path $DownloadRoot 'SlackSetup.exe'
        Type = 'Exe'
        Arguments = @('--silent')
    }
)

if ($Uninstall) {
    Write-Warning 'Uninstall is not implemented for communication apps yet.'
    return
}

Write-Host "Communication apps installer download root: $DownloadRoot"
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

    if ($app.Type -eq 'Msi') {
        Install-MsiPackage -Name $app.Name -InstallerPath $app.Path
    } else {
        Install-ExePackage -Name $app.Name -InstallerPath $app.Path -ArgumentList $app.Arguments
    }
}

if (-not $SkipValidation) {
    Invoke-CommunicationValidation
}
