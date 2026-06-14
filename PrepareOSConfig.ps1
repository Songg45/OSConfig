#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$GitInstallerUrl = 'https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/Git-2.54.0-64-bit.exe',
    [string]$TempRoot = 'C:\temp',
    [string]$RepoUrl = 'https://github.com/Songg45/OSConfig.git'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'PrepareOSConfig.ps1 must be run from an elevated PowerShell session.'
}

New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null

$gitInstallerPath = Join-Path $TempRoot 'Git-2.54.0-64-bit.exe'
$repoPath = Join-Path $TempRoot 'OSConfig'

Write-Host "Downloading Git installer to $gitInstallerPath"
Invoke-WebRequest -Uri $GitInstallerUrl -OutFile $gitInstallerPath

Write-Host 'Installing Git for Windows.'
$gitInstall = Start-Process -FilePath $gitInstallerPath -ArgumentList @('/VERYSILENT', '/NORESTART') -Wait -PassThru

if ($gitInstall.ExitCode -ne 0) {
    throw "Git installer failed with exit code $($gitInstall.ExitCode)."
}

$gitExe = 'C:\Program Files\Git\cmd\git.exe'

if (-not (Test-Path $gitExe)) {
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue

    if ($gitCommand) {
        $gitExe = $gitCommand.Source
    }
}

if (-not (Test-Path $gitExe)) {
    throw 'Git was installed, but git.exe was not found.'
}

if (Test-Path $repoPath) {
    Write-Host "$repoPath already exists. Pulling latest changes."
    & $gitExe -C $repoPath pull --ff-only
} else {
    Write-Host "Cloning $RepoUrl into $repoPath"
    & $gitExe clone $RepoUrl $repoPath
}

if ($LASTEXITCODE -ne 0) {
    throw "Git operation failed with exit code $LASTEXITCODE."
}

$invokeScript = Join-Path $repoPath 'Invoke-OSConfig.ps1'

if (-not (Test-Path $invokeScript)) {
    throw "Invoke-OSConfig.ps1 was not found at $invokeScript."
}

Write-Host 'Starting OSConfig installation and clone preparation.'
& PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $invokeScript -PrepareClone -RemoveOSConfigRepo
