# Release notes - WINDO v4.2.0

v4.2.0 is the Native Surface Prep release. It hardens profile startup and lays more local Windows-native wiring without exposing the reserved major-release package.

## New: `windo profile doctor`

`windo profile doctor` now reports prompt-initialization issues alongside WINDO profile block state.

```powershell
windo profile doctor
windo profile doctor --json
windo profile repair --prompt-init
```

The repair path wraps oh-my-posh init lines in a `try/catch` guard and writes a timestamped profile backup first. This keeps a missing oh-my-posh cached init script from breaking `. $PROFILE`.

## New: `windo motion`

```powershell
windo motion
windo motion auto
windo motion off
windo motion pulse
```

Motion defaults to `auto`: interactive terminals get small spinners/pulses, while CI, redirected output, and `WINDO_NO_SPINNER` stay quiet.

## New: `windo surface`

```powershell
windo surface
windo surface prime
windo surface pulse
```

`surface` reports native tray readiness, Windows Forms support, motion policy, prompt profile issues, and local next commands. `prime` writes a local manifest under `.pwsh_secure\surface\windo_surface_manifest.json`.

## Validation

```powershell
./tools/Sync-InstallerChecksum.ps1
./tools/Sync-VersionSnapshot.ps1 -Version 4.2.0
./tools/Test-WindoLogic.ps1
./tools/Validate-Windo.ps1
./tools/Invoke-PSScriptAnalyzer.ps1
```
