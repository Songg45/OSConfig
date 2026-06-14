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

function Install-ChatGpt {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue

    if (-not $winget) {
        Write-Warning 'winget is not available. Skipping ChatGPT Microsoft Store install.'
        Write-Warning 'Manual URL: https://apps.microsoft.com/detail/9nt1r1c2hh7j'
        return
    }

    if (-not $ForceDownload) {
        $listProcess = Start-Process -FilePath $winget.Source -ArgumentList @('list', '--id', '9NT1R1C2HH7J', '--source', 'msstore', '--accept-source-agreements') -Wait -PassThru -WindowStyle Hidden

        if ($listProcess.ExitCode -eq 0) {
            Write-Host 'ChatGPT is already installed; skipping. Use -ForceDownload to rerun the Store install.'
            return
        }
    }

    if ($PSCmdlet.ShouldProcess('ChatGPT', 'Install from Microsoft Store through winget')) {
        $arguments = @(
            'install',
            '--id', '9NT1R1C2HH7J',
            '--source', 'msstore',
            '--accept-package-agreements',
            '--accept-source-agreements'
        )

        $process = Start-Process -FilePath $winget.Source -ArgumentList $arguments -Wait -PassThru

        if ($process.ExitCode -ne 0) {
            Write-Warning "ChatGPT Store install failed with exit code $($process.ExitCode). Install manually from https://apps.microsoft.com/detail/9nt1r1c2hh7j"
        }
    }
}

function Invoke-ProductivityValidation {
    $expectedApps = @(
        @{
            Name = 'Visual Studio Code'
            DisplayNamePattern = 'Microsoft Visual Studio Code*'
            ExecutablePaths = @(
                'C:\Program Files\Microsoft VS Code\Code.exe',
                "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
            )
            Required = $true
        },
        @{
            Name = 'GitHub Desktop'
            DisplayNamePattern = 'GitHub Desktop*'
            ExecutablePaths = @(
                "$env:LOCALAPPDATA\GitHubDesktop\GitHubDesktop.exe",
                "$env:LOCALAPPDATA\GitHubDesktop\app-*\GitHubDesktop.exe"
            )
            Required = $true
        },
        @{
            Name = 'ChatGPT'
            DisplayNamePattern = 'ChatGPT*'
            ExecutablePaths = @(
                "$env:LOCALAPPDATA\Microsoft\WindowsApps\ChatGPT.exe"
            )
            Required = $false
        }
    )

    foreach ($app in $expectedApps) {
        $isInstalled = Test-InstalledProgram -DisplayNamePattern $app.DisplayNamePattern
        $executable = $app.ExecutablePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $isInstalled -and -not $executable) {
            if ($app.Required) {
                throw "$($app.Name) was not found after installation."
            }

            Write-Warning "$($app.Name) was not found. It may require Microsoft Store or winget availability."
            continue
        }

        if ($executable) {
            Write-Host "$($app.Name) executable found: $executable"
        } else {
            Write-Host "$($app.Name) is registered as installed."
        }
    }

    Write-Host 'Productivity apps validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Productivity.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\Productivity'
}

$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)

$apps = @(
    @{
        Name = 'Visual Studio Code'
        DisplayNamePattern = 'Microsoft Visual Studio Code*'
        Url = 'https://update.code.visualstudio.com/latest/win32-x64/stable'
        Path = Join-Path $DownloadRoot 'VSCodeSetup-x64.exe'
        Arguments = @('/VERYSILENT', '/NORESTART', '/MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath')
    },
    @{
        Name = 'GitHub Desktop'
        DisplayNamePattern = 'GitHub Desktop*'
        Url = 'https://central.github.com/deployments/desktop/desktop/latest/win32'
        Path = Join-Path $DownloadRoot 'GitHubDesktopSetup-x64.exe'
        Arguments = @('-s')
    }
)

if ($Uninstall) {
    Write-Warning 'Uninstall is not implemented for productivity apps yet.'
    return
}

Write-Host "Productivity apps installer download root: $DownloadRoot"
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

    Install-ExePackage -Name $app.Name -InstallerPath $app.Path -ArgumentList $app.Arguments
}

Install-ChatGpt

if (-not $SkipValidation) {
    Invoke-ProductivityValidation
}
