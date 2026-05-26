# WINDO v8.5.1 - Profile Parse Guard

Release date: 2026-05-25

## Summary

WINDO v8.5.1 is a focused V8.5 hardening release for update reliability. It fixes the generated profile syntax that could break `$PROFILE` after `windo install-latest`, then adds a permanent installer guard so invalid generated profile text is rejected before it can be written.

## Fixed

- Corrected generated help-marker parsing from `- ieq` to PowerShell's valid `-ieq` comparison operator.
- Added `Test-WindoProfileSyntax` to parse-check the full refreshed profile text before writing `$PROFILE`.
- Added regression coverage that extracts the generated profile here-strings from the installer, applies installer replacements, and validates the resulting profile block with the PowerShell parser.

## Operator Impact

- Updating to v8.5.1 should no longer replace a working profile with a generated WINDO block that fails to parse.
- If future generated profile code is invalid, the installer fails closed with a clear parser error and leaves the existing profile in place.

## Validation

- `./tools/Test-WindoLogic.ps1`
- `./tools/Validate-Windo.ps1`
- `./tools/Invoke-PSScriptAnalyzer.ps1`
- `./tools/Sync-InstallerChecksum.ps1`
- `./tools/Sync-VersionSnapshot.ps1 -Version 8.5.1`
