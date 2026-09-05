# WINDO Engineer Journal Entries

This directory extends `docs/ENGINEER_JOURNAL.md` with one-file-per-entry append-only engineering records.

The original journal remains canonical historical memory and is not rewritten. Modular entries exist to reduce merge conflicts as independent runtime, CI, release, security, and architecture work proceeds concurrently.

## Entry contract

Each material entry must include:

- `## YYYY-MM-DD — <title>`
- `**Category:** ...`
- `**Status:** ...`
- `**Related:** ...`
- `### Context / question`
- `### Evidence / observations`
- `### Alternatives considered`
- `### Decision / hypothesis`
- `### Result`
- `### Follow-up`

Failed hypotheses and experiments are preserved. A later entry may supersede a conclusion, but older evidence is never rewritten to make history look cleaner.

## File naming

Use:

`YYYY-MM-DD-<short-topic>.md`

Examples:

- `2026-09-05-ci-fabric-hardening.md`
- `2026-09-05-ps51-dpapi-certification.md`

## Guard behavior

For material engineering PRs, `WINDO Engineer Journal Guard` accepts either:

1. an append/update to `docs/ENGINEER_JOURNAL.md`; or
2. one or more structured Markdown entries in this directory.

Every changed modular entry is validated for the required sections. The README alone does not satisfy the material-change journal requirement.
