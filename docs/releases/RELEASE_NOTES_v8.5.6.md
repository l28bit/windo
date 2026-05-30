# WINDO v8.5.6 - Dr. Run

WINDO v8.5.6 fortifies the task runner workflow around download recovery, repair planning, config visibility, and cleanup safety.

## Highlights

- New `windo runner` command family:
  - `windo runner doctor`
  - `windo runner status`
  - `windo runner config`
  - `windo runner cleanup --dry-run`
  - `windo runner cleanup --apply`
  - `windo runner repair`
- `windo doctor` and `windo config` now surface runner lifecycle state.
- `windo cleanup` backs up and clears the active log, but runner artifact cleanup is dry-run unless explicitly applied.
- Installer manifest now includes schema and runner lifecycle command references.

## Safety Contract

Runner cleanup only considers known WINDO request/result/temp patterns under `.pwsh_secure`. Prefix-collision paths are rejected, and repair planning remains explicit and visible.

## Validation

Run:

```powershell
.\tools\Test-WindoLogic.ps1
.\tools\Validate-Windo.ps1
.\tools\Invoke-PSScriptAnalyzer.ps1
.\tools\Sync-InstallerChecksum.ps1
.\tools\Sync-VersionSnapshot.ps1 -Version 8.5.6
```
