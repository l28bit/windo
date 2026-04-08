
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

## Reporting Issues

If you discover a vulnerability, please open a private security advisory or contact the maintainer before publishing details.
