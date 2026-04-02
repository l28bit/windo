# Release helper — v2.6.0

## Checklist

1. `windo_install.ps1` has `$WindoVersion = "2.6.0"` and header matches.
2. Run `tools/Validate-Windo.ps1` or `tools/build.ps1`; CI runs `.github/workflows/validate.yml`.
3. Smoke: elevated `.\windo_install.ps1`, then `. $PROFILE`, `windo help`, `windo context`, `windo doctor --json` (confirm envelope), `windo replay --dry-run`, `windo report`, `windo export -n 5`, `windo integrity`.
4. Tag `v2.6.0` after merge.

## New in 2.6.0

- JSON envelope `schemaVersion` **2.6**; migrate scripts to `payload`.
- Integrity levels OK / DRIFT / TAMPERED / UNKNOWN.
- `context`, `replay`, `trace`, `export`, `--dry-run`, `windo_last_meta.json`.
- Enhanced HTML report; `windo export` zip bundle.
- `src/windo/`, `tools/build.ps1`, `docs/json-schema.md`.
