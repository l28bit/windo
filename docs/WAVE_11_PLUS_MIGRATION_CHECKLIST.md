# Wave 11+ migration checklist (to V8.4)

## Scope

For admins moving to **V8.4** from the prior two major lines:

- **Wave 9**
- **Wave 10**

This checklist is intentionally lightweight and verification-first: capture state, upgrade cleanly, and validate post-upgrade readiness with built-in checks.

## Migration checklist

### 1) Pre-check and safety lock

- Confirm your active source contract:
  - `windo source`
- Back up recent operator artifacts:
  - `windo export --redact --json`
- Capture health baselines before changes:
  - `windo doctor`
  - `windo integrity`
  - `windo version`

### 2) Upgrade execution

- Start from a non-elevated shell.
- Run the standard installer/update path:
  - `windo install-latest --force`
- If you are doing scripted or non-interactive rollout:
  - `WINDO_INSTALL_NONINTERACTIVE=1 windo install-latest --force`
- If non-default branch/source is required:
  - `windo config --json` and set `WINDO_TRACKING_BRANCH` in your environment intentionally.

### 3) Post-upgrade validation

- Re-check trust and health:
  - `windo trust --online --json`
  - `windo doctor`
  - `windo preflight --json`
- Validate JSON and visibility:
  - `windo stats`
  - `windo history -n 25`
  - `windo version`

### 4) Wave 11+ operator surface (optional, recommended)

- Reconcile preferred command surface:
  - `windo completion repair`
  - `windo surface status`
  - `windo control status`
  - `windo center status`
- Repair prompt and keybinding state if needed:
  - `windo repair`

## Optional command mapping (legacy → V8.4)

| Legacy/older form | V8.4 form | Notes |
|---|---|---|
| `windo !!` | `windo replay` | Replay alias is retained, command is clearer. |
| `windo upgrade` | `windo install-latest` | Alias behavior preserved. |
| `windo remove` | `windo uninstall` | `remove` remains legacy alias; use `uninstall` in playbooks. |
| `windo -` session workflows | `windo - <username> [command...]` | No functional change; syntax preserved. |
| `bootstrap` raw legacy URL usage | `windo install`/`windo install-latest` path in docs | Prefer documented installer contract for checksum/source consistency. |

## V8.4 recommended sequence (minimum viable)

1. `windo doctor`
2. `windo export --redact -o windo-operator-backup.zip`
3. `windo install-latest --force`
4. `windo trust --online`
5. `windo preflight --json`
6. `windo repair` *(if keybinding/prompt conflicts appear)*
7. `windo center status` *(if Wave 11+ native companions are used)*

## Rollback or pause criteria

- If `windo integrity` returns `TAMPERED`, pause and investigate before broad rollout.
- If `windo preflight --json` shows blocked tasks or blocked repair flows, stop and remediate blocked states before continuing.
- Keep `windo uninstall` / recovery docs handy for a controlled rollback window.

