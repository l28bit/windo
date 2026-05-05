# Release notes - WINDO v3.6.0 Special Edition

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

**Theme:** Quiet shell ergonomics, explicit trust posture, and safer command planning before elevation.

## Summary

WINDO v3.6.0 rolls the release-runway work shipped after v3.3.0 into the visible product version. The release includes the 3.4 Quiet Shell completion work, the 3.5 Trust Console, and the first 3.6 Syntax Forge capabilities.

This is not a jump to 4.x yet. Version 4 is still reserved for the Operator Mesh platform layer where modules, recipes, extras, prompt, launchpad, and export become one cohesive workflow surface.

## What is new

### Quiet Shell

- `windo completion` reports and persists completion mode.
- Default `native-first` completion delegates non-WINDO arguments to PowerShell completion.
- `WINDO_COMPLETION_MODE` can override completion behavior for the current process.

### Trust Console

- `windo trust` scores local posture from tasks, runner/updater integrity, audit-chain verification, profile block state, completion policy, and installer snapshot hash.
- `windo trust --online` compares the local installer snapshot to the published checksum from a non-elevated shell.
- Installer snapshot hashing uses the same line-ending-normalized checksum format as the release tooling.

### Syntax Forge

- `windo syntax [query]` maps common operator intent to exact WINDO commands.
- Syntax rows include aliases, category, command, preview command, risk class, and notes.
- Current intents include update, trust/proof, health, repair keys, support bundle, recipes, and launchpad.

### Recipe previews

- `windo recipes preview <name>` returns the exact recipe command without running it.
- `windo recipes run <name> --dry-run` exits before scheduled tasks, request files, result files, or audit entries.
- `windo run --recipe <name> --dry-run --json` returns the same structured preview payload.

## Upgrade

From a normal, non-elevated shell:

```powershell
windo install-latest
. $PROFILE
windo version
windo trust --online
windo syntax update
```

For a clean clone or first install:

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/Genesis/bootstrap.ps1)
. $PROFILE
windo preflight
windo trust --online
```

## Validation

Release validation should include:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Sync-InstallerChecksum.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Sync-VersionSnapshot.ps1 -Version 3.6.0
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-Windo.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-WindoLogic.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-PSScriptAnalyzer.ps1
```

The frozen release tree is stored under `versions/v3.6.0/`.
