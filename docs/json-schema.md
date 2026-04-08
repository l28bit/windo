# WINDO JSON output (schema 2.6)

Commands that support `--json` or `-Json` emit a single **envelope** so scripts can rely on stable top-level fields.

## Envelope

| Field | Type | Description |
|--------|------|-------------|
| `schemaVersion` | string | `"2.6"` for WINDO v2.6.x |
| `windoVersion` | string | Installer profile version (e.g. `"2.7.1"`) |
| `command` | string | Logical subcommand name (`doctor`, `integrity`, `version`, `verify`, `log`, `stats`, `history`, `last`, `context`, `trace`, `export` payload in bundles, etc.) |
| `generatedAt` | string | ISO-8601 timestamp |
| `payload` | object | Command-specific data |

Example:

```json
{
  "schemaVersion": "2.6",
  "windoVersion": "2.7.1",
  "command": "doctor",
  "generatedAt": "2026-04-01T12:00:00.0000000-04:00",
  "payload": { }
}
```

## Breaking change from pre-2.6 JSON

Earlier releases returned **flat** objects (for example `{ "windoVersion": "2.5.0", ... }`). From **2.6.0**, the same information lives under **`payload`**, with the envelope fields above. Scripts should read `payload` and check `schemaVersion`.

Patch releases (for example **v2.6.1**) may bump `windoVersion` without changing `schemaVersion` when JSON shape is unchanged.

## On-disk audit log

The DPAPI-encrypted log file (`windo_history.enc`) is **not** required to use this envelope; only **CLI** JSON output is standardized here. `windo verify` continues to validate the existing line format and hash chain.

## Last-command metadata

`%USERPROFILE%\.pwsh_secure\windo_last_meta.json` uses a separate small schema (e.g. `schemaVersion` `"1.0"`) with `commandLine`, `storedAt`, and `lastRequestId`. It is updated when an elevated run **completes** (including timeout paths).
