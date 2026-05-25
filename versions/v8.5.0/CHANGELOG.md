# Changelog

All notable changes to WINDO are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

No unreleased changes yet.

## [8.5.0] - Unreleased

Release notes: [`docs/releases/RELEASE_NOTES_v8.5.0.md`](docs/releases/RELEASE_NOTES_v8.5.0.md).

### Added

- **`windo contract`** — local release contract posture (semver, edition, profile version stamp, integrity, branch) with **`doctor`** mode for published source alignment.
- **`windo history search`** — filter encrypted audit entries by command text; **`--contains`** alias on `windo history`.
- Control/center quick action **`contract-doctor`** and Syntax Forge shortcut for contract posture.
- Dynamic **`_windo_edition_label`** so branding tracks semver (V8.5 from 8.5.0).

### Changed

- Installer and bootstrap identity updated to **`8.5.0` / V8.5**; edition-aware command center HTML titles.
- **`windo source`** JSON and human output include embedded **`contract`** metadata.
- Roadmap train marks **8.4.0 Prometheus Contract** as shipped and **8.5.0 Contract Posture** as active.

## [8.4.0] - 2026-05-24

Release notes: [`docs/releases/RELEASE_NOTES_v8.4.0.md`](docs/releases/RELEASE_NOTES_v8.4.0.md).

### Added

- Contract migration for V8.4: canonical source branch moved from `Exodus`/`v6` to `Prometheus`.
- Dual-release migration notes added for V6.x and V7.x operators.
- Installer manifest checks readiness for `Prometheus` and `8.4.0` release metadata.
- Release train entries for **6.0.0 Network Ops Plane**, **7.0.0 Sudo Shell**, and **8.4.0 Prometheus Contract**.
- `windo version --contract` for edition, branch, and schema visibility in human and JSON output.
- Control/center quick actions: `net-scan-status`, `studio-open`.
- Runtime alias wiring for `windo do` → `run` and `windo recdo` → `recipes run`.

### Changed

- Installer and bootstrap identity updated to `WINDO 8.4.0 V8.4` while preserving existing installer behavior and upgrade handshake.
- Published installer handoff function renamed to `_windo_run_published_installer` (replacing legacy `genisis` naming).
- `windo roadmap` now reports V8.4 as the active target major instead of the retired V4-only runway copy.

### Fixed

- Internal branch-selection and checksum tooling now normalize default branch selection to `Prometheus`, reducing contract ambiguity for upgrade and self-update paths.

## [6.0.0] - Superseded

This line was consolidated into the **8.4.0** release contract. Historical notes remain in [`docs/releases/RELEASE_NOTES_v6.0.0.md`](docs/releases/RELEASE_NOTES_v6.0.0.md) for operators who pinned older branch wording (`Exodus`, `v6`). The live installer semver and branding are **8.4.0 / V8.4** with **`Prometheus`** as the published source branch unless overridden.

## [5.4.1] - 2026-05-07

Release notes: [`docs/releases/RELEASE_NOTES_v5.4.1.md`](docs/releases/RELEASE_NOTES_v5.4.1.md).

### Fixed

- **Tab completion registration:** the PSReadLine keybinding block no longer uses top-level `return` before the profile completer block. This prevents `windo <Tab>` from silently falling back to current-path names when keybinding setup is skipped or Alt binding detection fails.

### Added

- **Completion Doctor:** `windo completion doctor` reports `TabExpansion2`, completer registration, profile completer text, early-return risk, and sample `windo ` completions.
- **Completion Repair:** `windo completion repair` re-registers `Register-WindoArgumentCompleter` in the current session.

## [5.4.0] - 2026-05-07

Release notes: [`docs/releases/RELEASE_NOTES_v5.4.0.md`](docs/releases/RELEASE_NOTES_v5.4.0.md).

### Added

- **Windows Integration Plane:** `windo integrate status|doctor|prime|repair|shortcuts|startup|shim|open` adds current-user Start Menu, desktop, startup tray, startup script, command shim, and PATH repair wiring.
- **Control-plane integration actions:** `integrate-status`, `integrate-doctor`, `integrate-repair`, `integrate-open`, `integrate-shim`, and `integrate-startup` are curated visible-shell action IDs.
- **Native surface wiring:** Power Studio and the tray action list now expose Windows integration status and repair flows.
- **Integration JSON:** `integrate` payloads report shortcut state, startup wiring, shim/PATH posture, doctor checks, repair results, and next commands.

### Changed

- Version, bootstrap banner, README release copy, roadmap, completion specs, and checksum/version tests now target v5.4.0.

## [5.3.0] - 2026-05-06

Release notes: [`docs/releases/RELEASE_NOTES_v5.3.0.md`](docs/releases/RELEASE_NOTES_v5.3.0.md).

### Added

- **Power Studio:** `windo studio`, `windo center studio`, `windo center wizard`, and `windo center power` now write and launch a guided Windows Forms workflow surface under `.pwsh_secure`.
- **Wizard workflow tabs:** Power Studio organizes curated actions into Start, Trust, Repair, Security, Developer, and Package lanes with Preview, Queue, and Run controls.
- **Expanded curated actions:** the control-plane catalog now includes `power-studio`, `center-status`, source/audit checks, surface repair flows, local security helpers, developer helpers, and package-manager posture actions.

### Changed

- **Native readiness:** `windo surface doctor` now checks the Power Studio script path in addition to tray and Surface Panel script freshness.
- **Command Center grammar:** `windo center` now advertises and completes `studio`, `wizard`, and `power` as native visual entrypoints.

## [5.2.0] - 2026-05-06

Release notes: [`docs/releases/RELEASE_NOTES_v5.2.0.md`](docs/releases/RELEASE_NOTES_v5.2.0.md).

### Added

- **Native Surface Panel:** `windo surface panel`, `windo surface window`, and `windo center panel` now write and launch a browser-independent Windows Forms panel under `.pwsh_secure`.
- **Curated visual executor:** the panel presents status cards and curated WINDO actions only; each action opens a visible PowerShell window so command output remains inspectable.
- **Control and tray wiring:** `surface-panel` is now a curated control action, the tray popup exposes Surface Panel, and tab completion includes the new surface/center verbs.

### Changed

- **Status-aware icon path:** native launch paths now resolve Enterprise tray icons by status, while preserving the `WINDO_TRAY_ICON` override.
- **Surface doctor coverage:** `windo surface doctor` now checks the generated panel script path alongside tray script and manifest readiness.

## [5.1.1] - 2026-05-06

Release notes: [`docs/releases/RELEASE_NOTES_v5.1.1.md`](docs/releases/RELEASE_NOTES_v5.1.1.md).

### Changed

- **Dashboard visual polish:** `windo dashboard --html` now uses the WINDO visual system, stronger hierarchy, responsive cards, darker operator styling, and clearer issue/audit/path sections.
- **Launchpad visual polish:** `windo launchpad --html` now uses final WINDO assets, stronger Command Center layout, cleaner cards/tables, and neutral operator copy.
- **Tray popup redesign:** `windo launchpad --tray` now writes a richer Windows Forms Command Center popup with scrollable action rows, clearer command text, and a local status-toast window.

## [5.1.0] - 2026-05-06

Release notes: [`docs/releases/RELEASE_NOTES_v5.1.0.md`](docs/releases/RELEASE_NOTES_v5.1.0.md).

### Added

- **WINDO command surface:** `windo edition status|open|html|pulse` adds a branded local V5+ console with final assets, animated HTML, Command Center status, curated action posture, and policy-aware terminal motion.
- **Command grammar hardening:** `windo control preview`, `windo control execute <request-id>`, `windo control next`, `windo center actions|preview|execute-next|execute|signal`, and `windo signal open` tighten the explicit command-center lifecycle.
- **Control catalog expansion:** `edition-open` becomes a curated visible-shell action and the native tray menu exposes the Command Center console.
- **Exodus branch move:** bootstrap, install/update, checksum, trust/source, extras, README, and build docs now use the `Exodus` branch as the live source contract.

## [5.0.0] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v5.0.0.md`](docs/releases/RELEASE_NOTES_v5.0.0.md).

### Added

- **Command Center:** `windo center status|open|tray|run|queue|history` unifies tray, control plane, Signal Deck, surface, motion, trust, recipes, modules, extras, audit, and export into a PowerShell-native command center.
- **Native companion scaffold:** `native-companion/` starts the future compiled-helper path without making a compiled binary required for install or V5 operation.

## [4.6.0] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v4.6.0.md`](docs/releases/RELEASE_NOTES_v4.6.0.md).

### Added

- **Native Shell Polish:** `windo surface doctor|repair|open` adds native readiness checks, repair handoff, and browser-independent tray open flow.
- **Motion polish:** surface/control run paths now include success, warning, and queue/run progress pulse labels when motion policy allows animation.

## [4.5.0] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v4.5.0.md`](docs/releases/RELEASE_NOTES_v4.5.0.md).

### Added

- **Signal Deck:** `windo signal status|timeline|last|export` correlates control requests/results, last elevation metadata, trust posture, audit-chain health, and native-surface readiness.
- **Signal HTML:** `windo signal export --open` writes a local evidence-first HTML deck.

## [4.4.0] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v4.4.0.md`](docs/releases/RELEASE_NOTES_v4.4.0.md).

### Added

- **Command Center Actions:** `windo control execute-next|inspect|cancel|history` adds request lifecycle states, result JSON, and explicit queue execution.
- **Tray queue actions:** `windo launchpad --tray` now exposes control history, run-next, queue folder, last result, and Signal Deck actions.

## [4.3.0] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v4.3.0.md`](docs/releases/RELEASE_NOTES_v4.3.0.md).

### Added

- **Control Plane Wiring:** `windo control status|prime|actions|queue|run|pulse|clear` adds a local Windows control-plane manifest, curated action catalog, explicit JSON request queue, and visible-shell executor for tray/native actions.
- **Tray action expansion:** `windo launchpad --tray` now surfaces native-surface, control-plane, and motion actions in the browser-independent Windows tray popup/menu.

## [4.2.0] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v4.2.0.md`](docs/releases/RELEASE_NOTES_v4.2.0.md).

### Added

- **Native Surface Prep:** `windo surface status|prime|pulse` reports tray/native readiness, motion policy, profile prompt issues, and writes a local native-surface manifest under `.pwsh_secure\surface`.
- **Motion policy:** `windo motion status|auto|on|quiet|off|reset|pulse` controls subtle terminal animation without affecting CI, redirected output, or `WINDO_NO_SPINNER`.
- **Profile prompt doctor:** `windo profile doctor` detects unguarded oh-my-posh init pipelines and missing cached prompt init scripts; `windo profile repair --prompt-init` wraps oh-my-posh init in a profile-load guard with a timestamped backup.

## [4.1.1] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v4.1.1.md`](docs/releases/RELEASE_NOTES_v4.1.1.md).

### Changed

- **Genesis branch cutover:** live installer, bootstrap, extras, checksum, trust, security docs, and install/update copy now point at **`Genesis`**.
- **README visual cleanup:** removed the rough secondary cropped wordmark and added constrained final logo/avatar/brand-mark assets for cleaner GitHub rendering.

## [4.1.0] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v4.1.0.md`](docs/releases/RELEASE_NOTES_v4.1.0.md).

### Added

- **Security Foundry:** `windo scan`, `windo vault`, `windo sshx`, and `windo crypto` add local-first security workflows without changing WINDO's deliberate elevation model.
- **WINDO scan:** local file/directory scanner for hashes, Mark-of-the-Web, launchable file types, and common suspicious script patterns. Supports multiple paths, recursive scans, max text-scan size, and JSON output.
- **DPAPI vault:** current-user protected vault under `.pwsh_secure` for named secrets such as API keys or local operator credentials.
- **SSH helpers:** `windo sshx status|keygen|config|test` wraps common OpenSSH operator tasks.
- **Crypto helpers:** `windo crypto status|cert|key|hash` provides quick certificate/key inspection and SHA256 hashing with OpenSSL/certutil/Get-FileHash.

## [4.0.1] - 2026-05-05

Release notes: [`docs/releases/RELEASE_NOTES_v4.0.1.md`](docs/releases/RELEASE_NOTES_v4.0.1.md).

### Added

- **Compact output policy:** `windo output status|compact|quiet|legacy|reset` controls elevated-command result verbosity. The default is now a single compact status line plus command output when present.
- **Account handoff wiring:** `windo - <username> [command...]` starts PowerShell as another local/domain account through Windows credentials.
- **Python venv helper:** `windo venv create|activate|deactivate|status|remove` manages local Python virtual environments without elevation.
- **Package-manager handoff:** `windo pkg status` and `windo pkg winget|choco|scoop <args...>` add clearer manager routing and guidance before package work goes through WINDO.

### Fixed

- **External flag pass-through:** `windo powercfg -h off` and similar external commands no longer have `-h` stolen as WINDO help. WINDO help flags are now interpreted after a target command only for WINDO built-ins.

### Changed

- **README visuals:** the README now uses the full-width blue banner and adds additional brand imagery from `brand/assets`.

## [4.0.0] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v4.0.0.md`](docs/releases/RELEASE_NOTES_v4.0.0.md).

### Added

- **Operator Mesh Workbench:** `windo mesh workbench`, `windo mesh workbench --json`, and `windo mesh workbench --html` assemble trust, recipes, modules, extras, launchpad, and export into V4 workflow lanes with readiness, platform pieces, recommended flow, and copy-ready commands.

### Changed

- **Release identity:** WINDO moves to **v4.0.0** because the Quiet Shell, Trust Console, Syntax Forge, Mesh preview/doctor/cockpit, and Recipe Atlas foundations now form a coherent Operator Mesh surface.
- **Roadmap:** marks 3.4, 3.5, 3.6, and 4.0 as shipped while keeping the future major package reserved.
- **Completion/help:** `windo mesh <Tab>` now suggests `workbench`.

## [3.6.9] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.9.md`](docs/releases/RELEASE_NOTES_v3.6.9.md).

### Added

- **Recipe Atlas:** expanded the bundled read-only recipe catalog from a small example set into a broad operator inventory covering identity, services, networking, firewall, storage, power, time, Defender, certificates, scheduled tasks, drivers, local accounts, tool versions, OS posture, and Ollama.

### Changed

- **Completion/help:** `windo recipes <Tab>` now advertises the expanded built-in recipe ids so recipe discovery does not depend on remembering names.
- **V4 runway:** Operator Mesh now sees a much larger recipe surface through the existing `windo mesh` inventory and cockpit.

## [3.6.8] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.8.md`](docs/releases/RELEASE_NOTES_v3.6.8.md).

### Added

- **Operator Mesh Doctor:** `windo mesh doctor` and `windo mesh doctor --json` score local V4 Operator Mesh readiness across scheduled tasks, integrity, audit chain, recipes, modules, extras, brand/tray assets, and export posture without executing workflows.

### Changed

- **Completion/help:** WINDO help and tab completion now include the `mesh doctor` subcommand.

## [3.6.7] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.7.md`](docs/releases/RELEASE_NOTES_v3.6.7.md).

### Added

- **Operator Mesh cockpit:** `windo mesh --html`, `windo mesh --open`, and `windo mesh --output <path>` render the read-only Operator Mesh inventory as a branded local HTML cockpit with copy-ready next commands, recipe preview rows, module rows, platform paths, and detected brand/tray assets.

### Changed

- **Completion/help:** WINDO help and tab completion now include the new `mesh` HTML/open/output flags.

## [3.6.6] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.6.md`](docs/releases/RELEASE_NOTES_v3.6.6.md).

### Added

- **Operator Mesh preview:** `windo mesh` and `windo mesh --json` provide a read-only V4-prep inventory of modules, enabled module ids, built-in recipe previews, installed extras, launchpad/tray asset readiness, and export bundle readiness.

### Changed

- **Roadmap alignment:** the 4.0 Operator Mesh focus now names `windo mesh` as the bridge from Syntax Forge into the platform layer.
- **Completion/help:** WINDO help and tab completion now include the `mesh` command.

## [3.6.5] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.5.md`](docs/releases/RELEASE_NOTES_v3.6.5.md).

### Added

- **Syntax Doctor:** `windo syntax doctor [query]` and `windo syntax --doctor [query]` classify intent matches as exact, single-match, ambiguous, no-match, or ready, then return safe next commands without executing privileged work.

### Changed

- **Quieter release runway:** `windo roadmap`, README, schema docs, and the roadmap doc now focus on shipped 3.x work and V4 preparation while keeping future major-package details reserved.
- **Syntax Forge completion:** tab completion now suggests `doctor` and `--doctor` for `windo syntax`.

## [3.6.4] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.4.md`](docs/releases/RELEASE_NOTES_v3.6.4.md).

### Added

- **Release runway: Source of Truth:** `windo source` reports the installed version, published installer source, published installer version, published checksum source, local snapshot hash/version, and whether the local snapshot matches the published checksum.

### Changed

- **API-first installer download:** `bootstrap.ps1` and `windo install-latest` now fetch `windo_install.ps1` through the GitHub Contents API first, with raw branch content as fallback. This aligns installer download behavior with the checksum hardening added in v3.6.2 and avoids stale raw-CDN installer pulls after sync.
- **Bootstrap identity:** the web bootstrap banner now reflects the current release train and API-first source behavior instead of the old v3.3.0 label.

## [3.6.3] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.3.md`](docs/releases/RELEASE_NOTES_v3.6.3.md).

### Fixed

- **Help dispatch:** `windo /?`, `windo --help`, and other global help forms now defer rendering until `_windo_show_help` and `_windo_set_exit` are defined, fixing the runtime error where `_windo_show_help` was not recognized.

### Changed

- **Syntax-aware tab completion:** the native WINDO argument completer now includes command-specific syntax suggestions for common built-ins such as `trust --online`, `completion native-first`, `recipes preview`, `launchpad --tray`, `dashboard --html`, `modules verify`, `extras fetch`, and `install-latest --force`.

## [3.6.2] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.2.md`](docs/releases/RELEASE_NOTES_v3.6.2.md).

### Changed

- **Checksum source hardening:** bootstrap, `windo install-latest`, and `windo trust --online` now prefer the GitHub Contents API for `checksums/installer.sha256`, with raw branch content as fallback. This avoids false mismatch reports when `raw.githubusercontent.com/Genesis` is temporarily stale after a push.
- **Trust Console detail:** `windo trust --online` now reports the checksum source (`github-api` or `raw-fallback`) alongside the published SHA256.

## [3.6.1] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.1.md`](docs/releases/RELEASE_NOTES_v3.6.1.md).

### Added

- **Release runway: Execution Plan:** `windo explain <command...>` now shows the expected route, privilege boundary, network use, local file impact, audit behavior, checksum posture, preflight checks, and exact next commands before anything runs. Use `windo explain -- <external command...>` when the target command has flags that should be explained rather than consumed as WINDO global options.

### Changed

- **Syntax Forge hardening:** the planner surface now connects intent discovery (`windo syntax`) with command execution safety (`windo explain`), giving operators a read-only path from "what should I run?" to "what will WINDO do?" before elevation.

## [3.6.0] - 2026-05-04

Release notes: [`docs/releases/RELEASE_NOTES_v3.6.0.md`](docs/releases/RELEASE_NOTES_v3.6.0.md).

### Added

- **Release runway: completion control surface:** `windo completion` now reports and persists the WINDO argument-completion mode. Modes are `native-first` (default), `hybrid`, `windo`, `off`, plus `reset`; `WINDO_COMPLETION_MODE` can override prefs for the current process.
- **Release runway: release-train surface:** `windo roadmap` / `windo roadmap --json` now ships the planned sub-version sequence from 3.4.0 through the reserved future-major marker, backed by [`docs/v5-roadmap.md`](docs/v5-roadmap.md).
- **Release runway: Trust Console:** `windo trust` scores local trust posture from scheduled tasks, runner/updater integrity, audit-chain verification, profile state, completion policy, and installer snapshot hash. `windo trust --online` compares the local installer snapshot against the published checksum from a non-elevated shell using the same line-ending-normalized hash as release tooling.
- **Release runway: Syntax Forge:** `windo syntax [query]` maps common operator intent to exact WINDO commands, preview commands, risk notes, and aliases without executing anything privileged.
- **Release runway: recipe previews:** `windo recipes preview <name>` and recipe `--dry-run` now return the exact elevated command, risk note, and run/preview commands without touching scheduled tasks, request files, result files, or audit logs.

### Changed

- **Native-first tab completion:** the profile completer now registers as a native argument completer and delegates non-WINDO input after the `windo` prefix to PowerShell completion. `windo Get-Ch<Tab>` behaves like `Get-Ch<Tab>`, while `windo key<Tab>` still completes WINDO built-ins.
- **Configuration visibility:** `windo config --json` now includes `completionPolicy`, and text output includes the effective `WINDO_COMPLETION_MODE`.
- **Release identity:** bumped to **v3.6.0** because the 3.4 Quiet Shell, 3.5 Trust Console, and 3.6 Syntax Forge runway features are now shipped in the main installer.

## [3.3.0] - 2026-05-01

Release notes: [`docs/releases/RELEASE_NOTES_v3.3.0.md`](docs/releases/RELEASE_NOTES_v3.3.0.md).

### Added

- **Command Center install/update visuals:** `bootstrap.ps1`, **`windo install-latest`**, and the installer now show a WINDO banner plus step-by-step status cards for download, checksum, UAC handoff, secure-dir hardening, task registration, manifest write, profile refresh, and snapshot write.
- **`windo preflight`** — read-only readiness scan with fix commands for non-elevated update posture, PowerShell runtime, scheduled tasks, runner integrity, audit-chain verification, profile block, and keybinding policy. Supports **`--json`**.
- **`windo launchpad`** — Command center with terminal, **`--json`**, **`--html`**, **`--open`**, and **`--tray`** modes.
- **Native tray launchpad:** **`windo launchpad --tray`** writes a local tray-agent script under **`.pwsh_secure`**, starts it hidden with Windows Forms, shows the WINDO tray icon when **`brand/Enterprise`** assets are present (or a Windows shield fallback), and exposes menu/window actions that open visible PowerShell command windows.
- **Enterprise brand pack:** **`brand/Enterprise/`** now carries clean transparent PNG/SVG/ICO assets, a manifest, and a contact sheet for docs, tray icons, badges, and future UI surfaces.

### Changed

- **Release identity:** bumped to **v3.3.0** for the command-center feature release.
- **Version snapshots:** **`tools/Sync-VersionSnapshot.ps1`** now copies **`brand/Enterprise/`** so release markdown images and tray assets stay with the frozen release tree.

## [3.2.8] - 2026-05-01

### Added

- **`windo dashboard`** — operator health dashboard for task presence, runner integrity, audit-chain verification, audit categories, recent audit entries, and local paths. Supports terminal output, **`--json`**, **`--html`**, **`-o` / `--output`**, and **`--open`**.
- **Reusable audit-chain verifier:** **`windo verify`** now uses the shared verifier used by **`windo dashboard`**, returning consistent JSON fields (**`error`**, **`failureLine`**) on failures.

### Changed

- **`windo report`** local HTML now has summary cards and category bars for faster visual triage.
- **Validation / release guardrails:** maintainer validation covers the normalized published installer checksum path so checksum drift is caught before publishing.

## [3.2.7] - 2026-04-13

### Added

- **`windo repair`** / **`windo repair keybindings`** — runs the same **keybindings safe-reset** as **`windo keybindings safe-reset`** (Alt+w, legacy WINDO PSReadLine chords removed in-session) and prints recovery hints (**`. $PROFILE`**, non-elevated **`windo install-latest`**). JSON payload **`command`:** **`repair`**.
- **Bundled local uninstaller:** installer now writes **`%USERPROFILE%\.pwsh_secure\windo_uninstall.ps1`** and snapshots it under **`Documents\windo\`**. **`windo uninstall`** prefers the local copy, **`windo remove`** is an explicit alias, and the profile adds **`windo-uninstall`** / **`windoremove`** helpers for direct removal.

### Fixed

- **Installer SHA256 verification:** [`bootstrap.ps1`](bootstrap.ps1) and **`windo install-latest`** (via **`_windo_verify_installer_sha256_optional`**) now fetch [`checksums/installer.sha256`](checksums/installer.sha256) with **`Invoke-WebRequest`** and extract the **first 64 hex** characters from the response. This matches one-line files, optional BOM/whitespace, and `sha256sum`-style lines, avoiding false **checksum mismatch** failures when the published file differs slightly in format from a bare 64-character line. **[`checksums/installer.sha256`](checksums/installer.sha256)** is updated to match the current **`windo_install.ps1`** bytes so verification succeeds after release edits.
- **Stats time filter (tests + parity):** [`Invoke-WindoFilterAuditEntriesByTime`](src/windo/snippets/StatsTimeFilter.ps1) and **`_windo_filter_entries_by_time`** in the installer now return a **single-element array** correctly (PowerShell no longer unwraps a one-entry result to a bare object), so **`windo stats`** filtering matches the intended entry list.
- **Profile cleanup during uninstall:** [`windo_uninstall.ps1`](windo_uninstall.ps1) no longer creates empty profile files during removal and now strips WINDO marker blocks from the known **current-user** PowerShell profiles, not just the active host profile.

## [3.2.6] - 2026-04-13

### Added

- **Ollama / local inference (Track A):** [`docs/ai-bridge.md`](docs/ai-bridge.md) — **Ollama on Windows** section (defaults, **`OLLAMA_HOST`**, elevation vs interactive CLI).
- **`windo ai`:** extends env snapshot with **Ollama-related names** (`OLLAMA_HOST`, `OLLAMA_MODELS`, etc.); **`ollamaSetNames`** / **`ollamaAdvisory`** in JSON; **`doctor`** adds **`OLLAMA_HOST`** hints (unset = local default; non-loopback / `0.0.0.0` = advisory). Cloud API key warnings no longer treat Ollama-only vars as secrets.
- **Recipes:** **`ollama-version`**, **`ollama-ps`**, **`ollama-list`** (read-only; requires **`ollama.exe`** on PATH).

### Changed

- **[`docs/json-schema.md`](docs/json-schema.md):** **`ai`** payload documents Ollama fields (**v3.2.6+**).

## [3.2.5] - 2026-04-13

### Added

- **`windo ai status`** / **`windo ai doctor`** — read-only snapshot of common vendor API-key **environment variable names** across Process, User, and Machine scope (**values are never emitted**). **`doctor`** adds recommendations and may set **`payload.exitCode` `3`** when policy issues are detected (elevated process with secrets; system-wide env). Does **not** call remote inference APIs or store keys.
- **Operator + security docs:** [`docs/ai-bridge.md`](docs/ai-bridge.md); [`SECURITY.md`](SECURITY.md) section **AI tooling and API keys**; [`docs/json-schema.md`](docs/json-schema.md) **`ai`** payload; [`docs/framework-wave.md`](docs/framework-wave.md) “after the wave” pointer.

### Changed

- **[`tools/Sync-VersionSnapshot.ps1`](tools/Sync-VersionSnapshot.ps1):** includes **`docs/ai-bridge.md`** in release snapshots; **[`docs/build.md`](docs/build.md)** lists it.

## [3.2.4] - 2026-04-13

### Added

- **Documentation:** [`docs/framework-wave.md`](docs/framework-wave.md) — canonical in-repo checklist mapping the **composable shell companion** wave (Tier 1–3: modules, recipes, prompt, extras, dev scaffolding, session, keybindings doctor) to shipped commands, paths, and related docs ([`modules-and-extras.md`](docs/modules-and-extras.md), [`json-schema.md`](docs/json-schema.md), [`SECURITY.md`](SECURITY.md)).

### Changed

- **[`docs/modules-and-extras.md`](docs/modules-and-extras.md):** links to the framework-wave doc at the top.
- **[`tools/Sync-VersionSnapshot.ps1`](tools/Sync-VersionSnapshot.ps1):** includes **`docs/framework-wave.md`** in the frozen **`versions/vX.Y.Z/`** tree; **[`docs/build.md`](docs/build.md)** version-snapshot section lists it.

## [3.2.3] - 2026-04-13

### Added

- **Maintainer tooling:** [`tools/Sync-VersionSnapshot.ps1`](tools/Sync-VersionSnapshot.ps1) copies a frozen release tree into **`versions/vX.Y.Z/`** — **`windo_install.ps1`**, **[`checksums/installer.sha256`](checksums/installer.sha256)**, **[`README.md`](README.md)**, **[`SECURITY.md`](SECURITY.md)**, **[`CHANGELOG.md`](CHANGELOG.md)**, **[`docs/json-schema.md`](docs/json-schema.md)** / **[`docs/build.md`](docs/build.md)** / **[`docs/modules-and-extras.md`](docs/modules-and-extras.md)**, and **`extras/`** (index + sample module).

### Changed

- **[`docs/build.md`](docs/build.md):** documents the **version snapshot** workflow (when to refresh **`checksums/installer.sha256`**, then run **`Sync-VersionSnapshot.ps1`**).
- **[`tools/Invoke-PSScriptAnalyzer.ps1`](tools/Invoke-PSScriptAnalyzer.ps1):** includes **`Sync-VersionSnapshot.ps1`** in the Error-severity pass.
- **[`tools/Test-WindoLogic.ps1`](tools/Test-WindoLogic.ps1):** asserts **`build.md`** mentions the snapshot script.

## [3.2.2] - 2026-04-13

### Added

- **`windo export --json`:** after a successful zip write, emits a **CLI envelope** with **`zipPath`**, **`sizeBytes`**, **`redacted`**, **`auditExcerptLimit`**, **`auditTotalEntries`**, **`auditIncludedInExcerpt`**, and **`exitCode`**; archive failures return **`error`** + **`exitCode` 2**.
- **Docs:** [`docs/json-schema.md`](docs/json-schema.md) now documents **`help`** and **`export`** payloads and extends the automation **`exitCode`** table; help topic examples include **`windo help --json`**. [`docs/modules-and-extras.md`](docs/modules-and-extras.md) cross-links those commands in the JSON schema overview.

### Fixed

- **Runner:** invalid nested **`try`** around preserve-environment restore prevented **`windo_runner.ps1`** (and the embedded runner block) from parsing; restore now runs in a single **`finally`** so AST validation passes.

### Changed

- **CI / local lint:** [`tools/Invoke-PSScriptAnalyzer.ps1`](tools/Invoke-PSScriptAnalyzer.ps1) now includes [`tools/Encode-ChildExec.ps1`](tools/Encode-ChildExec.ps1) in the Error-severity pass (maintainer helper for regenerating embedded **`ChildExec`** base64). [`docs/build.md`](docs/build.md) mentions this in the validation list.

## [3.2.1] - 2026-04-13

### Added

- **`windo config` / `--json`:** documents **`WINDO_EXTRAS_INDEX_URL`** and surfaces the resolved extras index URL (**`extrasIndexUrl`** in JSON).
- **Operator doc:** [`docs/modules-and-extras.md`](docs/modules-and-extras.md) describes modules, extras, and the Oh My Posh bridge; linked from the README.
- **JSON schema doc:** [`docs/json-schema.md`](docs/json-schema.md) updated for **`config`** (including **`keybindingPolicy`** / **`extrasIndexUrl`**), **`session`** (**`lastAudit`** / **`recentAudit`**), **`keybindings`** (**`status`** vs **`doctor`**), and **`modules`** / **`recipes`** / **`extras`** / **`dev`** / **`prompt`** payloads; automation **`exitCode`** table extended accordingly.
- **Build doc:** [`docs/build.md`](docs/build.md) adds a **JSON CLI schema** maintainer checklist (code → docs → tests → PR note).
- **`windo keybindings doctor`:** advisory pass that inspects PSReadLine handlers for the effective prefix chord and **`Shift+Enter`** / **`Alt+Enter`** run chords (heuristic only).
- **`windo dev init-module`:** writes a short **`README.md`** next to **`module.json`** / **`Load.ps1`**.
- **`windo session`:** includes **`lastAudit`** and a short **`recentAudit`** tail from the decrypted log for dashboards.

## [3.2.0] - 2026-04-13

### Added

- **Composable shell companion (optional):** **`windo modules`** discovers local folders under **`%USERPROFILE%\Documents\windo\modules`** with **`module.json`** + entry script; **`enable` / `disable`** persist **`enabledModules`** in **`windo_prefs.json`**; **`doctor`** and **`verify`** assist with manifests and optional per-file SHA256 in **`integrity`**. The installer appends a small profile stub that loads enabled modules after the WINDO block (failures are warnings only).
- **Recipes:** bundled named templates via **`windo recipes`**, **`windo recipes run`**, and **`windo run --recipe`** (same elevation path as normal **`windo <cmd>`**).
- **Prompt bridge:** **`windo prompt`** documents Oh My Posh integration; after each successful elevation WINDO sets **`WINDO_LAST_REQUEST_ID`** and **`WINDO_VERSION`** for themes and tooling.
- **Curated extras:** repo **`extras/index.json`** plus **`windo extras search`** / **`windo extras fetch`** (fetch **refused while elevated**; SHA256 enforced when published). Override index URL with **`WINDO_EXTRAS_INDEX_URL`**.
- **Developer scaffold:** **`windo dev init-module`** creates a starter module folder.
- **Session summary:** **`windo session`** combines task presence, integrity levels, and last stored command / **`RequestId`**.

## [3.1.2] - 2026-04-13

### Fixed

- **Embedded profile template:** balanced the nested `if` in the `windo keybindings status` “Effective” line so generated `$PROFILE` blocks parse correctly; keybinding policy objects now declare `appliedChord` so PSReadLine setup does not warn at profile load.
- **Keybinding policy:** the default interactive prefix no longer uses `w,w` by default. A plain `w`-key prefix could make commands that start with `w` (for example `w`, `where`, `winget`, `wsl`, etc.) feel untypeable.
  - Default prefix is now `Alt+w` on all hosts.
  - Auto-detection fallback remains available and now defaults to a non-typing chord (`Alt+;`) to avoid reintroducing `w` capture.
- **Profile repair and legacy cleanup:** installer/profile refresh now removes legacy single-key and historical WINDO key chords (`w`, `w,w`, `Alt+w`, `Shift+Enter`, `Alt+Enter`) before applying current policy, which prevents older profile blocks from re-breaking the `w` key after upgrade.
- **`windo keybindings status`/`set` robustness:** keybinding policy is now normalized consistently for both active session state and persisted profile block.
- **Installer ACL fallback:** same-user installs no longer fail early when Windows refuses ACL tightening on `.pwsh_secure`; WINDO now warns and continues so profile repair and snapshot refresh can still complete.
- **Installer repair mode:** if scheduled-task registration is denied in a non-elevated repair run, WINDO now warns and still refreshes the profile/snapshots so local shell recovery is not blocked behind task registration.

### Added

- **Builtin completion alignment:** `keybindings` is now treated as a built-in command for profile argument-completion and last-command bookkeeping consistency.
- **Sudo-style native execution controls:** added global command flags `--non-interactive` (`-n`), `--preserve-env` (`-E`), and `--timeout` (`-t`) for elevated runs. `--non-interactive` suppresses `install-latest` confirmation prompts for automation; `--preserve-env` snapshots selected process environment variables (or `ALL`) for the elevated child; `--timeout` overrides `WINDO_RUNNER_TIMEOUT_MS` per command.
- **SUDO_* parity knobs:** added `SUDO_TIMEOUT` (default `--timeout` source) and `SUDO_PROMPT` (custom install confirmation text), plus `WINDO_INSTALL_NONINTERACTIVE` compatibility note in install output paths.
- **Runner request propagation:** preserved environment is now carried in the request JSON and reapplied in `windo_runner.ps1` with automatic restore, so sudo-like `--preserve-env` works in elevation without leaking permanent env mutations.
- **Robust help experience:** added `windo help` topic mode and `windo /?`/`windo --help` support with categorized command reference and examples, including global/sudo-like flag guidance.
- **Logic checks for sudo-like payload propagation:** `tools/Test-WindoLogic.ps1` now validates source-level presence of timeout parsing, preserve-environment capture, and runner reapplication code paths to guard regressions during release updates.

## [3.1.1] - 2026-04-01

### Security

- **`windo install-latest` / `windo upgrade`:** the Genesis installer is **not** downloaded while the process is **elevated** (Administrator). Users must run the command from a **non-elevated** shell; after SHA256 verification (when published), an interactive **confirmation** runs before starting the installer. **`--force`**, **`WINDO_INSTALL_NONINTERACTIVE`**, or **`CI`** skips the prompt for automation.
- **`bootstrap.ps1`:** same **no download when elevated** rule; after a verified download, **`Read-Host`** confirms before launching the installer unless **`WINDO_BOOTSTRAP_FORCE_INSTALL`** or **`CI`** is set.

## [3.1.0] - 2026-04-01

### Added

- **`windo install-latest`:** explicit “get current Genesis installer” command (same behavior as **`windo upgrade`**); runs the downloaded script with **`pwsh.exe`** when present, otherwise **`powershell.exe`**.
- **`windo theme`:** sets **CLI JSON envelope presentation** only—**`classic`** (`schemaVersion` **2.6**, no **`meta`**), **`modern`** (**3.0** + **`meta`**), or **`auto`** (follow embedded profile). Preferences persist in **`%USERPROFILE%\.pwsh_secure\windo_prefs.json`**; optional env **`WINDO_JSON_ENVELOPE`** overrides the file. Does **not** downgrade runner, tasks, or audit security.

### Changed

- **`windo upgrade`** is documented as an **alias** of **`install-latest`** (shared implementation).

## [3.0.0] - 2026-04-01

### Added

- **`windo config`:** prints effective optional environment (`WINDO_*`, `CI`) with runner-aligned semantics (timeout ms, per-stream capture derived from `WINDO_RUNNER_MAX_OUTPUT_BYTES`, command length cap). **`--json`** returns structured rows plus `secureDir`.
- **`windo backups`:** lists `windo_history*.enc.bak` under the secure dir (newest first). **`windo backups --prune --keep N --force`** deletes older backups, keeping **N** newest files (destructive; **`--force`** required).
- **JSON schema 3.0:** CLI envelope includes **`meta`** (`psEdition`, `psVersion`, `osVersion`). **`schemaVersion`** is **`3.0`** on v3.0.0+ profiles.
- **`src/windo/snippets/WindoConfigEffective.ps1`:** shared effective-value helpers for tests (mirrors runner/installer).
- **`src/windo/snippets/JsonEnvelope.ps1`:** optional **`meta`**; aligned with v3 envelope.

### Changed

- **Breaking (JSON consumers):** scripts that only accept **`schemaVersion`** **`2.6`** must allow **`3.0`** (or branch on version). Payload layouts for existing commands are unchanged except for the new envelope **`meta`** field.

## [2.9.1] - 2026-04-01

### Added

- **`src/windo/snippets/StatsTimeFilter.ps1`:** shared cutoff + filter helpers (mirrors installer stats time logic); covered by **`tools/Test-WindoLogic.ps1`**.
- **`docs/json-schema.md`:** `stats` and `profile` payload fields, **`payload.exitCode`** table, **`--json`** envelope list includes **`profile`**.

### Changed

- **`windo stats`:** stricter **`--last-days`** handling — value required after the flag, must parse as an integer and be **> 0**; clearer errors; JSON **`filterLastDays`** is omitted unless **`--last-days`** was used.
- **`windo stats --json`:** **`payload.exitCode`** (**0**) for parity with other automation-friendly payloads.

## [2.9.0] - 2026-04-01

### Added

- **`windo profile`:** lists standard profile paths (current host + common pwsh / Windows PowerShell locations) and whether the WINDO block (`# >>> WINDO-BEGIN >>>`) is present; **`--json`** returns structured rows.
- **`windo stats --since YYYY-MM-DD`** and **`windo stats --last-days N`:** filter summarized entries by decrypted audit **`Timestamp`** (mutually exclusive filters).
- **Exit codes for automation:** **`$global:WINDO_EXIT_CODE`** (and **`exitCode`** in JSON for doctor / integrity / verify) with documented meanings (0, 2, 3, 4, 6).
- **`docs/build.md`:** branch **`Genesis`**, **`checksums/installer.sha256`**, and **`Encode-ChildExec.ps1`** / **`ChildExec.cs`** maintenance notes.

## [2.8.0] - 2026-04-01

### Added

- **Runner limits:** configurable timeout (`WINDO_RUNNER_TIMEOUT_MS`) and captured output size (`WINDO_RUNNER_MAX_OUTPUT_BYTES`); result JSON may include `RunnerTimedOut` and `OutputTruncated`. Implementation uses a small embedded C# helper (loaded from base64 in `windo_runner.ps1`).
- **Request validation:** max command length (`WINDO_MAX_COMMAND_CHARS`), control-character rejection, and strict `OutPath` under `.pwsh_secure` matching `windo_res.<id>.json`.
- **`windo log --tail`** with **`--json`:** decrypt only the last N physical log lines (avoids full-file decrypt for large logs).
- **Installer checksum:** [`checksums/installer.sha256`](checksums/installer.sha256) on `Genesis`; `bootstrap.ps1` and `windo upgrade` verify the downloaded `windo_install.ps1` unless `WINDO_SKIP_INSTALLER_SHA256` is set.
- **Documentation:** optional env vars in README and SECURITY; `windo doctor` lists env hint keys in JSON and prints a short env section in text mode.

## [2.7.1] - 2026-04-01

### Changed

- **Console polish:** ASCII spinner on interactive consoles while downloading the installer (`bootstrap.ps1`, `windo upgrade`, `windo uninstall`), while waiting for an elevated result (up to ~20s), and during `windo self-update` polling. Set `WINDO_NO_SPINNER=1`, use redirected output, or CI to keep plain text (no spinner).

## [2.7.0] - 2026-04-08

### Added

- **`windo upgrade`:** downloads latest `windo_install.ps1` from `Genesis` (same contract as `bootstrap.ps1`) so any prior **v2.x** install can refresh without a version check.
- **`windo uninstall`:** downloads `windo_uninstall.ps1` and runs it **elevated** (UAC) to remove scheduled tasks, WINDO profile block, WINDO files under `.pwsh_secure`, and `%USERPROFILE%\Documents\windo\` by default.
- **`windo_uninstall.ps1`:** standalone script with **`-Confirm`**, interactive prompt, and **`-KeepSnapshots`** to preserve `Documents\windo`.

## [2.6.2] - 2026-04-08

### Added

- **Single source for built-in subcommands:** `$WindoBuiltinVerbs` in `windo_install.ps1` drives both profile **tab-completion** skip list (plus `!!`) and **`windo` last-command** exclusions via injected `_windo_builtin_subcommands`.
- **`windo export --redact` / `-Redact`:** best-effort masking of path-like strings in envelope JSON written to the bundle.
- **`docs/performance.md`:** guidance for very large audit logs; warnings when log line count exceeds ~100k for `stats`, `history`, `report`, `export`.
- **CI / quality:** `tools/Test-WindoLogic.ps1`, `tools/Invoke-PSScriptAnalyzer.ps1` (Error severity), `src/windo/snippets/IntegrityLevels.ps1` aligned with installer integrity rules.

### Changed

- **Export:** `Compress-Archive` and zip presence validated; clearer failure messages.
- Installer/profile version **2.6.2**.

## [2.6.1] - 2026-04-01

### Added

- **Delegated tab completion:** when `windo` is the first token, `Register-WindoArgumentCompleter` strips `windo ` and runs `TabExpansion2` on the remainder so `windo git ch<TAB>`, `windo docker …`, etc. can complete like the underlying command. WINDO built-in subcommands (`doctor`, `help`, …) skip delegation so they do not steal completions.

### Changed

- Installer and profile block version **2.6.1**; profile now registers the completer after PSReadLine (additive).

### Notes

- **Preferred workflow unchanged:** type the command first, then `w,w` / `Shift+Enter` / `Alt+Enter` for full native completion reliability. Direct `windo <command>` completion is best-effort and depends on `TabExpansion2` and the host.

## [2.6.0] - 2026-04-01

### Added

- **JSON envelope (schema 2.6):** all `--json` outputs share `schemaVersion`, `windoVersion`, `command`, `generatedAt`, and `payload`. Documented in `docs/json-schema.md`.
- **Integrity levels:** per-component and overall **OK \| DRIFT \| TAMPERED \| UNKNOWN** in `windo integrity`, doctor, version, HTML report, and export bundle.
- **Operator commands:** `windo context`, `windo replay` (alias of `windo !!`), `windo trace <RequestId>` / `windo trace --id`, global **`--dry-run`** for the elevation path (no task, no req/res files, no audit append).
- **Last run metadata:** `windo_last_meta.json` (`commandLine`, `storedAt`, `lastRequestId`) updated when a run completes (including timeout).
- **Reporting:** `windo report` HTML adds summary counts, category breakdown (SUCCESS / NONZERO / ELEVATION_FAILED / OTHER), and integrity-level tables; `windo stats` text shows the same categories.
- **Export:** `windo export [-o zip] [-n N]` creates a zip with manifest copy, `doctor.json`, `integrity.json`, and `audit_excerpt.json` (envelope-wrapped).
- **Maintainability:** `src/windo/` scaffold, `tools/build.ps1` (validate by default; `-Concat` for review-only snippet concat), `docs/build.md` updated.

### Changed

- Installer and embedded `windo` function version **2.6.0**; `firstTok` exclusions extended for new verbs; usage text updated.

### Security

- No change to bootstrap URL pattern, scheduled task names, DPAPI on-disk log line format, or PSReadLine bindings. JSON and export/report content may include sensitive command text; operators must handle files accordingly. Pre-2.6 JSON consumers must migrate to the envelope `payload` field.

## [2.5.0] - 2026-04-01

### Added

- **Operator UX:** `windo help`, `windo last`, `windo stats`, `windo history [-n N]`, `windo report [-o path]` (local HTML audit summary under `%USERPROFILE%\Documents\windo\` by default).
- **Structured output:** append `--json` or `-Json` to `version`, `doctor`, `integrity`, `verify`, `log`, `stats`, `history`, and `last` for script-friendly output.
- **Trust / visibility:** explicit access-denied hints after failed runs; timeout path suggests checking tasks and installer (`_suggest_if_denied`).
- **Maintainability:** `tools/Validate-Windo.ps1` (AST parse all shipping scripts), `docs/build.md` (modularization direction), `docs/branding.md` (admin-focused logo guidance), `.github/workflows/validate.yml`.

### Changed

- Installer and embedded `windo` function version **2.5.0**; usage text and last-command exclusions updated for new subcommands.

### Security

- No change to the elevation model (scheduled tasks, RunLevel Highest), DPAPI logging, hash chain, or manifest semantics. HTML/JSON outputs may contain sensitive command text; operators must handle files accordingly.

## [2.4.0] - 2026-04-01

### Added

- PSReadLine keybindings (after `windo` is loaded in the profile): `w,w` to prefix the current line with `windo `; `Shift+Enter` and `Alt+Enter` to prefix and submit. Skips when the line is empty or already starts with `windo`.
- Repository layout: `versions/v2.3.0/` archive of prior release artifacts; `docs/releases/` for release notes and upgrade snippets.
- `CHANGELOG.md` and `RELEASE_HELPER_v2.4.0.md` for release hygiene.
- Resilient installer snapshot: if `windo_install.ps1` cannot be copied (pathless or in-memory execution), installation continues with a clear warning; other snapshot files are still written.
- Optional `-w` on `windo cleanup` (accepted and ignored; cleanup always backs up the log before clearing).

### Changed

- Version bump to 2.4.0 across installer, manifest, and embedded `windo` function.
- Clearer `windo integrity` and `windo doctor` output and short “what next” hints.
- `windo` last-command storage uses the first token so subcommands like `cleanup -w` and `log -n 10` are not stored as elevated replay targets.
- Bootstrap uses a unique temp installer filename to avoid concurrent-run collisions.

### Security

- No intentional weakening of the elevation model (scheduled task, RunLevel Highest), DPAPI log encryption, SHA256 hash chain, or runner/updater manifest checks.

## [2.3.0] - earlier

- Baseline described in repository history and under `versions/v2.3.0/`.

[3.1.2]: https://github.com/l28bit/windo/compare/v3.1.1...v3.1.2
[3.1.1]: https://github.com/l28bit/windo/compare/v3.1.0...v3.1.1
[3.1.0]: https://github.com/l28bit/windo/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/l28bit/windo/compare/v2.9.1...v3.0.0
[2.9.1]: https://github.com/l28bit/windo/compare/v2.9.0...v2.9.1
[2.9.0]: https://github.com/l28bit/windo/compare/v2.8.0...v2.9.0
[2.8.0]: https://github.com/l28bit/windo/compare/v2.7.1...v2.8.0
[2.7.1]: https://github.com/l28bit/windo/compare/v2.7.0...v2.7.1
[2.7.0]: https://github.com/l28bit/windo/compare/v2.6.2...v2.7.0
[2.6.2]: https://github.com/l28bit/windo/compare/v2.6.1...v2.6.2
[2.6.1]: https://github.com/l28bit/windo/compare/v2.6.0...v2.6.1
[2.6.0]: https://github.com/l28bit/windo/compare/v2.5.0...v2.6.0
[2.5.0]: https://github.com/l28bit/windo/compare/v2.4.0...v2.5.0
[2.4.0]: https://github.com/l28bit/windo/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/l28bit/windo/releases/tag/v2.3.0
