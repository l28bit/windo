# WINDO

<p align="center">
  <img src="brand/winDO.png" alt="WINDO logo" width="520">
</p>


WINDO is a PowerShell-first elevation helper for Windows. It gives administrators a **deliberate, auditable** way to request elevation **before** a command runs—instead of improvising after the fact.

---

## Philosophy

Experienced operators treat commands as intent. Elevation should not be accidental. WINDO keeps the workflow explicit:

**intent → choose elevation → execute with authority**

The default GitHub branch for raw URLs is **`Exodus`**.

---

## What's new in v5.4.0 Exodus Limited Edition

- **Windows Integration Plane** — `windo integrate` inspects and repairs current-user Start Menu, desktop, startup tray, and command-shim wiring so WINDO behaves more like a dedicated Windows tool.
- **Explicit integration repair** — `windo integrate repair` writes Start Menu shortcuts, a Power Studio desktop shortcut, a startup tray shortcut, `.pwsh_secure\windo_start_tray.ps1`, and a current-user `windo.cmd` shim without machine-wide writes.
- **Integration doctor** — `windo integrate doctor` checks shell COM, shortcut presence, startup wiring, shim presence, and user PATH posture with copy-ready repair commands.
- **Control-plane integration actions** — `integrate-status`, `integrate-doctor`, `integrate-repair`, `integrate-open`, `integrate-shim`, and `integrate-startup` are now curated visible-shell actions for tray, Power Studio, and Command Center flows.
- **Native startup path** — `WINDO Command Center Tray.lnk` can launch the browser-independent tray surface at sign-in through the same explicit current-user integration layer.
- **Power Studio** — `windo studio` and `windo center studio` open a modern Windows Forms wizard surface with guided Start, Trust, Repair, Security, Developer, and Package workflow tabs.
- **Preview, queue, run workflow controls** — Power Studio exposes curated actions with separate Preview, Queue, and Run buttons so operators can inspect intent before launching visible PowerShell execution.
- **Production visual jump** — native surfaces now lean into a Windows 11-style command room with status cards, tabbed workflows, progress motion, and tighter action hierarchy.
- **Native Surface Panel** — `windo surface panel` and `windo center panel` open a dedicated Windows Forms command surface with status cards and curated visible-shell actions.
- **Status-aware native icons** — tray and panel launch paths now resolve ready, warning, denied, elevated, or neutral Enterprise icons when those assets exist, with `WINDO_TRAY_ICON` still available as an override.
- **Control Center visual actions** — `surface-panel` joins the curated control action catalog, tray popup, and tab completion path so the browser-independent surface is discoverable everywhere.
- **Surface polish pass** — `windo dashboard --html`, `windo launchpad --html`, and `windo launchpad --tray` now share a stronger branded operator design system.
- **Tray Command Center redesign** — the native Windows Forms popup now uses scrollable action rows, clearer command text, and a local status-toast window.
- **Dashboard readability** — health, integrity, audit categories, recent audit, issues, and paths now have clearer hierarchy for repeated operational use.
- **Exodus Limited Edition surface** — `windo edition open` renders a local animated command-center console with the final brand assets, V5 status, curated actions, and release identity.
- **Limited Edition motion** — `windo edition pulse` adds a policy-aware terminal animation for the V5+ surface while still respecting `WINDO_MOTION`, CI, redirected output, and `WINDO_NO_SPINNER`.
- **Command grammar hardening** — `windo control preview <action-id>`, `windo control execute <request-id>`, `windo center actions`, `windo center preview`, `windo center execute-next`, and `windo signal open` make the V5 command language more explicit and easier to discover.
- **Exodus source move** — install/update, checksum, extras, trust, README, and build docs now point at the `Exodus` branch.
- **Command Center Special Edition** — `windo center` unifies tray, control plane, Signal Deck, surface, motion, trust, recipes, modules, extras, audit, and export into a PowerShell-native Windows command center.
- **Command Center Actions** — `windo control execute-next|inspect|cancel|history` adds explicit request lifecycle states and result JSON beside queued control-plane requests.
- **Signal Deck** — `windo signal status|timeline|last|export` correlates control requests, last elevation metadata, audit-chain health, trust posture, and native-surface readiness.
- **Native Shell Polish** — `windo surface doctor|repair|open` checks and repairs tray/surface/control readiness, then opens the browser-independent tray surface.
- **Native companion scaffold** — `native-companion/` starts the future compiled-helper path without making a compiled binary required for V5.
- **Control Plane Wiring** — `windo control` primes a local Windows control-plane manifest, exposes a curated action catalog, queues explicit JSON action requests, and launches known actions in visible PowerShell windows for tray/native orchestration.
- **Tray action expansion** — `windo launchpad --tray` now includes surface, control-plane, and motion actions in the native Windows popup/menu path.
- **Native Surface Prep** — `windo surface` inspects tray/native readiness, motion policy, profile prompt issues, and can prime a local surface manifest under `.pwsh_secure`.
- **Motion policy** — `windo motion auto|on|quiet|off|reset|pulse` controls subtle terminal animations while staying quiet in CI, redirected output, and `WINDO_NO_SPINNER`.
- **Profile prompt doctor** — `windo profile doctor` detects unguarded oh-my-posh init pipelines and missing cached prompt init scripts; `windo profile repair --prompt-init` wraps oh-my-posh init so profile load degrades to a warning instead of breaking.
- **Security Foundry** — `windo scan`, `windo vault`, `windo sshx`, and `windo crypto` add local-first security workflows without changing the elevation trust boundary.
- **Branch source cutover** — install/update, extras, checksum, and trust URLs now target the **`Exodus`** branch.
- **README brand polish** — removes the rough cropped wordmark and uses constrained final assets so GitHub renders cleanly.
- **WINDO scan** — scan files, directories, multiple paths, or recursive scopes for hashes, Mark-of-the-Web, launchable extensions, and suspicious script patterns.
- **DPAPI vault** — store named API keys or credentials under `.pwsh_secure` with current-user DPAPI protection.
- **SSH operator tools** — check OpenSSH tooling, create `.ssh\config`, generate ed25519 keys, and test SSH targets.
- **Crypto helpers** — inspect certificates/keys with OpenSSL/certutil and calculate SHA256 hashes with short syntax.
- **Compact execution output** — elevated external commands now default to one small sudo-like status line; `windo output legacy` restores the older multi-line Status/Duration/Output layout.
- **Syntax pass-through fix** — external command flags like `windo powercfg -h off` now stay with the target command instead of being interpreted as WINDO help.
- **Account handoff syntax** — `windo - <username> [command...]` starts a PowerShell process under another local/domain account using Windows credentials.
- **Python venv helper** — `windo venv create|activate|deactivate|status|remove` manages local virtual environments without elevation.
- **Package-manager routing** — `windo pkg winget|choco|scoop ...` adds clearer intent and guidance before handing package work to the elevated runner where appropriate.
- **Operator Mesh Workbench** — `windo mesh workbench` turns trust, recipes, modules, extras, launchpad, and export into workflow lanes with copy-ready next commands.
- **Quiet Shell** — native-first completion and completion policy make `windo <command><Tab>` behave more like normal PowerShell.
- **Source of Truth** — `windo source` shows the published installer source, version, checksum, and local snapshot alignment.
- **Trust Console** — `windo trust` and `windo trust --online` verify local posture and installer checksum provenance.
- **Recipe Atlas** — the built-in recipe catalog now includes a much larger read-only operator set for identity, services, networking, firewall, storage, power, time, Defender, certificates, scheduled tasks, drivers, tools, and OS posture.
- **Operator Mesh cockpit** — `windo mesh --html` and `windo mesh --open` render the V4-prep inventory as a branded local cockpit with copy-ready next commands.
- **Operator Mesh Doctor** — `windo mesh doctor` scores local Operator Mesh readiness across tasks, integrity, audit chain, recipes, modules, extras, brand/tray assets, and export posture.
- **Operator Mesh preview** — `windo mesh` shows modules, recipes, extras, launchpad/tray assets, and export readiness in one read-only V4-prep view.
- **Syntax Doctor** — `windo syntax doctor [query]` flags exact, fuzzy, ambiguous, or missing intent matches and suggests the safest next command.
- **Syntax Forge** — `windo syntax [query]` maps operator intent to exact commands, previews, risk notes, and aliases without executing anything.
- **Execution Plan** — `windo explain <command...>` shows route, privilege boundary, artifacts, audit behavior, and checksum posture before running anything.
- **API-first installer fetch** — bootstrap and `windo install-latest` fetch the installer through the GitHub Contents API first, with raw branch fallback.
- **Checksum source hardening** — online checksum checks prefer the GitHub Contents API and fall back to raw branch content to avoid stale raw-CDN results after a sync.
- **Quieter roadmap** — `windo roadmap` focuses on the current 3.x and V4 runway while future major-package details stay reserved.
- **Recipe previews** — `windo recipes preview <name>` and recipe `--dry-run` show exact elevated commands before scheduled tasks, request files, result files, or audit entries are touched.

Full list: [`CHANGELOG.md`](CHANGELOG.md). Release copy: [`docs/releases/RELEASE_NOTES_v5.4.0.md`](docs/releases/RELEASE_NOTES_v5.4.0.md).

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

**Recommended (GitHub):** downloads [`bootstrap.ps1`](https://raw.githubusercontent.com/l28bit/windo/Exodus/bootstrap.ps1), saves `windo_install.ps1` to a **temp file**, verifies its checksum, then starts it from the temp file. In interactive sessions WINDO requests **UAC elevation** for the installer so scheduled tasks and secure-dir ACL work can complete; the temp file is removed afterward. The **full installer is not** piped through `Invoke-Expression`.

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/Exodus/bootstrap.ps1)
```

Run the **installer** from an **elevated** session when you want scheduled tasks registered and `%USERPROFILE%\.pwsh_secure\` updated without permission issues—**after** you have downloaded and confirmed.

**Upgrade from any installed v2.x / v3.x:** with WINDO loaded in your profile, run **`windo install-latest`** from a **normal (non-elevated)** window. The installer is **not** downloaded while Administrator (avoids high-privilege fetch). After checksum verification you get a **prompt** before the installer runs; in interactive sessions WINDO then requests **UAC elevation** so scheduled tasks and secure-dir ACL work can complete. Use **`windo install-latest --force`** or **`WINDO_INSTALL_NONINTERACTIVE=1`** in CI/automation.

```powershell
windo install-latest
```

(`windo upgrade` is the same command.)

**Bootstrap** (`iex (irm …/bootstrap.ps1)`): same rule—**do not run from an elevated shell**; the script exits with instructions. After download you are prompted before launch (or set **`WINDO_BOOTSTRAP_FORCE_INSTALL=1`** / **`CI`** for unattended).

Or use the bootstrap one-liner above, or run `.\windo_install.ps1` from a clone. There is no version gate: the installer replaces the WINDO profile block and refreshes secure-dir artifacts.

**Remove WINDO completely:** run **`windo uninstall`** (or **`windo remove`**) from a normal shell. WINDO prefers the bundled local **`%USERPROFILE%\.pwsh_secure\windo_uninstall.ps1`** and starts it elevated with UAC; if the local copy is missing it falls back to the published raw uninstaller from `Exodus`. After your profile is loaded you can also run **`windo-uninstall`** (alias: **`windoremove`**) directly. Optional **`-KeepSnapshots`** / **`--keep-snapshots`** keeps `%USERPROFILE%\Documents\windo\`. The uninstaller removes WINDO marker blocks from the known **current-user** PowerShell profiles for **pwsh** and **Windows PowerShell**.

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
| `windo launchpad [--json] [--html [--output path\|--output=path]] [--open] [--tray]` | **v3.3.0+** Special Edition command center. `--tray` starts a native Windows task-tray agent; HTML mode remains available for portable reports. |
| `windo completion [status\|native-first\|hybrid\|windo\|off\|reset]` | **v3.4.0+** Control native-first WINDO tab-completion behavior. |
| `windo output [status\|compact\|quiet\|legacy\|reset]` | **v4.0.1+** Control elevated-command result verbosity. Default **`compact`** is sudo-like; **`legacy`** restores Status/Duration/Output lines. |
| `windo motion [status\|auto\|on\|quiet\|off\|reset\|pulse]` | **v4.2.0+** Control subtle terminal motion and animations; auto mode stays quiet for CI, redirected output, and `WINDO_NO_SPINNER`. |
| `windo surface [status\|prime\|pulse\|doctor\|repair\|open\|panel]` | **v4.2.0+ / v5.2.0+** Native surface readiness wiring, diagnostics, repair, tray open path, and browser-independent Windows Forms panel. |
| `windo integrate [status\|doctor\|prime\|repair\|shortcuts\|startup\|shim\|open]` | **v5.4.0+** Current-user Windows integration plane: Start Menu/Desktop shortcuts, sign-in tray shortcut, startup script, command shim, user PATH advisory/repair, and integration doctor. |
| `windo control [status\|prime\|actions\|preview\|queue\|run\|execute-next\|next\|execute\|inspect\|cancel\|history\|pulse\|clear]` | **v4.3.0+ / v5.1.0+** Local Windows control plane: manifest, curated action catalog, explicit JSON request queue, lifecycle states, result files, action preview, specific request execution, and visible-shell executor. |
| `windo signal [status\|timeline\|last\|export\|open]` | **v4.5.0+ / v5.1.0+** Signal Deck diagnostics across control requests, last elevation metadata, trust, audit chain, and native-surface readiness. |
| `windo center [status\|open\|tray\|panel\|studio\|actions\|preview\|run\|queue\|execute-next\|next\|execute\|history\|signal]` | **v5.0.0+ / v5.3.0+** PowerShell-native Command Center unifying tray, Power Studio, native panel, control, surface, motion, signal, trust, recipes, modules, extras, audit, and export. |
| `windo studio [--json]` | **v5.3.0+** Open the guided Windows-native Power Studio workflow surface. Alias path: `windo center studio`. |
| `windo edition [status\|open\|html\|pulse]` | **v5.1.0+** Exodus Limited Edition branded local console with final assets, animated HTML, edition status, and a policy-aware terminal pulse. |
| `windo roadmap [--json]` | **v3.4.0+** Show the release runway from Quiet Shell through V4 preparation, with future major-package details reserved. |
| `windo source [--json]` | **v3.6.4+** Show published installer source/version/checksum and local snapshot alignment. |
| `windo trust [--online] [--json]` | **v3.5.0+** Score local trust posture and optionally compare the installer snapshot against the published checksum. |
| `windo scan [path...] [--recurse] [--max-mb N] [--no-hash] [--json]` | **v4.1.0+** Local posture scanner for scripts, launchable files, Mark-of-the-Web, hashes, and suspicious text patterns. |
| `windo vault status\|list\|set\|get\|remove` | **v4.1.0+** DPAPI CurrentUser secret vault under `.pwsh_secure`. Useful for API keys and local operator secrets. |
| `windo sshx status\|keygen\|config\|test` | **v4.1.0+** OpenSSH helper for tool status, ed25519 key generation, `.ssh\config`, and SSH tests. |
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
| `windo install-latest [--force] [--non-interactive] [--timeout <seconds|ms>] [--preserve-env [ALL\|name1,name2]]` | **v3.1.0+** Download and run the latest `windo_install.ps1` from **`Exodus`**. **v3.1.1+:** download only in a **non-elevated** shell; **confirm** after verify, then run installer ( **`--force`** / env for CI). |
| `windo upgrade` | Alias of **`install-latest`**. |
| `windo theme [classic \| modern \| auto]` | **v3.1.0+** Choose **CLI JSON** “look” only: **`classic`** = `schemaVersion` **2.6** without **`meta`**; **`modern`** = **3.0** + **`meta`**; **`auto`** = follow the embedded profile. Runner, tasks, and audit **do not** change—see [`docs/json-schema.md`](docs/json-schema.md). |
| `windo modules list \| enable \| disable \| doctor \| verify` | **v3.2.0+** Optional modules under **`Documents\windo\modules`** (see **`windo help modules`**); enabled ids persist in **`windo_prefs.json`**. |
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

Append **`--json`** or **`-Json`** to supported commands for structured output. On v3.0.0+ profiles the default envelope uses **`schemaVersion`** **`3.0`** and **`meta`**. You can still get a **2.6-style** envelope (no **`meta`**) via **`windo theme classic`** or **`WINDO_JSON_ENVELOPE`**—without downgrading WINDO itself. See [`docs/json-schema.md`](docs/json-schema.md).

Append **`--dry-run`** (or **`-DryRun`**) on elevated commands or `windo replay` / `windo !!` to print what would run **without** starting the task, writing req/res files, or appending the audit log. **`windo self-update --dry-run`** prints that the update task would be started only.

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

**Shortcut:** **`windo repair`** (same as **`windo repair all`**) runs that safe-reset and prints reminders to **`. $PROFILE`** and run **`windo install-latest`** from a normal shell when your installed profile lags **Exodus**.

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
| `WINDO_SKIP_INSTALLER_SHA256` | Set to skip comparing downloaded `windo_install.ps1` to [`checksums/installer.sha256`](checksums/installer.sha256) on the `Exodus` branch (`bootstrap.ps1`, **`windo install-latest`** / **`upgrade`**). |
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
