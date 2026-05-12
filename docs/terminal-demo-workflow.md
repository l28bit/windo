# Terminal demo workflow: install, upgrade, repair, history

This concise flow covers install/upgrade/self-update/task repair/history from one terminal.

```powershell
# 1) Fresh install (official path)
iex (irm https://raw.githubusercontent.com/l28bit/windo/Exodus/bootstrap.ps1)
```

```text
[windo] WINDO bootstrap starting...
[windo] Download verified. Temporary file: %TEMP%\windo_install.ps1
[windo] (Prompt) Continue with install? [y/N]:
[windo] Starting installer...
```

```powershell
# 2) Upgrade an existing install (alias: upgrade)
windo install-latest
# Optional alias
windo upgrade
```

```text
[windo] install-latest: download is not performed while running as Administrator.
[windo] Download finished; checksum verified when published on Exodus.
[windo] The installer is ready. You can review the file before continuing: %TEMP%\windo_install.ps1
[windo] Run the installer now? (If approved, this same command relaunches elevated to register tasks.) [y/N]
[windo] Starting installer (pwsh.exe). When it finishes, reload: . $PROFILE
```

```powershell
# 2d) Legacy prompt check: if you see unfamiliar text like `Input content`
Remove-Item Env:SUDO_PROMPT -ErrorAction SilentlyContinue
windo install-latest
```

```text
If WINDO is showing an extra legacy `Read-Host`-style prompt, start from a clean, non-elevated shell (or clear `SUDO_PROMPT`) and rerun.
```

```powershell
# 2c) Contract note: strict mode is opt-in and fail-fast
$env:WINDO_STRICT_INSTALLER_VERIFICATION = 1
windo install-latest --force
```

```text
[windo] strict mode is enabled: checksum/source/branch compatibility mismatches now fail fast.
[windo] Installer path remains the same default branch artifact path on v6.
```

```powershell
# 3) Refresh task actions without downloading anything
windo self-update --dry-run
```

```text
[windo] self-update: dry-run mode
Task: windo-self-update
Would run: task repair for runner + self-update manifest
```

```powershell
# 3b) Apply the self-update task repair
windo self-update
```

```text
[windo] self-update: starting runner task
[windo] Status: SUCCESS
```

```powershell
# 3c) Contract note: repair prompts are interactive-only
$env:CI = 1
windo self-update
```

```text
[windo] self-update: interactive repair confirmation required when run interactively.
[windo] In non-interactive mode (CI), self-update returns repair guidance without prompting.
```

```powershell
# 4) Repair profile/task integration (full)
windo repair all
```

```text
[windo] repair: safe-reset keybindings
[windo] repair: profile and task checks complete
[windo] Next: reload profile + run `windo install-latest` when requested
```

```powershell
# 5) Optional quick checks
windo doctor
windo integrity --json
windo history -n 5
```

```text
Requested 5 history entries (compact view)
1) 2026-05-10T21:00:00-05:00 | windo install-latest | SUCCESS | 148ms
2) 2026-05-10T21:03:12-05:00 | windo self-update   | SUCCESS | 312ms
3) 2026-05-10T21:10:55-05:00 | windo repair all     | SUCCESS | 121ms
```
