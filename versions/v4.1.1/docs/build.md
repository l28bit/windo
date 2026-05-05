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

This runs `tools/Validate-Windo.ps1` (AST parse of shipped scripts plus normalized published-installer checksum checks for the root installer and current version snapshot when present). **No** installer file is modified.

CI also runs:

- `tools/Test-WindoLogic.ps1` — integrity-level logic (`src/windo/snippets/IntegrityLevels.ps1`), stats time filter (`src/windo/snippets/StatsTimeFilter.ps1`), and effective env helpers (`src/windo/snippets/WindoConfigEffective.ps1`)
- `tools/Invoke-PSScriptAnalyzer.ps1` — **Error**-severity rules on shipping scripts plus `tools/Encode-ChildExec.ps1` (requires `PSScriptAnalyzer` module)

## Optional `src/` fragments

To reduce monolithic edit risk without changing the install contract:

1. Keep **published** artifacts as today: `windo_install.ps1` at repo root.
2. Optionally maintain fragments under `src/windo/` (see `src/windo/README.md`). Snippets are **not** loaded by the installer automatically.
3. **Optional concat (review only):** `tools/build.ps1 -Concat` writes a single text file under `out/` joining `src/windo/snippets/*.ps1` for diff review. It **does not** replace `windo_install.ps1`; maintainers merge by hand.
4. **Validation**: run `tools/Validate-Windo.ps1` or `tools/build.ps1` in CI and before tagging.

No build step is required for end users.

## Branch `Genesis`, checksums, and embedded runner

- **Canonical raw URLs** for bootstrap and `windo upgrade` use the repository branch named **`Genesis`**.
- After changing **`windo_install.ps1`**, update **[`checksums/installer.sha256`](../checksums/installer.sha256)** with the **published** installer SHA256 (uppercase hex, one line). Use the helper so Windows checkout line endings do not produce a stale hash:
  `./tools/Sync-InstallerChecksum.ps1`
- **v3.2.7+:** **`bootstrap.ps1`** and **`_windo_verify_installer_sha256_optional`** compare the downloaded installer’s hash to the **first 64 hex** characters found in the fetched checksum file (so BOM, extra whitespace, or `sha256sum`-style lines still verify). The canonical file remains a single 64-character uppercase line.
- **v3.2.8+:** `tools/Validate-Windo.ps1` also validates the current `versions/vX.Y.Z/checksums/installer.sha256` when that snapshot exists.
- **`windo_runner.ps1`** embeds **`WindoRunner.ChildExec`** C# via base64. Source: [`src/windo/snippets/ChildExec.cs`](../src/windo/snippets/ChildExec.cs). Regenerate the base64 string with [`tools/Encode-ChildExec.ps1`](../tools/Encode-ChildExec.ps1), paste into **`windo_runner.ps1`**, then re-sync the **`$RunnerContent`** block in **`windo_install.ps1`** (same file content as `windo_runner.ps1`).
- **`bootstrap.ps1`** cannot dot-source repo helpers; keep it self-contained or duplicate small logic intentionally.

## Version snapshot (`versions/vX.Y.Z`)

After you bump **`$WindoVersion`** in **`windo_install.ps1`** and refresh **[`checksums/installer.sha256`](../checksums/installer.sha256)** (see above), generate a **frozen** tree for that tag:

```powershell
./tools/Sync-VersionSnapshot.ps1 -Version 3.2.3
```

This writes **`versions/v3.2.3/`** (example) with the installer, checksum, top-level **`README.md`**, **`SECURITY.md`**, **`CHANGELOG.md`**, **`docs/*.md`** (including **`json-schema.md`**, **`build.md`**, **`modules-and-extras.md`**, **`framework-wave.md`**, **`ai-bridge.md`**, **`v5-roadmap.md`**), **`brand/Enterprise/`**, and **`extras/`** (including **`samples/hello`**). Use it before publishing a release so the repo carries a point-in-time copy alongside **`Genesis`** raw URLs.

## JSON CLI schema

Structured command output uses a shared envelope (`schemaVersion` **3.0** on current installs; **2.6** on older v2.x profiles). See [`docs/json-schema.md`](json-schema.md).

### Maintainer checklist (when changing `--json` payloads)

1. **Implement** the shape in **`windo_install.ps1`** (single source of truth for the embedded **`windo`** function).
2. **Document** new or changed **`payload`** fields in **[`docs/json-schema.md`](json-schema.md)** — command name in the envelope, per-subcommand tables, and **`payload.exitCode`** semantics.
3. **Extend** **[`tools/Test-WindoLogic.ps1`](../tools/Test-WindoLogic.ps1)** with cheap static markers if the change is easy to regress (string presence of critical fields or section headings).
4. **Release / PR:** include a short note in the PR or release checklist that **`docs/json-schema.md`** was updated (or explicitly “no JSON shape change”) so reviewers can diff the doc alongside **`windo_install.ps1`**.

Optional: grep **`_emit_json`** in **`windo_install.ps1`** when auditing which commands emit JSON (including **`export`** after **`Compress-Archive`** when **`--json`** is set).
