# WINDO performance and large audit logs

WINDO stores encrypted audit entries in `%USERPROFILE%\.pwsh_secure\windo_history.enc`. Commands such as **`windo stats`**, **`windo history`**, **`windo report`**, and **`windo export`** read and decrypt **all** lines to build aggregates or excerpts, which uses memory proportional to log size.

## When logs grow large

- Above roughly **100,000** physical lines, WINDO may print a **warning** before running heavy commands. Processing can become slow or memory-intensive on low-RAM hosts.
- **`windo verify`** must read the entire file to validate the hash chain; there is no shortcut for integrity of the chain.

## Recommendations

- Periodically use **`windo cleanup`** (after backing up if needed) to rotate or archive old logs.
- For **`windo export`**, use **`-n`** to limit the audit excerpt in the bundle; the full log is still decrypted to compute total counts unless you change workflow in a future release.
- Use **`--redact`** on export when sharing bundles outside the host to mask path-like strings in JSON (best-effort; see release notes).

## Preferred workflow

Nothing here changes the security model: elevation remains deliberate, and audit integrity is preserved when you verify before cleanup.
