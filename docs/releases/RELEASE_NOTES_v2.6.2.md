# Release notes — WINDO v2.6.2

## Hardening and stability

- **Built-in subcommand names** are defined once in the installer (`$WindoBuiltinVerbs`) and injected into the profile so **delegated tab completion** and **last-command storage** stay aligned.
- **Large audit logs:** commands that decrypt the full log may warn above ~100k lines; see [`docs/performance.md`](../performance.md).
- **Export:** `Compress-Archive` failures are reported explicitly; **`--redact`** / **`-Redact`** masks path-like substrings in JSON payloads (best-effort; still treat bundles as sensitive).

## CI

- **`tools/Test-WindoLogic.ps1`** exercises integrity-level helpers in `src/windo/snippets/IntegrityLevels.ps1`.
- **`tools/Invoke-PSScriptAnalyzer.ps1`** runs **Error**-severity analysis on shipping scripts.

## Upgrade

Elevated `windo_install.ps1` or bootstrap, then `. $PROFILE`. Confirm `windo version` shows **2.6.2**.
