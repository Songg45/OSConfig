#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TimeZoneId = 'Eastern Standard Time',
    [string]$TaskName = 'OSConfig-FirstBootRandomizeHost',
    [string]$HostnamePrefix = 'DET',
    [string]$FirstBootScriptPath = 'C:\ProgramData\OSConfig\FirstBoot-RandomizeHost.ps1',
    [string]$OSConfigRepoPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$RemoveOSConfigRepo,
    [switch]$SkipReboot
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-AndDisableBeat {
    param(
        [string]$ServiceName,
        [int]$StopTimeoutSeconds = 60
    )

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if (-not $service) {
        Write-Warning "Service $ServiceName was not found."
        return
    }

    if ($service.Status -ne 'Stopped') {
        if ($PSCmdlet.ShouldProcess($ServiceName, 'Stop service')) {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            $service.WaitForStatus('Stopped', [timespan]::FromSeconds($StopTimeoutSeconds))
        }
    }

    if ($PSCmdlet.ShouldProcess($ServiceName, 'Disable service')) {
        Set-Service -Name $ServiceName -StartupType Disabled
    }
}

function Remove-PathIfPresent {
    param(
        [string]$Path,
        [int]$RetryCount = 12,
        [int]$RetryDelaySeconds = 5
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Path, 'Remove path')) {
        return
    }

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq $RetryCount) {
                throw
            }

            Write-Warning "Failed to remove $Path on attempt $attempt of $RetryCount. $($_.Exception.Message)"
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Register-FirstBootTask {
    $sourceScript = Join-Path $PSScriptRoot 'FirstBoot-RandomizeHost.ps1'
    $destinationFolder = Split-Path -Path $FirstBootScriptPath -Parent

    if (-not (Test-Path -LiteralPath $sourceScript)) {
        throw "First boot script was not found at $sourceScript."
    }

    if ($PSCmdlet.ShouldProcess($FirstBootScriptPath, 'Copy first-boot script')) {
        New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
        Copy-Item -Path $sourceScript -Destination $FirstBootScriptPath -Force
    }

    $argument = "-NoProfile -ExecutionPolicy Bypass -File `"$FirstBootScriptPath`" -TaskName `"$TaskName`" -Prefix `"$HostnamePrefix`""

    if ($RemoveOSConfigRepo) {
        $argument = "$argument -OSConfigRepoPath `"$OSConfigRepoPath`""
    }

    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

    if ($PSCmdlet.ShouldProcess($TaskName, 'Register first-boot scheduled task')) {
        Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'Prepare-Clone.ps1 must be run from an elevated PowerShell session.'
}

if ($PSCmdlet.ShouldProcess($TimeZoneId, 'Set timezone')) {
    Set-TimeZone -Id $TimeZoneId
}

foreach ($serviceName in @('winlogbeat', 'metricbeat')) {
    Stop-AndDisableBeat -ServiceName $serviceName
}

foreach ($path in @(
    'C:\Program Files\Winlogbeat-Data',
    'C:\Program Files\Metricbeat-Data'
)) {
    Remove-PathIfPresent -Path $path
}

foreach ($path in @(
    'C:\ProgramData\OSConfig\Browsers',
    'C:\ProgramData\OSConfig\Communication',
    'C:\ProgramData\OSConfig\DocumentTools',
    'C:\ProgramData\OSConfig\EverydayApps',
    'C:\ProgramData\OSConfig\Metricbeat',
    'C:\ProgramData\OSConfig\Productivity',
    'C:\ProgramData\OSConfig\Runtimes',
    'C:\ProgramData\OSConfig\Sysmon',
    'C:\ProgramData\OSConfig\Thunderbird',
    'C:\ProgramData\OSConfig\Winlogbeat'
)) {
    Remove-PathIfPresent -Path $path
}

Register-FirstBootTask

if ($RemoveOSConfigRepo) {
    Write-Host "OSConfig repository folder will be removed on first clone boot: $OSConfigRepoPath"
}

Write-Host 'Clone preparation complete.'
Write-Host "First boot task: $TaskName"
Write-Host "First boot script: $FirstBootScriptPath"

if (-not $SkipReboot) {
    if ($PSCmdlet.ShouldProcess('Computer', 'Reboot to run first-boot clone preparation task')) {
        Write-Host 'Waiting 2 minutes before rebooting.'
        Start-Sleep -Seconds 120
        Restart-Computer -Force
    }
}
