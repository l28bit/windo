# WINDO JSON output (schema 3.0)

Commands that support `--json` or `-Json` emit a single **envelope** so scripts can rely on stable top-level fields.

## Which version is WINDO—the product or `schemaVersion`?

**The release you have installed** is the **product (semver) version**: the same value as **`windo version`**, the installer **`$WindoVersion`** (e.g. **`3.0.0`**, **`2.9.1`**), and the JSON field **`windoVersion`**. That is the number to use when talking about “WINDO 2.9” vs “WINDO 3.0.”

**`schemaVersion`** (**`"2.6"`** or **`"3.0"`**) is **only** the name of the **CLI JSON envelope contract**. It stayed **`2.6`** for every product release from **v2.6.0** through **v2.9.x** because the envelope shape did not get a breaking change until **v3.0.0** (when **`meta`** was added). So you are **not** “on WINDO 2.6” in the product sense just because JSON says `schemaVersion: "2.6"`—you might be on **WINDO 2.9.1** with **`schemaVersion` `2.6`**.

**Summary:** **`windoVersion`** = actual WINDO release; **`schemaVersion`** = JSON wrapper version for automation authors.

## JSON envelope theme (v3.1.0+)

If you prefer the **pre-v3 JSON “look”** (no top-level **`meta`**, and **`schemaVersion`: `"2.6"`**) but want to stay on the **latest WINDO** for runner fixes and security, use presentation-only controls—**never** an old installer:

| Mechanism | Purpose |
|-----------|---------|
| **`windo theme classic`** | Writes **`jsonEnvelope`: `classic`** to **`%USERPROFILE%\.pwsh_secure\windo_prefs.json`**. Effective **`--json`** output uses a **2.6-shaped** envelope (no **`meta`**). |
| **`windo theme modern`** | **`meta`** + **`schemaVersion` `3.0`** (when the embedded profile supports it). |
| **`windo theme auto`** | Follow the embedded profile’s default (**`$SchemaVersion`** in the installed function). |
| **`WINDO_JSON_ENVELOPE`** | Environment override: **`classic`** \| **`modern`** \| **`auto`**. Takes precedence over **`windo_prefs.json`**. |

**Unchanged by theme:** elevated runner, scheduled tasks, DPAPI audit log, manifest integrity, request validation, and installer checksum behavior. Theme affects **CLI JSON formatting only**.

## Envelope

| Field | Type | Description |
|--------|------|-------------|
| `schemaVersion` | string | **`"3.0"`** for WINDO **v3.0.0+** CLI JSON (v2.6.x installers emitted `"2.6"`) |
| `windoVersion` | string | Installer profile version (e.g. `"3.0.0"`) |
| `command` | string | Logical command name for the envelope (e.g. `doctor`, `integrity`, `config`, `session`, `keybindings`, `modules`, `extras`, `recipes`, `ai`, `backups`, `version`, `verify`, `log`, `stats`, `history`, `last`, `context`, `trace`, `profile`; bundle-related commands when exporting, etc.) |
| `generatedAt` | string | ISO-8601 timestamp |
| `meta` | object | Host context (see below). Present when the effective theme is **modern** (or **auto** on v3.0.0+ profiles). Omitted in **classic** theme. |
| `payload` | object | Command-specific data |

### `meta` (when present)

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
| `config` | 0 | Listing only (see **`config`** payload; v3.2.1+ adds **`extrasIndexUrl`**) |
| `session` | 0 | Dashboard summary (v3.2.0+; v3.2.1+ adds audit tail fields) |
| `keybindings` | 0, 2 | **0** = status / doctor / mutating success; **2** = bad args or PSReadLine missing for doctor |
| `modules` | 0, 2, 3 | **2** = bad args / missing paths / prefs write failure; **3** = **`verify`** or **`doctor`** found issues |
| `recipes` | 0, 2 | **2** = unknown recipe or bad usage |
| `extras` | 0, 2 | **2** = elevated fetch, index/network/hash errors, missing id |
| `dev` | 0, 2 | **2** = bad name, directory exists, or wrong subcommand |
| `prompt` | 0, 2 | **2** = **`--export`** path write failure |
| `ai` | 0, 2, 3 | **v3.2.5+** **`status`** = **0**; **`doctor`** = **0** or **3** (policy concerns); **2** = bad subcommand |
| `help` | 0, 2 | **2** = topic not found (suggestions may be present) |
| `export` | 0, 2 | **v3.2.2+** CLI summary after zip write; **2** = archive failure or missing output |
| `backups` | 0, 2 | **2** = bad args, prune without `--force`, prune failure |
| `theme` | 0, 2 | **2** = invalid subcommand or prefs write failure |

## `theme` payload (v3.1.0+)

| Field | Type | Description |
|--------|------|-------------|
| `jsonEnvelopeFile` | string \| null | Value from **`windo_prefs.json`** (`classic` / `modern` / `auto`) |
| `environmentOverride` | string \| null | **`WINDO_JSON_ENVELOPE`** when set |
| `effective` | object | `schemaVersion` (**`2.6`** or **`3.0`**) and **`includeMeta`** (bool) |
| `embeddedProfileSchema` | string | Embedded **`$SchemaVersion`** (show mode) |
| `saved` | bool | (set mode) **true** when preset was written |
| `jsonEnvelope` | string | (set mode) value saved |
| `prefsFile` | string | Path to **`windo_prefs.json`** |
| `exitCode` | number | **0** on success |

## `config` payload (v3.0.0+)

| Field | Type | Description |
|--------|------|-------------|
| `secureDir` | string | WINDO secure directory (`.pwsh_secure`) |
| `settings` | array | Rows: `name`, `environmentValue` (string or null), `effectiveNote` (human-readable effective behavior). Includes **`WINDO_*`**, **`SUDO_*`**, **`CI`**, and (v3.2.0+) **`WINDO_EXTRAS_INDEX_URL`** when relevant. |
| `keybindingPolicy` | object | Effective PSReadLine policy (same shape as **`windo keybindings status --json`** `policy`: `enabled`, `chord`, `chordSource`, `fallbackChord`, `autoDetectAlt`, etc.) |
| `extrasIndexUrl` | string | **v3.2.1+** Resolved extras catalog URL (**`WINDO_EXTRAS_INDEX_URL`** or default **`Genisis`** `extras/index.json`) |
| `exitCode` | number | **0** |

The **`settings`** array is the machine-readable source of truth for env-driven behavior; **`extrasIndexUrl`** duplicates the resolved URL for quick automation without parsing **`effectiveNote`** on the **`WINDO_EXTRAS_INDEX_URL`** row.

## `session` payload (v3.2.0+ / v3.2.1+)

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Embedded profile / CLI version |
| `secureDir` | string | `.pwsh_secure` path |
| `mainTaskPresent` | bool | Main elevation task registered |
| `updateTaskPresent` | bool | Self-update task registered |
| `integrityOverall` | string | `OK` \| `DRIFT` \| `TAMPERED` \| `UNKNOWN` |
| `integrityRunner` | string | Per-component level for runner |
| `integrityUpdater` | string | Per-component level for self-update script |
| `lastCommand` | string \| null | Last stored interactive line for **`windo !!`** (not necessarily the last audit entry) |
| `lastRequestId` | string \| null | From **`windo_last_meta.json`** when present |
| `lastStoredAt` | string \| null | ISO timestamp from last meta |
| `lastAudit` | object \| null | **v3.2.1+** Last decrypted audit log entry (same shape as log entries): `timestamp`, `command`, `exitCode`, `elevation`, `requestId` |
| `recentAudit` | array | **v3.2.1+** Up to **5** compact objects from the tail of the decrypted log: `timestamp`, `command`, `exitCode`, `elevation`, `requestId` |
| `exitCode` | number | **0** |

## `keybindings` payload (v3.x)

The envelope **`command`** is always **`keybindings`**. Shape depends on the subcommand.

### `windo keybindings status --json`

| Field | Type | Description |
|--------|------|-------------|
| `profilePath` | string | Current **`$PROFILE`** |
| `prefsFile` | string | **`windo_prefs.json`** path |
| `policy` | object | Resolved keybinding policy |
| `bindings` | array | Rows: `chord`, `registered`, `matchesPolicy` |
| `effectiveChord` | string \| null | First registered chord among candidates, if any |
| `psReadLineAvailable` | bool | Whether **`Get-PSReadLineKeyHandler`** was available |
| `exitCode` | number | **0** |

### `windo keybindings doctor --json` (v3.2.1+)

Advisory only: inspects PSReadLine handlers for the effective prefix chord (when policy is enabled) and for **`Shift+Enter`** / **`Alt+Enter`** run chords. Heuristics flag script text that does not look like WINDO’s embedded bindings.

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | **`doctor`** |
| `policy` | object | Same as `status` |
| `chordChecks` | array | Rows: `chord`, `role` (`prefix` \| `run`), `handlerPresent`, `looksLikeWindoBinding`, `scriptPreview` (truncated), `advisory` (string or null) |
| `anyAdvisory` | bool | **true** if any row has a non-empty **`advisory`** |
| `exitCode` | number | **0** on success; **2** if PSReadLine cannot be loaded (then `error` may appear instead of these fields) |

### Mutating subcommands (`set`, `disable`, `enable`, `reset`, `safe-reset`)

Payloads include `action` (string), `policy`, `profilePath`, `prefsFile`, and optional `chord` (for `set`). **`exitCode`** is **0** on success.

## `modules` payload (v3.2.0+)

Envelope **`command`** is **`modules`**. Subcommands share error shapes: **`error`** (string), **`exitCode`** (**2**), optional context (**`sub`**, **`moduleId`**, **`path`**).

### `windo modules list --json`

| Field | Type | Description |
|--------|------|-------------|
| `modulesRoot` | string | `%USERPROFILE%\Documents\windo\modules` |
| `modules` | array | Discovered folders: `id` (directory name), `path`, `manifestName`, `version`, `entry`, `requiresWindoVersion`, `enabled` |
| `enabled` | array of string | Enabled module ids from prefs |
| `exitCode` | number | **0** |

### `windo modules enable|disable --json`

| Field | Type | Description |
|--------|------|-------------|
| `action` | string | **`enable`** or **`disable`** |
| `moduleId` | string | Folder id |
| `enabled` | array of string | Full enabled list after change |
| `exitCode` | number | **0** |

### `windo modules verify --json`

| Field | Type | Description |
|--------|------|-------------|
| `modulesRoot` | string | Modules root path |
| `verify` | array | Per enabled id: `id`, `ok`, `detail` |
| `allOk` | bool | **false** if any enabled module fails checks |
| `exitCode` | number | **0** if **`allOk`**; **3** otherwise |

### `windo modules doctor --json`

| Field | Type | Description |
|--------|------|-------------|
| `doctor` | bool | **true** |
| `modulesRoot` | string | Expected root path |
| `modulesRootExists` | bool | **false** when root missing (**`exitCode`** **2**) |
| `discovered` | array | Same rows as **list** `modules` |
| `enabled` | array of string | Enabled ids |
| `issues` | array of string | Human-readable problems |
| `exitCode` | number | **0** if no issues; **3** if **`issues`** non-empty; **2** if root missing |

## `recipes` payload (v3.2.0+)

| Field | Type | Description |
|--------|------|-------------|
| `recipes` | array | ( **`list`** ) Objects: `name`, `description`, `command` |
| `windoVersion` | string | Bundled profile version |
| `name` | string | ( **`show`** ) Canonical recipe id |
| `description` | string | ( **`show`** ) |
| `command` | string | ( **`show`** ) Elevated command line template |
| `error` | string | Unknown recipe / bad usage (**`exitCode`** **2**) |
| `exitCode` | number | **0** on success |

**Note:** Errors from **`windo run --recipe`** / **`windo recipes run`** may still use **`command`: `recipes`** in the envelope when JSON is emitted for a bad recipe name.

## `extras` payload (v3.2.0+)

### `windo extras search --json`

| Field | Type | Description |
|--------|------|-------------|
| `query` | string | Filter string (may be empty for full catalog) |
| `items` | array | Index entries (at minimum `id`, `description`; may include `maintainer`, `sourceUrl`, `sha256`) |
| `indexSchema` | string | From catalog **`schemaVersion`** when present |
| `exitCode` | number | **0** |

### `windo extras fetch <id> --json`

| Field | Type | Description |
|--------|------|-------------|
| `id` | string | Catalog id |
| `path` | string | Downloaded file path |
| `sha256` | string | Actual file hash (uppercase hex from `Get-FileHash`) |
| `error` | string | Failure reason (**`exitCode`** **2**): elevated session, missing **`sourceUrl`**, SHA mismatch, network, etc. |
| `expected` / `actual` | string | (optional) On SHA mismatch |
| `exitCode` | number | **0** on success |

## `dev` payload (v3.2.0+)

| Field | Type | Description |
|--------|------|-------------|
| `action` | string | **`init-module`** on success |
| `moduleId` | string | Folder name |
| `path` | string | Module directory |
| `readme` | string | Path to generated **`README.md`** |
| `error` | string | When **`exitCode`** **2** |
| `exitCode` | number | **0** on success |

## `prompt` payload (v3.2.0+)

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Profile version |
| `environmentHints` | array of string | Env vars WINDO documents for themes (**`WINDO_LAST_REQUEST_ID`**, **`WINDO_VERSION`**) |
| `ohMyPoshSegmentExample` | object | Sample Oh My Posh segment (template uses **`{{ .Env.* }}`**) |
| `exportedTo` | string | Present when **`--export <path>`** succeeds |
| `error` | string | Export/write failure (**`exitCode`** **2**) |
| `exitCode` | number | **0** on success |

## `ai` payload (v3.2.5+; Ollama fields v3.2.6+)

Read-only **AI / local env hygiene** (vendor API and **Ollama** env **names** only; **values are never emitted**). Elevated-session and Machine-scope warnings apply to **cloud API key names** only; Ollama advisories are separate.

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | **`status`** or **`doctor`** |
| `elevated` | bool | **true** if the current process is running as Administrator |
| `processSetNames` | array of string | Names set in **Process** scope |
| `userSetNames` | array of string | Names set in **User** scope |
| `machineSetNames` | array of string | Names set in **Machine** scope |
| `ollamaSetNames` | array of string | **v3.2.6+** Subset: Ollama-related names set in any scope |
| `ollamaAdvisory` | string \| null | **v3.2.6+** Informational or risk hint derived from **`OLLAMA_HOST`** (never contains secrets) |
| `processEnvFlags` | object | Map name → **bool** (set in process) |
| `userEnvFlags` | object | Map name → **bool** (user scope) |
| `machineEnvFlags` | object | Map name → **bool** (machine scope) |
| `issues` | array of string | Non-empty when **`doctor`** detects policy concerns |
| `recommendations` | array of string | Present on **`doctor`** (fixed guidance text) |
| `docHint` | string | **`docs/ai-bridge.md`** |
| `error` | string | Bad subcommand (**`exitCode`** **2**) |
| `exitCode` | number | **`status`**: **0**; **`doctor`**: **0** or **3** |

## `help` payload (v3.1.2+)

| Field | Type | Description |
|--------|------|-------------|
| `topic` | string \| null | Normalized topic when provided; **null** for full index |
| `available` | array | (index mode) Topic rows: `Name`, `Category`, `Aliases`, `Summary`, `Syntax`, `Description`, `Notes` |
| `usage` | string | (index mode) Short usage line |
| `query` | string | Topic query string |
| `found` | bool | **false** when topic unknown (**`exitCode`** **2**) |
| `suggestions` | array | (not found) Up to **3** topic objects: `Name`, `Category`, `Summary` |
| `command` | object | (found) Selected topic: `Name`, `Aliases`, `Category`, `Summary`, `Description`, `Syntax`, `Notes`, `Examples` |
| `exitCode` | number | **0** when found or index; **2** when not found |

## `export` payload (v3.2.2+)

**`windo export`** always writes a **zip** on disk. **`--json`** (global flag) adds a **CLI envelope** after a successful bundle so automation can capture path and size without parsing human output. The zip itself still contains **`doctor.json`**, **`integrity.json`**, and **`audit_excerpt.json`** — each file uses the usual envelope internally (**`command`** may be **`doctor`**, **`integrity`**, or **`export`** for the audit slice).

| Field | Type | Description |
|--------|------|-------------|
| `zipPath` | string | Absolute path to the created **`.zip`** |
| `sizeBytes` | number | File size in bytes |
| `redacted` | bool | **`true`** if **`--redact`** was used |
| `auditExcerptLimit` | number | **`-n`** value (default **30**) — max decrypted entries packed |
| `auditTotalEntries` | number | Total decrypted audit rows scanned |
| `auditIncludedInExcerpt` | number | Entries included in **`audit_excerpt.json`** (last **N**) |
| `error` | string | When **`exitCode`** **2** (archive failure, missing zip) |
| `exitCode` | number | **0** on success |

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
