# WINDO v5.2.0 - Native Surface Panel

WINDO v5.2.0 moves the Exodus Command Center deeper into Windows-native surfaces without adding a browser dependency or hiding execution.

## New Commands

```powershell
windo surface panel
windo surface window
windo center panel
```

These commands generate `.pwsh_secure\windo_surface_panel.ps1` and launch a Windows Forms panel with status cards and curated action rows.

## What Changed

- Added a browser-independent **WINDO Surface Panel** for common Command Center actions.
- Added `surface-panel` to the curated control-plane action catalog.
- Added Surface Panel to the native tray popup/menu action list.
- Added status-aware tray icon resolution for ready, warning, denied, elevated, and neutral Enterprise icons when available.
- Expanded `windo surface doctor` to check panel script freshness.
- Updated help, tab completion, README, changelog, and release-train metadata for v5.2.0.

## Safety Boundary

The panel does not execute arbitrary commands. It only exposes curated WINDO actions, and each action opens in a visible PowerShell window so output remains inspectable.

## Validation

Run:

```powershell
./tools/Test-WindoLogic.ps1
./tools/Validate-Windo.ps1
./tools/Invoke-PSScriptAnalyzer.ps1
```
