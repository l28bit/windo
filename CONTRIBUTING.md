
# Contributing

Contributions are welcome.

## Development Guidelines

1. Keep the core elevation mechanism simple.
2. Preserve audit logging and integrity checks.
3. Avoid features that weaken Windows security boundaries.
4. Maintain administrator‑first design philosophy.

## Default branch name

The production-ready release branch is **`jonex/windo-production-ready`**. Raw GitHub URLs and checksum manifests target it; update branch overrides through migration-safe procedures instead of casual renames. The V8.4 release codename *Prometheus Contract* is not a Git branch name.

## Workflow

Fork the repository and create a feature branch.

Submit a pull request with:

- clear description
- testing notes
- security considerations

## Validation

Before opening a PR that changes PowerShell scripts, run `./tools/Validate-Windo.ps1` in PowerShell 7 (local) or rely on the GitHub Actions workflow.
