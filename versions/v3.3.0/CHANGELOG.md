# Changelog

All notable changes to WINDO are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **V5 runway: completion control surface:** `windo completion` now reports and persists the WINDO argument-completion mode. Modes are `native-first` (default), `hybrid`, `windo`, `off`, plus `reset`; `WINDO_COMPLETION_MODE` can override prefs for the current process.

### Changed

- **Native-first tab completion:** the profile completer now registers as a native argument completer and delegates non-WINDO input after the `windo` prefix to PowerShell completion. `windo Get-Ch<Tab>` behaves like `Get-Ch<Tab>`, while `windo key<Tab>` still completes WINDO built-ins.
- **Configuration visibility:** `windo config --json` now includes `completionPolicy`, and text output includes the effective `WINDO_COMPLETION_MODE`.

## [3.3.0] - 2026-05-01

Release notes: [`docs/releases/RELEASE_NOTES_v3.3.0.md`](docs/releases/RELEASE_NOTES_v3.3.0.md).

### Added

- **Special Edition install/update visuals:** `bootstrap.ps1`, **`windo install-latest`**, and the installer now show a WINDO banner plus step-by-step status cards for download, checksum, UAC handoff, secure-dir hardening, task registration, manifest write, profile refresh, and snapshot write.
- **`windo preflight`** — read-only readiness scan with fix commands for non-elevated update posture, PowerShell runtime, scheduled tasks, runner integrity, audit-chain verification, profile block, and keybinding policy. Supports **`--json`**.
- **`windo launchpad`** — Special Edition operator command center with terminal, **`--json`**, **`--html`**, **`--open`**, and **`--tray`** modes.
- **Native tray launchpad:** **`windo launchpad --tray`** writes a local tray-agent script under **`.pwsh_secure`**, starts it hidden with Windows Forms, shows the WINDO tray icon when **`brand/Enterprise`** assets are present (or a Windows shield fallback), and exposes menu/window actions that open visible PowerShell command windows.
- **Enterprise brand pack:** **`brand/Enterprise/`** now carries clean transparent PNG/SVG/ICO assets, a manifest, and a contact sheet for docs, tray icons, badges, and future UI surfaces.

### Changed

- **Release identity:** bumped to **v3.3.0** for the Special Edition surface area.
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

- **`windo install-latest` / `windo upgrade`:** the Genisis installer is **not** downloaded while the process is **elevated** (Administrator). Users must run the command from a **non-elevated** shell; after SHA256 verification (when published), an interactive **confirmation** runs before starting the installer. **`--force`**, **`WINDO_INSTALL_NONINTERACTIVE`**, or **`CI`** skips the prompt for automation.
- **`bootstrap.ps1`:** same **no download when elevated** rule; after a verified download, **`Read-Host`** confirms before launching the installer unless **`WINDO_BOOTSTRAP_FORCE_INSTALL`** or **`CI`** is set.

## [3.1.0] - 2026-04-01

### Added

- **`windo install-latest`:** explicit “get current Genisis installer” command (same behavior as **`windo upgrade`**); runs the downloaded script with **`pwsh.exe`** when present, otherwise **`powershell.exe`**.
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
- **`docs/build.md`:** branch **`Genisis`**, **`checksums/installer.sha256`**, and **`Encode-ChildExec.ps1`** / **`ChildExec.cs`** maintenance notes.

## [2.8.0] - 2026-04-01

### Added

- **Runner limits:** configurable timeout (`WINDO_RUNNER_TIMEOUT_MS`) and captured output size (`WINDO_RUNNER_MAX_OUTPUT_BYTES`); result JSON may include `RunnerTimedOut` and `OutputTruncated`. Implementation uses a small embedded C# helper (loaded from base64 in `windo_runner.ps1`).
- **Request validation:** max command length (`WINDO_MAX_COMMAND_CHARS`), control-character rejection, and strict `OutPath` under `.pwsh_secure` matching `windo_res.<id>.json`.
- **`windo log --tail`** with **`--json`:** decrypt only the last N physical log lines (avoids full-file decrypt for large logs).
- **Installer checksum:** [`checksums/installer.sha256`](checksums/installer.sha256) on `Genisis`; `bootstrap.ps1` and `windo upgrade` verify the downloaded `windo_install.ps1` unless `WINDO_SKIP_INSTALLER_SHA256` is set.
- **Documentation:** optional env vars in README and SECURITY; `windo doctor` lists env hint keys in JSON and prints a short env section in text mode.

## [2.7.1] - 2026-04-01

### Changed

- **Console polish:** ASCII spinner on interactive consoles while downloading the installer (`bootstrap.ps1`, `windo upgrade`, `windo uninstall`), while waiting for an elevated result (up to ~20s), and during `windo self-update` polling. Set `WINDO_NO_SPINNER=1`, use redirected output, or CI to keep plain text (no spinner).

## [2.7.0] - 2026-04-08

### Added

- **`windo upgrade`:** downloads latest `windo_install.ps1` from `Genisis` (same contract as `bootstrap.ps1`) so any prior **v2.x** install can refresh without a version check.
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
