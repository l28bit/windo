# Release helper — v2.4.0

Use this checklist when cutting the v2.4.0 release (and as a template for later versions).

## Pre-release

1. **Version strings** — In [`windo_install.ps1`](windo_install.ps1), confirm `$WindoVersion = "2.4.0"` and header comment match.
2. **Installer is source of truth** — Embedded runner and self-update script bodies in `windo_install.ps1` match what gets written to `%USERPROFILE%\.pwsh_secure\`. Root [`windo_runner.ps1`](windo_runner.ps1) and [`windo_self_update.ps1`](windo_self_update.ps1) should mirror those for repository review.
3. **Bootstrap URL** — [`bootstrap.ps1`](bootstrap.ps1) downloads from  
   `https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_install.ps1`  
   (default branch name `Genisis` is intentional for existing raw links).
4. **Docs** — Update [`README.md`](README.md), [`CHANGELOG.md`](CHANGELOG.md), [`docs/releases/RELEASE_NOTES_v2.4.0.md`](docs/releases/RELEASE_NOTES_v2.4.0.md), and sync [`docs/releases/README_INSTALL_UPDATE_SECTION.md`](docs/releases/README_INSTALL_UPDATE_SECTION.md) if the install snippet changes.
5. **Archive** — For the next release, copy the prior release’s root artifacts into `versions/vX.Y.Z/` before overwriting root with the new version.

## Validation (manual)

Run in **elevated** PowerShell (installer requirement):

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& .\windo_install.ps1
```

Then in a **normal** shell:

```powershell
. $PROFILE
windo version
windo doctor
windo integrity
windo verify
```

Confirm PSReadLine bindings if using PowerShell 7 + PSReadLine: `w,w`, `Shift+Enter`, `Alt+Enter` on your terminal; see README for terminal caveats.

## Bootstrap smoke test

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/Genisis/bootstrap.ps1)
```

Confirms download-to-temp, `powershell.exe -File`, and cleanup (not `irm | iex` on the full installer).

## Git

- Tag: `v2.4.0` on the commit that contains the release-ready tree.
- Publish GitHub Release with notes from `docs/releases/RELEASE_NOTES_v2.4.0.md`.
