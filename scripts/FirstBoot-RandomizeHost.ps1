#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$TaskName = 'OSConfig-FirstBootRandomizeHost',
    [string]$Prefix = 'DET',
    [string]$OSConfigRepoPath
)

$ErrorActionPreference = 'Stop'

function New-RandomHostname {
    param(
        [string]$HostnamePrefix
    )

    $suffix = -join ((48..57) + (65..90) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
    $hostname = "$HostnamePrefix-$suffix"

    if ($hostname.Length -gt 15) {
        $hostname = $hostname.Substring(0, 15)
    }

    return $hostname
}

$newHostname = New-RandomHostname -HostnamePrefix $Prefix

Write-Host "Renaming computer to $newHostname"
Rename-Computer -NewName $newHostname -Force

foreach ($serviceName in @('winlogbeat', 'metricbeat')) {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if ($service) {
        Write-Host "Enabling $serviceName"
        Set-Service -Name $serviceName -StartupType Automatic
    }
}

Write-Host "Deleting scheduled task $TaskName"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

if (-not [string]::IsNullOrWhiteSpace($OSConfigRepoPath)) {
    $resolvedRepo = Resolve-Path -Path $OSConfigRepoPath -ErrorAction SilentlyContinue

    if ($resolvedRepo) {
        Write-Host "Removing OSConfig repository folder: $($resolvedRepo.Path)"
        Remove-Item -LiteralPath $resolvedRepo.Path -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning "OSConfig repository path was not found: $OSConfigRepoPath"
    }
}

Write-Host 'Shutting down after first-boot hostname randomization. The hostname change will apply on the next power-on.'
Stop-Computer -Force
