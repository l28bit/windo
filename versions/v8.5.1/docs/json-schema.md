# WINDO V8.4 JSON output (schema 3.0)

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
| `schemaVersion` | string | **`"3.0"`** for WINDO **v3.0.0+** CLI JSON (v2.6.x installers emitted `"2.6"`). **V8.4** does not introduce a new schema version; the envelope shape is unchanged. |
| `windoVersion` | string | Installer profile version (e.g. `"8.4.0"`). This is the product semver, not the schema version. |
| `command` | string | Logical command name for the envelope (for example `account`, `completion`, `config`, `context`, `container`, `help`, `keybindings`, `launchpad`, `mesh`, `modules`, `net-scan`, `profile`, `rdp`, `roadmap`, `scan`, `source`, `syntax`, `trace`, `version`, `verify`, `wsl`, and other v6 built-in commands). |
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
  "windoVersion": "8.4.0",
  "command": "doctor",
  "generatedAt": "2026-05-08T18:00:00.0000000-05:00",
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
| `account` | 0, 2 | **v6.0.0+** **0** = account handoff operation queued/validated, **2** = invalid username or launch handoff failure |
| `help` | 0, 2 | **2** = topic not found (suggestions may be present) |
| `export` | 0, 2 | **v3.2.2+** CLI summary after zip write; **2** = archive failure or missing output |
| `backups` | 0, 2 | **2** = bad args, prune without `--force`, prune failure |
| `theme` | 0, 2 | **2** = invalid subcommand or prefs write failure |
| `container` | 0, 1, 2, runtimeExit | **v6.0.0+** **0** = runtime command prepared/executed, **1** = runtime launch/exec exception, **2** = invalid args/runtime/subcommand, or delegated runtime exit code |
| `completion` | 0, 2, 3 | **v3.4.0+ / v6.0.0+** status/mode/reset success, prefs write failure, or doctor/repair attention state |
| `output` | 0, 2 | **v4.0.1+** **0** = status / mode saved / reset, **2** = bad mode or prefs write failure |
| `venv` | 0, 2, 3 | **v4.0.1+** **0** = venv action success, **2** = bad args or action failure, **3** = status missing/no active venv |
| `pkg` | 0, 2 | **v4.0.1+** **0** = manager status or handoff ready, **2** = unsupported/missing manager or missing args |
| `scan` | 0, 2, 3 | **v4.1.0+** **0** = no findings, **2** = path/arg errors, **3** = findings present |
| `net-scan` | 0, 2, 3 | **v6.0.0+** **0** = status/resolve/arp/ping success with no unreachable hosts, **2** = bad args or CIDR format error, **3** = at least one host unreachable or probe error |
| `vault` | 0, 2 | **v4.1.0+** **0** = status/list/set/get/remove success, **2** = missing secret/bad args/write failure |
| `sshx` | 0, 2, tool exit | **v4.1.0+** status/config success, bad args/tool missing, or raw ssh/ssh-keygen exit |
| `crypto` | 0, 2, tool exit | **v4.1.0+** status/hash success, bad args/tool missing, or raw openssl/certutil exit |
| `motion` | 0, 2 | **v4.2.0+** status/pulse success, bad mode, or prefs write failure |
| `surface` | 0, 2, 3 | **v4.2.0+ / v5.2.0+** status/prime/pulse/doctor/repair/open/panel success, write/repair failure, panel unavailable, or readiness issues |
| `integrate` | 0, 2, 3 | **v5.4.0+** status/doctor/prime/repair/shortcuts/startup/shim/open success, write/open failure, or integration attention state |
| `control` | 0, 2, 3 | **v4.3.0+ / v4.4.0+** status/prime/actions/queue/run/execute-next/inspect/cancel/history/pulse/clear success, bad subcommand, unknown action, no queued request, or manifest write failure |
| `signal` | 0, 2, 3 | **v4.5.0+** status/timeline/last/export success, bad subcommand, or attention state |
| `center` | 0, 2, 3 | **v5.0.0+ / v5.3.0+** status/open/tray/panel/studio/actions/preview/run/queue/execute/history/signal success, bad subcommand/action, or attention/native surface state |
| `studio` | 0, 3 | **v5.3.0+** guided Power Studio launch success or native desktop unavailable |
| `edition` | 0, 2, 3 | **v5.1.0+** status/open/html/pulse success, bad subcommand, or inherited center attention state |
| `rdp` | 0, 2, 3 | **v6.0.0+** built-in command for status/firewall/config/troubleshoot handling |
| `wsl` | 0, 1, 2, 3 | **v6.0.0+** built-in command for status/check/launch/path/import/export |

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

## `net-scan` payload (v6.0.0+)

Envelope **`command`** is always **`net-scan`**. The shape depends on the subcommand.

### Common fields (all subcommands)

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `status`, `resolve`, `arp`, or `ping`. |
| `scannedAt` | string | ISO-8601 timestamp of the probe. |
| `exitCode` | number | **0**, **2**, or **3**. |

### `windo net-scan [status]`

| Field | Type | Description |
|--------|------|-------------|
| `adapters` | array | Active network adapter rows: `alias`, `ipv4`, `ipv6`, `gateway`, `dnsServers`, `macAddress`, `linkSpeed`. Addresses are strings; `dnsServers` is an array of strings. |

### `windo net-scan resolve <host...>`

| Field | Type | Description |
|--------|------|-------------|
| `hosts` | array | Rows: `host`, `addresses` (array of strings), `addressCount`, `reverseHostnames` (array of arrays), `identityTags` (array of `{ip,names,tags[]}`), `error` (when resolution failed). |
| `errorCount` | number | Count of hosts that could not be resolved. |

### `windo net-scan arp`

| Field | Type | Description |
|--------|------|-------------|
| `neighbors` | array | ARP/neighbor table rows: `ip`, `mac`, `state`, `interfaceAlias`, `hostnames`, `identityTags`. `mac` is the link-layer address. |
| `includeStale` | bool | Whether unreachable/incomplete/invalid entries were included. |
| `interface` | string \| null | Filter alias when `--interface` was supplied. |

### `windo net-scan ping <cidr|host...>`

| Field | Type | Description |
|--------|------|-------------|
| `targets` | array \| null | Explicit host list when individual hosts were supplied (not CIDR). |
| `cidr` | string \| null | CIDR block when a subnet was supplied. |
| `hostLimit` | number | Effective `--host-limit` cap applied to the probe. |
| `timeoutSeconds` | number | Per-host ICMP timeout. |
| `ports` | array of number | TCP ports probed on each reachable host (empty when `--ports` was omitted). |
| `hosts` | array | Probe result rows: `ip`, `reachable`, `rttMs` (number or null), `ports` (object: port → `open` bool), `hostnames`, `identityTags`. |
| `hostTags` | array | Present when `--host-tags` is used (values indicate enabled tagging source). |
| `reachableCount` | number | Hosts that responded to ICMP. |
| `unreachableCount` | number | Hosts that did not respond. |
| `errorCount` | number | Probe errors (e.g. access denied, socket error). |
| `errors` | array | Rows: `ip`, `error`. |

Example (`windo net-scan ping 10.10.10.0/24 --ports 22,443 --json`):

```json
{
  "schemaVersion": "3.0",
  "windoVersion": "6.0.0",
  "command": "net-scan",
  "generatedAt": "2026-05-08T18:00:00.0000000-05:00",
  "meta": {
    "psEdition": "Core",
    "psVersion": "7.5.5",
    "osVersion": "Microsoft Windows NT 10.0.26200.0"
  },
  "payload": {
    "subcommand": "ping",
    "scannedAt": "2026-05-08T18:00:00.0000000-05:00",
    "cidr": "10.10.10.0/24",
    "hostLimit": 254,
    "timeoutSeconds": 1,
    "ports": [22, 443],
    "hosts": [
      { "ip": "10.10.10.1",  "reachable": true,  "rttMs": 1, "ports": { "22": false, "443": true } },
      { "ip": "10.10.10.10", "reachable": true,  "rttMs": 3, "ports": { "22": true,  "443": true } },
      { "ip": "10.10.10.20", "reachable": false, "rttMs": null, "ports": {} }
    ],
    "reachableCount": 2,
    "unreachableCount": 1,
    "errorCount": 0,
    "errors": [],
    "exitCode": 3
  }
}
```

### `windo net-scan resolve <host...> --json`

```json
{
  "schemaVersion": "3.0",
  "windoVersion": "6.0.0",
  "command": "net-scan",
  "generatedAt": "2026-05-08T18:05:00.0000000-05:00",
  "meta": {
    "psEdition": "Core",
    "psVersion": "7.5.5",
    "osVersion": "Microsoft Windows NT 10.0.26200.0"
  },
  "payload": {
    "subcommand": "resolve",
    "scannedAt": "2026-05-08T18:05:00.0000000-05:00",
    "hosts": [
      { "host": "dc01", "addresses": ["10.10.10.10", "fe80::1"], "addressCount": 2, "reverseHostnames": [["dc01.windo.local"], ["dc01-v6.windo.local"]], "identityTags": [], "error": null },
      { "host": "printer01", "addresses": [], "addressCount": 0, "reverseHostnames": [], "identityTags": [], "error": "host not found" }
    ],
    "errorCount": 1,
    "exitCode": 2
  }
}
```

### `windo net-scan arp --json`

```json
{
  "schemaVersion": "3.0",
  "windoVersion": "6.0.0",
  "command": "net-scan",
  "generatedAt": "2026-05-08T18:06:00.0000000-05:00",
  "meta": {
    "psEdition": "Core",
    "psVersion": "7.5.5",
    "osVersion": "Microsoft Windows NT 10.0.26200.0"
  },
  "payload": {
    "subcommand": "arp",
    "scannedAt": "2026-05-08T18:06:00.0000000-05:00",
    "interface": "Wi-Fi",
    "includeStale": false,
    "neighbors": [
      { "ip": "10.10.10.1", "mac": "9A-BC-21-3C-01-22", "state": "Reachable", "interfaceAlias": "Wi-Fi", "hostnames": ["dc01.windo.local"], "identityTags": [] },
      { "ip": "10.10.10.20", "mac": "88-77-66-55-44-33", "state": "Stale", "interfaceAlias": "Wi-Fi", "hostnames": ["legacy-printer"], "identityTags": [] }
    ],
    "errorCount": 0,
    "errors": [],
    "exitCode": 0
  }
}
```

## `container` payload (v6.0.0+)

`windo container` always emits envelope `command` as `container`.

### Common fields

| Field | Type | Description |
|--------|------|-------------|
| `runtime` | string | `docker` or `podman` when resolved successfully. |
| `runtimeUsed` | string \| null | Runtime actually selected for execution (`docker` or `podman`); null when resolution not yet complete. |
| `subcommand` | string | `ps`, `images`, `status`, `logs`, `restart`, `start`, `stop`, `rmi`, `rm`, `pull`. |
| `command` | array | Arguments passed to the resolved runtime executable. |
| `idOrImage` | string \| null | Primary target argument for mutating subcommands (`logs`, `restart`, `start`, `stop`, `rmi`, `rm`, `pull`) when supplied. |
| `runtimeCommand` | array | **Dry-run only**; same as `command` in dry-run mode. |
| `commandLine` | string | **Dry-run only**; reconstructed full command shown to operators. |
| `dryRun` | bool | **Dry-run mode** marker, present and `true` when no execution occurs. |
| `output` | array | Runtime stdout/stderr rows when available. |
| `error` | string | Wrapper/runtime failure text when present. |
| `exitCode` | number | `0`, `1`, `2`, or wrapped runtime exit code. |

### `windo container ps --json`

```json
{
  "schemaVersion": "3.0",
  "windoVersion": "6.0.0",
  "command": "container",
  "generatedAt": "2026-05-08T18:10:00.0000000-05:00",
  "meta": {
    "psEdition": "Core",
    "psVersion": "7.5.5",
    "osVersion": "Microsoft Windows NT 10.0.26200.0"
  },
  "payload": {
    "runtime": "docker",
    "subcommand": "ps",
    "command": [ "ps" ],
    "output": [
      "CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS   PORTS   NAMES",
      "4bd9...        nginx     \"nginx\"   1h ago    Up 1h    80/tcp   web"
    ],
    "exitCode": 0
  }
}
```

### `windo container --dry-run pull <image> --json`

```json
{
  "schemaVersion": "3.0",
  "windoVersion": "6.0.0",
  "command": "container",
  "generatedAt": "2026-05-08T18:11:00.0000000-05:00",
  "meta": {
    "psEdition": "Core",
    "psVersion": "7.5.5",
    "osVersion": "Microsoft Windows NT 10.0.26200.0"
  },
  "payload": {
    "runtime": "podman",
    "subcommand": "pull",
    "command": [ "pull", "nginx:latest" ],
    "runtimeCommand": [ "pull", "nginx:latest" ],
    "commandLine": "podman pull nginx:latest",
    "dryRun": true,
    "exitCode": 0
  }
}
```

## `rdp` payload (v6.0.0+)

`windo rdp` always emits envelope `command` as `rdp`.

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `status`, `firewall`, `config`, or `troubleshoot`. |
| `scannedAt` | string | ISO timestamp for the request snapshot. |
| `exitCode` | number | **0**, **2**, or **3**. |

### `windo rdp status`

| Field | Type | Description |
|--------|------|-------------|
| `service` | object | Service posture from local discovery and registry snapshot. |
| `config` | object | Registry/config posture used for checks. |
| `firewall` | object | `count` and `rules` from active firewall query. |

### `windo rdp firewall`

| Field | Type | Description |
|--------|------|-------------|
| `action` | string | `status`, `enable`, or `disable`. |
| `requestedPorts` | array | Ports requested by `--ports`. |
| `rules` | array | Candidate firewall rows. |
| `updates` | array | Planned changes when in mutating mode. |
| `dryRun` | bool | `true` in `--dry-run` mode. |
| `estimatedEffect` | string | Human-readable preview text. |
| `next` | string | Optional upgrade/elevation hint when blocked by policy. |

### `windo rdp config`

| Field | Type | Description |
|--------|------|-------------|
| `requested` | object | `enable`, `nla`, `securityLayer`, `restart`. |
| `dryRun` | bool | `true` when applying in preview mode. |
| `result` | object | Change result with `success` / `changes` / `error`. |

### `windo rdp troubleshoot`

| Field | Type | Description |
|--------|------|-------------|
| `host` | string | Target host/IP for end-to-end checks. |
| `timeoutSeconds` | number | Probe timeout. |
| `portChecks` | array | Per-port probe rows: `port`, `reachable`, `error`. |
| `config` | object | Snapshot used for the troubleshooting pass. |
| `firewall` | object | Rule and match summary used by the pass. |
| `credential` | object \| null | Optional credential probe preview result. |

## `wsl` payload (v6.0.0+)

`windo wsl` always emits envelope `command` as `wsl`.

| Field | Type | Description |
|--------|------|-------------|
| `command` | string | Subcommand label: `status`, `list`, `check install`, `check distro`, `check import`, `check export`, `version`, `install`, `convert`, `inspect`, `exec`, `launch`, `path`, `import`, or `export`. |
| `exitCode` | number | **0**, **1**, **2**, **3**; may include raw `wsl` command status in some paths. |

### `windo wsl status|list|ls`

| Field | Type | Description |
|--------|------|-------------|
| `wslAvailable` | bool | `wsl.exe` discoverability check. |
| `wslStatus` | array | Raw output from `wsl --status`. |
| `wslExitCode` | number | Raw exit code for `wsl --status`. |
| `distros` | array | Parsed distribution rows (`name`, `state`, `version`, `default`). |
| `default` | string \| null | Default distribution name. |

### `windo wsl check*`

| Field | Type | Description |
|--------|------|-------------|
| `command` | string | `check install`, `check distro`, `check import`, `check export`. |
| `distro` \| `distribution` | string \| object | Target distro string or resolved distro row. |
| `exists` | bool | Presence flag for targeted object. |
| `safeToApply` | bool | Preflight safety signal. |
| `applyRequired` | bool | `true` when the operation is gated by `--apply`. |
| `error` | string | Validation/preflight error text. |
| `errors` | array | Validation details for complex failures. |

### `windo wsl version`

| Field | Type | Description |
|--------|------|-------------|
| `output` | array | Raw output from `wsl --version`. |

### `windo wsl install|convert|exec`

| Field | Type | Description |
|--------|------|-------------|
| `distribution` | string | Target WSL distro name (for install/convert/exec). |
| `command` | array \| string | In `exec`, forwarded command arguments (array) or raw tokenized command text in other command paths. |
| `to` | string | Target WSL version (`1` or `2`) for `convert`. |
| `apply` | bool | `true` only when `--apply` was provided. |
| `dryRun` | bool | `true` for dry-run preview mode. |
| `commandLine` | string | Reconstructed command line for preview. |

### `windo wsl inspect`

| Field | Type | Description |
|--------|------|-------------|
| `distribution` | object | Target distro snapshot with `name`, `state`, `default`, `version`, `kernel`, and `ip`. |
| `osRelease` | array | Raw `/etc/os-release` lines from WSL execution. |
| `unameExitCode` | number \| null | Exit code for `uname -a` probe. |
| `osReleaseExitCode` | number \| null | Exit code for `/etc/os-release` probe. |
| `ipExitCode` | number \| null | Exit code for `hostname -I` probe. |

### `windo wsl launch`

| Field | Type | Description |
|--------|------|-------------|
| `distro` | string | Target distribution. |
| `args` | array | Arguments in dry-run mode. |
| `command` | array | Executed command tokens in run mode. |
| `commandLine` | string | Reconstructed command line preview. |
| `dryRun` | bool | `true` for preview execution. |
| `processId` | number | Process ID for interactive `launch`. |
| `output` | array | Command output rows when execution returns output. |

### `windo wsl path`

| Field | Type | Description |
|--------|------|-------------|
| `direction` | string | `to-wsl` or `to-win`. |
| `path` | string | Source path. |
| `distro` | string \| null | Optional distro selector. |
| `converted` | string \| null | Converted path when known. |
| `dryRun` | bool | `true` for preview. |
| `commandLine` | string | Planned command line for conversion preview. |

### `windo wsl import|export`

| Field | Type | Description |
|--------|------|-------------|
| `distribution` | string | Distribution name argument. |
| `tar` | string | Tar input path for import checks. |
| `out` | string | Export target path. |
| `path` | string | Import target path. |
| `version` | number | Selected WSL version (`1` or `2`). |
| `apply` | bool | Execution gate flag. |
| `dryRun` | bool | Preview marker. |
| `commandLine` | string | Reconstructed command in dry-run paths. |
| `output` | array | Output rows from run mode. |

## `network-ops` payloads (optional module)

The optional `extras/samples/network-ops` module registers these commands via `wincmd`.
They return native PowerShell objects by default, and use the WINDO `_emit_json` command envelope when `-AsJson` is requested for telemetry-focused paths.

### `netops-rdp-vnc` payload

`netops-rdp-vnc` uses envelope command `rdp` when `-AsJson` is active.

#### `netops-rdp-vnc status`

| Field | Type | Description |
|-------|------|-------------|
| `subcommand` | string | Always `status` for status queries. |
| `dryRun` | bool | `true` when check path was requested without applying, for example when confirmation is declined. |
| `scannedAt` | string | ISO timestamp for the request snapshot. |
| `service` | object | `name`, `status`, `startup`, and `exists` fields. |
| `config` | object | Registry/config posture values used in evaluation. |
| `firewall` | object | `count` and firewall rule rows. |
| `exitCode` | number | `0` success, `2` when service state is unknown. |

#### `netops-rdp-vnc firewall`

| Field | Type | Description |
|-------|------|-------------|
| `subcommand` | string | Always `firewall` for firewall operations. |
| `action` | string | `status`, `enable`, or `disable`. |
| `requestedPorts` | array | Placeholder for port-specific payload shaping. |
| `dryRun` | bool | `true` when requested action is staged without confirmation. |
| `rules` | array | Rule rows collected from matching firewall query. |
| `runCommand` | array | Commands prepared for mutating operations. |
| `command-executed` | array | Commands executed for mutating operations. |
| `updates` | array | Planned or applied rule updates. |
| `error` | string | Human-readable failure reason when execution fails. |
| `exitCode` | number | `0` when updates are successfully applied, `2` on pre/post failure, `3` when confirmation was skipped. |

### `netops-wsl` payload

`netops-wsl` uses envelope command `wsl` when `-AsJson` is active.

#### `netops-wsl status`

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | Always `status` for mode status output. |
| `wslAvailable` | bool | `wsl.exe` discoverability check. |
| `wslStatus` | array | Raw output from `wsl --status`. |
| `wslExitCode` | number | Raw `wsl --status` exit code. |
| `distros` | array | Parsed distro rows. |
| `default` | string \| null | Default distro name. |
| `exitCode` | number | `0` success, non-zero when preconditions fail. |

#### `netops-wsl check install`

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | Always `check install` for install preflight. |
| `wslAvailable` | bool | `wsl.exe` discoverability check. |
| `wslStatus` | array | Raw output from `wsl --status`. |
| `distros` | array | Parsed distro rows. |
| `default` | string \| null | Default distro name if available. |
| `notes` | array | Preflight notes. |
| `exitCode` | number | `0` on pass, `2` on preflight failure. |

### `netops-resolve`

Rows return:
`Host`, `IpAddress`, `AddressFamily`, and `ReverseDns` when available.

```json
[
  {
    "Host": "windo.local",
    "IpAddress": "10.10.10.10",
    "AddressFamily": "IPv4",
    "ReverseDns": ["windo.local.internal"]
  }
]
```

### `netops-netcat-send`

Rows/objects are native `netops-netcat-send` output objects. Not wrapped by the WINDO `command` envelope.

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | `netops-netcat-send` |
| `protocol` | string | `tcp` or `udp` |
| `mode` | string | `check`, `apply`, `interactive-apply`, `one-shot-apply`, `interactive-check`, or `one-shot-check` |
| `remoteHost` | string | Target host |
| `remotePort` | number | Target port |
| `timeoutSeconds` | number | Timeout in seconds |
| `maxPayloadBytes` | number | Maximum payload size per send line |
| `maxInteractiveLines` | number | Interactive input line cap |
| `allowRemote` | bool | Whether off-loopback was explicitly enabled |
| `allowlist` | array | Allowed destination values when apply mode runs |
| `allowlistMatched` | string \| null | Matching allowlist entry |
| `safety` | object | Validation metadata (`requestedMode`, `allowed`, `reason`, `resolvedAddresses`, optional `confirmationSkipped`) |
| `events` | array | Per-message objects (`sequence`, `bytes`, `text`, `preview`, etc.) |
| `messages` | number | Total message count |
| `bytes` | number | Total bytes sent |
| `timedOut` | bool | Timeout occurred before any complete exchange |
| `exitCode` | number | `0` success, `1` timeout, `2` failure, `3` canceled by confirmation |

### `netops-netcat-recv`

Rows/objects are native `netops-netcat-recv` output objects. Not wrapped by WINDO envelope.

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | `netops-netcat-recv` |
| `protocol` | string | `tcp` or `udp` |
| `mode` | string | `check`, `apply`, `interactive-apply`, `one-shot-apply`, `interactive-check`, or `one-shot-check` |
| `bindHost` | string | Bound listen host |
| `localPort` | number | Bound listen port |
| `timeoutSeconds` | number | Timeout in seconds |
| `maxPayloadBytes` | number | Maximum payload chunk size |
| `maxMessages` | number | Maximum message count |
| `allowRemote` | bool | Whether off-loopback bind was explicitly enabled |
| `allowlist` | array | Allowed bind targets when apply mode runs |
| `allowlistMatched` | string \| null | Matching allowlist entry |
| `safety` | object | Validation metadata (`requestedMode`, `allowed`, `reason`) |
| `events` | array | Received message preview rows |
| `messages` | number | Total messages captured |
| `bytes` | number | Total bytes received |
| `timedOut` | bool | Timeout occurred before any capture |
| `exitCode` | number | `0` success, `1` timeout, `2` failure, `3` canceled by confirmation |

### `netops-subnet-scan`

Rows return:
`IpAddress` and `Reachable`.

```json
[
  { "IpAddress": "10.10.10.1", "Reachable": true },
  { "IpAddress": "10.10.10.2", "Reachable": false }
]
```

### `netops-arp-map`

Rows return:
`InterfaceAlias`, `IPAddress`, `LinkLayerAddress`, and `State`.

```json
[
  {
    "InterfaceAlias": "Ethernet",
    "IPAddress": "10.10.10.1",
    "LinkLayerAddress": "A4-5D-36-9F-12-44",
    "State": "Reachable"
  }
]
```

### `netops-rdp-vnc`

Returns one or both objects:
`Protocol`, posture fields (`AllowRegistry`, `Service`, `ServiceStartup`, `FirewallEnabled`, `ListeningPorts`).

```json
[
  {
    "Protocol": "RDP",
    "AllowRegistry": true,
    "Service": "Running",
    "ServiceStartup": "Automatic",
    "FirewallEnabled": true
  },
  {
    "Protocol": "VNC",
    "ListeningPorts": [5901],
    "FirewallEnabled": false
  }
]
```

When used with `-AsJson`, `netops-rdp-vnc` emits `rdp` command payloads:

### `netops-rdp-vnc` `-Subcommand status`

| Field | Type | Description |
|-------|------|-------------|
| `subcommand` | string | `status`. |
| `dryRun` | bool | `true` when output is generated without applying changes. |
| `service` | object | Service posture snapshot from local RDP service checks. |
| `config` | object | Registry/posture snapshot used by status inspection. |
| `firewall` | object | Firewall summary including rule count and candidate rule rows. |
| `scannedAt` | string | ISO timestamp for the request snapshot. |
| `exitCode` | number | `0` success, `2` when service state is unknown. |

### `netops-rdp-vnc` `-Subcommand firewall`

| Field | Type | Description |
|-------|------|-------------|
| `subcommand` | string | `firewall`. |
| `action` | string | `status`, `enable`, or `disable`. |
| `requestedPorts` | array | Firewall rule input context for the command. |
| `dryRun` | bool | `true` when operation was staged without mutation due to confirmation workflow. |
| `rules` | array | Rule rows collected for the firewall command. |
| `runCommand` | array | Command plan used to apply the firewall action. |
| `command-executed` | array | Commands prepared for execution (when applicable). |
| `updates` | array | Planned state updates for each matching rule. |
| `error` | string | Error details for command-level failures. |
| `exitCode` | number | `0` when updates are applied, `2` when no targets or execution failures exist, `3` when confirmation was skipped. |

### `netops-wsl`

`status` returns rows with `Name`, `IsDefault`, `State`, `Version`, `Eth0Ip`; `ip` mode returns `Distro`, `IpAddress`, and `ProbeCommand`.

When used with `-AsJson`, `netops-wsl` emits `wsl` command payloads.

```json
[
  {
    "Name": "Ubuntu-24.04",
    "IsDefault": true,
    "State": "Running",
    "Version": 2,
    "Eth0Ip": "172.20.10.15"
  }
]
```

#### `netops-wsl` status payload

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | `status`. |
| `wslAvailable` | bool | `wsl.exe` discoverability at runtime. |
| `distros` | array | Parsed distro rows from local scan (`$distros.distros`). |
| `exitCode` | number | `0` for executable status path, otherwise non-zero. |

#### `netops-wsl` preflight payload

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | `check install`. |
| `wslAvailable` | bool | `wsl.exe` discoverability at runtime. |
| `distros` | array | Parsed distro rows from local scan (`$distros.distros`). |
| `notes` | array | Preflight notes for availability and command checks. |
| `exitCode` | number | `0` when preflight passes, `2` on missing runtime or failed check. |

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

## `motion` payload (v4.2.0+)

| Field | Type | Description |
|--------|------|-------------|
| `motion` | object | Effective motion policy: `mode` (`auto`, `on`, `quiet`, `off`), `source` (`env`, `prefs`, `default`), `enabled`, `interactive`, `environmentValue`, `preferenceValue`, `prefsFile`, and `description`. |
| `saved` | bool | Present when a mode was written to **`windo_prefs.json`**. |
| `reset` | bool | Present when saved mode was removed. |
| `pulseRendered` | bool | Present for `pulse`/`demo`; true when terminal motion was actually rendered. |
| `exitCode` | number | **0** on success, **2** for invalid mode or prefs write failure. |

`enabled` is computed by combining interactivity, source precedence (`env` > `prefs` > `default`), and CI constraints (`WINDO_NO_SPINNER`).  
For `mode=auto`, motion is enabled only when interactive and CI constraints allow spinner rendering.

## `surface` payload (v4.2.0+)

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `status`, `prime`, `pulse`, `doctor`, `repair`, `open`, or `panel`. |
| `surface` | object | Native-surface state: `surfaceRoot`, `manifestPath`, `manifestExists`, `nativeSurface`, `motion`, `profileIssues`, `ready`, and `nextCommands`. |
| `doctor` | object | Present for `doctor`; readiness checks, surface state, control state, and `readinessLevel`. |
| `repair` | object | Present for `repair`; result rows for surface manifest, control manifest, and prompt guard repair. |
| `tray` | object | Present for `open`; tray launch result from the native surface path. |
| `panel` | object | Present for `panel`; Windows Forms panel launch result, script path, and icon path. |
| `primed` | bool | Present for `prime`; true after writing the local surface manifest. |
| `pulseRendered` | bool | Present for `pulse`; true when terminal motion was rendered. |
| `exitCode` | number | **0** when ready/primed, **2** for prime write failure, **3** when profile prompt issues need attention. |

## `control` payload (v4.3.0+)

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `status`, `prime`, `actions`, `preview`, `queue`, `run`, `execute-next`, `next`, `execute`, `inspect`, `cancel`, `history`, `pulse`, or `clear`. |
| `control` | object | Control-plane state: `root`, `manifestPath`, `queueRoot`, `queuedCount`, `requestCount`, `resultCount`, `actions`, `queued`, `lastResult`, `surface`, `motion`, and `nextCommands`. |
| `actions` | array | Present for `actions`; curated action rows with `id`, `title`, `command`, `group`, `execution`, and `description`. |
| `history` | array | Present for `history`; recent control request rows with request state and optional result. |
| `request` | object | Present for `inspect`; request/result/path envelope for a control request. |
| `preview` | object | Present for `preview`; read-only action route, command, and safety posture. |
| `result` | object | Present for `queue`, `run`, `execute-next`, `execute`, or `cancel`; includes action/request status and paths where applicable. |
| `primed` | bool | Present for `prime`; true after writing the local control-plane manifest. |
| `pulseRendered` | bool | Present for `pulse`; true when terminal motion was rendered. |
| `removed` | number | Present for `clear`; count of queued request JSON files removed. |
| `exitCode` | number | **0** on success, **2** for unknown action, missing id, or write failure, **3** when `execute-next` has no queued request. |

### Control request file (v4.4.0+)

| Field | Type | Description |
|--------|------|-------------|
| `schemaVersion` | string | `"1.0"`. |
| `id` | string | Request id, e.g. `wcp-...`. |
| `actionId` | string | Curated action id from `windo control actions`. |
| `command` | string | Curated WINDO command text. |
| `status` | string | `queued`, `running`, `complete`, `failed`, or `cancelled`. |
| `createdAt`, `updatedAt`, `startedAt`, `completedAt`, `cancelledAt` | string | ISO timestamps when applicable. |
| `executorScriptPath` | string | Visible-shell executor script path when running. |
| `resultPath` | string | Adjacent result JSON path when available. |

### Control result file (v4.4.0+)

| Field | Type | Description |
|--------|------|-------------|
| `schemaVersion` | string | `"1.0"`. |
| `id` | string | Matching request id. |
| `actionId` | string | Curated action id. |
| `command` | string | Curated command text. |
| `status` | string | `complete` or `failed`. |
| `exitCode` | number | Command exit status as resolved by WINDO. |
| `startedAt`, `completedAt` | string | ISO timestamps. |
| `output` | array | Captured output strings from the visible executor. |

## `signal` payload (v4.5.0+)

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `status`, `timeline`, `last`, `export`, or `open`. |
| `signal` | object | Signal Deck state: timeline, control state, last signal, trust, integrity, audit, surface doctor, recommendations, and `exitCode`. |
| `last` | object | Present for `last`; latest signal timeline row. |
| `htmlPath` | string | Present for `export`/`open`; local HTML Signal Deck path. |
| `exitCode` | number | **0** ready, **2** bad subcommand/write failure, **3** attention state. |

## `integrate` payload (v5.4.0+)

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `status`, `doctor`, `prime`, `repair`, `shortcuts`, `startup`, `shim`, or `open`. |
| `integration` | object | Present for `status`; current-user integration state including shortcut rows, startup script, shim, user PATH posture, native surface state, next commands, and `exitCode`. |
| `doctor` | object | Present for `doctor`; readiness checks for shell COM, shortcut files, startup wiring, shim, and user PATH. |
| `result` | object | Present for repair/open actions; includes per-artifact repair rows or opened folder path. |
| `exitCode` | number | **0** ready/success, **2** bad args/write/open failure, **3** integration attention state. |

Integration repair is current-user scoped. Expected artifacts include Start Menu/Desktop `.lnk` files, a startup tray `.lnk`, `.pwsh_secure\windo_start_tray.ps1`, `.pwsh_secure\bin\windo.cmd`, and an optional current-user PATH update for new shells.

## `center` payload (v5.0.0+)

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `status`, `open`, `tray`, `panel`, `studio`, `actions`, `preview`, `run`, `queue`, `execute-next`, `next`, `execute`, `history`, or `signal`. |
| `center` | object | Command Center state: status, surface, control, Signal Deck, and command entrypoints. |
| `tray` | object | Present for `open`/`tray`; native tray launch result. |
| `panel` | object | Present for `panel`; native Surface Panel launch result. |
| `studio` | object | Present for `studio`; native Power Studio launch result. |
| `actions` | array | Present for `actions`; curated command-center action rows. |
| `preview` | object | Present for `preview`; read-only action route and command posture. |
| `result` | object | Present for `run`/`queue`/`execute-next`/`execute`; control action or request result. |
| `history` | array | Present for `history`; recent control-plane request rows. |
| `signal` | object | Present for `signal`; Signal Deck state. |
| `exitCode` | number | **0** ready/success, **2** bad args/action, **3** attention or tray unavailable. |

## `studio` payload (v5.3.0+)

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `open`. |
| `center` | object | Command Center state at launch time. |
| `studio` | object | Power Studio launch result: `ok`, `path`, `iconPath`, or `error`. |
| `exitCode` | number | **0** started, **3** native desktop APIs unavailable. |

## `edition` payload (v5.1.0+)

| Field | Type | Description |
|--------|------|-------------|
| `subcommand` | string | `status`, `open`, `html`, or `pulse`. |
| `edition` | object | WINDO command-surface state: version, branch, brand assets, center/control/signal state, motion policy, and entry commands. |
| `htmlPath` | string | Present for `open`/`html`; local animated edition console path. |
| `pulseRendered` | bool | Present for `pulse`; true when terminal motion was rendered. |
| `exitCode` | number | **0** ready/success, **2** bad args/write failure, **3** inherited center attention state. |

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
| `motionPolicy` | object | **v4.2.0+** Effective terminal motion policy when present in newer profiles. |
| `extrasIndexUrl` | string | **v3.2.1+** Resolved extras catalog URL (**`WINDO_EXTRAS_INDEX_URL`** or canonical **`Exodus`**-sourced `extras/index.json`) |
| `exitCode` | number | **0** |

The **`settings`** array is the machine-readable source of truth for env-driven behavior; **`extrasIndexUrl`** duplicates the resolved URL for quick automation without parsing **`effectiveNote`** on the **`WINDO_EXTRAS_INDEX_URL`** row.

## `completion` payload (v3.4.0+ / v6.0.0+)

| Field | Type | Description |
|--------|------|-------------|
| `completionPolicy` | object | Effective completion mode and source (`native-first`, `hybrid`, `windo`, or `off`). |
| `doctor` | object | Present for `doctor`; reports `TabExpansion2`, completer registration, profile completer text, early-return risk, sample completions, readiness, and next commands. |
| `repair` | object | Present for `repair`; includes before/after doctor states and optional error text. |
| `saved` | bool | Present when a mode was written to **`windo_prefs.json`**. |
| `reset` | bool | Present when saved mode was removed. |
| `exitCode` | number | **0** on success, **2** for invalid mode or prefs write failure, **3** for doctor/repair attention state. |

### Completion/help semantics (v6)

`completion` command arguments support `status`, `doctor`, `repair`, `native-first`, `hybrid`, `windo`, and `off` as canonical modes, with compatibility aliases (`native`, `stealth`, `builtin`, `builtins`) normalized to existing v6 modes.  
The same command-topic registry used for completions powers `windo help <topic>` suggestion behavior, enabling parity between tab-completion and help query normalization.

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

Command center from `windo launchpad --json`; `--tray` starts a native Windows Forms tray process and does not depend on a browser.

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

`help` topic matching is case-insensitive and alias-aware.  
The CLI `help`/`completion` index path is the same source of truth for topic names, so automation can rely on consistent `topic` normalization and `suggestions` output.

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
| `subcommand` | string | **v4.2.0+** `status`, `doctor`, or `repair`. |
| `profiles` | array | Objects: `path`, `filePresent`, `hasWindoBlock`, `isCurrentProfile`, and **v4.2.0+** `promptIssues`. |
| `promptIssues` | array | **v4.2.0+** Flattened profile prompt findings such as `oh-my-posh-unguarded-init` and `oh-my-posh-missing-cache`. |
| `results` | array | **v4.2.0+** Repair results when `windo profile repair --json` is used: `ok`, `changed`, `path`, `backupPath`, and `error`. |
| `changedCount` | number | **v4.2.0+** Count of changed profiles during repair. |
| `exitCode` | number | **0** when OK, **2** for repair failure, **3** when prompt issues are found. |

`hasWindoBlock` is true when the file contains the WINDO profile block marker (`# >>> WINDO-BEGIN >>>`).
