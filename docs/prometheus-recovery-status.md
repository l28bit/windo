# Prometheus Recovery Status

This branch is the isolated WINDO recovery candidate.

Promotion to `main` and the public one-line installer remain blocked until all of the following are true:

- Windows PowerShell 5.1 parses every shipped PowerShell entry point.
- PowerShell 7 logic and release validation pass.
- `ChildExec.cs`, its Base64 payload, the standalone runner, and the installer-generated runner are identical.
- Inline stdout and stderr delivery, exact exit-code propagation, timeout, cancellation, cleanup, upgrade, and uninstall are validated.
- The release checksum manifest is regenerated and verified with the published release-signing key.
- A clean Windows interactive UAC smoke test is recorded.

The Prometheus validation workflow is installed on the `main` base branch so every synchronization of this recovery branch is evaluated against the same Windows release gate.

No private signing key belongs in this repository.
