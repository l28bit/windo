# Canonical Install / Update snippet (README)

Use this block in the main README and keep it identical wherever the one-liner is repeated.

**Install or update** (downloads the current installer from the default branch, runs it from a temp file, then deletes the temp file):

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/v6/bootstrap.ps1)
```

Notes:

- The one-liner targets **bootstrap only**. The bootstrap script does **not** pipe the full `windo_install.ps1` through `Invoke-Expression`; it saves the installer to disk and runs it with `powershell.exe -File`.
- Run bootstrap from an elevated session when you want the installer to register scheduled tasks and write `%USERPROFILE%\.pwsh_secure\` without elevation prompts inside the installer flow (follow README guidance).
- Offline or repo-clone installs: run `windo_install.ps1` from disk per README.
- From an existing profile: **`windo upgrade`** uses the same installer URL and temp-file pattern as bootstrap (no version gate).
- Full removal: **`windo uninstall`** or elevated **`windo_uninstall.ps1`** (see README).
