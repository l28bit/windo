<p align="center">
  <img src="brand/winDO.png" alt="WINDO logo" width="520">
</p>


WINDO is a PowerShell-first elevation helper for Windows. It gives administrators a **deliberate, auditable** way to request elevation **before** a command runs—instead of improvising after the fact.

---

## Philosophy

Experienced operators treat commands as intent. Elevation should not be accidental. WINDO keeps the workflow explicit:

**intent → choose elevation → execute with authority**

The default GitHub branch for raw URLs is **`Exodus`** unless overridden by `WINDO_TRACKING_BRANCH`.

---

## What's new in WINDO V6

- **V6 command surface and branding** — refreshed installer identity (`WINDO 6.0.0 V6`) and aligned README guidance for concise operator workflows.
- **Network posture in one command** — `windo net-scan` now covers `status`, `resolve`, `arp`, and `ping` with clear local-only behavior and bounded probing defaults.
- **Container handoff** — `windo container` now provides a validated docker/podman control surface with `--runtime` explicitness and safe defaults.
- **NetOps companion module** — `extras/network-ops` adds `netops-*` local helpers for subnet scan, ARP map, RDP/VNC posture checks, and WSL access helpers.
- **Safety defaults documented** — `net-scan` defaults keep scans bounded (`--host-limit 254`, `--timeout 1`) and do not transmit probe data off the host unless user commands do.

Full list: [`CHANGELOG.md`](CHANGELOG.md).

---

## What WINDO does

<p align="center">
  <img src="brand/assets/logos/transparent-github-avatar-panel.png" alt="WINDO avatar panel" width="280">
</p>

- Run `windo <command…>` to send work through a **scheduled task** configured with **RunLevel Highest**.
- Keep a **DPAPI-encrypted** log under `%USERPROFILE%\.pwsh_secure\windo_history.enc` with **SHA256** per entry and a **hash chain** you can verify.
- Ship **runner** and **self-update** scripts whose hashes are recorded in **`windo_manifest.json`**; `windo integrity` detects tamper or drift.

WINDO does **not** bypass Windows security boundaries; it uses a controlled elevation path suitable for administrators who understand UAC and task-based elevation.

**Optional shell companion layer** (modules, recipes, prompt bridge, curated extras—**v3.2.0+**): see [`docs/framework-wave.md`](docs/framework-wave.md) for how these features map to the shipped plan and trust model. For **AI/agent CLIs**, API-key discipline, and **local Ollama**, see [`docs/ai-bridge.md`](docs/ai-bridge.md).

---

## Install / Update

**Recommended (GitHub):** downloads [`bootstrap.ps1`](https://raw.githubusercontent.com/l28bit/windo/Exodus/bootstrap.ps1), saves `windo_install.ps1` to a **temp file**, verifies its checksum when published on the default `Exodus` branch (or overridden via `WINDO_TRACKING_BRANCH`), then starts it from the temp file. The **full installer is not** piped through `Invoke-Expression`. The temp file is removed afterward.

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/Exodus/bootstrap.ps1)
```

Use a **standard (non-elevated)** session for bootstrap handoff. If you need strict install verification in automated `install-latest`/`upgrade` flows, pair `WINDO_STRICT_INSTALLER_VERIFICATION=1` with `windo install-latest --force` or `WINDO_INSTALL_NONINTERACTIVE=1`.

**Upgrade from any installed v2.x / v3.x:** with WINDO loaded in your profile, run **`windo install-latest`** from a **normal (non-elevated)** window. The installer is **not** downloaded while Administrator (avoids high-privilege fetch). After checksum verification you get a **prompt** before the installer runs; in interactive sessions WINDO then requests **UAC elevation** so scheduled tasks and secure-dir ACL work can complete. Use **`windo install-latest --force`** or **`WINDO_INSTALL_NONINTERACTIVE=1`** in CI/automation.

```powershell
windo install-latest
```

(`windo upgrade` is the same command.)

After answering the installer confirmation prompt, WINDO performs a one-shot elevated handoff attempt (UAC) to complete runner/task registration and secure-dir updates.

**Bootstrap** (`iex (irm …/bootstrap.ps1)`): same rule—**do not run from an elevated shell**; the script exits with instructions. After download it is prompted before launch (or set **`WINDO_BOOTSTRAP_FORCE_INSTALL=1`** / **`WINDO_INSTALL_NONINTERACTIVE=1`** / **`CI`** for unattended).

## Troubleshooting install/update and verification behavior

### Prompt behavior

- `windo install-latest` and bootstrap:
  - run in a normal shell by default,
  - prompt before launch when interactive,
  - skip confirmation in non-interactive mode (`--non-interactive` / `CI` / `WINDO_INSTALL_NONINTERACTIVE` / `WINDO_BOOTSTRAP_FORCE_INSTALL`).
  - source contract for prompts and checksum checks comes from the canonical `Exodus` branch artifacts.
  - `windo self-update` follows the same interactive contract and branch/source checks as install flows.
  - prompts before launching installer repair when required in interactive sessions,
  - skips the repair prompt in non-interactive mode and returns a repair recommendation instead.

### Legacy or unexpected prompts

If you see an old/foreign prompt (for example `Input content`) while running install/update, treat it as a host or wrapper artifact (often `SUDO_PROMPT`), not as a different WINDO install flow.

- Check `SUDO_PROMPT`: `Get-Item Env:SUDO_PROMPT` and clear it if set.
- Rerun from a clean, non-elevated PowerShell session.
- In automation, use `windo install-latest --force` or `WINDO_INSTALL_NONINTERACTIVE=1` instead of manually answering legacy prompts.
- `windo self-update`:
  - starts the `WindoSelfUpdate` task,
  - prompts for installer repair when task state is missing or blocked,
  - skips the repair prompt in non-interactive mode and returns a repair recommendation.
- `windo self-update --dry-run` prints planned repair/task start only and does not execute.

### Hash and strict-mode behavior

- Default behavior is compatibility mode: checksum validation runs when checksums are available and continues on most drift paths after warnings.
- Set `WINDO_STRICT_INSTALLER_VERIFICATION=1` to require strict installer checks instead of compatibility-path warnings. In strict mode, checksum, source, and branch mismatches (including checksum-source failures) are treated as hard failures instead of warnings.
- `WINDO_SKIP_INSTALLER_SHA256=1` disables installer checksum checks in both bootstrap and upgrade/install flows.

### Known limitations

- Compatibility paths are accepted as warnings in non-strict mode:
  - GitHub blob SHA1 match to object hash,
  - snapshot checksum match for the same version,
  - checksum-source fetch or parsing failures that still have a valid fallback path,
  - release metadata/branch drift.
- In strict mode, those compatibility paths fail the install path.
- Bootstrap can fail early in strict mode when the published checksum source is unavailable or unparseable.

Or use the bootstrap one-liner above, or run `.\windo_install.ps1` from a clone. There is no version gate: the installer replaces the WINDO profile block and refreshes secure-dir artifacts.

**Remove WINDO completely:** run **`windo uninstall`** (or **`windo remove`**) from a normal shell. WINDO prefers the bundled local **`%USERPROFILE%\.pwsh_secure\windo_uninstall.ps1`** and starts it elevated with UAC; if the local copy is missing it falls back to the published raw uninstaller from the configured raw branch (default `Exodus`). After your profile is loaded you can also run **`windo-uninstall`** (alias: **`windoremove`**) directly. Optional **`-KeepSnapshots`** / **`--keep-snapshots`** keeps `%USERPROFILE%\Documents\windo\`. The uninstaller removes WINDO marker blocks from the known **current-user** PowerShell profiles for **pwsh** and **Windows PowerShell**.

**Offline / clone:** run the installer from disk:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\windo_install.ps1
```

Then reload your profile:

```powershell
. $PROFILE
```

Verify:

```powershell
windo doctor
windo version
windo integrity
```

The canonical install snippet is also kept in `docs/releases/README_INSTALL_UPDATE_SECTION.md` for copy/paste consistency across docs.

For a concise terminal workflow that covers install → upgrade → self-update → repair → history with sample output, see [`docs/terminal-demo-workflow.md`](docs/terminal-demo-workflow.md).

---

## Commands

<p align="center">
  <img src="brand/Enterprise/assets/svg/windo-brand-mark-contained-dark.svg" alt="WINDO brand mark" width="96">
</p>

| Command | Purpose |
|--------|---------|
| `windo help` / `windo /?` / `windo --help` | Full command help and topic docs (`windo help <command>` for details). |
| `windo <command…>` | Elevate and run the command via the task bridge. |
| `windo - <username> [command...]` | **v4.0.1+** Windows credential handoff: start PowerShell as another local/domain account. Not automatic UAC elevation. |
| `windo !!` / `windo replay` | Re-run the last stored elevated command (`replay` is the explicit name). |
| `windo last` | Show the last stored command text and optional metadata (no execution). |
| `windo context [--json]` | One-screen environment summary (version, paths, tasks, last `RequestId` when known). |
| `windo config [--json]` | **v3.0+** Effective optional env (`WINDO_*`, `CI`) and runner-related semantics (timeouts, caps). **v3.2.1+** includes **`WINDO_EXTRAS_INDEX_URL`** and JSON field **`extrasIndexUrl`**. |
| `windo backups [--json]` | **v3.0+** List encrypted log backups (`windo_history*.enc.bak`); **`--prune --keep N --force`** removes older files. |
| `windo keybindings [status|doctor|set --chord <chord>|disable|enable|reset|safe-reset]` | Inspect and control `windo` PSReadLine prefixing behavior (no install required, applies to current session when possible). **`doctor`** runs advisory heuristics for chord conflicts. |
| `windo trace <RequestId>` / `windo trace --id <id>` | Find a decrypted audit entry by `RequestId`. |
| `windo stats` | Summarize the encrypted audit log (counts, categories, optional avg duration). |
| `windo history [-n N]` | Compact recent commands (default last 50). |
| `windo report [-o path]` | Write a local HTML audit report with summary, categories, and integrity levels. |
| `windo dashboard [--json] [--html [-o path]] [--open]` | **v3.2.8+** Operator health view: tasks, integrity, audit-chain status, category bars, recent entries, and optional local HTML dashboard. |
| `windo preflight [--json]` | **v3.3.0+** Readiness scan with actionable fix commands; checks update posture, tasks, integrity, audit chain, profile, and keybindings. |
| `windo launchpad [--json] [--html [--output path\|--output=path]] [--open] [--tray]` | **v3.3.0+** Command center with terminal, JSON, HTML, and native tray output modes. `--tray` starts a native Windows task-tray agent; HTML mode remains available for portable reports. |
| `windo completion [status\|doctor\|repair\|native-first\|hybrid\|windo\|off\|reset]` | **v3.4.0+ / v5.4.1+** Control native-first WINDO tab-completion behavior, diagnose registration, and re-register the completer in-session. |
| `windo output [status\|compact\|quiet\|legacy\|reset]` | **v4.0.1+** Control elevated-command result verbosity. Default **`compact`** is sudo-like; **`legacy`** restores Status/Duration/Output lines. |
| `windo motion [status\|auto\|on\|quiet\|off\|reset\|profile\|pulse]` | **v4.2.0+** Control terminal motion and animation profiles; auto mode stays quiet for CI, redirected output, and `WINDO_NO_SPINNER`. |
| `windo surface [status\|prime\|pulse\|doctor\|repair\|open\|panel]` | **v4.2.0+ / v5.2.0+** Native surface readiness wiring, diagnostics, repair, tray open path, and browser-independent Windows Forms panel. |
| `windo integrate [status\|doctor\|prime\|repair\|shortcuts\|startup\|shim\|open]` | **v5.4.0+** Current-user Windows integration plane: Start Menu/Desktop shortcuts, sign-in tray shortcut, startup script, command shim, user PATH advisory/repair, and integration doctor. |
| `windo control [status\|prime\|actions\|preview\|queue\|run\|execute-next\|next\|execute\|inspect\|cancel\|history\|pulse\|clear]` | **v4.3.0+ / v5.1.0+** Local Windows control plane: manifest, curated action catalog, explicit JSON request queue, lifecycle states, result files, action preview, specific request execution, and visible-shell executor. |
| `windo signal [status\|timeline\|last\|export\|open]` | **v4.5.0+ / v5.1.0+** Signal Deck diagnostics across control requests, last elevation metadata, trust, audit chain, and native-surface readiness. |
| `windo center [status\|open\|tray\|panel\|studio\|actions\|preview\|run\|queue\|execute-next\|next\|execute\|history\|signal]` | **v5.0.0+ / v5.3.0+** PowerShell-native Command Center unifying tray, Power Studio, native panel, control, surface, motion, signal, trust, recipes, modules, extras, audit, and export. |
| `windo studio [--json]` | **v5.3.0+** Open the guided Windows-native Power Studio workflow surface. Alias path: `windo center studio`. |
| `windo edition [status\|open\|html\|pulse]` | **v5.1.0+** Local command-surface console with animated HTML, edition status, and policy-aware terminal pulse. |
| `windo roadmap [--json]` | **v3.4.0+** Show the release runway from Quiet Shell through V4 preparation, with future major-package details reserved. |
| `windo source [--json]` | **v3.6.4+** Show published installer source/version/checksum and local snapshot alignment. |
| `windo trust [--online] [--json]` | **v3.5.0+** Score local trust posture and optionally compare the installer snapshot against the published checksum. |
| `windo scan [path...] [--recurse] [--max-mb N] [--no-hash] [--json]` | **v4.1.0+** Local posture scanner for scripts, launchable files, Mark-of-the-Web, hashes, and suspicious text patterns. |
| `windo net-scan [status] [--json]` \| `windo net-scan resolve <host...> [--json]` \| `windo net-scan arp [--interface <alias>] [--include-stale] [--json]` \| `windo net-scan ping <cidr \| host...> [--timeout <seconds>] [--host-limit N] [--ports <port,...>] [--json]` | **v6.0.0+** Local network posture and reachable-host checks (`status`, `resolve`, `arp`, `ping`) with bounded default probing (`hostLimit=254`, `timeout=1`) and consistent JSON payloads. |
| `windo rdp [status\|firewall\|config\|troubleshoot] [--json]` | **v6.0.0+** RDP posture checks and firewall posture actions with consistent JSON payloads (`status`, `firewall`, `config`, `troubleshoot`). |
| `windo wsl [status\|list\|ls\|check\|version\|install\|convert\|inspect\|exec\|launch\|path\|import\|export] [--json]` | **v6.0.0+** WSL availability, conversion/import/export workflows, inspection, command forwarding, and runtime launch strategies with `--dry-run` and JSON payloads. |
| `windo vault status\|list\|set\|get\|remove` | **v4.1.0+** DPAPI CurrentUser secret vault under `.pwsh_secure`. Useful for API keys and local operator secrets. |
| `windo sshx status\|keygen\|config\|test` | **v4.1.0+** OpenSSH helper for tool status, ed25519 key generation, `.ssh\config`, and SSH tests. |
| `windo container [ps\|images\|status\|logs\|restart\|start\|stop\|rmi\|rm\|pull] [--runtime docker\|podman\|auto]` | **v6.0.0+** Container runtime passthrough (docker/podman) with explicit runtime selection (`--runtime auto` prefers docker when both are available). |
| `windo crypto status\|cert\|key\|hash` | **v4.1.0+** Certificate, key, and SHA256 helper backed by local OpenSSL/certutil/Get-FileHash. |
| `windo syntax [query] [--json]` / `windo syntax doctor [query] [--json]` | **v3.6.0+** Read-only intent-to-command planner with preview commands, risk notes, aliases, and **v3.6.5+** intent diagnosis. |
| `windo mesh [doctor\|workbench] [--json] [--html [--output path\|--output=path]] [--open]` | **v3.6.6+** Read-only Operator Mesh preview; **v3.6.8+** readiness scoring; **v4.0.0+** workflow workbench lanes and optional local HTML workbench. |
| `windo explain <command...> [--json]` | **v3.6.1+** Read-only execution plan: route, privilege boundary, network/file/audit impact, checksum posture, and exact next commands. |
| `windo export [-o zip] [-n N] [--redact] [--json]` | Zip bundle: manifest copy, `doctor.json` / `integrity.json` (envelope JSON), last N audit entries. Optional **`--redact`** masks path-like strings in JSON. **`--json`** (**v3.2.2+**) adds a CLI envelope after the zip is written (`zipPath`, sizes, audit excerpt stats). |
| `windo self-update` | Trigger the self-update scheduled task (repairs task actions). |
| `windo version` | Version, paths, hashes, task presence, integrity levels. |
| `windo doctor` | Paths, tasks, logs, quick health, last `RequestId` when known. |
| `windo integrity` | Runner vs manifest with levels **OK \| DRIFT \| TAMPERED \| UNKNOWN**. |
| `windo verify` | Validate encrypted log format and hash chain. |
| `windo log -n N [--tail] [--json]` | Show last N log entries (decrypted). **`--tail`** with **`--json`** reads only the last N **physical** log lines (faster on large logs). |
| `windo stats [--since YYYY-MM-DD] [--last-days N]` | Audit log summary; optional filters on decrypted entry **`Timestamp`** (still scans full log to decrypt). **`--last-days`** must be a **positive** integer; **`--since`** and **`--last-days`** are mutually exclusive. |
| `windo profile [status\|doctor\|repair] [--prompt-init] [--all] [--json]` | Show known profile paths, WINDO block state, and prompt-init issues. **v4.2.0+** can guard oh-my-posh init so missing cached prompt scripts do not break profile load. |
| `windo cleanup [-w]` | Back up log to `.pwsh_secure`, clear active log, remove pending req/res JSON. Optional `-w` is accepted for compatibility and ignored. |
| `windo install-latest [--force] [--non-interactive] [--timeout <seconds|ms>] [--preserve-env [ALL\|name1,name2]]` | **v3.1.0+** Download and run the latest `windo_install.ps1` from **`v6`**. **v3.1.1+:** download only in a **non-elevated** shell; **confirm** after verify, then run installer ( **`--force`** / env for CI). |
| `windo upgrade` | Alias of **`install-latest`**. |
| `windo theme [classic \| modern \| auto]` | **v3.1.0+** Choose **CLI JSON** “look” only: **`classic`** = `schemaVersion` **2.6** without **`meta`**; **`modern`** = **3.0** + **`meta`**; **`auto`** = follow the embedded profile. Runner, tasks, and audit **do not** change—see [`docs/json-schema.md`](docs/json-schema.md). |
| `windo modules list \| enable \| disable \| doctor \| verify` | **v3.2.0+** Optional modules under **`Documents\windo\modules`** (see **`windo help modules`**); enabled ids persist in **`windo_prefs.json`**. |
| `windo netops-resolve \| netops-subnet-scan \| netops-arp-map \| netops-rdp-vnc \| netops-wsl` | **v6.0.0+ (module)** Optional **`extras/samples/network-ops`** module helpers; return local PowerShell objects (no WINDO JSON envelope). |
| `windo recipes [list] \| show \| preview \| run` / `windo run --recipe <name>` | **v3.2.0+** Built-in elevated **recipe** templates (bundled data, not arbitrary script). **v3.6.0+** adds first-class preview and recipe dry-run payloads. **v3.6.9+** expands the catalog into a broad read-only operator atlas; optional tool recipes report gracefully when the tool is absent. |
| `windo venv create\|activate\|deactivate\|status\|remove` | **v4.0.1+** Local Python virtual environment helper. Activation affects the current shell by dot-sourcing `Activate.ps1`. |
| `windo pkg status` / `windo pkg winget\|choco\|scoop <args...>` | **v4.0.1+** Package-manager handoff with clearer status and manager-specific guidance before elevation. |
| `windo prompt [--export <path>]` | **v3.2.0+** Oh My Posh bridge: env hints + sample segment JSON (**`WINDO_VERSION`**, **`WINDO_LAST_REQUEST_ID`** after each elevation). |
| `windo extras search [query]` / `windo extras fetch <id>` | **v3.2.0+** Search the published extras index; **fetch** is **non-elevated only**, with optional SHA256 verification (see **`SECURITY.md`**). |
| `windo dev init-module [name]` | **v3.2.0+** Scaffold **`module.json`** + **`Load.ps1`** under **`Documents\windo\modules`**. |
| `windo session [--json]` | **v3.2.0+** Compact summary: tasks, integrity levels, last stored command / `RequestId`. **v3.2.1+** adds **`lastAudit`** / **`recentAudit`** from the decrypted log tail. |
| `windo ai [status] \| doctor` | **v3.2.5+** Read-only checks for common AI API key **env names** (Process/User/Machine); **never** prints secrets. Use with OpenAI/agents/IDE CLIs—see [`docs/ai-bridge.md`](docs/ai-bridge.md). |
| `windo repair [all \| keybindings]` | **v3.2.7+** Quick recovery: same as **`windo keybindings safe-reset`** with hints (reload profile, **`install-latest`**). Use when **`w`** / prefix feels stuck or after upgrading from an older WINDO. |
| `windo uninstall` / `windo remove` | Run the elevated uninstaller, preferring the bundled local copy under `.pwsh_secure`; removes tasks, current-user WINDO profile blocks, WINDO files under `.pwsh_secure`, optional `Documents\windo`. |

Append **`--json`** or **`-Json`** to supported commands for structured output. On v3.0.0+ profiles the default envelope uses **`schemaVersion`** **`3.0`** and **`meta`**. You can still get a **2.6-style** envelope (no **`meta`**) via **`windo theme classic`** or **`WINDO_JSON_ENVELOPE`**—without downgrading WINDO itself. See [`docs/json-schema.md`](docs/json-schema.md) for `scan`, `net-scan`, `container`, `rdp`, `wsl`, and optional `network-ops` payload examples.

Append **`--dry-run`** (or **`-DryRun`**) on elevated commands or `windo replay` / `windo !!` to print what would run **without** starting the task, writing req/res files, or appending the audit log. **`windo self-update --dry-run`** prints that the update task would be started only.

### V6 example commands

These show the safer defaults and explicit options introduced for network scanning and container handoff:

```powershell
windo net-scan status --json
windo net-scan resolve myserver.local DC01 --json
windo net-scan arp --interface Ethernet --json
windo net-scan ping 10.10.10.0/24 --host-limit 254 --timeout 1 --ports 22,80,443 --json
windo container --runtime podman ps
windo container --runtime auto images --json
windo container --dry-run pull nginx:latest
windo control run system-diagnostics-open
windo center run system-diagnostics-open
```

Representative `windo net-scan ping` JSON payload (safe default `hostLimit=254`, `timeoutSeconds=1`):

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
      { "ip": "10.10.10.1", "reachable": true, "rttMs": 1, "ports": { "22": false, "443": true } },
      { "ip": "10.10.10.10", "reachable": true, "rttMs": 3, "ports": { "22": true, "443": true } },
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

Global sudo-like flags for elevated commands can be placed before the command:
- `--non-interactive` (or `-n`) to avoid install confirmation prompts for `install-latest` in automation
- `--preserve-env` (or `-E`) to pass selected env vars into the elevated child
- `--timeout` (or `-t`) to set a per-command runner timeout override (`10`, `10s`, `500ms`)

---

## PSReadLine keybindings (v2.4.0+)

When **PSReadLine** is available (typical in **PowerShell 7**), WINDO registers optional bindings so you can type normally and only add `windo` when you mean to. The active prefix chord is resolved in this order:

1. `WINDO_PREFIX_CHORD` environment variable (preferred)
2. `keybindingPrefixChord` in `windo_prefs.json`
3. VSCode fallback (`TERM_PROGRAM == vscode`): `Alt+w`
4. Default: `Alt+w`

| Input | Action |
|--------|--------|
| `<prefix chord>` | Prefix the current line with `windo ` (no-op if empty or line already starts with `windo`). |
| `Shift+Enter` | Prefix, then **submit** the line. |
| `Alt+Enter` | Same as `Shift+Enter` if your terminal does not send Shift+Enter reliably. |

If your terminal binds `Alt+w` directly as text in a way that blocks normal editing, use the recovery path:

```powershell
windo keybindings disable
windo keybindings set --chord Alt+w
windo keybindings status --json
```

If the chord still feels wrong in your terminal, try:

```powershell
windo keybindings safe-reset
```

`safe-reset` removes legacy WINDO handlers, reapplies `Alt+w`, and then applies fallback logic in one command.

**Shortcut:** **`windo repair`** (same as **`windo repair all`**) runs that safe-reset and prints reminders to **`. $PROFILE`** and run **`windo install-latest`** from a normal shell when your installed profile lags **`v6`**.

To keep the classic style everywhere, set `WINDO_PREFIX_CHORD=Alt+w` (or your preferred chord) in your profile session and avoid `windo keybindings` edits for that machine.

Bindings are **skipped** with a warning if PSReadLine is missing; your profile still loads.

### Quick verification checklist

- **Normal shell (pwsh/Windows PowerShell):** open a fresh shell and run `windo keybindings status --json`; confirm `policy.enabled` and `effectiveChord`; optionally run **`windo keybindings doctor`** (advisory heuristics for chord conflicts with other PSReadLine handlers).
- **Plain typing check:** in a fresh prompt, type `w` and `hello`; it should appear as expected (single-character typing works).
- **Prefix shortcut check:** type `g` + `it` (or any text), then press your reported chord (for example `Alt+w`) and ensure `windo ` is prepended.
- **Terminal profile reload check:** run:
  - `windo keybindings disable`
  - `windo keybindings enable`
  - `windo keybindings status`
  and confirm outputs update.
- **Auto-detect behavior check:** intentionally disable auto fallback and run:
  - `Set-Item -Path Env:WINDO_AUTO_DETECT_ALT_BINDINGS -Value 0`
  - `windo keybindings safe-reset`
  - `windo keybindings status --json`
  and confirm auto-detect is disabled and `effectiveChord` matches your configured fallback or requested chord.
- **VSCode sanity:** run the same `windo keybindings status --json` and typing checks in a VSCode terminal; set `windo keybindings set --chord Alt+w` if your preferred chord differs.
- **JSON status checks:** `windo config --json`, `windo keybindings status --json`, and `windo verify --json` should return structured payloads with `exitCode` for scripting and dashboards.
- **Help command checks (new):**
  - `windo help`, `windo --help`, and `windo /?` all render usage.
  - `windo help install-latest` shows the topic doc.
  - `windo help install-latest --json` returns a JSON payload with `found=true` and `query=install-latest`.
  - `windo /? install-latest` is available as shorthand for in-terminal recall.

### Direct `windo <command>` tab completion (v2.6.1+)

If you **start the line with `windo`**, the installer registers **`Register-WindoArgumentCompleter`**: it detects a leading `windo `, strips it, and delegates completion to **`TabExpansion2`** on the rest of the line. That lets examples like `windo git ch<TAB>` or `windo kubectl get po<TAB>` behave more like typing the underlying command alone.

**Preferred workflow is still** to type the command **without** `windo`, use **native tab completion**, then add elevation with **`Alt+w`**, **`Shift+Enter`**, or **`Alt+Enter`**—that path remains the most reliable across hosts and terminals.

**Limitations (honest):** delegation depends on **`TabExpansion2`** and the interactive host. It does not run for WINDO built-in subcommands (e.g. `windo doctor`, `windo help`) so those are not mis-completed as external tools. Partial first tokens that are ambiguous (`doc` vs `doctor` vs `docker`) may complete like a bare command line; use the preferred workflow when precision matters. If **`TabExpansion2`** is missing, registration is skipped with a warning.

---

## Security model

- **Elevation:** scheduled tasks for the current user, **RunLevel Highest**; runner runs hidden (`pwshw.exe` if present, else `powershell.exe` with hidden window).
- **Audit:** DPAPI (Current User), SHA256 per line, **PreviousHash** chain; `windo verify` checks the chain.
- **Integrity:** `windo_manifest.json` stores expected SHA256 for runner and self-update; **`windo integrity`** compares disk to manifest and reports **OK**, **DRIFT**, **TAMPERED**, or **UNKNOWN** per component and overall.

See [`SECURITY.md`](SECURITY.md) for expectations and reporting.

Optional **modules** and **extras** (v3.2+): [`docs/modules-and-extras.md`](docs/modules-and-extras.md).

### Optional environment variables

| Variable | Purpose |
|----------|---------|
| `WINDO_NO_SPINNER` | Set to any value to disable console spinners (redirect-safe logs). |
| `WINDO_MOTION` | **v4.2.0+** Override saved motion policy for the current process: `auto`, `on`, `quiet`, or `off`. |
| `WINDO_RUNNER_TIMEOUT_MS` | Max wait for the elevated child process (default **7200000** ms = 2 h; max **86400000**). |
| `WINDO_RUNNER_MAX_OUTPUT_BYTES` | Approximate cap on captured stdout+stderr (default **4194304**; split per stream in the runner). |
| `WINDO_MAX_COMMAND_CHARS` | Max length of the command line passed to `cmd.exe` (default **8191**). |
| `WINDO_SKIP_INSTALLER_SHA256` | Set to skip comparing downloaded `windo_install.ps1` to [`checksums/installer.sha256`](checksums/installer.sha256) on the configured branch (`bootstrap.ps1`, **`windo install-latest`** / **`upgrade`**). |
| `WINDO_STRICT_INSTALLER_VERIFICATION` | Set to `1` for strict installer hash checking. |
| `WINDO_JSON_ENVELOPE` | **v3.1.0+** Optional override for **`--json`** envelope shape: **`classic`** (2.6, no **`meta`**), **`modern`** (3.0 + **`meta`**), or **`auto`**. Overrides **`windo_prefs.json`** when set (see [`docs/json-schema.md`](docs/json-schema.md)). Does not change runner or security behavior. |
| `SUDO_TIMEOUT` | Per-command override (seconds or `ms`, e.g. `10`, `10s`, `500ms`) for the `--timeout` flag when not passed explicitly. |
| `SUDO_PROMPT` | Optional custom text for the `windo install-latest` confirmation prompt. |
| `WINDO_PREFIX_CHORD` | Set explicit prefix chord for keybinding injection (`Alt+w`, `Ctrl+Alt+w`, etc). Avoid plain `w,w` unless you intentionally accept that keying any line starting with `w` may be affected. |
| `WINDO_DISABLE_PSREADLINE_BINDINGS` | Set to `1`/`true` to disable WINDO keybindings for the session. |
| `WINDO_AUTO_DETECT_ALT_BINDINGS` | Set to `0`/`false` to disable automatic fallback for Alt-based chords (default: enabled). |
| `WINDO_KEYBINDING_FALLBACK_CHORD` | Alternate chord to fallback to when automatic Alt detection cannot keep `Alt+*` usable. Default: `Alt+;`. |
| `WINDO_INSTALL_NONINTERACTIVE` | **v3.1.1+** If set, **`windo install-latest`** runs the downloaded installer **without** an interactive confirmation (for CI; use with care). |
| `WINDO_BOOTSTRAP_FORCE_INSTALL` | **v3.1.1+** If set, **`bootstrap.ps1`** launches the installer **without** **`Read-Host`** after download (CI / scripts). |

**Automation exit codes (`$global:WINDO_EXIT_CODE`):** set after **`windo doctor`**, **`windo integrity`**, and **`windo verify`** (also exposed as **`exitCode`** in JSON payloads where applicable).

| Code | Typical meaning |
|------|-----------------|
| 0 | Success / OK |
| 2 | Doctor: main task or runner missing; verify: no log or empty log; stats: bad `--since`, conflicting filters, invalid or missing `--last-days`, or non-positive `--last-days` (no JSON envelope on stats validation errors); backups: bad args or prune without **`--force`**; **`install-latest`** / **`upgrade`**: session is elevated (download blocked) or non-interactive without **`--force`** / **`WINDO_INSTALL_NONINTERACTIVE`** |
| 3 | Doctor or integrity: manifest/hash state not OK (DRIFT/TAMPERED) |
| 4 | Verify: hash chain or format failure |
| 6 | Doctor or integrity: UNKNOWN component level |

Scripts: run `windo doctor` (or `integrity` / `verify`), then test **`$global:WINDO_EXIT_CODE`**.

---


## Reporting and automation

- **`windo report`** produces a **local HTML** summary (entry counts, category breakdown, integrity levels, recent audit lines). Treat reports as **sensitive**; they may echo elevated command text.
- **`windo export`** builds a **zip** under `Documents\windo\exports\` (or `-o`) with manifest, envelope JSON, and a truncated audit excerpt—handle as sensitive.
- **`--json` / `-Json`** uses the **v3.0 envelope** (and usually **`meta`**) on v3.0.0+ installs for `doctor`, `integrity`, `version`, `verify`, `log`, `stats`, `history`, `last`, `context`, `trace`, `profile`, `config`, `backups`, and **`theme`**. Use **`windo theme`** / **`WINDO_JSON_ENVELOPE`** if you prefer the older 2.6-style JSON wrapper. See [`docs/json-schema.md`](docs/json-schema.md).
- **`windo stats`** / **`windo history`** give fast situational awareness without full `log` verbosity.

- Maintainer notes: [`docs/build.md`](docs/build.md) (validation + optional `src/` concat), [`docs/json-schema.md`](docs/json-schema.md), [`docs/performance.md`](docs/performance.md) (large logs), [`docs/branding.md`](docs/branding.md) (logo direction).

---

## Execution flow

```text
You type windo …
        →
scheduled task starts hidden runner
        →
elevated command runs
        →
result returned; encrypted audit line appended
```

---

## Version archive in this repository

- **Repository root** — current release scripts and docs (`windo_install.ps1`, `bootstrap.ps1`, etc.).
- **`versions/vX.Y.Z/`** — frozen copies of older release files (e.g. [`versions/v2.3.0/`](versions/v2.3.0)) for reference and diffing.
- **`docs/releases/`** — release notes and shared snippets.

---

## Local snapshot

After install, a copy of deployment artifacts is kept under:

`%USERPROFILE%\Documents\windo\`

If the installer could not snapshot itself (pathless execution), other files may still be present; see the installer warning.

---

## Credits

WINDO was conceived and built by Chris Jones. Development and hardening include collaborative work with AI assistance, with emphasis on security, auditability, and deliberate elevation for administrators.

---

## License

MIT License — see [`LICENSE`](LICENSE).
