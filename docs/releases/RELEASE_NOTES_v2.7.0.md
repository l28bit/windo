# Release notes — WINDO v2.7.0

## Upgrade from any v2.x

- **`windo upgrade`** downloads the current [`windo_install.ps1`](https://raw.githubusercontent.com/l28bit/windo/Genesis/windo_install.ps1) and runs it the same way as **`bootstrap.ps1`** (temp file, `powershell.exe -File`, no `iex` on the full installer).
- Reload your profile after the installer finishes: **`. $PROFILE`**.

## Full removal

- **`windo uninstall`** pulls [`windo_uninstall.ps1`](https://raw.githubusercontent.com/l28bit/windo/Genesis/windo_uninstall.ps1) and starts an **elevated** uninstall (UAC). It removes **WindoElevatedRunner** / **WindoSelfUpdate**, strips the WINDO block from the **current** `$PROFILE`, deletes WINDO files under **`.pwsh_secure`**, and removes **`%USERPROFILE%\Documents\windo\`** unless you use the standalone script’s **`-KeepSnapshots`**.
- For **pwsh** and **Windows PowerShell** both, you may need to run uninstall **per host** (or remove the second profile block manually)—same scope as install.

## Repository

- Root **`windo_uninstall.ps1`** is the same script served from `Genesis` for raw downloads.
