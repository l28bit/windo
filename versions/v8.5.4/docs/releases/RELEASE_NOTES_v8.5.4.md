# WINDO v8.5.4 - Generated Profile Prelude

Release date: 2026-05-25

## Summary

WINDO v8.5.4 fixes a generated-profile ordering defect where early command paths could call `_windo_set_exit` before the helper existed in the active `windo` function scope.

## Fixed

- `_windo_set_exit` is now defined at the top of the generated `windo` function before any argument parsing or help/update dispatch can use it.
- `_windo_parse_timeout_override_ms` is also available before timeout flags are parsed.
- The stale early `_windo_set_exit 0` call before helper definition was removed.

## Validation

- Generated installed profile block parses.
- Generated profile helper definitions are checked before first use.
- Runtime smoke invokes low-risk generated `windo` commands in a clean PowerShell process.
