# Release notes - WINDO v3.3.0 Special Edition

![WINDO logo](../../brand/Enterprise/assets/logo/windo-logo-full-dark-512.png)

**Theme:** Faster install confidence, native operator visuals, and a command center that does not require a browser.

## Summary

WINDO remains a PowerShell-first elevation helper for Windows: choose elevation before execution, run through a scheduled task with `RunLevel Highest`, keep a DPAPI-encrypted audit log, and verify runner/updater integrity from the local manifest.

v3.3.0 Special Edition adds a new visual install/update experience plus two operator commands: `windo preflight` for readiness checks and `windo launchpad` for a command-center view in terminal, JSON, HTML, or native Windows task-tray mode.

## What is new

### Special Edition install and update visuals

- `bootstrap.ps1`, `windo install-latest`, and `windo_install.ps1` now show a Special Edition banner and step cards.
- The flow calls out download, checksum, UAC handoff, secure-dir hardening, scheduled-task registration, manifest write, profile refresh, and snapshot write.
- The checksum remains the normalized installer checksum used by the release tooling and bootstrap verification path.

### Native tray launchpad

`windo launchpad --tray` creates a local tray-agent script under `%USERPROFILE%\.pwsh_secure\windo_launchpad_tray.ps1`, starts it hidden with Windows Forms, and exposes a shield tray icon, balloon notification, popup action window, and menu actions.

The tray path is local-only and browser-independent. Actions open visible PowerShell windows so command output remains available to the operator. When `brand/Enterprise` assets are present, tray mode uses the clean WINDO ICO instead of the generic Windows shield.

### Launchpad command center

`windo launchpad` shows the Special Edition operator surface:

- Readiness score and `READY` / `ATTENTION` / `REPAIR` status.
- Preflight checks with fix commands.
- Copy-ready actions for profile refresh, dashboard, integrity, verify, repair, and safe update.
- Built-in recipe list and discovered module list.
- `--json` for automation, `--html` for a portable local report, and `--open` for browser-based HTML when desired.

Use `--output <path>` or `--output=<path>` with HTML mode. The short `-o` form is intentionally not documented for `launchpad` because PowerShell can bind it as a common parameter before WINDO receives it.

### Preflight readiness scan

`windo preflight` is read-only and returns actionable check rows for:

- Non-elevated update posture.
- PowerShell runtime.
- Main and self-update scheduled tasks.
- Runner/updater integrity.
- Audit-chain verification.
- Current profile WINDO block.
- Keybinding policy.

Exit codes: `0` ready, `3` warnings, `4` critical.

## Upgrade

From a normal, non-elevated shell:

```powershell
windo install-latest
. $PROFILE
windo preflight
windo launchpad --tray
```

For a clean clone or first install:

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/Genesis/bootstrap.ps1)
. $PROFILE
windo doctor
windo integrity
windo preflight
```

## Validation

Release validation should include:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Sync-InstallerChecksum.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Sync-VersionSnapshot.ps1 -Version 3.3.0
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-Windo.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-WindoLogic.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-PSScriptAnalyzer.ps1
```

The frozen release tree is stored under `versions/v3.3.0/`.
