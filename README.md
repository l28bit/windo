# WINDO

**Choose elevation before execution.**

WINDO is a PowerShell-first elevation helper for Windows. It gives administrators a **deliberate, auditable** way to request elevation **before** a command runs—instead of improvising after the fact.

---

## Philosophy

Experienced operators treat commands as intent. Elevation should not be accidental. WINDO keeps the workflow explicit:

**intent → choose elevation → execute with authority**

The default GitHub branch for raw URLs is named **`Genisis`** (historical spelling). It is **not** renamed automatically, so existing links keep working.

---

## What WINDO does

- Run `windo <command…>` to send work through a **scheduled task** configured with **RunLevel Highest**.
- Keep a **DPAPI-encrypted** log under `%USERPROFILE%\.pwsh_secure\windo_history.enc` with **SHA256** per entry and a **hash chain** you can verify.
- Ship **runner** and **self-update** scripts whose hashes are recorded in **`windo_manifest.json`**; `windo integrity` detects tamper or drift.

WINDO does **not** bypass Windows security boundaries; it uses a controlled elevation path suitable for administrators who understand UAC and task-based elevation.

---

## Install / Update

**Recommended (GitHub):** downloads [`bootstrap.ps1`](https://raw.githubusercontent.com/l28bit/windo/Genisis/bootstrap.ps1), saves `windo_install.ps1` to a **temp file**, runs it with `powershell.exe -File`, then removes the temp file. The **full installer is not** piped through `Invoke-Expression`.

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/Genisis/bootstrap.ps1)
```

Run from an **elevated** PowerShell session when you want the installer to register scheduled tasks and write `%USERPROFILE%\.pwsh_secure\` without surprises.

**Offline / clone:** run the installer from disk:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\windo_install.ps1
```

Then reload your profile:

```powershell
. $PROFILE
```

Verify:

```powershell
windo doctor
windo version
windo integrity
```

The canonical install snippet is also kept in `docs/releases/README_INSTALL_UPDATE_SECTION.md` for copy/paste consistency across docs.

---

## Commands

| Command | Purpose |
|--------|---------|
| `windo <command…>` | Elevate and run the command via the task bridge. |
| `windo !!` | Re-run the last stored elevated command. |
| `windo self-update` | Trigger the self-update scheduled task (repairs task actions). |
| `windo version` | Version, paths, hashes, task presence. |
| `windo doctor` | Paths, tasks, logs, quick health. |
| `windo integrity` | Compare runner/updater SHA256 to manifest. |
| `windo verify` | Validate encrypted log format and hash chain. |
| `windo log -n N` | Show last N log entries (decrypted). |
| `windo cleanup [-w]` | Back up log to `.pwsh_secure`, clear active log, remove pending req/res JSON. Optional `-w` is accepted for compatibility and ignored. |

---

## PSReadLine keybindings (v2.4.0+)

When **PSReadLine** is available (typical in **PowerShell 7**), the installer registers optional bindings so you can **type normally** and only add `windo` when you mean to:

| Input | Action |
|--------|--------|
| `w,w` | Prefix the current line with `windo ` (no-op if empty or line already starts with `windo`). |
| `Shift+Enter` | Prefix, then **submit** the line. |
| `Alt+Enter` | Same as `Shift+Enter` if your terminal does not send Shift+Enter reliably. |

**Note:** Some terminals do not distinguish `Shift+Enter` from a normal newline. If that happens, use **`Alt+Enter`** or type `windo` explicitly. Bindings are **skipped** with a warning if PSReadLine is missing; your profile still loads.

---

## Security model

- **Elevation:** scheduled tasks for the current user, **RunLevel Highest**; runner runs hidden (`pwshw.exe` if present, else `powershell.exe` with hidden window).
- **Audit:** DPAPI (Current User), SHA256 per line, **PreviousHash** chain; `windo verify` checks the chain.
- **Integrity:** `windo_manifest.json` stores expected SHA256 for runner and self-update; **`windo integrity`** compares disk to manifest.

See [`SECURITY.md`](SECURITY.md) for expectations and reporting.

---

## Execution flow

```text
You type windo …
        →
scheduled task starts hidden runner
        →
elevated command runs
        →
result returned; encrypted audit line appended
```

---

## Version archive in this repository

- **Repository root** — current release scripts and docs (`windo_install.ps1`, `bootstrap.ps1`, etc.).
- **`versions/vX.Y.Z/`** — frozen copies of older release files (e.g. [`versions/v2.3.0/`](versions/v2.3.0)) for reference and diffing.
- **`docs/releases/`** — release notes and shared snippets.

---

## Local snapshot

After install, a copy of deployment artifacts is kept under:

`%USERPROFILE%\Documents\windo\`

If the installer could not snapshot itself (pathless execution), other files may still be present; see the installer warning.

---

## Credits

WINDO was conceived and built by Chris Jones. Development and hardening include collaborative work with AI assistance, with emphasis on security, auditability, and deliberate elevation for administrators.

---

## License

MIT License — see [`LICENSE`](LICENSE).
