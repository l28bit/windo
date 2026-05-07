# WINDO v5.4.0 - Windows Integration Plane

WINDO v5.4.0 makes the Command Center feel more like a dedicated current-user Windows tool.

## New: `windo integrate`

```powershell
windo integrate
windo integrate doctor
windo integrate repair
windo integrate shortcuts
windo integrate startup
windo integrate shim
windo integrate open
```

The integration plane inspects and repairs:

- Start Menu shortcuts under the current user profile.
- A Power Studio desktop shortcut.
- A sign-in startup shortcut for the browser-independent tray.
- `.pwsh_secure\windo_start_tray.ps1`.
- `.pwsh_secure\bin\windo.cmd`.
- Current-user PATH posture for the shim directory.

## Control actions

New curated action IDs:

- `integrate-status`
- `integrate-doctor`
- `integrate-repair`
- `integrate-open`
- `integrate-shim`
- `integrate-startup`

These remain visible-shell actions. No arbitrary hidden executor was added.

## Native surfaces

Power Studio and the tray action list now include Windows integration status and repair entries.

## Safety boundary

The integration plane is current-user scoped. It does not write Program Files, HKLM, or machine-wide PATH.
