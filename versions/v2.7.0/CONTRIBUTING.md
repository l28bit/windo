
# Contributing

Contributions are welcome.

## Development Guidelines

1. Keep the core elevation mechanism simple.
2. Preserve audit logging and integrity checks.
3. Avoid features that weaken Windows security boundaries.
4. Maintain administrator‑first design philosophy.

## Default branch name

The public default branch is **`Genisis`** (historical spelling). Raw GitHub URLs depend on it; do not rename it casually without a documented migration and coordination.

## Workflow

Fork the repository and create a feature branch.

Submit a pull request with:

- clear description
- testing notes
- security considerations

## Validation

Before opening a PR that changes PowerShell scripts, run 	ools/Validate-Windo.ps1 in PowerShell 7 (local) or rely on the GitHub Actions workflow.
