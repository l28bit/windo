# Composable shell companion — framework wave (shipped)

WINDO’s core remains **deliberate elevation + auditability**. This document is the **repository checklist** for the phased “oh-my-* style” layer: optional modules, recipes, prompt bridge, curated extras, dev scaffolding, session summary, and advisory keybindings—**without** weakening the security model in [`SECURITY.md`](../SECURITY.md).

Planning may have started outside the repo; **this file is the canonical map from that wave to shipped commands and docs.**

## Principles (unchanged)

- **Composable:** opt-in per feature; defaults stay minimal.
- **Trust-bounded:** verified remote content; **no** high-privilege fetches for install/extras (see [`SECURITY.md`](../SECURITY.md)).
- **Inspectable:** `--json`, `windo doctor`, manifests, and [`json-schema.md`](json-schema.md).

## Tier 1 — “Framework feel”

| # | Plan item | Shipped as | Notes |
|---|-----------|------------|--------|
| 1 | Local **`windo modules`** | **`windo modules` `list` \| `enable` \| `disable` \| `doctor` \| `verify`** | Module root: **`%USERPROFILE%\Documents\windo\modules\<id>\`** (not under `.pwsh_secure`; prefs in **`windo_prefs.json`**). Optional per-file SHA256 in **`module.json`** → **`verify`**. Profile stub loads **enabled** modules after the WINDO block; failures are warnings only. |
| 2 | Recipes (data-only templates) | **`windo recipes`**, **`windo recipes run`**, **`windo run --recipe`** | Bundled data in the installer; reviewed and versioned with **`$WindoVersion`**. |
| 3 | Prompt bridge (no bundled theme) | **`windo prompt`** [ **`--export`** ] | Documents **`WINDO_LAST_REQUEST_ID`**, **`WINDO_VERSION`**; Oh My Posh segment guidance—see [`modules-and-extras.md`](modules-and-extras.md). |

## Tier 2 — Community-shaped, low supply-chain risk

| # | Plan item | Shipped as | Notes |
|---|-----------|------------|--------|
| 4 | Curated extras index | **`extras/index.json`** + **`windo extras search`** / **`windo extras fetch`** | Index URL override: **`WINDO_EXTRAS_INDEX_URL`** (surfaced in **`windo config --json`**). Fetch **non-elevated only**; SHA256 when published. |
| 5 | Dev scaffolding | **`windo dev init-module`** | Creates **`module.json`**, **`Load.ps1`**, **`README.md`**; builtins remain centralized (**`$WindoBuiltinVerbs`** in **`windo_install.ps1`**). |

## Tier 3 — Power-user quality of life

| # | Plan item | Shipped as | Notes |
|---|-----------|------------|--------|
| 6 | Session / dashboard summary | **`windo session`** [ **`--json`** ] | Tasks, integrity, last command / **`RequestId`**; **v3.2.1+** **`lastAudit`** / **`recentAudit`** tail. |
| 7 | PSReadLine advisory | **`windo keybindings doctor`** | Heuristic conflict hints; not authoritative—see [`json-schema.md`](json-schema.md) **`keybindings`**. |

## Explicitly out of scope (this wave)

- Arbitrary unsigned remote plugin execution by default.
- Auto-elevating installs or silent network fetches from elevated sessions.
- Replacing Oh My Posh or PSReadLine as products.

## Related docs

- Operator guide: [`modules-and-extras.md`](modules-and-extras.md)
- JSON payloads: [`json-schema.md`](json-schema.md)
- Maintainer build / snapshots: [`build.md`](build.md)
