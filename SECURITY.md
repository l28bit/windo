
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

## Bootstrap and upgrade integrity

`bootstrap.ps1` and **`windo upgrade`** download `windo_install.ps1` from the **`Genisis`** branch. If [`checksums/installer.sha256`](checksums/installer.sha256) is present on that branch, the downloaded file’s SHA256 must match unless **`WINDO_SKIP_INSTALLER_SHA256`** is set. If the checksum file is missing (older branches) or the URL fails, the check is skipped.

## Automation exit codes

For **`windo doctor`**, **`windo integrity`**, and **`windo verify`**, WINDO sets **`$global:WINDO_EXIT_CODE`** (and includes **`exitCode`** in JSON payloads where applicable). See the README table for meanings (for example: missing task or runner, integrity state, verify chain failure). This supports non-interactive scripts without relying on parsing human-readable output.

## Reporting Issues

If you discover a vulnerability, please open a private security advisory or contact the maintainer before publishing details.
