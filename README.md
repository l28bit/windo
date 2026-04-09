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

**Upgrade from any installed v2.x** (same mechanism as bootstrap): after WINDO is loaded in your profile, run:

```powershell
windo upgrade
```

Or use the bootstrap one-liner above, or run `.\windo_install.ps1` from a clone. There is no version gate: the installer replaces the WINDO profile block and refreshes secure-dir artifacts.

**Remove WINDO completely:** run **`windo uninstall`** (downloads the uninstaller from `Genisis`, then starts an **elevated** session—approve UAC). Or run [`windo_uninstall.ps1`](windo_uninstall.ps1) elevated; optional **`-KeepSnapshots`** keeps `%USERPROFILE%\Documents\windo\`. Only the **current** host’s `$PROFILE` is edited; if you use both **pwsh** and **Windows PowerShell**, run uninstall once per shell or strip the second profile manually.

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
| `windo help` | Short usage reference. |
| `windo <command…>` | Elevate and run the command via the task bridge. |
| `windo !!` / `windo replay` | Re-run the last stored elevated command (`replay` is the explicit name). |
| `windo last` | Show the last stored command text and optional metadata (no execution). |
| `windo context [--json]` | One-screen environment summary (version, paths, tasks, last `RequestId` when known). |
| `windo trace <RequestId>` / `windo trace --id <id>` | Find a decrypted audit entry by `RequestId`. |
| `windo stats` | Summarize the encrypted audit log (counts, categories, optional avg duration). |
| `windo history [-n N]` | Compact recent commands (default last 50). |
| `windo report [-o path]` | Write a local HTML audit report with summary, categories, and integrity levels. |
| `windo export [-o zip] [-n N] [--redact]` | Zip bundle: manifest copy, `doctor.json` / `integrity.json` (envelope JSON), last N audit entries. Optional **`--redact`** masks path-like strings in JSON. |
| `windo self-update` | Trigger the self-update scheduled task (repairs task actions). |
| `windo version` | Version, paths, hashes, task presence, integrity levels. |
| `windo doctor` | Paths, tasks, logs, quick health, last `RequestId` when known. |
| `windo integrity` | Runner vs manifest with levels **OK \| DRIFT \| TAMPERED \| UNKNOWN**. |
| `windo verify` | Validate encrypted log format and hash chain. |
| `windo log -n N [--tail] [--json]` | Show last N log entries (decrypted). **`--tail`** with **`--json`** reads only the last N **physical** log lines (faster on large logs). |
| `windo stats [--since YYYY-MM-DD] [--last-days N]` | Audit log summary; optional filters on decrypted entry **`Timestamp`** (still scans full log to decrypt). |
| `windo profile [--json]` | Show known profile paths and whether the WINDO profile block is present (pwsh and Windows PowerShell paths). |
| `windo cleanup [-w]` | Back up log to `.pwsh_secure`, clear active log, remove pending req/res JSON. Optional `-w` is accepted for compatibility and ignored. |
| `windo upgrade` | Download and run the latest `windo_install.ps1` from `Genisis` (same as bootstrap). |
| `windo uninstall` | Download and run the elevated uninstaller (removes tasks, profile block, WINDO files under `.pwsh_secure`, optional `Documents\windo`). |

Append **`--json`** or **`-Json`** to supported commands for structured output. WINDO **v2.6.0+** wraps payloads in a shared envelope (`schemaVersion`, `windoVersion`, `command`, `generatedAt`, `payload`). See [`docs/json-schema.md`](docs/json-schema.md).

Append **`--dry-run`** (or **`-DryRun`**) on elevated commands or `windo replay` / `windo !!` to print what would run **without** starting the task, writing req/res files, or appending the audit log. **`windo self-update --dry-run`** prints that the update task would be started only.

---

## PSReadLine keybindings (v2.4.0+)

When **PSReadLine** is available (typical in **PowerShell 7**), the installer registers optional bindings so you can **type normally** and only add `windo` when you mean to:

| Input | Action |
|--------|--------|
| `w,w` | Prefix the current line with `windo ` (no-op if empty or line already starts with `windo`). |
| `Shift+Enter` | Prefix, then **submit** the line. |
| `Alt+Enter` | Same as `Shift+Enter` if your terminal does not send Shift+Enter reliably. |

**Note:** Some terminals do not distinguish `Shift+Enter` from a normal newline. If that happens, use **`Alt+Enter`** or type `windo` explicitly. Bindings are **skipped** with a warning if PSReadLine is missing; your profile still loads.

### Direct `windo <command>` tab completion (v2.6.1+)

If you **start the line with `windo`**, the installer registers **`Register-WindoArgumentCompleter`**: it detects a leading `windo `, strips it, and delegates completion to **`TabExpansion2`** on the rest of the line. That lets examples like `windo git ch<TAB>` or `windo kubectl get po<TAB>` behave more like typing the underlying command alone.

**Preferred workflow is still** to type the command **without** `windo`, use **native tab completion**, then add elevation with **`w,w`**, **`Shift+Enter`**, or **`Alt+Enter`**—that path remains the most reliable across hosts and terminals.

**Limitations (honest):** delegation depends on **`TabExpansion2`** and the interactive host. It does not run for WINDO built-in subcommands (e.g. `windo doctor`, `windo help`) so those are not mis-completed as external tools. Partial first tokens that are ambiguous (`doc` vs `doctor` vs `docker`) may complete like a bare command line; use the preferred workflow when precision matters. If **`TabExpansion2`** is missing, registration is skipped with a warning.

---

## Security model

- **Elevation:** scheduled tasks for the current user, **RunLevel Highest**; runner runs hidden (`pwshw.exe` if present, else `powershell.exe` with hidden window).
- **Audit:** DPAPI (Current User), SHA256 per line, **PreviousHash** chain; `windo verify` checks the chain.
- **Integrity:** `windo_manifest.json` stores expected SHA256 for runner and self-update; **`windo integrity`** compares disk to manifest and reports **OK**, **DRIFT**, **TAMPERED**, or **UNKNOWN** per component and overall.

See [`SECURITY.md`](SECURITY.md) for expectations and reporting.

### Optional environment variables

| Variable | Purpose |
|----------|---------|
| `WINDO_NO_SPINNER` | Set to any value to disable console spinners (redirect-safe logs). |
| `WINDO_RUNNER_TIMEOUT_MS` | Max wait for the elevated child process (default **7200000** ms = 2 h; max **86400000**). |
| `WINDO_RUNNER_MAX_OUTPUT_BYTES` | Approximate cap on captured stdout+stderr (default **4194304**; split per stream in the runner). |
| `WINDO_MAX_COMMAND_CHARS` | Max length of the command line passed to `cmd.exe` (default **8191**). |
| `WINDO_SKIP_INSTALLER_SHA256` | Set to skip comparing downloaded `windo_install.ps1` to [`checksums/installer.sha256`](checksums/installer.sha256) on the `Genisis` branch (`bootstrap.ps1` and `windo upgrade`). |

**Automation exit codes (`$global:WINDO_EXIT_CODE`):** set after **`windo doctor`**, **`windo integrity`**, and **`windo verify`** (also exposed as **`exitCode`** in JSON payloads where applicable).

| Code | Typical meaning |
|------|-----------------|
| 0 | Success / OK |
| 2 | Doctor: main task or runner missing; verify: no log or empty log; stats: bad `--since` / conflicting filters |
| 3 | Doctor or integrity: manifest/hash state not OK (DRIFT/TAMPERED) |
| 4 | Verify: hash chain or format failure |
| 6 | Doctor or integrity: UNKNOWN component level |

Scripts: run `windo doctor` (or `integrity` / `verify`), then test **`$global:WINDO_EXIT_CODE`**.

---


## Reporting and automation

- **`windo report`** produces a **local HTML** summary (entry counts, category breakdown, integrity levels, recent audit lines). Treat reports as **sensitive**; they may echo elevated command text.
- **`windo export`** builds a **zip** under `Documents\windo\exports\` (or `-o`) with manifest, envelope JSON, and a truncated audit excerpt—handle as sensitive.
- **`--json` / `-Json`** uses the **v2.6 envelope** for `doctor`, `integrity`, `version`, `verify`, `log`, `stats`, `history`, `last`, `context`, and `trace`. See [`docs/json-schema.md`](docs/json-schema.md).
- **`windo stats`** / **`windo history`** give fast situational awareness without full `log` verbosity.

- Maintainer notes: [`docs/build.md`](docs/build.md) (validation + optional `src/` concat), [`docs/json-schema.md`](docs/json-schema.md), [`docs/performance.md`](docs/performance.md) (large logs), [`docs/branding.md`](docs/branding.md) (logo direction).

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
