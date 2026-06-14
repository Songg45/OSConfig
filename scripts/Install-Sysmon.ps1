#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallRoot,
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

function Invoke-SysmonValidation {
    param(
        [int]$TimeoutSeconds = 30
    )

    $logName = 'Microsoft-Windows-Sysmon/Operational'
    $marker = "OSCONFIG_SYSMON_TEST_$([guid]::NewGuid().ToString('N'))"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $commandProcessor = $env:ComSpec

    if ([string]::IsNullOrWhiteSpace($commandProcessor)) {
        $commandProcessor = Join-Path $env:SystemRoot 'System32\cmd.exe'
    }

    Write-Host "Generating Sysmon test command: $commandProcessor /c echo $marker"
    Start-Process -FilePath $commandProcessor -ArgumentList @('/c', "echo $marker") -Wait -WindowStyle Hidden

    do {
        Start-Sleep -Seconds 1

        $event = Get-WinEvent -FilterHashtable @{
            LogName = $logName
            Id = 1
            StartTime = (Get-Date).AddMinutes(-5)
        } -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -like "*$marker*" } |
            Select-Object -First 1

        if ($event) {
            Write-Host 'Sysmon validation event found.'
            Write-Host '----- Sysmon Event Viewer Message -----'
            Write-Host $event.Message
            Write-Host '----- End Sysmon Event Viewer Message -----'

            return
        }
    } while ((Get-Date) -lt $deadline)

    throw "Sysmon validation event was not found in '$logName' within $TimeoutSeconds seconds. Test marker: $marker"
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-Sysmon.ps1 must be run from an elevated PowerShell session.'
}

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $programData = [Environment]::GetFolderPath('CommonApplicationData')

    if ([string]::IsNullOrWhiteSpace($programData)) {
        $programData = 'C:\ProgramData'
    }

    $InstallRoot = Join-Path $programData 'OSConfig\Sysmon'
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot '..\configuration\sysmon\sysmonconfig-export.xml'
}

$InstallRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot)
$ConfigPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)

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

Write-Host "Sysmon install root: $InstallRoot"
Write-Host "Sysmon config path: $ConfigPath"

New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null
New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

if ($ForceDownload -or -not (Test-Path $sysmonExe)) {
    if ($PSCmdlet.ShouldProcess($downloadUrl, "Download to $zipPath")) {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
    }

    if (-not (Test-Path $zipPath)) {
        throw "Sysmon download did not create the expected archive at $zipPath."
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

if (-not $SkipValidation) {
    Invoke-SysmonValidation
}
