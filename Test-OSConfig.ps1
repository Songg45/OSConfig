#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SeedRoot = $env:USERPROFILE,
    [switch]$AsJson,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

function Format-ElapsedTime {
    param(
        [timespan]$Elapsed
    )

    return '{0:00}:{1:00}:{2:00}' -f [math]::Floor($Elapsed.TotalHours), $Elapsed.Minutes, $Elapsed.Seconds
}

function Test-InstalledProgram {
    param(
        [string]$DisplayNamePattern
    )

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        $program = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $DisplayNamePattern } |
            Select-Object -First 1

        if ($program) {
            return $true
        }
    }

    return $false
}

function New-CheckResult {
    param(
        [string]$Category,
        [string]$Name,
        [bool]$Passed,
        [string]$Detail,
        [bool]$Required = $true
    )

    [pscustomobject]@{
        Category = $Category
        Name = $Name
        Passed = $Passed
        Required = $Required
        Detail = $Detail
    }
}

function Test-PathSafe {
    param(
        [string]$Path
    )

    try {
        return Test-Path -Path $Path -ErrorAction Stop
    } catch {
        return $false
    }
}

function Test-ServiceCheck {
    param(
        [string]$Name,
        [string]$ServiceName,
        [bool]$Required = $true
    )

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if (-not $service) {
        return New-CheckResult -Category 'Service' -Name $Name -Passed $false -Required $Required -Detail "Service '$ServiceName' was not found."
    }

    $passed = $service.Status -eq 'Running'
    return New-CheckResult -Category 'Service' -Name $Name -Passed $passed -Required $Required -Detail "Service '$ServiceName' status: $($service.Status)."
}

function Test-PathCheck {
    param(
        [string]$Category,
        [string]$Name,
        [string[]]$Paths,
        [bool]$Required = $true
    )

    $found = $Paths | Where-Object { Test-PathSafe -Path $_ } | Select-Object -First 1

    if ($found) {
        return New-CheckResult -Category $Category -Name $Name -Passed $true -Required $Required -Detail "Found: $found"
    }

    return New-CheckResult -Category $Category -Name $Name -Passed $false -Required $Required -Detail "Missing paths: $($Paths -join '; ')"
}

function Test-ProgramCheck {
    param(
        [string]$Name,
        [string]$DisplayNamePattern,
        [string[]]$Paths = @(),
        [bool]$Required = $true
    )

    $isInstalled = Test-InstalledProgram -DisplayNamePattern $DisplayNamePattern
    $foundPath = $Paths | Where-Object { Test-PathSafe -Path $_ } | Select-Object -First 1

    if ($isInstalled -or $foundPath) {
        $detail = if ($foundPath) { "Found: $foundPath" } else { "Registry match: $DisplayNamePattern" }
        return New-CheckResult -Category 'Application' -Name $Name -Passed $true -Required $Required -Detail $detail
    }

    return New-CheckResult -Category 'Application' -Name $Name -Passed $false -Required $Required -Detail "Not found. Registry pattern: $DisplayNamePattern"
}

$repoRoot = $PSScriptRoot
$SeedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SeedRoot)
$results = @()
$healthStarted = Get-Date

$results += Test-PathCheck -Category 'Configuration' -Name 'Sysmon config' -Paths @(Join-Path $repoRoot 'configuration\sysmon\sysmonconfig-export.xml')
$results += Test-PathCheck -Category 'Configuration' -Name 'Winlogbeat config' -Paths @(Join-Path $repoRoot 'configuration\winlogbeat\winlogbeat.yml')
$results += Test-PathCheck -Category 'Configuration' -Name 'Metricbeat config' -Paths @(Join-Path $repoRoot 'configuration\metricbeat\metricbeat.yml')
$results += Test-PathCheck -Category 'Assets' -Name 'Seeded cat pictures' -Paths @(Join-Path $repoRoot 'assets\seed-files\cats\cat-picture-001.jpg')

$results += Test-ServiceCheck -Name 'Sysmon' -ServiceName 'Sysmon64'
$results += Test-ServiceCheck -Name 'Winlogbeat' -ServiceName 'winlogbeat'
$results += Test-ServiceCheck -Name 'Metricbeat' -ServiceName 'metricbeat'

$results += Test-ProgramCheck -Name 'Google Chrome' -DisplayNamePattern 'Google Chrome*' -Paths @('C:\Program Files\Google\Chrome\Application\chrome.exe', 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe')
$results += Test-ProgramCheck -Name 'Mozilla Firefox' -DisplayNamePattern 'Mozilla Firefox*' -Paths @('C:\Program Files\Mozilla Firefox\firefox.exe', 'C:\Program Files (x86)\Mozilla Firefox\firefox.exe')
$results += Test-ProgramCheck -Name 'Mozilla Thunderbird' -DisplayNamePattern 'Mozilla Thunderbird*' -Paths @('C:\Program Files\Mozilla Thunderbird\thunderbird.exe', 'C:\Program Files (x86)\Mozilla Thunderbird\thunderbird.exe')
$results += Test-ProgramCheck -Name 'LibreOffice' -DisplayNamePattern 'LibreOffice*' -Paths @('C:\Program Files\LibreOffice\program\soffice.exe')
$results += Test-ProgramCheck -Name '7-Zip' -DisplayNamePattern '7-Zip*' -Paths @('C:\Program Files\7-Zip\7zFM.exe', 'C:\Program Files\7-Zip\7z.exe')
$results += Test-ProgramCheck -Name 'Notepad++' -DisplayNamePattern 'Notepad++*' -Paths @('C:\Program Files\Notepad++\notepad++.exe')
$results += Test-ProgramCheck -Name 'VLC media player' -DisplayNamePattern 'VLC media player*' -Paths @('C:\Program Files\VideoLAN\VLC\vlc.exe', 'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe')
$results += Test-ProgramCheck -Name 'Spotify' -DisplayNamePattern 'Spotify*' -Paths @((Join-Path $SeedRoot 'AppData\Roaming\Spotify\Spotify.exe')) -Required $false
$results += Test-ProgramCheck -Name 'GIMP' -DisplayNamePattern 'GIMP*' -Paths @('C:\Program Files\GIMP 3\bin\gimp-3.0.exe', 'C:\Program Files\GIMP 2\bin\gimp-2.10.exe')
$results += Test-ProgramCheck -Name 'Discord' -DisplayNamePattern 'Discord*' -Paths @("$env:LOCALAPPDATA\Discord\Update.exe", "$env:LOCALAPPDATA\Discord\app-*\Discord.exe")
$results += Test-ProgramCheck -Name 'Zoom' -DisplayNamePattern 'Zoom*' -Paths @('C:\Program Files\Zoom\bin\Zoom.exe', 'C:\Program Files (x86)\Zoom\bin\Zoom.exe')
$results += Test-ProgramCheck -Name 'Slack' -DisplayNamePattern 'Slack*' -Paths @("$env:LOCALAPPDATA\slack\slack.exe", "$env:LOCALAPPDATA\slack\app-*\slack.exe", 'C:\Program Files\Slack\slack.exe')
$results += Test-ProgramCheck -Name 'Visual Studio Code' -DisplayNamePattern 'Microsoft Visual Studio Code*' -Paths @('C:\Program Files\Microsoft VS Code\Code.exe', "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe")
$results += Test-ProgramCheck -Name 'GitHub Desktop' -DisplayNamePattern 'GitHub Desktop*' -Paths @("$env:LOCALAPPDATA\GitHubDesktop\GitHubDesktop.exe", "$env:LOCALAPPDATA\GitHubDesktop\app-*\GitHubDesktop.exe")
$results += Test-ProgramCheck -Name 'ChatGPT' -DisplayNamePattern 'ChatGPT*' -Paths @("$env:LOCALAPPDATA\Microsoft\WindowsApps\ChatGPT.exe") -Required $false

$results += Test-ProgramCheck -Name 'Visual C++ Redistributable x64' -DisplayNamePattern 'Microsoft Visual C++*Redistributable* (x64)*'
$results += Test-ProgramCheck -Name 'Visual C++ Redistributable x86' -DisplayNamePattern 'Microsoft Visual C++*Redistributable* (x86)*'
$results += Test-ProgramCheck -Name '.NET Desktop Runtime x64' -DisplayNamePattern 'Microsoft Windows Desktop Runtime - 10.0.9 (x64)*' -Paths @('C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App\10.0.9')
$results += Test-ProgramCheck -Name '.NET Desktop Runtime x86' -DisplayNamePattern 'Microsoft Windows Desktop Runtime - 10.0.9 (x86)*' -Paths @('C:\Program Files (x86)\dotnet\shared\Microsoft.WindowsDesktop.App\10.0.9')
$results += Test-ProgramCheck -Name 'Eclipse Temurin Java 8 JRE' -DisplayNamePattern 'Eclipse Temurin JRE with Hotspot 8*' -Paths @('C:\Program Files\Eclipse Adoptium')
$results += Test-ProgramCheck -Name 'Python 3.13' -DisplayNamePattern 'Python 3.13*' -Paths @('C:\Program Files\Python313\python.exe')

$seedChecks = @(
    @{ Name = 'Seeded PDF'; Paths = @(Join-Path $SeedRoot 'Downloads\invoice-1042.pdf') },
    @{ Name = 'Seeded DOCX'; Paths = @(Join-Path $SeedRoot 'Documents\Work\project-outline.docx') },
    @{ Name = 'Seeded XLSX'; Paths = @(Join-Path $SeedRoot 'Documents\Work\expense-tracker.xlsx') },
    @{ Name = 'Seeded ZIP'; Paths = @(Join-Path $SeedRoot 'Downloads\q2-reports.zip') },
    @{ Name = 'Seeded image'; Paths = @(Join-Path $SeedRoot 'Pictures\vacation-photo-001.jpg') },
    @{ Name = 'Seeded cat picture'; Paths = @(Join-Path $SeedRoot 'Pictures\Cats\cat-picture-001.jpg') },
    @{ Name = 'Chrome bookmarks'; Paths = @(Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Bookmarks'); Required = $false },
    @{ Name = 'Edge bookmarks'; Paths = @(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Bookmarks'); Required = $false }
)

foreach ($check in $seedChecks) {
    $required = if ($check.ContainsKey('Required')) { [bool]$check.Required } else { $true }
    $results += Test-PathCheck -Category 'UserProfileSeed' -Name $check.Name -Paths $check.Paths -Required $required
}

$requiredFailures = @($results | Where-Object { $_.Required -and -not $_.Passed })
$optionalFailures = @($results | Where-Object { -not $_.Required -and -not $_.Passed })

if ($AsJson) {
    [pscustomobject]@{
        Passed = $requiredFailures.Count -eq 0
        RequiredFailures = $requiredFailures.Count
        OptionalFailures = $optionalFailures.Count
        Results = $results
    } | ConvertTo-Json -Depth 5
} else {
    Write-Host 'OSConfig health check'
    Write-Host '====================='
    Write-Host "Started: $($healthStarted.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host ''

    foreach ($group in ($results | Group-Object Category)) {
        Write-Host "[$($group.Name)]"

        foreach ($result in $group.Group) {
            $status = if ($result.Passed) { 'PASS' } elseif ($result.Required) { 'FAIL' } else { 'WARN' }
            Write-Host ("{0,-4} {1} - {2}" -f $status, $result.Name, $result.Detail)
        }

        Write-Host ''
    }

    Write-Host "Required failures: $($requiredFailures.Count)"
    Write-Host "Optional warnings: $($optionalFailures.Count)"

    $healthEnded = Get-Date
    Write-Host "Ended: $($healthEnded.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "Elapsed: $(Format-ElapsedTime -Elapsed ($healthEnded - $healthStarted))"
}

if ($requiredFailures.Count -gt 0) {
    if ($NoExit) {
        throw "$($requiredFailures.Count) required OSConfig health check(s) failed."
    }

    exit 1
}

if ($NoExit) {
    return
}

exit 0
