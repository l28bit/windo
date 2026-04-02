# Release notes — WINDO v2.6.1

## Delegated completion for direct invocation

**WINDO v2.6.1** adds **delegated tab completion** when you type `windo` first: a **`Register-WindoArgumentCompleter`** handler strips the leading `windo ` and runs **`TabExpansion2`** on the remainder, so wrapped commands can complete similarly to typing them without the prefix (e.g. `windo git ch<TAB>`, `windo docker run --na<TAB>`, `windo kubectl get po<TAB>`).

## Preferred workflow (unchanged)

For the most reliable, administrator-friendly experience:

1. Type the command **normally** (full native tab completion).
2. Elevate at the end with **`w,w`**, **`Shift+Enter`**, or **`Alt+Enter`**.

That model remains **recommended**; v2.6.1 makes **direct** `windo <command>` less awkward when you intentionally lead with `windo`.

## Built-in subcommands

Completions are **not** delegated when the first token after `windo` is a WINDO built-in (`help`, `doctor`, `last`, `stats`, …) so the wrapper does not steal those lines from external tools.

## Requirements and limits

- Requires **`TabExpansion2`** (standard in Windows PowerShell 5.1 and PowerShell 7+). If it is unavailable, registration is skipped and a **warning** is shown once.
- Behavior can vary by **terminal** and **PSReadLine** version; see README for caveats on `Shift+Enter`.

## Upgrade

Run the installer elevated, then `. $PROFILE`. Verify `windo version` shows **2.6.1** and try `windo git ch<TAB>` in your usual shell.
