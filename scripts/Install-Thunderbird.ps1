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
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
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

        if ($process.ExitCode -notin @(0, 3010)) {
            throw "$Name installer failed with exit code $($process.ExitCode)."
        }
    }
}

function Uninstall-MsiProduct {
    param(
        [string]$Name,
        [string]$DisplayNamePattern
    )

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $program = foreach ($path in $registryPaths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $DisplayNamePattern } |
            Select-Object -First 1
    }

    $program = $program | Select-Object -First 1

    if (-not $program) {
        Write-Host "$Name is not installed."
        return
    }

    if (-not $program.PSChildName) {
        throw "Could not determine product code for $Name."
    }

    if ($PSCmdlet.ShouldProcess($Name, "Uninstall product $($program.PSChildName)")) {
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $program.PSChildName, '/qn', '/norestart') -Wait -PassThru

        if ($process.ExitCode -notin @(0, 3010, 1605)) {
            throw "$Name uninstall failed with exit code $($process.ExitCode)."
        }
    }
}

function Invoke-ThunderbirdValidation {
    $isInstalled = Test-InstalledProgram -DisplayNamePattern 'Mozilla Thunderbird*'
    $executable = @(
        'C:\Program Files\Mozilla Thunderbird\thunderbird.exe',
        'C:\Program Files (x86)\Mozilla Thunderbird\thunderbird.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $isInstalled -and -not $executable) {
        throw 'Mozilla Thunderbird was not found after installation.'
    }

    if ($executable) {
        Write-Host "Mozilla Thunderbird executable found: $executable"
    } else {
        Write-Host 'Mozilla Thunderbird is registered as installed.'
    }

    Write-Host 'Thunderbird validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Thunderbird.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\Thunderbird'
}

$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)

$name = 'Mozilla Thunderbird'
$displayNamePattern = 'Mozilla Thunderbird*'
$downloadUrl = 'https://download.mozilla.org/?product=thunderbird-msi-latest-ssl&os=win64&lang=en-US'
$installerPath = Join-Path $DownloadRoot 'Thunderbird-latest-win64-en-US.msi'

if ($Uninstall) {
    Uninstall-MsiProduct -Name $name -DisplayNamePattern $displayNamePattern
    return
}

Write-Host "Thunderbird installer download root: $DownloadRoot"
New-Item -Path $DownloadRoot -ItemType Directory -Force | Out-Null

$isInstalled = Test-InstalledProgram -DisplayNamePattern $displayNamePattern

if ($isInstalled -and -not $ForceDownload) {
    Write-Host "$name is already installed; skipping. Use -ForceDownload to refresh the installer and rerun installation."
} else {
    if ($ForceDownload -or -not (Test-Path $installerPath)) {
        if ($PSCmdlet.ShouldProcess($downloadUrl, "Download to $installerPath")) {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        }
    }

    if (-not (Test-Path $installerPath)) {
        throw "$name download did not create the expected installer at $installerPath."
    }

    if ($isInstalled) {
        Write-Host "$name is already installed; refreshing install with latest downloaded MSI."
    }

    Install-MsiPackage -Name $name -InstallerPath $installerPath
}

if (-not $SkipValidation) {
    Invoke-ThunderbirdValidation
}
