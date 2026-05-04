# WINDO V5 runway

WINDO’s major-version path should keep the product useful every step of the way. The V5 reveal is the packaging moment; the hardening, shell ergonomics, and platform pieces should land earlier in small verified releases.

## Product direction

- Keep deliberate elevation and auditability as the core contract.
- Make the shell experience feel native first, with WINDO available when needed.
- Expand modules, recipes, extras, prompt, launchpad, and export into a coherent local operations platform.
- Prefer visible trust posture and repair commands over hidden magic.
- Build V5 as the polished Special Edition reveal after the foundations are proven.

## Release train

| Version | Codename | Theme | Status |
|---|---|---|---|
| 3.4.0 | Quiet Shell | Make WINDO disappear until it is useful. | Shipped |
| 3.5.0 | Trust Console | Make trust state explicit before elevation. | Shipped |
| 3.6.0 | Syntax Forge | Make common elevation workflows shorter and safer. | In progress |
| 4.0.0 | Operator Mesh | Turn modules, recipes, extras, prompt, and launchpad into one coherent platform layer. | Planned |
| 4.5.0 | Signal Deck | Make diagnosis and audit evidence faster to consume. | Planned |
| 5.0.0 | Special Edition Extravaganza | Package the runway into the next major reveal. | Target |

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
- `windo explain <command...>` execution plan before privileged work.
- Safer short aliases for common workflows.
- Parameterized recipes with first-class preview and dry-run payloads.
- Syntax doctor for ambiguous commands.
- Better help surfacing by workflow.

### 4.0.0 Operator Mesh

- Module lifecycle polish.
- Verified extras as workflow packs.
- Launchpad workflow grouping.
- Structured export profiles for support, audit, and local debugging.

### 4.5.0 Signal Deck

- Timeline-style request correlation.
- Health scoring improvements.
- More useful `trace`, `session`, and export links.
- Evidence-first dashboards.

### 5.0.0 Special Edition Extravaganza

- Major install/update visual polish.
- Cohesive command center experience.
- Trust posture, workflow packs, and operator evidence in one release story.
- Release notes that make the jump feel intentional rather than sudden.

## CLI surface

Use `windo roadmap` or `windo roadmap --json` to inspect this release train from the installed profile. Use `windo trust` to inspect the first Trust Console slice.
