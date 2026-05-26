# WINDO v8.5.0 - Unreleased

## Highlights

- Semver: **8.5.0** with **V8.5** edition branding (derived from installer semver).
- Published branch contract is **`Exodus`** (GitHub default) unless overridden by `WINDO_TRACKING_BRANCH` / `WINDO_RELEASE_COMMIT`. Legacy env value `Prometheus` normalizes to `Exodus`.

## New commands

### `windo contract`

Local release contract posture beyond raw version fields:

```powershell
windo contract
windo contract doctor
windo contract --json
```

Checks include profile WINDO block version stamp, runner integrity, effective release branch, and (in doctor mode) published installer/checksum alignment via read-only network calls.

### `windo history search`

Search encrypted audit history by command text (case-insensitive substring by default):

```powershell
windo history search install-latest
windo history search "windo run" -n 10
windo history --contains elevation
windo history search 'windo\s+run' --regex --json
```

## Enrichments

- `windo source` JSON includes embedded `contract` metadata.
- Control/center quick action **Contract Doctor** (`windo contract doctor`).
- Syntax Forge shortcut for contract posture discovery.
- Edition-aware command center HTML titles (`WINDO V8.5 Command Center`).

## Operator notes

- Doctor mode performs the same class of read-only network lookups as `windo source`; run from a normal shell when possible.
- History search decrypts the full audit log; see `docs/performance.md` for large-log guidance.

## Validation

```powershell
./tools/Test-WindoLogic.ps1
./tools/Validate-Windo.ps1
./tools/Sync-InstallerChecksum.ps1
./tools/Sync-VersionSnapshot.ps1 -Version 8.5.0
```
