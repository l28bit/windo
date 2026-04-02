# Changelog

All notable changes to WINDO are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

[2.5.0]: https://github.com/l28bit/windo/compare/v2.4.0...v2.5.0
[2.4.0]: https://github.com/l28bit/windo/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/l28bit/windo/releases/tag/v2.3.0
