
# Security Policy

## Security Model

WINDO does not bypass Windows security controls.

Elevation is performed using a scheduled task configured with **RunLevel Highest** for the current user.
Commands execute through a controlled runner which preserves Windows privilege boundaries.

Key protections:

- DPAPI encrypted command history
- SHA256 hash‑chained audit logs
- Runner and updater integrity validation
- Tamper detection diagnostics

Audit logs are stored locally:

%USERPROFILE%\.pwsh_secure\windo_history.enc

## Runner execution and request validation

The elevated **runner** (`windo_runner.ps1`) executes `cmd.exe /c <command>` with:

- **Timeout:** `WINDO_RUNNER_TIMEOUT_MS` (default two hours). If the child does not exit in time, it is terminated and the result JSON includes `RunnerTimedOut`.
- **Output cap:** `WINDO_RUNNER_MAX_OUTPUT_BYTES` bounds captured stdout/stderr (see README). Truncation sets `OutputTruncated` on the result JSON.
- **Command line:** `WINDO_MAX_COMMAND_CHARS` (default 8191) and rejection of control characters (except tab) before execution.
- **Result path:** `OutPath` in each request must stay under `%USERPROFILE%\.pwsh_secure\` and match `windo_res.<hex>.json`. Invalid paths are rejected without writing outside that directory (request is dropped; the interactive client may time out).

Request JSON files under `.pwsh_secure` are writable by the same user as WINDO. The checks above limit accidental or malicious misuse of the runner entrypoint; they are **not** a substitute for endpoint protection or least-privilege policy elsewhere on the system.

During installation, WINDO attempts to tighten `.pwsh_secure` ACLs to the current user. If Windows denies that ACL rewrite on a same-user install, the installer now warns and continues so profile repair and snapshot refresh can still complete. Re-run the installer elevated once if you need the strict per-user ACL reset applied automatically.

## Bootstrap and upgrade integrity

`bootstrap.ps1`, **`windo install-latest`**, and **`windo upgrade`** (same as install-latest) download `windo_install.ps1` from the **`Genisis`** branch. **v3.1.1+:** that download is **refused while the shell is elevated** (Administrator), so remote content is not fetched under high privilege; run from a normal user PowerShell, confirm after verification, then the installer may prompt **UAC** for task registration. Unattended flows may set **`WINDO_BOOTSTRAP_FORCE_INSTALL`**, **`WINDO_INSTALL_NONINTERACTIVE`**, or **`CI`** as documented in the README. If [`checksums/installer.sha256`](checksums/installer.sha256) is present on that branch, the downloaded file’s SHA256 must match unless **`WINDO_SKIP_INSTALLER_SHA256`** is set. If the checksum file is missing (older branches) or the URL fails, the check is skipped.

## AI tooling and API keys (v3.2.5+)

WINDO does **not** call OpenAI or other vendor inference APIs from the installer. Optional **`windo ai status`** / **`windo ai doctor`** commands report **which common API-key-related environment variable names** are set in Process / User / Machine scope—**never the values**—so you can avoid carrying secrets in **elevated** shells or **system-wide** env. Do **not** pass API keys through **`windo --preserve-env`** into elevated children. See [`docs/ai-bridge.md`](docs/ai-bridge.md).

## Optional modules and curated extras (v3.2.0+)

- **Local modules:** `windo modules` stores enabled module ids in **`windo_prefs.json`** (`enabledModules`). Module files live under **`%USERPROFILE%\Documents\windo\modules\<id>\`** with a **`module.json`** plus an entry script (default **`Load.ps1`**). The profile stub dot-sources **only** enabled modules **after** the WINDO core block; load failures are non-fatal and emit a warning. This path never performs network fetches.
- **Curated extras index:** the repo may ship **`extras/index.json`** (read-only catalog). **`windo extras search`** downloads the index from **`Genisis`** (override with **`WINDO_EXTRAS_INDEX_URL`**, also shown in **`windo config`** / **`windo config --json`**). **`windo extras fetch <id>`** downloads the listed artifact to **`%USERPROFILE%\Documents\windo\extras\<id>\`** **only from a non-elevated** interactive shell, verifies **SHA256** when the index publishes it, and refuses the download while **Administrator** (same spirit as **`install-latest`**). Treat catalog entries like any supply-chain input: prefer pinned checksums and review before execution. See also [`docs/modules-and-extras.md`](docs/modules-and-extras.md).

## JSON envelope (v3.0.0+)

`--json` output uses **`schemaVersion`** **`3.0`** and may include **`meta`** (PowerShell edition/version and a host OS version string) unless you set presentation-only **`windo theme classic`** or **`WINDO_JSON_ENVELOPE=classic`** (v3.1.0+). **`meta`** is for diagnostics and automation context only—not a substitute for log redaction when sharing exports. Theme preferences do **not** weaken runner validation, audit logging, or installer checksums.

## Automation exit codes

For **`windo doctor`**, **`windo integrity`**, and **`windo verify`**, WINDO sets **`$global:WINDO_EXIT_CODE`** (and includes **`exitCode`** in JSON payloads where applicable). See the README table for meanings (for example: missing task or runner, integrity state, verify chain failure). This supports non-interactive scripts without relying on parsing human-readable output.

## Reporting Issues

If you discover a vulnerability, please open a private security advisory or contact the maintainer before publishing details.
