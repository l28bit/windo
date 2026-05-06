# WINDO modules and curated extras

For the **full framework-wave checklist** (modules, recipes, prompt, extras, dev, session, keybindings doctor), see **[`framework-wave.md`](framework-wave.md)**. For **AI / agent CLI** hygiene (**`windo ai`**) and **local Ollama** guidance, see **[`ai-bridge.md`](ai-bridge.md)**.

WINDO’s core remains **deliberate elevation + auditability**. Optional **modules** and **extras** add a composable, “oh-my-* style” layer **without** mixing high-privilege network fetches with interactive polish.

## Local modules (`windo modules`)

- **Layout:** `%USERPROFILE%\Documents\windo\modules\<id>\` with **`module.json`** and an entry script (default **`Load.ps1`**).
- **Prefs:** enabled module ids are stored in **`%USERPROFILE%\.pwsh_secure\windo_prefs.json`** under **`enabledModules`** (array of strings).
- **Load order:** the installer appends a small profile stub **after** the WINDO block. Only **enabled** modules are dot-sourced; failures are **non-fatal** and emit a single warning.
- **Integrity (optional):** in **`module.json`**, an **`integrity`** map can list relative paths to files and expected **SHA256** hex strings. Use **`windo modules verify`** to compare on-disk hashes.
- **Trust:** modules are **local code** in your profile. Review before **`windo modules enable`**. WINDO does not auto-fetch module code from the network during elevation.

**Commands:** `windo modules list | enable | disable | doctor | verify` (all support **`--json`** where applicable).

**Scaffold:** `windo dev init-module [name]` creates **`module.json`**, **`Load.ps1`**, and a short **`README.md`** for contributors.

## Curated extras (`windo extras`)

- **Index:** the repository ships **`extras/index.json`** (schema **`schemaVersion`**). Each item should include **`id`**, **`description`**, **`maintainer`**, **`sourceUrl`**, and **`sha256`** when publishing a downloadable artifact.
- **Search:** `windo extras search [query]` downloads the index from the **`Exodus`** branch unless you set **`WINDO_EXTRAS_INDEX_URL`** (also shown in **`windo config`** / **`windo config --json`** as **`extrasIndexUrl`**).
- **Fetch:** `windo extras fetch <id>` downloads to **`%USERPROFILE%\Documents\windo\extras\<id>\`**, verifies **SHA256** when the index provides it, and **refuses to run while elevated (Administrator)**—same spirit as **`windo install-latest`**. Use **`--force`** only when the catalog entry intentionally omits a hash (discouraged for production use).

See **[`SECURITY.md`](../SECURITY.md)** for the full rules on optional remote extras.

## Oh My Posh bridge (`windo prompt`)

WINDO does not ship a full theme. After each successful elevation, the CLI sets **`WINDO_LAST_REQUEST_ID`** and **`WINDO_VERSION`** for prompts and tooling. Use **`windo prompt`** / **`windo prompt --export <path>`** for a sample Oh My Posh segment and documentation.

## JSON (`--json`) shapes

Structured payloads for **`windo modules`**, **`windo recipes`**, **`windo extras`**, **`windo prompt`**, **`windo dev`**, **`windo ai`**, **`windo help`**, **`windo export`**, plus **`windo config`**, **`windo session`**, and **`windo keybindings`** (including **`doctor`**) are documented in **[`json-schema.md`](json-schema.md)** (per-command **`payload`** tables and **`exitCode`** semantics).
