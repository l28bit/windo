# Release notes - WINDO v4.1.1

v4.1.1 is a Genesis prep release. It keeps the Security Foundry feature set from v4.1.0 and corrects the published branch contract before the next major runway work.

## Changed

- Install/update, checksum, trust, extras, and security documentation now target the corrected `Genesis` branch.
- README visuals now use constrained final brand assets:
  - `brand/winDO.png`
  - `brand/assets/logos/transparent-github-avatar-panel.png`
  - `brand/Enterprise/assets/svg/windo-brand-mark-contained-dark.svg`
- The rough cropped secondary wordmark image was removed from the main README.

## Validation

```powershell
./tools/Sync-InstallerChecksum.ps1
./tools/Sync-VersionSnapshot.ps1 -Version 4.1.1
./tools/Test-WindoLogic.ps1
./tools/Validate-Windo.ps1
./tools/Invoke-PSScriptAnalyzer.ps1
```
