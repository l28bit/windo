# Release helper — v2.6.2

## Checklist

1. `$WindoVersion = "2.6.2"` and `$WindoBuiltinVerbs` includes every non-elevated `windo` subcommand.
2. `./tools/Validate-Windo.ps1`, `./tools/Test-WindoLogic.ps1`, `./tools/Invoke-PSScriptAnalyzer.ps1` (after `Install-Module PSScriptAnalyzer`).
3. Smoke: `windo export --redact`, large-log warning (optional), `windo git <TAB>` still delegates.
4. Archive: `versions/v2.6.2/` contains frozen copies of root scripts + docs per repo discipline.
5. Tag `v2.6.2`.
