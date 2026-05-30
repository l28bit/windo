# WINDO v8.5.7 - Midflight Fuel

WINDO v8.5.7 makes preflight repairable. Red/yellow checks now point to a curated repair lane instead of leaving the operator to guess what to run next.

## Highlights

- New `windo midflightfuel` command.
- `windo preflight` prints `Repair option: windo midflightfuel` when anything is not OK.
- Preflight JSON includes:
  - `repairCommand`
  - `repairPlan`
  - per-check `repairAction`
  - per-check `repairCommand`
- Supported repair lanes include:
  - verified reinstall/update handoff
  - keybinding safe reset
  - audit-chain backup and reset
  - trust posture repair
  - normal-shell launch guidance
  - manual PowerShell install guidance

## Rescue Path

When an installed WINDO profile is too old or damaged to update itself, use the bootstrap rescue path from a fresh normal PowerShell window:

```powershell
irm https://raw.githubusercontent.com/l28bit/windo/Exodus/bootstrap.ps1 | iex
```

## Validation

Run:

```powershell
.\tools\Test-WindoLogic.ps1
.\tools\Validate-Windo.ps1
.\tools\Invoke-PSScriptAnalyzer.ps1
.\tools\Sync-InstallerChecksum.ps1
.\tools\Sync-VersionSnapshot.ps1 -Version 8.5.7
```
