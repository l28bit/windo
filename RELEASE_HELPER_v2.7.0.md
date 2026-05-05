# Release helper — v2.7.0

## Checklist

1. **`windo_uninstall.ps1`** is present at repo root and reachable at `https://raw.githubusercontent.com/l28bit/windo/Genesis/windo_uninstall.ps1` after push.
2. `$WindoVersion = "2.7.0"`; `$WindoBuiltinVerbs` includes `upgrade`, `uninstall`.
3. `tools/Validate-Windo.ps1` and CI pass; `windo upgrade` / `windo uninstall` smoke-tested.
4. Tag **`v2.7.0`**.

## Smoke tests

- `windo upgrade` → installer runs → `. $PROFILE` → `windo version` shows new build.
- `windo uninstall` → UAC → tasks removed → new shell has no `windo` → reinstall via bootstrap works.
