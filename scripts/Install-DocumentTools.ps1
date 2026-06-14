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

function Uninstall-InstalledProgram {
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

    if ($program.QuietUninstallString) {
        if ($PSCmdlet.ShouldProcess($Name, "Run quiet uninstall command")) {
            $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $program.QuietUninstallString) -Wait -PassThru

            if ($process.ExitCode -notin @(0, 3010, 1605)) {
                throw "$Name uninstall failed with exit code $($process.ExitCode)."
            }
        }

        return
    }

    if ($program.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
        if ($PSCmdlet.ShouldProcess($Name, "Uninstall MSI product $($program.PSChildName)")) {
            $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $program.PSChildName, '/qn', '/norestart') -Wait -PassThru

            if ($process.ExitCode -notin @(0, 3010, 1605)) {
                throw "$Name uninstall failed with exit code $($process.ExitCode)."
            }
        }

        return
    }

    if (-not $program.UninstallString) {
        throw "Could not determine uninstall command for $Name."
    }

    if ($PSCmdlet.ShouldProcess($Name, "Run uninstall command")) {
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "$($program.UninstallString) /S") -Wait -PassThru

        if ($process.ExitCode -notin @(0, 3010, 1605)) {
            throw "$Name uninstall failed with exit code $($process.ExitCode)."
        }
    }
}

function Invoke-DocumentToolValidation {
    $expectedTools = @(
        @{
            Name = 'LibreOffice'
            DisplayNamePattern = 'LibreOffice*'
            ExecutablePaths = @(
                'C:\Program Files\LibreOffice\program\soffice.exe'
            )
        },
        @{
            Name = '7-Zip'
            DisplayNamePattern = '7-Zip*'
            ExecutablePaths = @(
                'C:\Program Files\7-Zip\7zFM.exe',
                'C:\Program Files\7-Zip\7z.exe'
            )
        },
        @{
            Name = 'Notepad++'
            DisplayNamePattern = 'Notepad++*'
            ExecutablePaths = @(
                'C:\Program Files\Notepad++\notepad++.exe'
            )
        }
    )

    foreach ($tool in $expectedTools) {
        $isInstalled = Test-InstalledProgram -DisplayNamePattern $tool.DisplayNamePattern
        $executable = $tool.ExecutablePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $isInstalled -and -not $executable) {
            throw "$($tool.Name) was not found after installation."
        }

        if ($executable) {
            Write-Host "$($tool.Name) executable found: $executable"
        } else {
            Write-Host "$($tool.Name) is registered as installed."
        }
    }

    Write-Host 'Document tools validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-DocumentTools.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\DocumentTools'
}

$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)

$tools = @(
    @{
        Name = 'LibreOffice'
        DisplayNamePattern = 'LibreOffice*'
        Url = 'https://download.documentfoundation.org/libreoffice/stable/26.2.4/win/x86_64/LibreOffice_26.2.4_Win_x86-64.msi'
        Path = Join-Path $DownloadRoot 'LibreOffice_26.2.4_Win_x86-64.msi'
        Type = 'Msi'
    },
    @{
        Name = '7-Zip'
        DisplayNamePattern = '7-Zip*'
        Url = 'https://github.com/ip7z/7zip/releases/download/26.01/7z2601-x64.exe'
        Path = Join-Path $DownloadRoot '7z2601-x64.exe'
        Type = 'Exe'
        Arguments = @('/S')
    },
    @{
        Name = 'Notepad++'
        DisplayNamePattern = 'Notepad++*'
        Url = 'https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.6.4/npp.8.9.6.4.Installer.x64.exe'
        Path = Join-Path $DownloadRoot 'npp.8.9.6.4.Installer.x64.exe'
        Type = 'Exe'
        Arguments = @('/S')
    }
)

if ($Uninstall) {
    foreach ($tool in $tools) {
        Uninstall-InstalledProgram -Name $tool.Name -DisplayNamePattern $tool.DisplayNamePattern
    }

    return
}

Write-Host "Document tools installer download root: $DownloadRoot"
New-Item -Path $DownloadRoot -ItemType Directory -Force | Out-Null

foreach ($tool in $tools) {
    $isInstalled = Test-InstalledProgram -DisplayNamePattern $tool.DisplayNamePattern

    if ($isInstalled -and -not $ForceDownload) {
        Write-Host "$($tool.Name) is already installed; skipping. Use -ForceDownload to refresh the installer and rerun installation."
        continue
    }

    if ($ForceDownload -or -not (Test-Path $tool.Path)) {
        if ($PSCmdlet.ShouldProcess($tool.Url, "Download to $($tool.Path)")) {
            Invoke-WebRequest -Uri $tool.Url -OutFile $tool.Path
        }
    }

    if (-not (Test-Path $tool.Path)) {
        throw "$($tool.Name) download did not create the expected installer at $($tool.Path)."
    }

    if ($isInstalled) {
        Write-Host "$($tool.Name) is already installed; refreshing install with latest downloaded installer."
    }

    if ($tool.Type -eq 'Msi') {
        Install-MsiPackage -Name $tool.Name -InstallerPath $tool.Path
    } else {
        Install-ExePackage -Name $tool.Name -InstallerPath $tool.Path -ArgumentList $tool.Arguments
    }
}

if (-not $SkipValidation) {
    Invoke-DocumentToolValidation
}
