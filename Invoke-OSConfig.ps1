#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('WindowsUpdates', 'Sysmon', 'Winlogbeat', 'Metricbeat', 'Browsers', 'Thunderbird', 'DocumentTools', 'EverydayApps', 'Runtimes', 'Communication', 'Productivity', 'UserProfileSeed')]
    [string[]]$Component = @('WindowsUpdates', 'Runtimes', 'Sysmon', 'Winlogbeat', 'Metricbeat', 'Browsers', 'Thunderbird', 'DocumentTools', 'EverydayApps', 'Communication', 'Productivity', 'UserProfileSeed'),
    [switch]$ForceDownload,
    [switch]$SkipValidation,
    [switch]$SkipInstall,
    [switch]$SkipHealthCheck,
    [switch]$PrepareClone,
    [switch]$RemoveOSConfigRepo,
    [switch]$SkipReboot,
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Format-ElapsedTime {
    param(
        [timespan]$Elapsed
    )

    return '{0:00}:{1:00}:{2:00}' -f [math]::Floor($Elapsed.TotalHours), $Elapsed.Minutes, $Elapsed.Seconds
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    Write-Host ""
    Write-Host "===== $Name ====="
    $stepStarted = Get-Date
    Write-Host "Started: $($stepStarted.ToString('yyyy-MM-dd HH:mm:ss'))"

    try {
        & $ScriptBlock
        $stepEnded = Get-Date
        Write-Host "Ended: $($stepEnded.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Host "Elapsed: $(Format-ElapsedTime -Elapsed ($stepEnded - $stepStarted))"
    } catch {
        $stepEnded = Get-Date
        Write-Host "Ended: $($stepEnded.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Host "Elapsed: $(Format-ElapsedTime -Elapsed ($stepEnded - $stepStarted))"
        Write-Warning "$Name failed. $($_.Exception.Message)"

        if (-not $ContinueOnError) {
            throw
        }
    }
}

$repoRoot = $PSScriptRoot
$wrapperStarted = Get-Date

Write-Host 'OSConfig wrapper starting.'
Write-Host "Started: $($wrapperStarted.ToString('yyyy-MM-dd HH:mm:ss'))"

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
        & $healthScript -NoExit
    }
}

if ($PrepareClone) {
    Invoke-Step -Name 'Prepare Clone' -ScriptBlock {
        $prepareArgs = @{}

        if ($RemoveOSConfigRepo) {
            $prepareArgs.RemoveOSConfigRepo = $true
        }

        if ($SkipReboot) {
            $prepareArgs.SkipReboot = $true
        }

        & (Join-Path $repoRoot 'scripts\Prepare-Clone.ps1') @prepareArgs
    }
}

Write-Host ""
$wrapperEnded = Get-Date
Write-Host "OSConfig wrapper started: $($wrapperStarted.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "OSConfig wrapper ended: $($wrapperEnded.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "OSConfig wrapper elapsed: $(Format-ElapsedTime -Elapsed ($wrapperEnded - $wrapperStarted))"
Write-Host 'OSConfig wrapper completed.'
