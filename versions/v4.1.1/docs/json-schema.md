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
| `command` | string | Logical command name for the envelope (e.g. `doctor`, `integrity`, `config`, `session`, `dashboard`, `preflight`, `launchpad`, `keybindings`, `completion`, `roadmap`, `source`, `syntax`, `mesh`, `repair`, `modules`, `extras`, `recipes`, `ai`, `backups`, `version`, `verify`, `log`, `stats`, `history`, `last`, `context`, `trace`, `profile`; bundle-related commands when exporting, etc.) |
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
| `trust` | 0, 2, 3, 4 | **Release runway** **0** = trusted, **2** = bad args, **3** = attention, **4** = repair required |
| `source` | 0, 2, 3 | **v3.6.4+** **0** = published source and local snapshot align, **2** = bad args, **3** = source/checksum unavailable or snapshot mismatch |
| `syntax` | 0, 2, 3 | **Release runway** **0** = matches found or doctor passes, **2** = bad args, **3** = no shortcut matched or doctor needs a narrower intent |
| `mesh` | 0, 2, 3, 4 | **v3.6.6+** **0** = read-only platform inventory produced, **2** = bad args; **v3.6.7+** `--html` / `--open` write a local cockpit artifact; **v3.6.8+** doctor uses **3** = attention and **4** = repair |
| `explain` | 0, 2 | **v3.6.1+** **0** = execution plan produced, **2** = missing target command |
| `stats` | 0 | Success; invalid filters exit **before** JSON is printed (host exit **2**, no envelope) |
| `profile` | 0 | Listing only |
| `config` | 0 | Listing only (see **`config`** payload; v3.2.1+ adds **`extrasIndexUrl`**) |
| `session` | 0 | Dashboard summary (v3.2.0+; v3.2.1+ adds audit tail fields) |
| `dashboard` | 0, 3, 4 | **v3.2.8+** **0** = healthy, **3** = warning, **4** = critical health status |
| `preflight` | 0, 3, 4 | **v3.3.0+** **0** = ready, **3** = warnings, **4** = critical readiness issue |
| `launchpad` | 0, 3, 4 | **v3.3.0+** command center status; `tray.started` indicates native tray launch result |
| `keybindings` | 0, 2 | **0** = status / doctor / mutating success; **2** = bad args or PSReadLine missing for doctor |
| `modules` | 0, 2, 3 | **2** = bad args / missing paths / prefs write failure; **3** = **`verify`** or **`doctor`** found issues |
| `recipes` | 0, 2 | **2** = unknown recipe or bad usage |
| `extras` | 0, 2 | **2** = elevated fetch, index/network/hash errors, missing id |
| `dev` | 0, 2 | **2** = bad name, directory exists, or wrong subcommand |
| `prompt` | 0, 2 | **2** = **`--export`** path write failure |
| `ai` | 0, 2, 3 | **v3.2.5+** **`status`** = **0**; **`doctor`** = **0** or **3** (policy concerns); **2** = bad subcommand |
| `repair` | 0, 2 | **v3.2.7+** **`keybindings` safe-reset** + hints; **2** = bad subcommand or prefs write failure |
| `help` | 0, 2 | **2** = topic not found (suggestions may be present) |
| `export` | 0, 2 | **v3.2.2+** CLI summary after zip write; **2** = archive failure or missing output |
| `backups` | 0, 2 | **2** = bad args, prune without `--force`, prune failure |
| `theme` | 0, 2 | **2** = invalid subcommand or prefs write failure |
| `output` | 0, 2 | **v4.0.1+** **0** = status / mode saved / reset, **2** = bad mode or prefs write failure |
| `venv` | 0, 2, 3 | **v4.0.1+** **0** = venv action success, **2** = bad args or action failure, **3** = status missing/no active venv |
| `pkg` | 0, 2 | **v4.0.1+** **0** = manager status or handoff ready, **2** = unsupported/missing manager or missing args |
| `scan` | 0, 2, 3 | **v4.1.0+** **0** = no findings, **2** = path/arg errors, **3** = findings present |
| `vault` | 0, 2 | **v4.1.0+** **0** = status/list/set/get/remove success, **2** = missing secret/bad args/write failure |
| `sshx` | 0, 2, tool exit | **v4.1.0+** status/config success, bad args/tool missing, or raw ssh/ssh-keygen exit |
| `crypto` | 0, 2, tool exit | **v4.1.0+** status/hash success, bad args/tool missing, or raw openssl/certutil exit |

## `scan` payload (v4.1.0+)

| Field | Type | Description |
|--------|------|-------------|
| `scannedAt` | string | ISO timestamp. |
| `recurse` | bool | Whether directory recursion was enabled. |
| `maxTextScanMb` | number | Maximum text file size scanned for patterns. |
| `hash` | bool | Whether SHA256 was calculated. |
| `fileCount` | number | Files scanned. |
| `findingFileCount` | number | Files with one or more findings. |
| `errorCount` | number | Path/read errors. |
| `files` | array | Rows: `path`, `sizeBytes`, `sha256`, `findingCount`, `findings`. |
| `files[].findings` | array | Rows: `id`, `severity`, `detail`. |
| `errors` | array | Rows: `path`, `error`. |
| `exitCode` | number | **0**, **2**, or **3**. |

## `vault` payload (v4.1.0+)

| Field | Type | Description |
|--------|------|-------------|
| `vaultPath` | string | `.pwsh_secure\windo_vault.json`. |
| `protectedBy` | string | `DPAPI CurrentUser`. |
| `count` | number | Number of stored entries for status/list. |
| `names` | array | Secret names only; values are not listed. |
| `action` | string | `set` or `remove` for mutating commands. |
| `name` | string | Secret name for set/get/remove. |
| `value` | string | Present only for explicit `get`; contains the decrypted secret. |
| `warning` | string | Present with `get` JSON because secret value is included. |
| `removed` | bool | Remove result. |
| `error` | string | Bad args, missing secret, or write failure. |
| `exitCode` | number | **0** or **2**. |

## `sshx` payload (v4.1.0+)

| Field | Type | Description |
|--------|------|-------------|
| `sshDir` | string | User `.ssh` directory. |
| `tools` | array | Tool rows: `name`, `available`, `path`. |
| `keys` | array | Key file rows from `.ssh`. |
| `configPath` | string | `.ssh\config`. |
| `action` | string | `keygen` or `config` when applicable. |
| `keyPath` | string | Generated private key path. |
| `publicKeyPath` | string | Generated public key path. |
| `exitCode` | number | WINDO or underlying tool exit. |

## `crypto` payload (v4.1.0+)

| Field | Type | Description |
|--------|------|-------------|
| `tools` | array | Tool rows for `openssl` and `certutil`. |
| `action` | string | `hash` when JSON hash output is requested. |
| `path` | string | Resolved file path for hash. |
| `sha256` | string | SHA256 hash. |
| `error` | string | Bad args or missing tool/file. |
| `exitCode` | number | WINDO or underlying tool exit. |

## `output` payload (v4.0.1+)

| Field | Type | Description |
|--------|------|-------------|
| `outputPolicy` | object | Effective output mode: `mode` (`compact`, `quiet`, `legacy`), `source`, `environmentValue`, `preferenceValue`, `prefsFile`, and `description`. |
| `saved` | bool | Present when a mode was written to **`windo_prefs.json`**. |
| `reset` | bool | Present when the saved mode was removed. |
| `exitCode` | number | **0** on success, **2** for invalid mode or prefs write failure. |

## `venv` payload (v4.0.1+)

| Field | Type | Description |
|--------|------|-------------|
| `action` | string | Present for mutating actions: `create`, `activate`, `deactivate`, or `remove`. |
| `path` | string | Virtual environment path when applicable. |
| `exists` | bool | Status mode: whether `Scripts\Activate.ps1` exists. |
| `active` | bool | Status mode: whether `VIRTUAL_ENV` is set. |
| `activePath` | string \| null | Active venv path from `VIRTUAL_ENV` when present. |
| `activateScript` | string | Expected `Activate.ps1` path. |
| `python` | string \| null | Venv Python executable path when present, or selected Python command during create. |
| `ok` | bool | Create mode: whether Python created a usable venv. |
| `removed` | bool | Remove mode success marker. |
| `error` | string | Present for bad args or failed action. |
| `exitCode` | number | **0**, **2**, or **3**. |

## `pkg` payload (v4.0.1+)

| Field | Type | Description |
|--------|------|-------------|
| `managers` | array | Status rows: `id`, `available`, and `path` for `winget`, `choco`, and `scoop`. |
| `manager` | string | Requested manager on error payloads. |
| `error` | string | Unsupported manager, missing manager, or missing package-manager args. |
| `exitCode` | number | **0** on status success, **2** for bad usage. Handoff executions use the normal elevated-command result path. |

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
| `completionPolicy` | object | Effective tab-completion policy: `mode`, `source`, `environmentValue`, `preferenceValue`, `prefsFile`, `description`. |
| `outputPolicy` | object | **v4.0.1+** Effective compact/quiet/legacy result-output policy. |
| `extrasIndexUrl` | string | **v3.2.1+** Resolved extras catalog URL (**`WINDO_EXTRAS_INDEX_URL`** or default **`Genesis`** `extras/index.json`) |
| `exitCode` | number | **0** |

The **`settings`** array is the machine-readable source of truth for env-driven behavior; **`extrasIndexUrl`** duplicates the resolved URL for quick automation without parsing **`effectiveNote`** on the **`WINDO_EXTRAS_INDEX_URL`** row.

## `completion` payload (v3.4.0 runway)

| Field | Type | Description |
|--------|------|-------------|
| `completionPolicy` | object | Effective completion mode and source (`native-first`, `hybrid`, `windo`, or `off`). |
| `saved` | bool | Present when a mode was written to **`windo_prefs.json`**. |
| `reset` | bool | Present when saved mode was removed. |
| `exitCode` | number | **0** on success, **2** for invalid mode or prefs write failure. |

## `roadmap` payload (release runway)

| Field | Type | Description |
|--------|------|-------------|
| `currentVersion` | string | Installed WINDO version. |
| `targetMajor` | string | Current public target marker. `reserved` means future major-package details are intentionally brief. |
| `releaseTrain` | array | Planned sub-version rows: `version`, `codename`, `theme`, `focus`, `status`, `operatorValue`. |
| `principles` | array | Release-train guardrails. |
| `docs` | string | Roadmap doc path. |
| `exitCode` | number | **0** |

## `trust` payload (release runway)

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Installed WINDO version. |
| `trustLevel` | string | `TRUSTED`, `ATTENTION`, or `REPAIR`. |
| `score` | number | Local trust score from 0 to 100. |
| `online` | bool | Whether published checksum validation was requested. |
| `isElevated` | bool | Whether the current shell is elevated; online checksum fetches are blocked when true. |
| `checks` | array | Check rows with `id`, `label`, `ok`, `severity`, `detail`, and `fixCommand`. |
| `tasks` | object | Main/update scheduled task presence and names. |
| `integrity` | object | Same runner/updater manifest state as `windo integrity`. |
| `audit` | object | Same audit-chain verification state as `windo verify`. |
| `profile` | object | Current profile WINDO block status. |
| `completionPolicy` | object | Effective tab-completion policy. |
| `installerSnapshot` | object | Local `Documents\windo\windo_install.ps1` path, presence, and line-ending-normalized published-text SHA-256 when available. |
| `publishedChecksum` | object | `requested`, `status`, `url`, `source`, `sha256`, `matchesSnapshot`, and `error`. `source` is `github-api`, `raw-fallback`, `none`, or null. |
| `recommendations` | array | Remediation guidance strings. |
| `exitCode` | number | **0** trusted, **3** attention, **4** repair required. |

## `source` payload (v3.6.4 runway)

Read-only source-of-truth check from `windo source`.

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Installed WINDO version. |
| `installedVersion` | string | Same installed profile version for automation convenience. |
| `publishedInstaller` | object | `status`, `source`, `url`, `version`, and `error` for the published installer fetch. `source` is `github-api`, `raw-fallback`, or `none`. |
| `publishedChecksum` | object | `status`, `source`, `url`, `sha256`, and `error` for the published checksum lookup. |
| `localSnapshot` | object | Local `Documents\windo\windo_install.ps1` `path`, `present`, `version`, `sha256`, and `matchesPublishedChecksum`. |
| `recommendation` | string | Human-readable next action. |
| `exitCode` | number | **0** when source/checksum are available and the local snapshot is aligned; **3** when unavailable or mismatched. |

## `syntax` payload (release runway)

| Field | Type | Description |
|--------|------|-------------|
| `query` | string \| null | Optional intent query after `windo syntax`. |
| `count` | number | Number of matching shortcut rows. |
| `shortcuts` | array | Shortcut rows: `id`, `aliases`, `category`, `summary`, `command`, `preview`, `risk`, and `notes`. |
| `doctor` | object \| null | Present for `windo syntax doctor [query]` or `windo syntax --doctor [query]`; includes `status`, `message`, `bestMatch`, `matches`, `recommendations`, and `exitCode`. |
| `exitCode` | number | **0** when matches exist or doctor finds a safe single path, **3** when no shortcut matched or the doctor reports ambiguity. |

## `mesh` payload (v3.6.6+)

Read-only Operator Mesh preview from `windo mesh --json`. v3.6.7 adds `--html`, `--open`, and `--output` for a local branded cockpit artifact. v3.6.8 adds `windo mesh doctor --json`, which returns a readiness payload instead of the inventory payload. v4.0.0 adds `windo mesh workbench --json`, which returns workflow lanes, platform pieces, and recommended flows.

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Installed WINDO version. |
| `status` | string | Current preview state. |
| `counts` | object | `modules`, `enabledModules`, `recipes`, and `installedExtras`. |
| `modules` | object | Module root, enabled module ids, and discovered module rows. |
| `recipes` | array | Built-in recipe ids with descriptions and preview/run commands. |
| `extras` | object | Extras index URL, install root, and locally installed extras. |
| `launchpad` | object | Terminal/html/tray commands plus tray support and detected brand assets. |
| `nativeSurface` | object | Local Windows-native surface capability map: `status`, `windowsDesktop`, `windowsFormsAvailable`, `traySupported`, tray/brand paths, shell paths, and native-surface commands. |
| `export` | object | Export command, export root, and latest zip when present. |
| `nextCommands` | array | Suggested read-only or review-first commands to continue platform setup. |
| `htmlPath` | string \| null | Set when `--html`, `--open`, or `--output` writes local cockpit HTML. |
| `exitCode` | number | **0** on success. |

### `windo mesh doctor --json` (v3.6.8+)

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Installed WINDO version. |
| `generatedAt` | string | ISO-8601 timestamp for the local doctor run. |
| `readinessLevel` | string | `READY`, `ATTENTION`, or `REPAIR`. |
| `score` | number | 0-100 readiness score after failed-check weighting. |
| `checks` | array | Check rows with `id`, `label`, `ok`, `detail`, `fixCommand`, and `severity`. |
| `inventory` | object | Embedded `windo mesh --json` inventory used as the doctor source. |
| `recommendations` | array | Suggested next commands or setup actions. |
| `exitCode` | number | **0** = ready, **3** = attention, **4** = repair required. |

### `windo mesh workbench --json` (v4.0.0+)

| Field | Type | Description |
|--------|------|-------------|
| `mode` | string | `operator-mesh-workbench`. |
| `readinessLevel` | string | Mirrored doctor readiness level. |
| `score` | number | Mirrored doctor readiness score. |
| `counts` | object | Modules, enabled modules, recipes, and installed extras. |
| `platform` | array | Platform pieces with `name`, `count`, `ready`, `command`, and `path`. |
| `lanes` | array | Workflow lanes with `id`, `title`, `summary`, `cardCount`, and recipe/command `cards`. |
| `recommendedFlow` | array | Ordered next-step commands with short rationale. |
| `nativeSurface` | object | Embedded native-surface capability map used by the workbench and tray handoff. |
| `doctor` | object | Embedded `windo mesh doctor --json` payload. |
| `inventory` | object | Embedded `windo mesh --json` inventory payload. |
| `htmlPath` | string \| null | Set when `--html`, `--open`, or `--output` writes local workbench HTML. |
| `exitCode` | number | **0** on success. |

## `explain` payload (v3.6.1 runway)

Read-only execution plan from `windo explain <command...>`; use `windo explain -- <external command...>` when the target command has flags that should remain part of the explained command.

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Installed WINDO version. |
| `target` | array | Target command arguments after `explain`; a leading literal `windo` is ignored. |
| `commandLine` | string | Shell-safe-ish preview of the target command line. |
| `route` | string | Planned route, such as `external elevated command`, `published installer update`, `trust console`, `recipe elevation`, or `native tray launchpad`. |
| `category` | string | Planning category (`Lifecycle`, `Security`, `Workflow`, `Elevation`, etc.). |
| `privilegeBoundary` | string | Human-readable boundary description. |
| `network` | bool | Whether the plan expects network access. |
| `writesLocalFiles` | bool | Whether the plan expects local file writes. |
| `createsAuditEntry` | bool | Whether the plan expects the encrypted audit log to receive an entry. |
| `checksumValidation` | string | Checksum/provenance posture for the planned route. |
| `artifacts` | array | Local paths or artifact classes the route may touch. |
| `preflight` | array | Suggested read-only checks before running. |
| `nextCommands` | array | Exact commands to run next if the plan is acceptable. |
| `warnings` | array | Planner warnings, such as unknown recipe ids. |
| `exitCode` | number | **0** when a target plan exists; **2** when no target command was provided. |

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

## `dashboard` payload (v3.2.8+)

Operator health summary from `windo dashboard --json`; `--html` / `--open` produce a local visual dashboard file.

| Field | Type | Description |
|--------|------|-------------|
| `generatedAt` | string | ISO timestamp |
| `windoVersion` | string | Embedded profile / CLI version |
| `host` | string | Local host name |
| `status` | string | `OK` \| `WARN` \| `CRITICAL` |
| `healthScore` | number | 0-100 score derived from task presence, integrity, audit-chain verification, and elevation failures |
| `issues` | array | Human-readable issue strings |
| `tasks` | object | `main`, `selfUpdate` booleans |
| `integrity` | object | `overallLevel`, `runnerLevel`, `updaterLevel` |
| `verify` | object | `verifyOk`, `physicalLines`, optional `error`, optional `failureLine` |
| `audit` | object | `totalEntries`, `categories` (`SUCCESS`, `NONZERO`, `ELEVATION_FAILED`, `OTHER`), `avgDurationMs`, `recent` |
| `paths` | object | `secureDir`, `logFile`, `manifestFile` |
| `htmlPath` | string \| null | Set when `--html`, `--open`, or `-o`/`--output` writes local HTML |
| `exitCode` | number | **0**, **3**, or **4** matching status |

## `preflight` payload (v3.3.0+)

Read-only readiness scan from `windo preflight --json`.

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Embedded profile / CLI version |
| `generatedAt` | string | ISO timestamp |
| `ok` | bool | True when all checks pass |
| `failedCount` | number | Count of checks where `ok=false` |
| `criticalCount` | number | Count of failed checks with `severity=critical` |
| `checks` | array | Rows: `id`, `label`, `ok`, `severity`, `detail`, `fixCommand` |
| `exitCode` | number | **0**, **3**, or **4** |

## `launchpad` payload (v3.3.0+)

Special Edition command center from `windo launchpad --json`; `--tray` starts a native Windows Forms tray process and does not depend on a browser.

| Field | Type | Description |
|--------|------|-------------|
| `windoVersion` | string | Embedded profile / CLI version |
| `generatedAt` | string | ISO timestamp |
| `status` | string | `READY` \| `ATTENTION` \| `REPAIR` |
| `score` | number | 0-100 readiness score |
| `checks` | array | Same row shape as `preflight` |
| `actions` | array | Copy/run suggestions: `title`, `command`, `note` |
| `recipes` | array | Built-in recipe ids, descriptions, and command templates |
| `modules` | array | Discovered module rows |
| `paths` | object | `secureDir`, `snapshotDir`, `profile`, `brandLogo` |
| `htmlPath` | string \| null | Set when `--html`, `--open`, or `--output` writes local HTML |
| `tray` | object | `requested`, `started`, `scriptPath`, `iconPath`, `error`; populated by `--tray` |
| `exitCode` | number | **0**, **3**, or **4** |

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

v3.6.9 expands the bundled read-only recipe catalog substantially. The JSON shape is unchanged; callers should treat recipe ids as data returned by `windo recipes --json` instead of hard-coding a small fixed list.

| Field | Type | Description |
|--------|------|-------------|
| `recipes` | array | ( **`list`** ) Objects: `name`, `description`, `command` |
| `windoVersion` | string | Bundled profile version |
| `subcommand` | string | `show`, `preview`, or `run` when applicable |
| `preview` | object | ( **`show`**, **`preview`**, or recipe **`--dry-run`** ) Recipe preview object |
| `preview.name` | string | Canonical recipe id |
| `preview.description` | string | Recipe description |
| `preview.command` | string | Elevated command line template |
| `preview.elevatedCommand` | string | Same exact command submitted to the audited elevation path when run |
| `preview.runCommand` | string | `windo recipes run <name>` |
| `preview.previewCommand` | string | `windo recipes preview <name>` |
| `preview.dryRunCommand` | string | `windo recipes run <name> --dry-run` |
| `preview.risk` | string | Human-readable risk class |
| `dryRun` | bool | Present and **true** for recipe dry-run payloads |
| `error` | string | Unknown recipe / bad usage (**`exitCode`** **2**) |
| `exitCode` | number | **0** on success |

**Note:** **`windo recipes preview <name>`** and recipe **`--dry-run`** are read-only and return before scheduled tasks, request/result files, or audit entries are touched. Errors from **`windo run --recipe`** / **`windo recipes run`** may still use **`command`: `recipes`** in the envelope when JSON is emitted for a bad recipe name.

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

## `repair` payload (v3.2.7+)

| Field | Type | Description |
|--------|------|-------------|
| `actions` | array of string | e.g. **`keybindings-safe-reset`** |
| `scope` | string | **`all`** or **`keybindings`** (same behavior today) |
| `keybindingsPolicy` | object | Effective policy after safe-reset (same shape as **`keybindings`**) |
| `profilePath` | string | Current **`$PROFILE`** |
| `prefsFile` | string | **`windo_prefs.json`** path |
| `hints` | array of string | Next steps (reload profile, **`install-latest`**) |
| `error` | string | When **`exitCode`** **2** |
| `exitCode` | number | **0** on success |

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
