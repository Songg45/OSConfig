#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Sysmon')]
    [string[]]$Component = @('Sysmon'),
    [switch]$ForceDownload,
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-OSConfig.ps1 must be run from an elevated PowerShell session.'
}

$installSteps = [ordered]@{
    Sysmon = @{
        Path = Join-Path $PSScriptRoot 'scripts\Install-Sysmon.ps1'
    }
}

$failures = @()

foreach ($componentName in $Component) {
    $step = $installSteps[$componentName]

    if (-not $step) {
        throw "No install step is registered for component '$componentName'."
    }

    if (-not (Test-Path $step.Path)) {
        throw "Install script was not found for component '$componentName' at $($step.Path)."
    }

    $arguments = @()

    if ($ForceDownload) {
        $arguments += '-ForceDownload'
    }

    try {
        if ($PSCmdlet.ShouldProcess($componentName, "Run $($step.Path) $($arguments -join ' ')")) {
            Write-Host "Installing $componentName..."
            & $step.Path @arguments
            Write-Host "Finished $componentName."
        }
    } catch {
        $failures += [pscustomobject]@{
            Component = $componentName
            Error = $_.Exception.Message
        }

        Write-Warning "Failed to install $componentName. $($_.Exception.Message)"

        if (-not $ContinueOnError) {
            throw
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | Format-Table -AutoSize
    throw "$($failures.Count) OSConfig component install step(s) failed."
}

Write-Host 'OSConfig installation completed.'
