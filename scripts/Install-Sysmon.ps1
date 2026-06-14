#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallRoot = "$env:ProgramData\OSConfig\Sysmon",
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\configuration\sysmon\sysmonconfig-export.xml'),
    [switch]$ForceDownload,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Sysmon.ps1 must be run from an elevated PowerShell session.'
}

$downloadUrl = 'https://download.sysinternals.com/files/Sysmon.zip'
$zipPath = Join-Path $InstallRoot 'Sysmon.zip'
$extractPath = Join-Path $InstallRoot 'bin'
$sysmonExe = Join-Path $extractPath 'Sysmon64.exe'

if ($Uninstall) {
    if (-not (Test-Path $sysmonExe)) {
        throw "Sysmon executable was not found at $sysmonExe."
    }

    if ($PSCmdlet.ShouldProcess('Sysmon service and driver', 'Uninstall')) {
        & $sysmonExe -u
    }

    return
}

if (-not (Test-Path $ConfigPath)) {
    throw "Sysmon configuration was not found at $ConfigPath."
}

New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null
New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

if ($ForceDownload -or -not (Test-Path $sysmonExe)) {
    if ($PSCmdlet.ShouldProcess($downloadUrl, "Download to $zipPath")) {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
    }

    if ($PSCmdlet.ShouldProcess($zipPath, "Expand to $extractPath")) {
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    }
}

if (-not (Test-Path $sysmonExe)) {
    throw "Sysmon64.exe was not found after extraction at $sysmonExe."
}

$service = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue

if ($service) {
    if ($PSCmdlet.ShouldProcess('Sysmon64', "Update configuration from $ConfigPath")) {
        & $sysmonExe -accepteula -c $ConfigPath
    }
} else {
    if ($PSCmdlet.ShouldProcess('Sysmon64', "Install with configuration $ConfigPath")) {
        & $sysmonExe -accepteula -i $ConfigPath
    }
}

Get-Service -Name 'Sysmon64'
