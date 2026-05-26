# WINDO v8.5.2 - Profile Reliability Contract

Release date: 2026-05-25

## Summary

WINDO v8.5.2 hardens the entire update path: bootstrap fallback, generated profile replacement, profile backups, and user-owned customizations.

## Fixed

- Bootstrap no longer touches a missing exception `Response` property under strict mode.
- Generated profile source checks use the same strict-mode-safe response handling.
- Installer no longer falls back to an empty profile body when an existing `$PROFILE` cannot be read or repaired.

## Added

- Managed profile block v2 metadata between the existing WINDO begin/end markers.
- Timestamped profile backups before WINDO rewrites the managed block.
- `profile.d` customization loading from:
  - `$HOME\Documents\windo\profile.d`
  - `$HOME\.pwsh_secure\profile.d`

## Operator Impact

- Existing profile content before and after the WINDO block remains outside WINDO ownership.
- WINDO replaces only its managed block during install/update.
- Custom local PowerShell should move into `profile.d` files so updates remain clean and repeatable.
