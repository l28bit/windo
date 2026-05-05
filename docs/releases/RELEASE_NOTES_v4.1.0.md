# Release notes - WINDO v4.1.0

v4.1.0 is the Security Foundry release. It adds local-first security workflows that fit WINDO's operator model: inspect before acting, protect secrets by default, and keep elevation deliberate.

## New: `windo scan`

`windo scan` is a WINDO-native posture scanner. It is not a signature antivirus replacement; it is a fast local inspection tool for operator review.

```powershell
windo scan .
windo scan $HOME\Downloads --recurse
windo scan .\script.ps1 --json
```

It reports:

- SHA256 hashes by default
- Mark-of-the-Web alternate data streams
- launchable/script-capable file extensions
- suspicious script patterns such as encoded commands, download-and-execute chains, execution-policy bypasses, hidden window usage, and obvious plaintext secret assignments

Exit codes:

- `0` no findings
- `2` path or argument errors
- `3` findings present

## New: `windo vault`

`windo vault` stores named values under `.pwsh_secure\windo_vault.json` using DPAPI CurrentUser protection.

```powershell
windo vault set OPENAI_API_KEY
windo vault list
windo vault get OPENAI_API_KEY
windo vault remove OPENAI_API_KEY
```

Secrets decrypt only in the same Windows user context. `get` prints the value only when explicitly requested.

## New: `windo sshx`

SSH operator helpers:

```powershell
windo sshx status
windo sshx keygen --name id_ed25519_ops
windo sshx config
windo sshx test git@github.com
```

`keygen` uses `ssh-keygen -t ed25519 -a 100`.

## New: `windo crypto`

Certificate/key/hash helpers:

```powershell
windo crypto status
windo crypto cert .\server.crt
windo crypto key .\server.key
windo crypto hash .\file.zip --json
```

Certificate inspection uses OpenSSL when available, with `certutil -dump` fallback. Key inspection requires OpenSSL. Hashing uses local SHA256.

## Validation

```powershell
windo scan .\windo_install.ps1 --json
windo vault status --json
windo sshx status --json
windo crypto status --json
windo source
windo trust --online
```
