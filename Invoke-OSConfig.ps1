#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Sysmon', 'Winlogbeat', 'Metricbeat', 'Browsers', 'Thunderbird', 'DocumentTools', 'EverydayApps', 'Runtimes', 'Communication', 'Productivity', 'UserProfileSeed')]
    [string[]]$Component = @('Runtimes', 'Sysmon', 'Winlogbeat', 'Metricbeat', 'Browsers', 'Thunderbird', 'DocumentTools', 'EverydayApps', 'Communication', 'Productivity', 'UserProfileSeed'),
    [switch]$ForceDownload,
    [switch]$SkipValidation,
    [switch]$SkipInstall,
    [switch]$SkipHealthCheck,
    [switch]$PrepareClone,
    [switch]$RemoveOSConfigRepo,
    [switch]$SkipShutdown,
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    Write-Host ""
    Write-Host "===== $Name ====="

    try {
        & $ScriptBlock
    } catch {
        Write-Warning "$Name failed. $($_.Exception.Message)"

        if (-not $ContinueOnError) {
            throw
        }
    }
}

$repoRoot = $PSScriptRoot

if (-not $SkipInstall) {
    Invoke-Step -Name 'Install OSConfig Components' -ScriptBlock {
        $installArgs = @{
            Component = $Component
        }

        if ($ForceDownload) {
            $installArgs.ForceDownload = $true
        }

        if ($SkipValidation) {
            $installArgs.SkipValidation = $true
        }

        if ($ContinueOnError) {
            $installArgs.ContinueOnError = $true
        }

        & (Join-Path $repoRoot 'Install-OSConfig.ps1') @installArgs
    }
}

if (-not $SkipHealthCheck) {
    Invoke-Step -Name 'Test OSConfig Health' -ScriptBlock {
        $healthScript = Join-Path $repoRoot 'Test-OSConfig.ps1'
        $healthProcess = Start-Process -FilePath 'PowerShell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $healthScript) -Wait -PassThru

        if ($healthProcess.ExitCode -ne 0) {
            throw "OSConfig health check failed with exit code $($healthProcess.ExitCode)."
        }
    }
}

if ($PrepareClone) {
    Invoke-Step -Name 'Prepare Clone' -ScriptBlock {
        $prepareArgs = @{}

        if ($RemoveOSConfigRepo) {
            $prepareArgs.RemoveOSConfigRepo = $true
        }

        if ($SkipShutdown) {
            $prepareArgs.SkipShutdown = $true
        }

        & (Join-Path $repoRoot 'scripts\Prepare-Clone.ps1') @prepareArgs
    }
}

Write-Host ""
Write-Host 'OSConfig wrapper completed.'
