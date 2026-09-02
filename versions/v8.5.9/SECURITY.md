
# Security Policy

## Security Model

WINDO does not bypass Windows security controls.

Elevation is performed using SID-scoped scheduled tasks configured with **RunLevel Highest** for the current user (`WindoElevatedRunner-<identity-scope>` and `WindoSelfUpdate-<identity-scope>`).
Commands execute through a controlled runner which preserves Windows privilege boundaries.

Key protections:

- DPAPI encrypted command history
- SHA256 hash‑chained audit logs
- Runner and updater integrity validation
- Tamper detection diagnostics

Audit logs are stored locally:

%USERPROFILE%\.pwsh_secure\windo_history.enc

## Runner execution and request validation

The elevated **runner** (`windo_runner.ps1`) launches a no-profile PowerShell child matching the caller's supported host (`pwsh.exe` or `powershell.exe`) and passes a validated, encoded execution wrapper with:

- **Invocation fidelity:** the caller's existing filesystem working directory, exact argv (when `windo [global options] -- <target> ...` is used), stdout/stderr, and final exit code are carried across the task boundary.
- **Timeout:** `WINDO_RUNNER_TIMEOUT_MS` (default two hours). If the child does not exit in time, it is terminated and the result JSON includes `RunnerTimedOut`.
- **Output cap:** `WINDO_RUNNER_MAX_OUTPUT_BYTES` bounds captured stdout/stderr (see README). Truncation sets `OutputTruncated` on the result JSON.
- **Command line:** `WINDO_MAX_COMMAND_CHARS` (default 8191) and rejection of control characters (except tab) before execution.
- **Result path:** `OutPath` in each request must stay under `%USERPROFILE%\.pwsh_secure\` and match `windo_res.<hex>.json`. Invalid paths are rejected without writing outside that directory (request is dropped; the interactive client may time out).

Request JSON files under `.pwsh_secure` are writable by the same user as WINDO. DPAPI protects request contents at rest; it does not distinguish between processes running as that same user. Consequently, the scheduled runner is an intentional same-user elevation broker, not an authorization boundary between same-user processes. The checks above limit accidental or malformed use of the runner entrypoint; they are **not** a substitute for endpoint protection, application control, or least-privilege policy elsewhere on the system.

During installation, WINDO attempts to tighten `.pwsh_secure` ACLs to the current user. If Windows denies that ACL rewrite on a same-user install, the installer now warns and continues so profile repair and snapshot refresh can still complete. Re-run the installer elevated once if you need the strict per-user ACL reset applied automatically.

## Bootstrap and upgrade integrity

`bootstrap.ps1`, **`windo install-latest`**, and **`windo upgrade`** (same as install-latest) download `windo_install.ps1` from the canonical **`jonex/windo-production-ready`** branch unless `WINDO_TRACKING_BRANCH` overrides it, or `WINDO_RELEASE_COMMIT` pins a specific commit. That download is **refused while the shell is elevated** (Administrator), so remote content is not fetched under high privilege; run from a normal user PowerShell, confirm after verification, then approve **UAC** for task registration and secure local writes. `WINDO_BOOTSTRAP_FORCE_INSTALL`, `WINDO_INSTALL_NONINTERACTIVE`, and `CI=1` skip confirmation only. They do not suppress required elevation; headless jobs need separate unprivileged verification and trusted local elevated-execution stages.

Hash behavior:

- `WINDO_SKIP_INSTALLER_SHA256=1` disables `windo_install.ps1` checksum checks for both bootstrap and upgrade/install flows.
- Bootstrap always rejects a published installer checksum mismatch. When the checksum endpoint is unavailable, it may continue only if installer bytes match the Git blob object at the already resolved release commit.
- `WINDO_STRICT_INSTALLER_VERIFICATION=1` makes install-latest/upgrade reject their remaining compatibility fallback paths.
- If [`checksums/installer.sha256`](checksums/installer.sha256) is present on the resolved release commit, bootstrap requires the downloaded file's SHA256 to match `installerSha256` exactly.
- `WINDO_SESSION_AUDIT=1` enriches handoff audit entries with request context and caller identity for incident traceability; this is useful when auditing elevated launch attempts (`WindoSelfUpdate`, installer handoff, and similar flows).

Legacy prompt recovery:
- If install/update appears to stop at an unfamiliar legacy prompt (including `Input content`), treat the prompt text as a host wrapper artifact and clear custom prompt text with `Remove-Item Env:SUDO_PROMPT -ErrorAction SilentlyContinue` before re-running in a clean non-elevated shell.

## Self-update path and non-interactive behavior

`windo self-update` runs the current user's SID-scoped `WindoSelfUpdate-<identity-scope>` scheduled task. If the task is missing or blocked, the command can route into an installer repair path:

- In interactive sessions, WINDO prompts before launching the installer repair.
- In non-interactive sessions (`--non-interactive`, `CI`, or non-interactive shell), the repair prompt is skipped and a repair recommendation is returned instead.
- `windo self-update --dry-run` reports the planned repair/task-start behavior and does not execute either.

## Known limitations

- Headless sessions cannot approve UAC; unattended environments need a controlled two-stage download/verification and elevated local execution flow.
- Elevated targets are non-interactive and receive no stdin or console/TTY. Prompt-driven installers, password entry, full-screen programs, and profile-only aliases/functions are unsupported; pass input through arguments or files.

## AI tooling and API keys (v3.2.5+)

WINDO does **not** call OpenAI or other vendor inference APIs from the installer. Optional **`windo ai status`** / **`windo ai doctor`** commands report **which common API-key-related environment variable names** are set in Process / User / Machine scope—**never the values**—so you can avoid carrying secrets in **elevated** shells or **system-wide** env. Do **not** pass API keys through **`windo --preserve-env`** into elevated children. See [`docs/ai-bridge.md`](docs/ai-bridge.md).

## Optional modules and curated extras (v3.2.0+)

- **Local modules:** `windo modules` stores enabled module ids in **`windo_prefs.json`** (`enabledModules`). Module files live under **`%USERPROFILE%\Documents\windo\modules\<id>\`** with a **`module.json`** plus an entry script (default **`Load.ps1`**). The profile stub dot-sources **only** enabled modules **after** the WINDO core block; load failures are non-fatal and emit a warning. This path never performs network fetches.
- **Curated extras index:** the repo may ship **`extras/index.json`** (read-only catalog). **`windo extras search`** downloads the index from the canonical **`jonex/windo-production-ready`** branch (override with **`WINDO_EXTRAS_INDEX_URL`**, also shown in **`windo config`** / **`windo config --json`**). **`windo extras fetch <id>`** downloads the listed artifact to **`%USERPROFILE%\Documents\windo\extras\<id>\`** **only from a non-elevated** interactive shell, verifies **SHA256** when the index publishes it, and refuses the download while **Administrator** (same spirit as **`install-latest`**). Treat catalog entries like any supply-chain input: prefer pinned checksums and review before execution. See also [`docs/modules-and-extras.md`](docs/modules-and-extras.md).

## JSON envelope (v3.0.0+)

`--json` output uses **`schemaVersion`** **`3.0`** and may include **`meta`** (PowerShell edition/version and a host OS version string) unless you set presentation-only **`windo theme classic`** or **`WINDO_JSON_ENVELOPE=classic`** (v3.1.0+). **`meta`** is for diagnostics and automation context only—not a substitute for log redaction when sharing exports. Theme preferences do **not** weaken runner validation, audit logging, or installer checksums.

## Automation exit codes

For **`windo doctor`**, **`windo integrity`**, and **`windo verify`**, WINDO sets **`$global:WINDO_EXIT_CODE`** (and includes **`exitCode`** in JSON payloads where applicable). See the README table for meanings (for example: missing task or runner, integrity state, verify chain failure). This supports non-interactive scripts without relying on parsing human-readable output.

## Reporting Issues

If you discover a vulnerability, please open a private security advisory or contact the maintainer before publishing details.
