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

function Invoke-BrowserValidation {
    $expectedBrowsers = @(
        @{
            Name = 'Google Chrome'
            DisplayNamePattern = 'Google Chrome*'
            ExecutablePaths = @(
                'C:\Program Files\Google\Chrome\Application\chrome.exe',
                'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
            )
        },
        @{
            Name = 'Mozilla Firefox'
            DisplayNamePattern = 'Mozilla Firefox*'
            ExecutablePaths = @(
                'C:\Program Files\Mozilla Firefox\firefox.exe',
                'C:\Program Files (x86)\Mozilla Firefox\firefox.exe'
            )
        }
    )

    foreach ($browser in $expectedBrowsers) {
        $isInstalled = Test-InstalledProgram -DisplayNamePattern $browser.DisplayNamePattern
        $executable = $browser.ExecutablePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $isInstalled -and -not $executable) {
            throw "$($browser.Name) was not found after installation."
        }

        if ($executable) {
            Write-Host "$($browser.Name) executable found: $executable"
        } else {
            Write-Host "$($browser.Name) is registered as installed."
        }
    }

    Write-Host 'Browser validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Browsers.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\Browsers'
}

$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)

$installers = @(
    @{
        Name = 'Google Chrome'
        DisplayNamePattern = 'Google Chrome*'
        Url = 'https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi'
        Path = Join-Path $DownloadRoot 'GoogleChromeStandaloneEnterprise64.msi'
    },
    @{
        Name = 'Mozilla Firefox'
        DisplayNamePattern = 'Mozilla Firefox*'
        Url = 'https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=en-US'
        Path = Join-Path $DownloadRoot 'Firefox-latest-win64-en-US.msi'
    }
)

if ($Uninstall) {
    foreach ($installer in $installers) {
        Uninstall-MsiProduct -Name $installer.Name -DisplayNamePattern $installer.DisplayNamePattern
    }

    return
}

Write-Host "Browser installer download root: $DownloadRoot"
New-Item -Path $DownloadRoot -ItemType Directory -Force | Out-Null

foreach ($installer in $installers) {
    if ($ForceDownload -or -not (Test-Path $installer.Path)) {
        if ($PSCmdlet.ShouldProcess($installer.Url, "Download to $($installer.Path)")) {
            Invoke-WebRequest -Uri $installer.Url -OutFile $installer.Path
        }
    }

    if (-not (Test-Path $installer.Path)) {
        throw "$($installer.Name) download did not create the expected installer at $($installer.Path)."
    }

    if (Test-InstalledProgram -DisplayNamePattern $installer.DisplayNamePattern) {
        Write-Host "$($installer.Name) is already installed; refreshing install with latest downloaded MSI."
    }

    Install-MsiPackage -Name $installer.Name -InstallerPath $installer.Path
}

if (-not $SkipValidation) {
    Invoke-BrowserValidation
}
