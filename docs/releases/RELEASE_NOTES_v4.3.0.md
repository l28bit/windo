# Release notes - WINDO v4.3.0

v4.3.0 is the Control Plane Wiring release. It connects tray, surface, motion, and curated command launch into a local Windows-native control layer while keeping execution explicit and visible.

## New: `windo control`

```powershell
windo control
windo control prime
windo control actions
windo control queue surface-prime
windo control run launchpad-tray
windo control pulse
```

`control prime` writes `.pwsh_secure\control\windo_control_plane.json` plus a request-queue folder. The manifest includes native surface readiness, motion policy, queued requests, and a curated action catalog for tray/native consumers.

`control queue <action-id>` writes an explicit JSON request artifact. `control run <action-id>` launches only known WINDO actions in a visible PowerShell window, so command output remains inspectable.

## Tray expansion

`windo launchpad --tray` now includes actions for:

- native surface status
- control plane status and prime
- motion pulse
- existing launchpad, dashboard, integrity, repair, and update flows

## Animation status

Animations are present through `windo motion pulse`, `windo surface pulse`, and `windo control pulse`. Motion remains policy-aware: auto mode stays quiet in CI, redirected output, or when `WINDO_NO_SPINNER` is set.

## Validation

```powershell
./tools/Sync-InstallerChecksum.ps1
./tools/Sync-VersionSnapshot.ps1 -Version 4.3.0
./tools/Test-WindoLogic.ps1
./tools/Validate-Windo.ps1
./tools/Invoke-PSScriptAnalyzer.ps1
```
