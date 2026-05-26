# WINDO v8.5.3 - Bootstrap Reliability Contract

Release date: 2026-05-25

## Summary

WINDO v8.5.3 hardens the bootstrap/update download path under PowerShell strict mode. It removes the specific failure modes that caused empty `-OutFile` binding and missing environment-variable property errors during API/raw fallback.

## Fixed

- Bootstrap web wrappers now pass `-OutFile` only when a real path is supplied.
- Bootstrap environment reads use a safe helper that returns `$null` for missing variables instead of touching `.Value` on a missing item.
- Raw fallback downloads now run directly instead of inside a background job that can lose parent-scope helper functions.
- Installed update helpers use safer environment reads and direct download behavior.

## Validation

- Missing env vars under `Set-StrictMode -Version Latest`.
- Exceptions without a `Response` property.
- Web/rest wrapper calls with omitted `OutFile`.
- GitHub API and raw checksum comparison after publish.
