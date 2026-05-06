# WINDO v5.3.0 - Power Studio

WINDO v5.3.0 adds the first guided Windows-native workflow surface: **Power Studio**.

## New Commands

```powershell
windo studio
windo center studio
windo center wizard
windo center power
```

Power Studio generates `.pwsh_secure\windo_power_studio.ps1` and opens a modern Windows Forms command room with guided workflow tabs.

## Workflow Lanes

- Start
- Trust
- Repair
- Security
- Developer
- Package

Each lane exposes curated WINDO actions with separate **Preview**, **Queue**, and **Run** controls. Preview and Queue use the control-plane catalog. Run opens a visible PowerShell window.

## Safety Boundary

Power Studio does not run arbitrary hidden commands. It only exposes curated WINDO action IDs and visible-shell command launch paths.

## Validation

Run:

```powershell
./tools/Test-WindoLogic.ps1
./tools/Validate-Windo.ps1
./tools/Invoke-PSScriptAnalyzer.ps1
```
