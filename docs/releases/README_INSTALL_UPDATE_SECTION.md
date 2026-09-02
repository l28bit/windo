# Canonical Install / Update snippet (README)

Use this block in the main README and keep it identical wherever the one-liner is repeated.

**Install or update** (downloads the current installer from the canonical `jonex/windo-production-ready` branch, runs it from a temp file, then deletes the temp file):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; iex (irm 'https://raw.githubusercontent.com/l28bit/windo/jonex/windo-production-ready/bootstrap.ps1')
```

Notes:

- The one-liner targets **bootstrap only**. The bootstrap script does **not** pipe the full `windo_install.ps1` through `Invoke-Expression`; it saves the installer to disk and runs it with `pwsh.exe` when available, otherwise `powershell.exe -File`.
- Run bootstrap from a standard (non-elevated), interactive shell; installer flows confirm before launch and perform the required UAC handoff.
- The one-liner returns control to the caller and sets `$global:WINDO_EXIT_CODE`. Direct `pwsh -File bootstrap.ps1` execution returns the same native exit code.
- Set `WINDO_SESSION_AUDIT=1` to include elevated handoff correlation metadata in `windo_history.enc` entries.
- Source contract is `jonex/windo-production-ready` by default, with optional overrides via `WINDO_TRACKING_BRANCH` or `WINDO_RELEASE_COMMIT`.
- `windo install-latest` and `windo upgrade` share this same source and checksum contract, including strict-mode fail-fast behavior with `WINDO_STRICT_INSTALLER_VERIFICATION=1`.
- In interactive sessions, `windo install-latest / windo upgrade` prompts before launch (`Run the installer now? ... [y/N]`) and then performs a one-shot elevated handoff attempt (UAC) when confirmed.
- If elevation is blocked, retry from a normal shell, load the existing profile when applicable, and approve UAC:

```powershell
. $PROFILE
windo install-latest
windo self-update
```

- `windo self-update` prompts before installer repair launches in interactive mode and returns a repair recommendation when non-interactive.
- Bootstrap always fails on a published checksum mismatch. A checksum-source outage can continue only when the installer matches the commit-pinned Git blob object.
- Automation flags skip confirmation, not elevation. Headless automation must use separate unprivileged download/verification and trusted local elevated-install stages.
- Offline or repo-clone installs: run `windo_install.ps1` from disk per README.
- From an existing profile: **`windo upgrade`** uses the same installer URL and temp-file pattern as bootstrap (no version gate).
- Full removal: **`windo uninstall`** or elevated **`windo_uninstall.ps1`** (see README).
- For a concise terminal demo with install/upgrade/self-update/task repair/history, use [`terminal-demo-workflow.md`](terminal-demo-workflow.md).
