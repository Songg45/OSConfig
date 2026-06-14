# OSConfig

OSConfig is a Windows VM baseline configuration project for malware analysis and security telemetry labs.

The goal is to build repeatable PowerShell-based setup steps for installing common monitoring tools, runtime dependencies, and baseline utilities that malware samples often expect to find on a Windows host.

## Planned Components

- Sysmon
- Winlogbeat
- Metricbeat
- Sysinternals Suite
- Visual C++ runtimes
- .NET updates
- Python
- Additional baseline Windows VM tooling as needed

## Repository Layout

```text
configuration/
  sysmon/
    sysmonconfig-export.xml
  metricbeat/
    metricbeat.yml
  winlogbeat/
    winlogbeat.yml
assets/
  seed-files/
    cats/
scripts/
  Install-Sysmon.ps1
  Install-Winlogbeat.ps1
  Install-Metricbeat.ps1
  Install-Browsers.ps1
  Install-Thunderbird.ps1
  Install-DocumentTools.ps1
  Install-EverydayApps.ps1
  Install-Runtimes.ps1
  Install-Communication.ps1
  Install-Productivity.ps1
  Seed-UserProfile.ps1
  Prepare-Clone.ps1
  FirstBoot-RandomizeHost.ps1
Test-OSConfig.ps1
Install-OSConfig.ps1
Invoke-OSConfig.ps1
```

## Current Configuration

### Sysmon

The Sysmon configuration is stored at:

```text
configuration\sysmon\sysmonconfig-export.xml
```

This file is captured from the SwiftOnSecurity Sysmon configuration project:

```text
https://github.com/SwiftOnSecurity/sysmon-config/blob/master/sysmonconfig-export.xml
```

Install or update the current OSConfig baseline from an elevated PowerShell session:

```powershell
.\Install-OSConfig.ps1
```

Run the full wrapper, including installation and health check:

```powershell
.\Invoke-OSConfig.ps1
```

Run installation, health check, clone prep, OSConfig repo cleanup, and shutdown:

```powershell
.\Invoke-OSConfig.ps1 -PrepareClone -RemoveOSConfigRepo
```

Force fresh downloads for supported components:

```powershell
.\Install-OSConfig.ps1 -ForceDownload
```

Skip post-install validation checks:

```powershell
.\Install-OSConfig.ps1 -SkipValidation
```

Install or update Sysmon directly:

```powershell
.\scripts\Install-Sysmon.ps1
```

The Sysmon installer runs a harmless test command by default and then prints the matching Sysmon Event ID 1 Event Viewer message. This verifies that Sysmon is installed, logging process creation events, and readable from PowerShell.

The Sysmon installer is safe to run repeatedly. If Sysmon is already installed, the script updates the existing Sysmon configuration instead of installing a duplicate service. The validation step intentionally generates a fresh test event each time; use `-SkipValidation` if you want a quieter repeat run.

Force a fresh Sysmon download:

```powershell
.\scripts\Install-Sysmon.ps1 -ForceDownload
```

Uninstall Sysmon:

```powershell
.\scripts\Install-Sysmon.ps1 -Uninstall
```

### Metricbeat

The Metricbeat configuration sends events to Logstash at:

```text
172.20.200.200:30200
```

It also sets:

```yaml
pipeline_source: metricbeat
fields_under_root: true
```

Install or update Metricbeat directly from an elevated PowerShell session:

```powershell
.\scripts\Install-Metricbeat.ps1
```

The Metricbeat installer defaults to Metricbeat `8.19.16`, downloads the Windows x86_64 zip from Elastic, installs the service, copies `configuration\metricbeat\metricbeat.yml` into `C:\Program Files\Metricbeat`, enables the `system` and `windows` modules when present, starts the service, and tests the configuration. It is safe to run repeatedly; existing installs have their configuration refreshed and service restarted.

Install a different 8.x version:

```powershell
.\scripts\Install-Metricbeat.ps1 -Version 8.19.5
```

### Winlogbeat

The Winlogbeat configuration collects these Windows event logs:

- Application
- System
- Security
- Microsoft-Windows-Sysmon/Operational
- Microsoft-Windows-PowerShell/Operational
- Windows PowerShell

Events are sent to Logstash at:

```text
172.20.200.200:30200
```

It also sets:

```yaml
pipeline_source: winlogbeat
fields_under_root: true
```

Install or update Winlogbeat directly from an elevated PowerShell session:

```powershell
.\scripts\Install-Winlogbeat.ps1
```

The Winlogbeat installer defaults to Winlogbeat `8.19.16`, downloads the Windows x86_64 zip from Elastic, installs the service, copies `configuration\winlogbeat\winlogbeat.yml` into `C:\Program Files\Winlogbeat`, starts the service, tests the configuration, and verifies the configured Windows event logs are readable. It is safe to run repeatedly; existing installs have their configuration refreshed and service restarted.

Install a different 8.x version:

```powershell
.\scripts\Install-Winlogbeat.ps1 -Version 8.19.5
```

### Browsers

The browser installer adds common workstation browsers for detonation realism:

- Google Chrome
- Mozilla Firefox

Install or update browsers directly from an elevated PowerShell session:

```powershell
.\scripts\Install-Browsers.ps1
```

The installer downloads Chrome from Google's standalone enterprise MSI endpoint and Firefox from Mozilla's latest Windows MSI endpoint, installs both silently, and validates that each browser is present. It is safe to run repeatedly; existing browser installs are skipped by default. Use `-ForceDownload` to refresh the installer cache and rerun installation.

### Email

The email installer adds Mozilla Thunderbird as a realistic desktop email client for the detonation VM.

Install or update Thunderbird directly from an elevated PowerShell session:

```powershell
.\scripts\Install-Thunderbird.ps1
```

The installer downloads Thunderbird from Mozilla's latest Windows MSI endpoint, installs it silently, and validates that Thunderbird is present. It is safe to run repeatedly; existing Thunderbird installs are skipped by default. Use `-ForceDownload` to refresh the installer cache and rerun installation.

### Office And Documents

The document tools installer adds common workstation document and archive tools:

- LibreOffice
- 7-Zip
- Notepad++

Install or update document tools directly from an elevated PowerShell session:

```powershell
.\scripts\Install-DocumentTools.ps1
```

The installer downloads LibreOffice from The Document Foundation, 7-Zip from the official 7-Zip GitHub release mirror, and Notepad++ from the official Notepad++ GitHub release. It installs each tool silently and validates that each tool is present. It is safe to run repeatedly; existing installs are skipped by default. Use `-ForceDownload` to refresh the installer cache and rerun installation.

7-Zip covers the archive and file-handling baseline.

### Media And Everyday Apps

The everyday apps installer adds common media and personal-use applications:

- VLC Media Player
- Spotify
- GIMP

Install or update everyday apps directly from an elevated PowerShell session:

```powershell
.\scripts\Install-EverydayApps.ps1
```

The installer downloads VLC from VideoLAN, Spotify from Spotify's Windows installer endpoint, and GIMP from the official GIMP Windows download path. It installs each app silently and validates that each app is present. It is safe to run repeatedly; existing installs are skipped by default. Use `-ForceDownload` to refresh the installer cache and rerun installation.

### Runtimes And Dependencies

The runtimes installer adds common runtime dependencies for detonation compatibility:

- Microsoft Visual C++ Redistributable x64
- Microsoft Visual C++ Redistributable x86
- .NET Desktop Runtime x64
- .NET Desktop Runtime x86
- Eclipse Temurin Java 8 JRE
- Python 3.13

Install or update runtimes directly from an elevated PowerShell session:

```powershell
.\scripts\Install-Runtimes.ps1
```

The installer uses Microsoft's current Visual C++ redistributable links, Microsoft .NET Desktop Runtime `10.0.9`, Eclipse Adoptium's Temurin Java 8 JRE endpoint, and Python `3.13.14` from python.org. It is safe to run repeatedly; existing installs are skipped by default. Use `-ForceDownload` to refresh the installer cache and rerun installation.

### Communication

The communication installer adds common desktop communication apps:

- Discord
- Zoom
- Slack

Install or update communication apps directly from an elevated PowerShell session:

```powershell
.\scripts\Install-Communication.ps1
```

The installer downloads Discord from Discord's Windows download endpoint, Zoom from Zoom's latest x64 MSI endpoint, and Slack from Slack's Windows x64 download endpoint. Discord and Slack use per-user style installers, while Zoom installs through MSI. Existing installs are skipped by default. Use `-ForceDownload` to refresh the installer cache and rerun installation.

### Productivity

The productivity installer adds common workstation productivity tools:

- Visual Studio Code
- ChatGPT
- GitHub Desktop

Install or update productivity apps directly from an elevated PowerShell session:

```powershell
.\scripts\Install-Productivity.ps1
```

VS Code is downloaded from Microsoft's stable Windows x64 endpoint. GitHub Desktop is downloaded from GitHub's latest Windows endpoint. ChatGPT's official Windows app is distributed through the Microsoft Store, so the installer attempts a best-effort Store install through `winget` when available and otherwise prints the manual Store URL.

### User Profile Seeding

The user profile seeding script adds benign files and workstation artifacts:

- Desktop, Documents, Downloads, Pictures, and Screenshots folders
- RTF notes and resume-style documents
- CSV spreadsheet-style files
- HTML saved-page style documents
- ZIP archives
- Generated JPG and PNG images
- Seeded cat pictures in `Pictures\Cats`
- Chrome and Edge bookmarks when browser profile folders exist
- Local account full name update when running elevated

Run the seeding step directly:

```powershell
.\scripts\Seed-UserProfile.ps1
```

The seeding step runs last in the orchestrator. It avoids overwriting existing seeded files by default; use `-Force` to recreate seeded artifacts. Cat pictures are copied from `assets\seed-files\cats` so VM setup does not need to download them. Browser history is not modified in this pass because Chromium and Firefox history databases require careful SQLite edits while browsers are closed.

### Health Check

Run the health check after installation to report services, applications, configuration files, and seeded profile artifacts:

```powershell
.\Test-OSConfig.ps1
```

Emit JSON for automation:

```powershell
.\Test-OSConfig.ps1 -AsJson
```

The health check does not install or change anything. It exits with a nonzero status when required checks fail. Optional items, such as ChatGPT or browser bookmarks, are reported as warnings.

### Clone Preparation

Prepare the VM for cloning after installation and seeding:

```powershell
.\scripts\Prepare-Clone.ps1
```

The clone prep script:

- Sets the timezone to `Eastern Standard Time`
- Stops and disables Winlogbeat and Metricbeat
- Removes `C:\Program Files\Winlogbeat-Data`
- Removes `C:\Program Files\Metricbeat-Data`
- Cleans installer caches under `C:\ProgramData\OSConfig`
- Optionally schedules removal of the OSConfig repository folder with `-RemoveOSConfigRepo`
- Registers a one-time startup task
- Shuts down the VM

On the first boot of a clone, the startup task runs `FirstBoot-RandomizeHost.ps1`, randomizes the hostname, enables Winlogbeat and Metricbeat, deletes the startup task, optionally removes the OSConfig repository folder, and restarts the VM. After that second boot, the clone should have fresh Beat state and a unique hostname.

Test clone preparation without shutting down:

```powershell
.\scripts\Prepare-Clone.ps1 -SkipShutdown
```

Remove the OSConfig repository during clone prep:

```powershell
.\scripts\Prepare-Clone.ps1 -RemoveOSConfigRepo
```

## Usage

Copy the relevant configuration file into the matching Beat installation directory on the Windows VM.

Example target paths may vary by install method, but commonly look like:

```text
C:\Program Files\Metricbeat\metricbeat.yml
C:\Program Files\Winlogbeat\winlogbeat.yml
```

After copying the configuration, restart the matching service.

## Status

This project is in early setup. Configuration files are being added first, followed by PowerShell installers and baseline VM setup scripts.
