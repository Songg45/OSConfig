#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Version = '8.19.16',
    [string]$InstallRoot = 'C:\Program Files\Metricbeat',
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

function Invoke-MetricbeatValidation {
    param(
        [string]$MetricbeatExe,
        [string]$MetricbeatConfig
    )

    Write-Host 'Testing Metricbeat configuration...'
    & $MetricbeatExe test config -c $MetricbeatConfig -e

    if ($LASTEXITCODE -ne 0) {
        throw "Metricbeat configuration test failed with exit code $LASTEXITCODE."
    }

    $service = Get-Service -Name 'metricbeat' -ErrorAction SilentlyContinue

    if (-not $service) {
        throw 'Metricbeat service was not found after installation.'
    }

    if ($service.Status -ne 'Running') {
        throw "Metricbeat service is $($service.Status), expected Running."
    }

    Write-Host 'Metricbeat validation completed.'
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Metricbeat.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $DownloadRoot = Join-Path $programData 'OSConfig\Metricbeat'
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot '..\configuration\metricbeat\metricbeat.yml'
}

$InstallRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot)
$DownloadRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadRoot)
$ConfigPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)

$downloadUrl = "https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-$Version-windows-x86_64.zip"
$zipPath = Join-Path $DownloadRoot "metricbeat-$Version-windows-x86_64.zip"
$extractPath = Join-Path $DownloadRoot 'extract'
$metricbeatExe = Join-Path $InstallRoot 'metricbeat.exe'
$installServiceScript = Join-Path $InstallRoot 'install-service-metricbeat.ps1'
$installedConfigPath = Join-Path $InstallRoot 'metricbeat.yml'
$systemModulePath = Join-Path $InstallRoot 'modules.d\system.yml.disabled'
$enabledSystemModulePath = Join-Path $InstallRoot 'modules.d\system.yml'
$windowsModulePath = Join-Path $InstallRoot 'modules.d\windows.yml.disabled'
$enabledWindowsModulePath = Join-Path $InstallRoot 'modules.d\windows.yml'

if ($Uninstall) {
    $service = Get-Service -Name 'metricbeat' -ErrorAction SilentlyContinue

    if ($service) {
        if ($PSCmdlet.ShouldProcess('metricbeat', 'Stop service')) {
            Stop-Service -Name 'metricbeat' -Force -ErrorAction SilentlyContinue
        }

        if ($PSCmdlet.ShouldProcess('metricbeat', 'Delete service')) {
            & sc.exe delete metricbeat | Out-Host
        }
    }

    return
}

if (-not (Test-Path $ConfigPath)) {
    throw "Metricbeat configuration was not found at $ConfigPath."
}

Write-Host "Metricbeat version: $Version"
Write-Host "Metricbeat install root: $InstallRoot"
Write-Host "Metricbeat config path: $ConfigPath"

New-Item -Path $DownloadRoot -ItemType Directory -Force | Out-Null
New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null

$service = Get-Service -Name 'metricbeat' -ErrorAction SilentlyContinue

if ($ForceDownload -or -not (Test-Path $metricbeatExe)) {
    if ($service -and $service.Status -ne 'Stopped') {
        if ($PSCmdlet.ShouldProcess('metricbeat', 'Stop service before updating files')) {
            Stop-Service -Name 'metricbeat' -Force
        }
    }

    if ($PSCmdlet.ShouldProcess($downloadUrl, "Download to $zipPath")) {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
    }

    if (-not (Test-Path $zipPath)) {
        throw "Metricbeat download did not create the expected archive at $zipPath."
    }

    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

    if ($PSCmdlet.ShouldProcess($zipPath, "Expand to $extractPath")) {
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    }

    $extractedRoot = Get-ChildItem -Path $extractPath -Directory |
        Where-Object { $_.Name -like "metricbeat-$Version-windows-x86_64*" } |
        Select-Object -First 1

    if (-not $extractedRoot) {
        throw "Could not find extracted Metricbeat directory under $extractPath."
    }

    if ($PSCmdlet.ShouldProcess($InstallRoot, "Copy Metricbeat files from $($extractedRoot.FullName)")) {
        Copy-Item -Path (Join-Path $extractedRoot.FullName '*') -Destination $InstallRoot -Recurse -Force
    }
}

if (-not (Test-Path $metricbeatExe)) {
    throw "metricbeat.exe was not found at $metricbeatExe."
}

if ($PSCmdlet.ShouldProcess($installedConfigPath, "Copy configuration from $ConfigPath")) {
    Copy-Item -Path $ConfigPath -Destination $installedConfigPath -Force
}

if ((Test-Path $systemModulePath) -and -not (Test-Path $enabledSystemModulePath)) {
    if ($PSCmdlet.ShouldProcess($enabledSystemModulePath, 'Enable Metricbeat system module')) {
        Rename-Item -Path $systemModulePath -NewName 'system.yml'
    }
}

if ((Test-Path $windowsModulePath) -and -not (Test-Path $enabledWindowsModulePath)) {
    if ($PSCmdlet.ShouldProcess($enabledWindowsModulePath, 'Enable Metricbeat windows module')) {
        Rename-Item -Path $windowsModulePath -NewName 'windows.yml'
    }
}

if (-not (Get-Service -Name 'metricbeat' -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $installServiceScript)) {
        throw "Metricbeat service installer was not found at $installServiceScript."
    }

    if ($PSCmdlet.ShouldProcess('metricbeat', "Install service using $installServiceScript")) {
        Push-Location $InstallRoot
        try {
            PowerShell.exe -ExecutionPolicy Bypass -File $installServiceScript
        } finally {
            Pop-Location
        }
    }
}

$service = Get-Service -Name 'metricbeat' -ErrorAction Stop

if ($PSCmdlet.ShouldProcess('metricbeat', 'Set service startup type to Automatic')) {
    Set-Service -Name 'metricbeat' -StartupType Automatic
}

if ($service.Status -eq 'Running') {
    if ($PSCmdlet.ShouldProcess('metricbeat', 'Restart service')) {
        Restart-Service -Name 'metricbeat' -Force
    }
} else {
    if ($PSCmdlet.ShouldProcess('metricbeat', 'Start service')) {
        Start-Service -Name 'metricbeat'
    }
}

Get-Service -Name 'metricbeat'

if (-not $SkipValidation) {
    Invoke-MetricbeatValidation -MetricbeatExe $metricbeatExe -MetricbeatConfig $installedConfigPath
}
