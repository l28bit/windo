# WINDO JSON output (schema 3.0)

Commands that support `--json` or `-Json` emit a single **envelope** so scripts can rely on stable top-level fields.

## Which version is WINDO—the product or `schemaVersion`?

**The release you have installed** is the **product (semver) version**: the same value as **`windo version`**, the installer **`$WindoVersion`** (e.g. **`3.0.0`**, **`2.9.1`**), and the JSON field **`windoVersion`**. That is the number to use when talking about “WINDO 2.9” vs “WINDO 3.0.”

**`schemaVersion`** (**`"2.6"`** or **`"3.0"`**) is **only** the name of the **CLI JSON envelope contract**. It stayed **`2.6`** for every product release from **v2.6.0** through **v2.9.x** because the envelope shape did not get a breaking change until **v3.0.0** (when **`meta`** was added). So you are **not** “on WINDO 2.6” in the product sense just because JSON says `schemaVersion: "2.6"`—you might be on **WINDO 2.9.1** with **`schemaVersion` `2.6`**.

**Summary:** **`windoVersion`** = actual WINDO release; **`schemaVersion`** = JSON wrapper version for automation authors.

## Envelope

| Field | Type | Description |
|--------|------|-------------|
| `schemaVersion` | string | **`"3.0"`** for WINDO **v3.0.0+** CLI JSON (v2.6.x installers emitted `"2.6"`) |
| `windoVersion` | string | Installer profile version (e.g. `"3.0.0"`) |
| `command` | string | Logical subcommand name (`doctor`, `integrity`, `config`, `backups`, `version`, `verify`, `log`, `stats`, `history`, `last`, `context`, `trace`, `profile`, `export` payload in bundles, etc.) |
| `generatedAt` | string | ISO-8601 timestamp |
| `meta` | object | Host context (see below). **New in v3.0.0.** |
| `payload` | object | Command-specific data |

### `meta` (v3.0.0+)

| Field | Type | Description |
|--------|------|-------------|
| `psEdition` | string | e.g. `Core` or `Desktop` |
| `psVersion` | string | PowerShell version (e.g. `7.5.5`) |
| `osVersion` | string | `Environment.OSVersion` string |

Example:

```json
{
  "schemaVersion": "3.0",
  "windoVersion": "3.0.0",
  "command": "doctor",
  "generatedAt": "2026-04-01T12:00:00.0000000-04:00",
  "meta": {
    "psEdition": "Core",
    "psVersion": "7.5.5",
    "osVersion": "Microsoft Windows NT 10.0.26200.0"
  },
  "payload": { }
}
```

## Migrating from schema 2.6

- **v2.6.x** envelopes had **no** `meta` object; **`schemaVersion`** was **`"2.6"`**.
- **v3.0.0+** adds **`meta`** and sets **`schemaVersion`** to **`"3.0"`**. **`payload` shapes** for existing commands are unchanged unless noted in the changelog.
- Automation should accept **`schemaVersion`** **`2.6`** or **`3.0`** (or branch on `schemaVersion` if you need `meta`).

## Breaking change from pre-2.6 JSON

Earlier releases returned **flat** objects (for example `{ "windoVersion": "2.5.0", ... }`). From **2.6.0**, the same information lives under **`payload`**, with the envelope fields above. Scripts should read `payload` and check `schemaVersion`.

Patch releases may bump `windoVersion` without changing `schemaVersion` when JSON shape is unchanged.

## On-disk audit log

The DPAPI-encrypted log file (`windo_history.enc`) is **not** required to use this envelope; only **CLI** JSON output is standardized here. `windo verify` continues to validate the existing line format and hash chain.

## Last-command metadata

`%USERPROFILE%\.pwsh_secure\windo_last_meta.json` uses a separate small schema (e.g. `schemaVersion` `"1.0"`) with `commandLine`, `storedAt`, and `lastRequestId`. It is updated when an elevated run **completes** (including timeout paths).

## Automation `exitCode` in `payload`

Several commands mirror **`$global:WINDO_EXIT_CODE`** inside **`payload.exitCode`** so scripts can parse JSON only (no host exit code). Meanings align with the README table:

| `command` | `payload.exitCode` | Notes |
|-----------|-------------------|--------|
| `doctor` | 0, 2, 3, 6 | Health / tasks / integrity-style signals |
| `integrity` | 0, 3, 6 | Overall component state |
| `verify` | 0, 2, 4 | Log missing/empty vs chain failure |
| `stats` | 0 | Success; invalid filters exit **before** JSON is printed (host exit **2**, no envelope) |
| `profile` | 0 | Listing only |
| `config` | 0 | Listing only |
| `backups` | 0, 2 | **2** = bad args, prune without `--force`, prune failure |

## `config` payload (v3.0.0+)

| Field | Type | Description |
|--------|------|-------------|
| `secureDir` | string | WINDO secure directory (`.pwsh_secure`) |
| `settings` | array | Rows: `name`, `environmentValue` (string or null), `effectiveNote` (human-readable effective behavior) |
| `exitCode` | number | **0** |

## `backups` payload (v3.0.0+)

Lists **`windo_history*.enc.bak`** files created by **`windo cleanup`** (newest first).

| Field | Type | Description |
|--------|------|-------------|
| `backups` | array | Objects: `name`, `fullPath`, `lastWriteTime`, `sizeBytes` |
| `backupCount` | number | (list mode) count of backup files |
| `exitCode` | number | **0** on success |
| `prunedFiles` | array of string | (after **`--prune --keep N --force`**) basenames removed |
| `keep` | number | requested keep count when pruning |
| `error` | string | when **`exitCode`** is **2** |

## `stats` payload (v2.9.0+)

| Field | Type | Description |
|--------|------|-------------|
| `entryCount` | number | Decrypted entries after optional time filter |
| `successCount` | number | Entries with exit code 0 |
| `nonZeroExitCount` | number | Entries with non-zero exit |
| `avgDurationMs` | number \| null | Average of `DurationMs` when present |
| `logFile` | string | Path to encrypted audit log |
| `categories` | object | Counts: `SUCCESS`, `NONZERO`, `ELEVATION_FAILED`, `OTHER` |
| `filterSince` | string \| null | `--since` argument if set (`YYYY-MM-DD`) |
| `filterLastDays` | number \| null | `--last-days` value if that flag was used (positive integer) |
| `exitCode` | number | Always **0** when JSON is emitted |

Time filtering uses each entry’s decrypted **`Timestamp`**; **`--since`** and **`--last-days`** are mutually exclusive. **`--last-days`** must be a positive integer (v2.9.1+ rejects zero, non-numeric values, or a missing value after the flag).

## `profile` payload (v2.9.0+)

| Field | Type | Description |
|--------|------|-------------|
| `profiles` | array | Objects: `path`, `filePresent`, `hasWindoBlock`, `isCurrentProfile` |
| `exitCode` | number | **0** when JSON is emitted |

`hasWindoBlock` is true when the file contains the WINDO profile block marker (`# >>> WINDO-BEGIN >>>`).
