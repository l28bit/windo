# AI / agent CLI bridge (hygiene and delegation)

WINDO’s core remains **deliberate elevation + auditability**. This page describes how to use **OpenAI**, other cloud LLM APIs, and **local agent / IDE CLIs** safely alongside WINDO—without turning WINDO into a secret store or a network client for AI vendors.

## What WINDO does **not** do

- **No** built-in calls to OpenAI or other AI APIs (no HTTP client for inference in the installer).
- **No** automatic key storage in the WINDO profile as of today—use platform vaults or your own workflow.
- **No** recommendation to pass API keys through **`windo --preserve-env`** into elevated children (they can appear in audit-adjacent process metadata and expand blast radius).

## What WINDO **does** provide (v3.2.5+)

- **`windo ai status`** / **`windo ai doctor`** — read-only checks that list **which common env *names*** are set in **Process**, **User**, and **Machine** scope. **Values are never printed.** Use this to confirm you are not accidentally loading API keys into an **elevated** shell or **system-wide** environment.
- Alignment with existing rules: remote fetches for installers and extras stay **non-elevated** (see [`SECURITY.md`](../SECURITY.md)).

## Threat model (short)

| Risk | Mitigation |
|------|------------|
| Keys in **elevated** interactive shells | Avoid setting `OPENAI_*` / vendor keys before “Run as Administrator”; run agents from **normal** sessions. |
| Keys in **Machine** env | Prefer **User** scope, **Credential Manager**, or **SecretManagement**; avoid machine-wide secrets for personal API keys. |
| Keys leaked via **`windo -E`** | Never list API key variable names in `--preserve-env`. |
| Keys in repo / profile | Never commit `.env`; use `.gitignore` and IDE secret scanners. |

## Suggested patterns

1. **OpenAI / Anthropic official CLIs** — install in the **user** context; set keys via vendor-supported login or **user**-scoped env in a **non-elevated** profile, not in `$PROFILE.AllUsersAllHosts`.
2. **IDE agents (Cursor, Copilot, etc.)** — store credentials in the IDE or OS vault; keep **WINDO elevation** for system commands, not for launching cloud agents with inherited secrets.
3. **Automation** — use a dedicated service account or pipeline secret store; do not reuse interactive WINDO shells as a secret channel.
4. **Optional: `WINDO_AI_KEY_FILE`** — you may point tools at a **user-readable** path outside git; WINDO reports only whether this **name** is set, not the path contents.

## Commands

```powershell
windo ai status
windo ai doctor
windo ai doctor --json
```

**`doctor`** adds fixed **recommendations** in JSON and on the console; non-zero **`payload.exitCode`** (**3**) indicates policy concerns (e.g. secrets visible in an elevated process).

## Local inference: Ollama on Windows

**Ollama** runs a **local** HTTP server (default **`127.0.0.1:11434`**) and usually does **not** need cloud API keys in your shell. It is a good fit for “AI near WINDO” without starting from secret vaults.

| Topic | Guidance |
|-------|------------|
| **Default binding** | With **`OLLAMA_HOST` unset**, the server listens on **loopback** only — not reachable from other machines. |
| **`OLLAMA_HOST`** | Set only when you intentionally bind to a **LAN address** or custom port (e.g. `0.0.0.0:11434`). That **exposes** the API on your network — use firewall rules and treat it like any network service. |
| **`OLLAMA_MODELS`** | Optional override for where models are stored (disk path). |
| **WINDO vs Ollama** | Use **WINDO elevation** for admin-style work (installers, services, firewall). Run **`ollama`** and clients from a **normal (non-elevated)** shell, consistent with WINDO’s rule that **remote fetches** and **optional tooling** should avoid high-privilege sessions. |
| **Recipes** | **`windo recipes run ollama-list`** (and similar) are **read-only** peeks via the same elevated path as other recipes — prefer running **`ollama`** directly in your user shell for day-to-day use. |

**`windo ai status` / `doctor`** includes **Ollama-related env names** (still **values never shown**). **`doctor`** may add an **advisory** when **`OLLAMA_HOST`** suggests non-loopback exposure.

## Future direction (not promised in a given release)

A future iteration could offer an **optional DPAPI-backed keyring** under **`.pwsh_secure`** with explicit **delegate-to-child** semantics; that would require a separate design and security review. Until then, treat this doc + **`windo ai`** as **visibility and discipline**, not a vault product.
