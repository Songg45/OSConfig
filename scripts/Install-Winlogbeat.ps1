#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Version = '8.19.16',
    [string]$InstallRoot = 'C:\Program Files\Winlogbeat',
    [string]$DownloadRoot,
    [string]$ConfigPath,
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

function Invoke-WinlogbeatValidation {
    param(
        [string]$WinlogbeatExe,
        [string]$WinlogbeatConfig
    )

    Write-Host 'Testing Winlogbeat configuration...'
    & $WinlogbeatExe test config -c $WinlogbeatConfig -e

    if ($LASTEXITCODE -ne 0) {
        throw "Winlogbeat configuration test failed with exit code $LASTEXITCODE."
    }

    $requiredLogs = @(
        'Application',
        'System',
        'Security',
        'Microsoft-Windows-Sysmon/Operational',
        'Microsoft-Windows-PowerShell/Operational',
        'Windows PowerShell'
    )

    Write-Host 'Checking configured Windows event logs...'

    foreach ($logName in $requiredLogs) {
        $log = Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue

        if ($log) {
            Write-Host "Event log available: $logName"
        } else {
            Write-Warning "Event log was not found or is not readable: $logName"
        }
    }

    $service = Get-Service -Name 'winlogbeat' -ErrorAction SilentlyContinue

    if (-not $service) {
        throw 'Winlogbeat service was not found after installation.'
    }

    if ($service.Status -ne 'Running') {
        throw "Winlogbeat service is $($service.Status), expected Running."
    }

    Write-Host 'Winlogbeat validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Winlogbeat.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\Winlogbeat'
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot '..\configuration\winlogbeat\winlogbeat.yml'
}

$InstallRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot)
$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)
$ConfigPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)

$downloadUrl = "https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-$Version-windows-x86_64.zip"
$zipPath = Join-Path $DownloadRoot "winlogbeat-$Version-windows-x86_64.zip"
$extractPath = Join-Path $DownloadRoot 'extract'
$winlogbeatExe = Join-Path $InstallRoot 'winlogbeat.exe'
$installServiceScript = Join-Path $InstallRoot 'install-service-winlogbeat.ps1'
$installedConfigPath = Join-Path $InstallRoot 'winlogbeat.yml'

if ($Uninstall) {
    $service = Get-Service -Name 'winlogbeat' -ErrorAction SilentlyContinue

    if ($service) {
        if ($PSCmdlet.ShouldProcess('winlogbeat', 'Stop service')) {
            Stop-Service -Name 'winlogbeat' -Force -ErrorAction SilentlyContinue
        }

        if ($PSCmdlet.ShouldProcess('winlogbeat', 'Delete service')) {
            & sc.exe delete winlogbeat | Out-Host
        }
    }

    return
}

if (-not (Test-Path $ConfigPath)) {
    throw "Winlogbeat configuration was not found at $ConfigPath."
}

Write-Host "Winlogbeat version: $Version"
Write-Host "Winlogbeat install root: $InstallRoot"
Write-Host "Winlogbeat config path: $ConfigPath"

New-Item -Path $DownloadRoot -ItemType Directory -Force | Out-Null
New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null

$service = Get-Service -Name 'winlogbeat' -ErrorAction SilentlyContinue

if ($ForceDownload -or -not (Test-Path $winlogbeatExe)) {
    if ($service -and $service.Status -ne 'Stopped') {
        if ($PSCmdlet.ShouldProcess('winlogbeat', 'Stop service before updating files')) {
            Stop-Service -Name 'winlogbeat' -Force
        }
    }

    if ($PSCmdlet.ShouldProcess($downloadUrl, "Download to $zipPath")) {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
    }

    if (-not (Test-Path $zipPath)) {
        throw "Winlogbeat download did not create the expected archive at $zipPath."
    }

    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

    if ($PSCmdlet.ShouldProcess($zipPath, "Expand to $extractPath")) {
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    }

    $extractedRoot = Get-ChildItem -Path $extractPath -Directory |
        Where-Object { $_.Name -like "winlogbeat-$Version-windows-x86_64*" } |
        Select-Object -First 1

    if (-not $extractedRoot) {
        throw "Could not find extracted Winlogbeat directory under $extractPath."
    }

    if ($PSCmdlet.ShouldProcess($InstallRoot, "Copy Winlogbeat files from $($extractedRoot.FullName)")) {
        Copy-Item -Path (Join-Path $extractedRoot.FullName '*') -Destination $InstallRoot -Recurse -Force
    }
}

if (-not (Test-Path $winlogbeatExe)) {
    throw "winlogbeat.exe was not found at $winlogbeatExe."
}

if ($PSCmdlet.ShouldProcess($installedConfigPath, "Copy configuration from $ConfigPath")) {
    Copy-Item -Path $ConfigPath -Destination $installedConfigPath -Force
}

if (-not (Get-Service -Name 'winlogbeat' -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $installServiceScript)) {
        throw "Winlogbeat service installer was not found at $installServiceScript."
    }

    if ($PSCmdlet.ShouldProcess('winlogbeat', "Install service using $installServiceScript")) {
        Push-Location $InstallRoot
        try {
            PowerShell.exe -ExecutionPolicy Bypass -File $installServiceScript
        } finally {
            Pop-Location
        }
    }
}

$service = Get-Service -Name 'winlogbeat' -ErrorAction Stop

if ($PSCmdlet.ShouldProcess('winlogbeat', 'Set service startup type to Automatic')) {
    Set-Service -Name 'winlogbeat' -StartupType Automatic
}

if ($service.Status -eq 'Running') {
    if ($PSCmdlet.ShouldProcess('winlogbeat', 'Restart service')) {
        Restart-Service -Name 'winlogbeat' -Force
    }
} else {
    if ($PSCmdlet.ShouldProcess('winlogbeat', 'Start service')) {
        Start-Service -Name 'winlogbeat'
    }
}

Get-Service -Name 'winlogbeat'

if (-not $SkipValidation) {
    Invoke-WinlogbeatValidation -WinlogbeatExe $winlogbeatExe -WinlogbeatConfig $installedConfigPath
}
