# WINDO release runway

WINDO's major-version path should keep the product useful every step of the way. The public runway now focuses on work operators can use and validate now; future major-package details stay intentionally brief until they are ready.

## Product direction

- Keep deliberate elevation and auditability as the core contract.
- Make the shell experience feel native first, with WINDO available when needed.
- Expand modules, recipes, extras, prompt, launchpad, and export into a coherent local operations platform.
- Prefer visible trust posture and repair commands over hidden magic.
- Keep future major-package details reserved until the foundation is proven.

## Release train

| Version | Codename | Theme | Status |
|---|---|---|---|
| 3.4.0 | Quiet Shell | Make WINDO disappear until it is useful. | Shipped |
| 3.5.0 | Trust Console | Make trust state explicit before elevation. | Shipped |
| 3.6.0 | Syntax Forge | Make common elevation workflows shorter and safer. | Shipped |
| 4.0.0 | Operator Mesh | Turn modules, recipes, extras, prompt, and launchpad into one coherent platform layer. | Shipped |
| 4.0.1 | Quiet Runway | Tighten command syntax, compact output, developer helpers, and package handoff. | Shipped |
| 4.5.0 | Signal Deck | Make diagnosis and audit evidence faster to consume. | Planned |
| 5.0.0 | Reserved | Hold the future major package until the platform layers are proven. | Reserved |

## Scope by phase

### 3.4.0 Quiet Shell

- Native-first tab completion.
- Completion mode policy: `native-first`, `hybrid`, `windo`, `off`.
- Profile repair and install smoke coverage.
- Config visibility for shell behavior.

### 3.5.0 Trust Console

- `windo trust` and `windo trust --online --json`.
- Explicit install trust summary.
- Provenance and checksum posture in one command.
- Profile/task drift remediation guidance.
- Clear support handoff for installer state.

### 3.6.0 Syntax Forge

- `windo syntax [query]` intent-to-command planner.
- `windo syntax doctor [query]` intent ambiguity and next-command diagnosis.
- `windo explain <command...>` execution plan before privileged work.
- `windo source` published installer/source-of-truth check.
- Safer short aliases for common workflows.
- Parameterized recipes with first-class preview and dry-run payloads.
- Better help surfacing by workflow.

### 4.0.0 Operator Mesh

- `windo mesh` read-only platform inventory.
- `windo mesh doctor` readiness score for the local platform surface.
- `windo mesh workbench` workflow lanes for trust, network, identity, system, services, and platform operations.
- Module lifecycle polish.
- Verified extras as workflow packs.
- Launchpad workflow grouping.
- Structured export profiles for support, audit, and local debugging.

### 4.0.1 Quiet Runway

- External target flags such as `powercfg -h off` pass through correctly.
- `windo output` controls compact, quiet, and legacy elevated-command result rendering.
- `windo - <username>` starts a Windows credential handoff shell.
- `windo venv` manages local Python virtual environments.
- `windo pkg` gives winget/choco/scoop package-manager handoffs clearer intent and diagnostics.

### 4.5.0 Signal Deck

- Timeline-style request correlation.
- Health scoring improvements.
- More useful `trace`, `session`, and export links.
- Evidence-first dashboards.

### Future major package

Reserved. The public roadmap should only name enough to keep sequencing clear while the 3.x and 4.x foundations keep shipping.

## CLI surface

Use `windo roadmap` or `windo roadmap --json` to inspect this release train from the installed profile. Use `windo mesh workbench`, `windo trust`, `windo syntax doctor`, `windo explain`, and `windo source` to inspect the shipped foundation.
