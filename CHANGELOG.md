# Changelog

All notable changes to WINDO are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
