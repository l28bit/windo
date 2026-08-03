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

## Branch `Exodus`, checksums, and embedded runner

- **Canonical raw URLs** for bootstrap and `windo upgrade` use the repository branch named **`Exodus`** (GitHub default). Legacy env values `Genesis`, `Genisis`, and `Prometheus` normalize to `Exodus`.
- After changing **`windo_install.ps1`** or **`windo_uninstall.ps1`**, regenerate the deterministic multi-hash manifest at **[`checksums/installer.sha256`](../checksums/installer.sha256)**. `.gitattributes` pins release artifacts to LF, and the helper canonicalizes an existing CRLF worktree to the exact LF byte domain GitHub publishes:
  `./tools/Sync-InstallerChecksum.ps1`
- Sign the final manifest with the offline/private release key, then verify it with the committed public key. The signer defaults to `RSA-PKCS1-SHA256` so the same signature verifies on Windows PowerShell 5.1 and PowerShell 7; `RSA-PSS-SHA256` is an explicit CNG-capable-estate opt-in:
  `./tools/Sign-WindoChecksumManifest.ps1`
  `./tools/Test-WindoChecksumSignature.ps1`
- **Bootstrap** resolves one release commit and requires the downloaded installer's raw SHA256 to match `installerSha256` from that commit. A temporarily unavailable checksum source may fall back only to an exact Git blob-object attestation; a checksum mismatch always fails.
- **v3.2.8+:** `tools/Validate-Windo.ps1` also validates the current `versions/vX.Y.Z/checksums/installer.sha256` when that snapshot exists.
- **`windo_runner.ps1`** embeds **`WindoRunner.ChildExec`** C# via base64. Source: [`src/windo/snippets/ChildExec.cs`](../src/windo/snippets/ChildExec.cs). Regenerate the base64 string with [`tools/Encode-ChildExec.ps1`](../tools/Encode-ChildExec.ps1), paste into **`windo_runner.ps1`**, then re-sync the **`$RunnerContent`** block in **`windo_install.ps1`** (same file content as `windo_runner.ps1`).
- **`bootstrap.ps1`** cannot dot-source repo helpers; keep it self-contained or duplicate small logic intentionally.

## Version snapshot (`versions/vX.Y.Z`)

After you bump **`$WindoVersion`** in **`windo_install.ps1`**, refresh and sign **[`checksums/installer.sha256`](../checksums/installer.sha256)** (see above), then generate a **frozen** tree for that tag:

```powershell
./tools/Sync-VersionSnapshot.ps1 -Version 8.5.9
```

The tool requires the requested version to match the installer, validates root hashes/signature before copying, and refuses to overwrite a frozen snapshot unless `-Force` is explicitly supplied for an unpublished rebuild. It writes **`versions/v8.5.9/`** (example) with bootstrap, installer, runner, self-update, uninstaller, healer, checksum manifest/signature, release public key, top-level docs, selected supporting docs/assets, and extras. It then reruns validation against the frozen copy.

## JSON CLI schema

Structured command output uses a shared envelope (`schemaVersion` **3.0** on current installs; **2.6** on older v2.x profiles). See [`docs/json-schema.md`](json-schema.md).

### Maintainer checklist (when changing `--json` payloads)

1. **Implement** the shape in **`windo_install.ps1`** (single source of truth for the embedded **`windo`** function).
2. **Document** new or changed **`payload`** fields in **[`docs/json-schema.md`](json-schema.md)** — command name in the envelope, per-subcommand tables, and **`payload.exitCode`** semantics.
3. **Extend** **[`tools/Test-WindoLogic.ps1`](../tools/Test-WindoLogic.ps1)** with cheap static markers if the change is easy to regress (string presence of critical fields or section headings).
4. **Release / PR:** include a short note in the PR or release checklist that **`docs/json-schema.md`** was updated (or explicitly “no JSON shape change”) so reviewers can diff the doc alongside **`windo_install.ps1`**.

Optional: grep **`_emit_json`** in **`windo_install.ps1`** when auditing which commands emit JSON (including **`export`** after **`Compress-Archive`** when **`--json`** is set).
