# Canonical Install / Update snippet (README)

Use this block in the main README and keep it identical wherever the one-liner is repeated.

**Install or update** (downloads the current installer from the canonical `Exodus` branch, runs it from a temp file, then deletes the temp file):

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/Exodus/bootstrap.ps1)
```

Notes:

- The one-liner targets **bootstrap only**. The bootstrap script does **not** pipe the full `windo_install.ps1` through `Invoke-Expression`; it saves the installer to disk and runs it with `pwsh.exe` when available, otherwise `powershell.exe -File`.
- Run bootstrap from a standard (non-elevated) shell; installer flows confirm before launch in interactive sessions.
- Set `WINDO_SESSION_AUDIT=1` to include elevated handoff correlation metadata in `windo_history.enc` entries.
- Source contract is `Exodus` by default, with optional overrides via `WINDO_TRACKING_BRANCH` or `WINDO_RELEASE_COMMIT`.
- `windo install-latest` and `windo upgrade` share this same source and checksum contract, including strict-mode fail-fast behavior with `WINDO_STRICT_INSTALLER_VERIFICATION=1`.
- In interactive sessions, `windo install-latest / windo upgrade` prompts before launch (`Run the installer now? ... [y/N]`) and then performs a one-shot elevated handoff attempt (UAC) when confirmed.
- If elevation is blocked, retry with one of the following:

```powershell
Start-Process pwsh.exe -Verb RunAs -ArgumentList '-NoProfile','-Command','windo install-latest'
windo self-update
```

- `windo self-update` prompts before installer repair launches in interactive mode and returns a repair recommendation when non-interactive.
- Compatibility mode remains default for checksum/source/branch drift; non-strict mode warns and continues, strict mode fails fast on mismatch.
- Offline or repo-clone installs: run `windo_install.ps1` from disk per README.
- From an existing profile: **`windo upgrade`** uses the same installer URL and temp-file pattern as bootstrap (no version gate).
- Full removal: **`windo uninstall`** or elevated **`windo_uninstall.ps1`** (see README).
- For a concise terminal demo with install/upgrade/self-update/task repair/history, use [`terminal-demo-workflow.md`](terminal-demo-workflow.md).
