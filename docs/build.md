# Build / modularization (WINDO)

WINDO ships a single **installer** (`windo_install.ps1`) as the source of truth: it embeds the profile `windo` function, PSReadLine block, runner, and self-update script text.

## Current model

- One file to copy and run elevated on target machines.
- Bootstrap downloads that file from GitHub and executes it from disk.

## Maintainer validation (default)

From the repo root:

```powershell
./tools/build.ps1
```

This runs `tools/Validate-Windo.ps1` (AST parse of `bootstrap.ps1`, `windo_install.ps1`, `windo_runner.ps1`, `windo_self_update.ps1`). **No** installer file is modified.

## Optional `src/` fragments

To reduce monolithic edit risk without changing the install contract:

1. Keep **published** artifacts as today: `windo_install.ps1` at repo root.
2. Optionally maintain fragments under `src/windo/` (see `src/windo/README.md`). Snippets are **not** loaded by the installer automatically.
3. **Optional concat (review only):** `tools/build.ps1 -Concat` writes a single text file under `out/` joining `src/windo/snippets/*.ps1` for diff review. It **does not** replace `windo_install.ps1`; maintainers merge by hand.
4. **Validation**: run `tools/Validate-Windo.ps1` or `tools/build.ps1` in CI and before tagging.

No build step is required for end users.

## JSON CLI schema

Structured command output uses a shared envelope (`schemaVersion` **2.6**). See [`docs/json-schema.md`](json-schema.md).
