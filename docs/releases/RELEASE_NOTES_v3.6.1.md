# Release notes - WINDO v3.6.1 Special Edition

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

**Theme:** Explain the path before crossing the privilege boundary.

WINDO v3.6.1 extends the Syntax Forge runway with a new read-only execution planner. The point is simple: before an operator runs a command through WINDO, they can ask what route it will take, what it will touch, and what trust checks matter.

## New: `windo explain`

`windo explain <command...>` produces an execution plan without running the command.

It reports:

- planned route
- privilege boundary
- network expectation
- local file impact
- audit behavior
- checksum/provenance posture
- local artifacts
- suggested preflight checks
- exact next commands

Examples:

```powershell
windo explain install-latest
windo explain trust --online
windo explain recipes run firewall-profiles
windo explain -- Get-Service Spooler
windo explain --json -- install-latest
```

Use `--` before target commands that have their own flags. That keeps the target flags attached to the command being explained instead of letting WINDO consume them as global options.

## Why this matters

`windo syntax` answers "what should I run?".

`windo explain` answers "what will WINDO do if I run it?".

That gives operators a safer path from intent to execution before scheduled tasks, request/result files, audit entries, installer downloads, or tray helpers come into play.

## Validation

```powershell
windo explain install-latest
windo explain --json -- Get-Service Spooler
windo trust --online
```

## Release engineering

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Sync-InstallerChecksum.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Sync-VersionSnapshot.ps1 -Version 3.6.1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-Windo.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-WindoLogic.ps1
```
