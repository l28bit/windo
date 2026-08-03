# WINDO 8.5.9 — Elevation and Release Reliability

WINDO 8.5.9 hardens the two critical paths: `windo <command>` elevation and the README bootstrap installer.

## Elevated command path

- `windo [global options] -- <target> [args...]` is the exact-argv contract. Tokens after `--` are never consumed as WINDO flags or built-ins.
- The caller's supported PowerShell host and existing filesystem working directory are preserved.
- SID-scoped task and mutex names prevent local users from sharing one runner namespace.
- DPAPI request/result protection fails closed instead of falling back to plaintext-compatible Base64.
- Long-running work no longer causes accepted queued requests to be deleted by the old two-minute cleanup path.
- Timeout handling attempts process-tree termination and bounds stdout/stderr drain waits.

Elevated children remain intentionally non-interactive: stdin and console/TTY prompts are not forwarded. Use arguments or files for input.

## Install and update path

- The README one-liner enables TLS 1.2 before its first GitHub request.
- Bootstrap resolves the tracking branch to one immutable commit, retries transient requests, verifies the installer, and never downloads from a moving-branch fallback.
- Published checksum mismatches fail closed. A checksum-source outage is accepted only when the downloaded bytes match the resolved Git blob object.
- UAC handoff safely quotes temporary paths containing spaces, and caller shells survive IEX or dot-sourced bootstrap execution.
- The installer does not activate the profile or report success until Add-Type, ScheduledTasks, and the current user's highest-runlevel task pass verification.

## Release integrity

- Release artifacts and snapshots are pinned to LF bytes for deterministic GitHub hashes.
- The schema-2 manifest covers SHA-256, SHA-384, and SHA-512 for installer and uninstaller artifacts.
- Manifest signing defaults to `RSA-PKCS1-SHA256` for Windows PowerShell 5.1 and PowerShell 7 compatibility.
- CI parses every shipped PowerShell surface, runs logic tests and PSScriptAnalyzer on both hosts, verifies the embedded trust root, and requires a complete signed current-version snapshot.

