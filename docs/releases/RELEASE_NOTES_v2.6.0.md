# Release notes — WINDO v2.6.0

## Summary

v2.6.0 deepens **operator commands**, **structured JSON**, a **four-state integrity model**, **reporting and export**, and optional **maintainer scaffolding**—without changing bootstrap, scheduled tasks, DPAPI log line format, or PSReadLine behavior.

## JSON envelope

All supported `--json` outputs use:

- `schemaVersion`: `"2.6"`
- `windoVersion`: e.g. `"2.6.0"`
- `command`, `generatedAt`, `payload`

Scripts that parsed flat v2.5.x JSON should read **`payload`** instead. See `docs/json-schema.md`.

## Integrity levels

`windo integrity`, `windo doctor`, `windo version`, HTML **report**, and **export** bundles surface **OK \| DRIFT \| TAMPERED \| UNKNOWN** per runner, self-update script, and overall.

## New / updated commands

| Command | Description |
|--------|-------------|
| `windo context [--json]` | Environment summary (version, paths, tasks, last RequestId when present). |
| `windo replay` | Same as `windo !!` (re-run last stored command). |
| `windo trace <RequestId>` / `windo trace --id <id>` | Locate audit entry by RequestId. |
| `windo export [-o zip] [-n N]` | Zip: manifest, envelope JSON (doctor, integrity), audit excerpt. |
| `--dry-run` | With elevated commands or replay: no task, no req/res files, no audit append. |

## Last-command metadata

`%USERPROFILE%\.pwsh_secure\windo_last_meta.json` records `commandLine`, `storedAt`, and `lastRequestId` when a run finishes (including timeout). `windo last` and `windo doctor` surface it when available.

## Report

`windo report` HTML includes summary counts, category breakdown, integrity levels, and recent entries (with elevation column).

## Upgrade

Run the installer elevated (`bootstrap` or `windo_install.ps1`), then `. $PROFILE`. Verify with `windo help`, `windo doctor --json`, and spot-check `payload.schemaVersion` in the output.
