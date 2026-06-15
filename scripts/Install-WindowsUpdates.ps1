#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$IncludeDrivers,
    [switch]$ForceDownload,
    [switch]$SkipValidation,
    [switch]$SkipInstall,
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-WindowsUpdates.ps1 must be run from an elevated PowerShell session.'
}

$criteria = "IsInstalled=0 and IsHidden=0"

if (-not $IncludeDrivers) {
    $criteria = "$criteria and Type='Software'"
}

Write-Host "Searching for Windows updates with criteria: $criteria"

$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$searchResult = $searcher.Search($criteria)

if ($searchResult.Updates.Count -eq 0) {
    Write-Host 'No applicable Windows updates were found.'
    return
}

Write-Host "Found $($searchResult.Updates.Count) applicable Windows update(s)."

$updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
    $update = $searchResult.Updates.Item($i)
    Write-Host ("[{0}] {1}" -f ($i + 1), $update.Title)

    if ($update.EulaAccepted -eq $false) {
        $update.AcceptEula()
    }

    [void]$updatesToInstall.Add($update)
}

if ($SkipInstall) {
    Write-Host 'SkipInstall was set. Windows updates were listed but not installed.'
    return
}

Write-Host 'Downloading Windows updates.'
$downloader = $session.CreateUpdateDownloader()
$downloader.Updates = $updatesToInstall
$downloadResult = $downloader.Download()

Write-Host "Windows update download result code: $($downloadResult.ResultCode)"

if ($downloadResult.ResultCode -notin @(2, 3)) {
    $message = "Windows update download failed with result code $($downloadResult.ResultCode)."

    if ($ContinueOnError) {
        Write-Warning $message
        return
    }

    throw $message
}

Write-Host 'Installing Windows updates.'
$installer = $session.CreateUpdateInstaller()
$installer.Updates = $updatesToInstall
$installResult = $installer.Install()

Write-Host "Windows update install result code: $($installResult.ResultCode)"
Write-Host "Windows update reboot required: $($installResult.RebootRequired)"

for ($i = 0; $i -lt $updatesToInstall.Count; $i++) {
    $updateResult = $installResult.GetUpdateResult($i)
    Write-Host ("[{0}] ResultCode={1} HResult={2}" -f ($i + 1), $updateResult.ResultCode, $updateResult.HResult)
}

if ($installResult.ResultCode -notin @(2, 3)) {
    $message = "Windows update install failed with result code $($installResult.ResultCode)."

    if ($ContinueOnError) {
        Write-Warning $message
        return
    }

    throw $message
}
