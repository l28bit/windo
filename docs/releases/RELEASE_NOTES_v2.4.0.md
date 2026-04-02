# Release notes — WINDO v2.4.0

**Theme:** Choose elevation before execution — with faster profile UX and safer packaging.

## Summary

WINDO remains a PowerShell-first elevation helper for Windows: you **decide** to elevate before the command runs, using a scheduled-task bridge (`RunLevel Highest`), hidden runner, DPAPI-encrypted audit log, and SHA256 hash-chained entries with manifest-backed integrity for the runner and self-update script.

v2.4.0 adds **optional PSReadLine keybindings** so you can keep typing normally (including tab completion) and only prepend `windo` when you intend to elevate—without requiring `windo` as the first characters on the line.

## What’s new

### PSReadLine keybindings (PowerShell 7 + PSReadLine)

Registered in your profile **inside the same WINDO marker block** as the `windo` function (installer-managed, idempotent):

| Input | Behavior |
|--------|----------|
| `w,w` | Prefix the current buffer with `windo ` (leading indentation preserved). No-op if the line is empty or already starts with `windo`. |
| `Shift+Enter` | Same prefix rules, then submit the line (same idea as Enter after prefixing). |
| `Alt+Enter` | Same as `Shift+Enter` for terminals that do not send a distinct Shift+Enter sequence. |

If PSReadLine is missing or key registration fails, profile load continues with a **warning**; the `windo` function still works when invoked normally.

**Terminal caveat:** Some hosts do not distinguish `Shift+Enter` from a normal newline. If `Shift+Enter` is unreliable, use `Alt+Enter` or type `windo` explicitly.

### Installer and bootstrap

- **Snapshot:** If the installer cannot determine its own path (pathless or in-memory execution), it **skips** copying `windo_install.ps1` into `%USERPROFILE%\Documents\windo\` but still writes runner, self-update script, and manifest, with a **warning** explaining the skip.
- **Bootstrap:** Uses a **unique** temp filename for the downloaded installer to avoid collisions.

### Repository layout

- **`versions/v2.3.0/`** — Frozen copies of v2.3.0-era root files for reference.
- **`docs/releases/`** — Release notes and shared install/update snippets.

### Commands and polish

- **`windo cleanup [-w]`** — `-w` is optional and ignored (cleanup always backs up the log before clearing); unknown arguments are reported.
- **`windo integrity` / `windo doctor`** — Clearer labels and short next-step hints (behavior unchanged).

## Upgrade from 2.3.x

1. Pull or download current `windo_install.ps1` (or run bootstrap).
2. Run the installer **elevated** once so tasks and `%USERPROFILE%\.pwsh_secure\` stay consistent.
3. Restart the shell or `. $PROFILE`.
4. Run `windo version`, `windo doctor`, `windo integrity`.

## Security model (unchanged)

- Elevation via scheduled tasks for the interactive user with **RunLevel Highest**.
- Runner executes elevated work without weakening UAC boundaries beyond that deliberate path.
- Local audit log: DPAPI (Current User), SHA256 per entry, optional `windo verify` chain check.
- Runner and self-update script hashes recorded in `windo_manifest.json`; `windo integrity` compares on-disk files to the manifest.

See [`SECURITY.md`](../../SECURITY.md) at the repo root.
