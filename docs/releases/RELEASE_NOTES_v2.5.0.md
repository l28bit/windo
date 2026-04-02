# Release notes — WINDO v2.5.0

## Summary

v2.5.0 strengthens **operator experience**, **visibility**, and **repository hygiene** while keeping the same elevation model: **choose elevation before execution.**

## New commands

| Command | Description |
|--------|-------------|
| `windo help` | Short usage reference. |
| `windo last` | Show last stored command (no run). |
| `windo stats` | Aggregate stats over the DPAPI audit log. |
| `windo history [-n N]` | Compact history (default N=50). |
| `windo report [-o path]` | Local HTML audit report. |

## JSON output

Append `--json` or `-Json` to supported commands for structured output: `version`, `doctor`, `integrity`, `verify`, `log`, `stats`, `history`, `last`.

## Hints

After failures that look like **access denied** (or task timeout), WINDO may print a short, **non-silent** hint to run `windo doctor` or re-run the installer elevated—without auto-elevating your shell.

## Upgrade

Run the installer elevated (`bootstrap` or `windo_install.ps1`), then `. $PROFILE`. Verify with `windo help` and `windo doctor`.
