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

Install or update Sysmon directly:

```powershell
.\scripts\Install-Sysmon.ps1
```

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
