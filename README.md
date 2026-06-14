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
scripts/
  Install-Sysmon.ps1
  Install-Winlogbeat.ps1
  Install-Metricbeat.ps1
  Install-Browsers.ps1
  Install-Thunderbird.ps1
Install-OSConfig.ps1
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
