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
    [switch]$ContinueOnError,
    [int]$MaxWindowsUpdateReboots = 5,
    [string]$LogRoot,
    [string]$StateRoot,
    [string]$BootstrapUrl = 'http://osconfig.puterlabs.us',
    [string]$UserProfileRoot = $env:USERPROFILE,
    [switch]$ResumeOSConfig
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Format-ElapsedTime {
    param(
        [timespan]$Elapsed
    )

    return '{0:00}:{1:00}:{2:00}' -f [math]::Floor($Elapsed.TotalHours), $Elapsed.Minutes, $Elapsed.Seconds
}

function Resolve-UserProfileRoot {
    param(
        [string]$RequestedPath
    )

    $systemProfilePath = Join-Path $env:SystemRoot 'System32\config\systemprofile'

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath) -and
        $RequestedPath.TrimEnd('\') -ine $systemProfilePath.TrimEnd('\') -and
        (Test-Path -LiteralPath $RequestedPath)) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RequestedPath)
    }

    $candidate = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $profilePath = [Environment]::ExpandEnvironmentVariables($_.ProfileImagePath)

            if ([string]::IsNullOrWhiteSpace($profilePath) -or
                $profilePath -like "$env:SystemRoot*" -or
                $profilePath -match '\\(Default|Public|defaultuser0)$' -or
                -not (Test-Path -LiteralPath (Join-Path $profilePath 'NTUSER.DAT'))) {
                return $null
            }

            Get-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $candidate) {
        throw 'Unable to resolve a non-system Windows user profile for profile seeding.'
    }

    return $candidate.FullName
}

function ConvertTo-CommandArgument {
    param(
        [string]$Value
    )

    return '"' + ($Value -replace '"', '`"') + '"'
}

function Add-SwitchArgument {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [bool]$Enabled
    )

    if ($Enabled) {
        $Arguments.Add("-$Name")
    }
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

function Get-ResumeArgumentList {
    $resumeTokens = [System.Collections.Generic.List[string]]::new()

    if ($Component.Count -gt 0) {
        $resumeTokens.Add('-Component')

        foreach ($componentName in $Component) {
            $resumeTokens.Add($componentName)
        }
    }

    Add-SwitchArgument -Arguments $resumeTokens -Name 'ForceDownload' -Enabled $ForceDownload.IsPresent
    Add-SwitchArgument -Arguments $resumeTokens -Name 'SkipValidation' -Enabled $SkipValidation.IsPresent
    Add-SwitchArgument -Arguments $resumeTokens -Name 'SkipInstall' -Enabled $SkipInstall.IsPresent
    Add-SwitchArgument -Arguments $resumeTokens -Name 'SkipHealthCheck' -Enabled $SkipHealthCheck.IsPresent
    Add-SwitchArgument -Arguments $resumeTokens -Name 'PrepareClone' -Enabled $PrepareClone.IsPresent
    Add-SwitchArgument -Arguments $resumeTokens -Name 'RemoveOSConfigRepo' -Enabled $RemoveOSConfigRepo.IsPresent
    Add-SwitchArgument -Arguments $resumeTokens -Name 'SkipReboot' -Enabled $SkipReboot.IsPresent
    Add-SwitchArgument -Arguments $resumeTokens -Name 'ContinueOnError' -Enabled $ContinueOnError.IsPresent
    $resumeTokens.Add('-MaxWindowsUpdateReboots')
    $resumeTokens.Add($MaxWindowsUpdateReboots.ToString())
    $resumeTokens.Add('-LogRoot')
    $resumeTokens.Add($LogRoot)
    $resumeTokens.Add('-StateRoot')
    $resumeTokens.Add($StateRoot)
    $resumeTokens.Add('-BootstrapUrl')
    $resumeTokens.Add($BootstrapUrl)
    $resumeTokens.Add('-UserProfileRoot')
    $resumeTokens.Add($UserProfileRoot)
    $resumeTokens.Add('-ResumeOSConfig')

    $resumeJson = $resumeTokens.ToArray() | ConvertTo-Json -Compress
    $resumeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($resumeJson))

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('-NoProfile')
    $arguments.Add('-ExecutionPolicy')
    $arguments.Add('Bypass')
    $arguments.Add('-Command')

    $commandParts = [System.Collections.Generic.List[string]]::new()
    $commandParts.Add('[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12')
    $commandParts.Add("`$env:OSCONFIG_RESUME = '1'")
    $commandParts.Add("`$env:OSCONFIG_RESUME_ARGS_B64 = '$resumeEncoded'")
    $commandParts.Add("irm '$BootstrapUrl' | iex")
    $arguments.Add((ConvertTo-CommandArgument -Value ($commandParts -join '; ')))

    return ($arguments -join ' ')
}

function Register-OSConfigResumeTask {
    param(
        [string]$TaskName,
        [string]$ArgumentList
    )

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $ArgumentList
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

    Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
}

function Get-OSConfigState {
    param(
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }

    return [pscustomobject]@{
        WindowsUpdateReboots = 0
        StartedAt = (Get-Date).ToString('o')
    }
}

function Save-OSConfigState {
    param(
        [string]$Path,
        [object]$State
    )

    $folder = Split-Path -Path $Path -Parent
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding ASCII
}

function Set-OSConfigStateValue {
    param(
        [object]$State,
        [string]$Name,
        [object]$Value
    )

    $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Invoke-WindowsUpdatePhase {
    param(
        [string]$WindowsUpdateScript,
        [string]$ResumeTaskName,
        [string]$StatePath
    )

    $state = Get-OSConfigState -Path $StatePath

    Invoke-Step -Name 'Install Windows Updates' -ScriptBlock {
        $updateArgs = @{
            AsJson = $true
        }

        if ($ForceDownload) {
            $updateArgs.ForceDownload = $true
        }

        if ($SkipValidation) {
            $updateArgs.SkipValidation = $true
        }

        if ($ContinueOnError) {
            $updateArgs.ContinueOnError = $true
        }

        $json = & $WindowsUpdateScript @updateArgs

        if (-not $json) {
            throw 'Windows update script did not return a status object.'
        }

        $result = $json | Select-Object -Last 1 | ConvertFrom-Json
        Write-Host "Windows update status: $($result.Status)"
        Write-Host "Windows updates found: $($result.UpdatesFound)"
        Write-Host "Windows updates installed: $($result.UpdatesInstalled)"
        Write-Host "Windows update reboot required: $($result.RebootRequired)"

        if ([int]$result.UpdatesFound -eq 0) {
            Unregister-ScheduledTask -TaskName $ResumeTaskName -Confirm:$false -ErrorAction SilentlyContinue

            if (Test-Path -LiteralPath $StatePath) {
                Remove-Item -LiteralPath $StatePath -Force
            }

            return
        }

        $windowsUpdateReboots = [int]$state.WindowsUpdateReboots + 1
        Set-OSConfigStateValue -State $state -Name 'WindowsUpdateReboots' -Value $windowsUpdateReboots

        if ($windowsUpdateReboots -gt $MaxWindowsUpdateReboots) {
            throw "Windows updates requested more than $MaxWindowsUpdateReboots reboot(s)."
        }

        Set-OSConfigStateValue -State $state -Name 'LastRebootRequestedAt' -Value (Get-Date).ToString('o')
        Save-OSConfigState -Path $StatePath -State $state

        $resumeArgs = Get-ResumeArgumentList
        Register-OSConfigResumeTask -TaskName $ResumeTaskName -ArgumentList $resumeArgs

        Write-Host "Windows updates were found. Rebooting for update pass $windowsUpdateReboots of $MaxWindowsUpdateReboots."
        Write-Host "Windows update reported reboot required: $($result.RebootRequired)"
        Write-Host "Registered resume task: $ResumeTaskName"
        Write-Host 'Restarting in 30 seconds so Windows Updates can search again.'
        Start-Sleep -Seconds 30

        if ($script:TranscriptStarted) {
            Stop-Transcript | Out-Null
            $script:TranscriptStarted = $false
        }

        Restart-Computer -Force
        exit 3010
    }
}

$repoRoot = $PSScriptRoot
$UserProfileRoot = Resolve-UserProfileRoot -RequestedPath $UserProfileRoot

if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'OSConfig\Logs'
}

if ([string]::IsNullOrWhiteSpace($StateRoot)) {
    $StateRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'OSConfig\State'
}

New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
New-Item -Path $StateRoot -ItemType Directory -Force | Out-Null

$logPath = Join-Path $LogRoot ("Invoke-OSConfig-{0}.log" -f (Get-Date).ToString('yyyyMMdd-HHmmss'))
$statePath = Join-Path $StateRoot 'Invoke-OSConfig.json'
$resumeTaskName = 'OSConfig-Resume'
$script:TranscriptStarted = $false

try {
    Start-Transcript -Path $logPath -Append | Out-Null
    $script:TranscriptStarted = $true
} catch {
    Write-Warning "Unable to start transcript at $logPath. $($_.Exception.Message)"
}

$wrapperStarted = Get-Date

Write-Host 'OSConfig wrapper starting.'
Write-Host "Started: $($wrapperStarted.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Log file: $logPath"
Write-Host "User profile root: $UserProfileRoot"

if ($ResumeOSConfig) {
    Write-Host 'Resuming OSConfig from scheduled startup task.'
}

$remainingComponents = @($Component | Where-Object { $_ -ne 'WindowsUpdates' })

if (-not $SkipInstall -and ($Component -contains 'WindowsUpdates')) {
    Invoke-WindowsUpdatePhase -WindowsUpdateScript (Join-Path $repoRoot 'scripts\Install-WindowsUpdates.ps1') -ResumeTaskName $resumeTaskName -StatePath $statePath
}

if (-not $SkipInstall -and $remainingComponents.Count -gt 0) {
    Invoke-Step -Name 'Install OSConfig Components' -ScriptBlock {
        $installArgs = @{
            Component = $remainingComponents
            UserProfileRoot = $UserProfileRoot
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
        & $healthScript -SeedRoot $UserProfileRoot -NoExit
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

Unregister-ScheduledTask -TaskName $resumeTaskName -Confirm:$false -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $statePath) {
    Remove-Item -LiteralPath $statePath -Force
}

Write-Host ""
$wrapperEnded = Get-Date
Write-Host "OSConfig wrapper started: $($wrapperStarted.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "OSConfig wrapper ended: $($wrapperEnded.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "OSConfig wrapper elapsed: $(Format-ElapsedTime -Elapsed ($wrapperEnded - $wrapperStarted))"
Write-Host 'OSConfig wrapper completed.'

if ($script:TranscriptStarted) {
    Stop-Transcript | Out-Null
}
