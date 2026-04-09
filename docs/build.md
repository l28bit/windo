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

CI also runs:

- `tools/Test-WindoLogic.ps1` — integrity-level logic (`src/windo/snippets/IntegrityLevels.ps1`) and stats time filter (`src/windo/snippets/StatsTimeFilter.ps1`)
- `tools/Invoke-PSScriptAnalyzer.ps1` — **Error**-severity rules on shipping scripts (requires `PSScriptAnalyzer` module)

## Optional `src/` fragments

To reduce monolithic edit risk without changing the install contract:

1. Keep **published** artifacts as today: `windo_install.ps1` at repo root.
2. Optionally maintain fragments under `src/windo/` (see `src/windo/README.md`). Snippets are **not** loaded by the installer automatically.
3. **Optional concat (review only):** `tools/build.ps1 -Concat` writes a single text file under `out/` joining `src/windo/snippets/*.ps1` for diff review. It **does not** replace `windo_install.ps1`; maintainers merge by hand.
4. **Validation**: run `tools/Validate-Windo.ps1` or `tools/build.ps1` in CI and before tagging.

No build step is required for end users.

## Branch `Genisis`, checksums, and embedded runner

- **Canonical raw URLs** for bootstrap and `windo upgrade` use the repository branch named **`Genisis`** (historical spelling).
- After changing **`windo_install.ps1`**, update **[`checksums/installer.sha256`](../checksums/installer.sha256)** with the file’s SHA256 (uppercase hex, one line). CI or local:  
  `(Get-FileHash -Path .\windo_install.ps1 -Algorithm SHA256).Hash | Set-Content .\checksums\installer.sha256 -NoNewline`
- **`windo_runner.ps1`** embeds **`WindoRunner.ChildExec`** C# via base64. Source: [`src/windo/snippets/ChildExec.cs`](../src/windo/snippets/ChildExec.cs). Regenerate the base64 string with [`tools/Encode-ChildExec.ps1`](../tools/Encode-ChildExec.ps1), paste into **`windo_runner.ps1`**, then re-sync the **`$RunnerContent`** block in **`windo_install.ps1`** (same file content as `windo_runner.ps1`).
- **`bootstrap.ps1`** cannot dot-source repo helpers; keep it self-contained or duplicate small logic intentionally.

## JSON CLI schema

Structured command output uses a shared envelope (`schemaVersion` **2.6**). See [`docs/json-schema.md`](json-schema.md).
