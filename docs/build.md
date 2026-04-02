# Build / modularization (WINDO)

WINDO ships a single **installer** (`windo_install.ps1`) as the source of truth: it embeds the profile `windo` function, PSReadLine block, runner, and self-update script text.

## Current model

- One file to copy and run elevated on target machines.
- Bootstrap downloads that file from GitHub and executes it from disk.

## Direction for modular sources (future)

To reduce monolithic edit risk without changing the install contract:

1. Keep **published** artifacts as today: `windo_install.ps1` at repo root.
2. Optionally maintain fragments under `src/` (e.g. `src/windo/ProfileWindo.ps1`) that are **concatenated** by a small `tools/Build-WindoInstaller.ps1` into `windo_install.ps1` before release.
3. **Validation**: run `tools/Validate-Windo.ps1` in CI and before tagging.

No build step is required for end users; a build is only for maintainers who choose to split sources.

