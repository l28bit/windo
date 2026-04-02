# Release helper — v2.6.1

## Checklist

1. `windo_install.ps1` has `$WindoVersion = "2.6.1"` and header matches.
2. Profile block includes `Register-WindoArgumentCompleter` after PSReadLine; no edits to keybinding chords.
3. Run `tools/Validate-Windo.ps1`.
4. Smoke (interactive pwsh):
   - `. $PROFILE`
   - `windo version` → 2.6.1
   - `windo git ch<TAB>` (or another tool you have) — completions appear
   - `windo doctor<TAB>` — no delegation to external `doctor` (built-in path)
   - `w,w` / `Alt+Enter` still prefix and run as before
5. Tag `v2.6.1` after merge.

## New in 2.6.1

- `Register-WindoArgumentCompleter` + `TabExpansion2` delegation for direct `windo <command>` lines.

## Test guidance

| Try | Expect |
|-----|--------|
| `windo git ch<TAB>` | Branch / git completions (if git on PATH) |
| `windo docker run --na<TAB>` | Docker completions (if docker completions registered) |
| `windo kubectl get po<TAB>` | kubectl completions (if available) |
| `windo doctor` + Tab | No spurious external command completion for built-in |
