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

        if ($process.ExitCode -notin @(0, 3010, 1638)) {
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

function Invoke-RuntimeValidation {
    $checks = @(
        @{
            Name = 'Visual C++ Redistributable x64'
            DisplayNamePattern = 'Microsoft Visual C++*Redistributable* (x64)*'
        },
        @{
            Name = 'Visual C++ Redistributable x86'
            DisplayNamePattern = 'Microsoft Visual C++*Redistributable* (x86)*'
        },
        @{
            Name = '.NET Desktop Runtime x64'
            DisplayNamePattern = 'Microsoft Windows Desktop Runtime - 10.0.9 (x64)*'
            Paths = @('C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App\10.0.9')
        },
        @{
            Name = '.NET Desktop Runtime x86'
            DisplayNamePattern = 'Microsoft Windows Desktop Runtime - 10.0.9 (x86)*'
            Paths = @('C:\Program Files (x86)\dotnet\shared\Microsoft.WindowsDesktop.App\10.0.9')
        },
        @{
            Name = 'Eclipse Temurin Java 8 JRE'
            DisplayNamePattern = 'Eclipse Temurin JRE with Hotspot 8*'
            Paths = @('C:\Program Files\Eclipse Adoptium')
        },
        @{
            Name = 'Python 3.13'
            DisplayNamePattern = 'Python 3.13*'
            Paths = @('C:\Program Files\Python313\python.exe')
        }
    )

    foreach ($check in $checks) {
        $isInstalled = Test-InstalledProgram -DisplayNamePattern $check.DisplayNamePattern
        $pathFound = $false

        if ($check.Paths) {
            $pathFound = [bool]($check.Paths | Where-Object { Test-Path $_ } | Select-Object -First 1)
        }

        if (-not $isInstalled -and -not $pathFound) {
            throw "$($check.Name) was not found after installation."
        }

        if ($pathFound) {
            Write-Host "$($check.Name) path found."
        } else {
            Write-Host "$($check.Name) is registered as installed."
        }
    }

    Write-Host 'Runtime validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Runtimes.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\Runtimes'
}

$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)

$packages = @(
    @{
        Name = 'Visual C++ Redistributable x64'
        DisplayNamePattern = 'Microsoft Visual C++*Redistributable* (x64)*'
        Url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
        Path = Join-Path $DownloadRoot 'vc_redist.x64.exe'
        Type = 'Exe'
        Arguments = @('/install', '/quiet', '/norestart')
    },
    @{
        Name = 'Visual C++ Redistributable x86'
        DisplayNamePattern = 'Microsoft Visual C++*Redistributable* (x86)*'
        Url = 'https://aka.ms/vs/17/release/vc_redist.x86.exe'
        Path = Join-Path $DownloadRoot 'vc_redist.x86.exe'
        Type = 'Exe'
        Arguments = @('/install', '/quiet', '/norestart')
    },
    @{
        Name = '.NET Desktop Runtime x64'
        DisplayNamePattern = 'Microsoft Windows Desktop Runtime - 10.0.9 (x64)*'
        Url = 'https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.9/windowsdesktop-runtime-10.0.9-win-x64.exe'
        Path = Join-Path $DownloadRoot 'windowsdesktop-runtime-10.0.9-win-x64.exe'
        Type = 'Exe'
        Arguments = @('/install', '/quiet', '/norestart')
    },
    @{
        Name = '.NET Desktop Runtime x86'
        DisplayNamePattern = 'Microsoft Windows Desktop Runtime - 10.0.9 (x86)*'
        Url = 'https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.9/windowsdesktop-runtime-10.0.9-win-x86.exe'
        Path = Join-Path $DownloadRoot 'windowsdesktop-runtime-10.0.9-win-x86.exe'
        Type = 'Exe'
        Arguments = @('/install', '/quiet', '/norestart')
    },
    @{
        Name = 'Eclipse Temurin Java 8 JRE'
        DisplayNamePattern = 'Eclipse Temurin JRE with Hotspot 8*'
        Url = 'https://api.adoptium.net/v3/binary/latest/8/ga/windows/x64/jre/hotspot/normal/eclipse'
        Path = Join-Path $DownloadRoot 'temurin-8-jre-x64.msi'
        Type = 'Msi'
    },
    @{
        Name = 'Python 3.13'
        DisplayNamePattern = 'Python 3.13*'
        Url = 'https://www.python.org/ftp/python/3.13.14/python-3.13.14-amd64.exe'
        Path = Join-Path $DownloadRoot 'python-3.13.14-amd64.exe'
        Type = 'Exe'
        Arguments = @('/quiet', 'InstallAllUsers=1', 'PrependPath=1', 'Include_launcher=1', 'Include_pip=1')
    }
)

if ($Uninstall) {
    Write-Warning 'Uninstall is not implemented for runtimes yet.'
    return
}

Write-Host "Runtime installer download root: $DownloadRoot"
New-Item -Path $DownloadRoot -ItemType Directory -Force | Out-Null

foreach ($package in $packages) {
    $isInstalled = Test-InstalledProgram -DisplayNamePattern $package.DisplayNamePattern

    if ($isInstalled -and -not $ForceDownload) {
        Write-Host "$($package.Name) is already installed; skipping. Use -ForceDownload to refresh the installer and rerun installation."
        continue
    }

    if ($ForceDownload -or -not (Test-Path $package.Path)) {
        if ($PSCmdlet.ShouldProcess($package.Url, "Download to $($package.Path)")) {
            Invoke-WebRequest -Uri $package.Url -OutFile $package.Path
        }
    }

    if (-not (Test-Path $package.Path)) {
        throw "$($package.Name) download did not create the expected installer at $($package.Path)."
    }

    if ($isInstalled) {
        Write-Host "$($package.Name) is already installed; refreshing install with latest downloaded installer."
    }

    if ($package.Type -eq 'Msi') {
        Install-MsiPackage -Name $package.Name -InstallerPath $package.Path
    } else {
        Install-ExePackage -Name $package.Name -InstallerPath $package.Path -ArgumentList $package.Arguments
    }
}

if (-not $SkipValidation) {
    Invoke-RuntimeValidation
}
