# Release helper — v2.5.0

## Checklist

1. `windo_install.ps1` has `$WindoVersion = "2.5.0"` and header matches.
2. Run `tools/Validate-Windo.ps1`; CI runs `.github/workflows/validate.yml`.
3. Smoke: elevated `.\windo_install.ps1`, then `. $PROFILE`, `windo help`, `windo doctor --json`, `windo report`, `windo stats`.
4. Tag `v2.5.0` after merge.

## New in 2.5.0

- `last`, `stats`, `history`, `report`, `help`
- JSON output on key diagnostics
- HTML report, access-denied hints, timeout hint
- `tools/Validate-Windo.ps1`, `docs/build.md`, `docs/branding.md`
