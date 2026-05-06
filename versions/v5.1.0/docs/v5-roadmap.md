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
| 4.1.0 | Security Foundry | Add local scanning, DPAPI vault, SSH helpers, and crypto inspection. | Shipped |
| 4.1.1 | Genesis Prep | Correct the published branch contract and clean up main README brand presentation. | Shipped |
| 4.2.0 | Native Surface Prep | Harden profile startup and wire local native-surface readiness. | Shipped |
| 4.3.0 | Control Plane Wiring | Connect tray, surface, motion, and curated command launch into a local Windows control plane. | Shipped |
| 4.4.0 | Command Center Actions | Make the control-plane queue executable and inspectable. | Shipped |
| 4.5.0 | Signal Deck | Make diagnosis and audit evidence faster to consume. | Shipped |
| 4.6.0 | Native Shell Polish | Harden tray, surface, motion, and native readiness before V5. | Shipped |
| 5.0.0 | Command Center Special Edition | A native-feeling Windows command center for deliberate elevation. | Shipped |
| 5.1.0 | Exodus Limited Edition | Add the branded limited-edition surface, edition pulse, Exodus source move, and hardened command grammar. | Shipped |

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

### 4.1.0 Security Foundry

- `windo scan` provides local file posture scanning with hashes, MOTW checks, launchable extension flags, and suspicious script-pattern detection.
- `windo vault` stores named secrets with DPAPI CurrentUser protection.
- `windo sshx` wraps common OpenSSH status, keygen, config, and test workflows.
- `windo crypto` simplifies certificate, key, and SHA256 inspection.

### 4.1.1 Genesis Prep

- Canonical install/update, trust, checksum, and extras URLs targeted `Genesis` for that release. v5.1.0 moves the live branch contract to `Exodus`.
- README uses constrained final brand assets and removes the rough secondary crop.

### 4.2.0 Native Surface Prep

- `windo profile doctor` detects prompt-init problems that can break profile load.
- `windo profile repair --prompt-init` guards oh-my-posh init and writes a backup first.
- `windo motion` controls subtle terminal motion while respecting CI and redirected output.
- `windo surface` reports and primes the local native-surface manifest for future Windows-native work.

### 4.3.0 Control Plane Wiring

- `windo control` reports local Windows control-plane state.
- `windo control prime` writes a manifest and request-queue root for tray/native consumers.
- `windo control actions` exposes curated surface, workbench, trust, lifecycle, and motion actions.
- `windo control queue <action-id>` writes explicit JSON requests.
- `windo control run <action-id>` launches only curated actions in visible PowerShell windows.
- The tray launchpad now includes surface, control-plane, and motion actions.

### 4.4.0 Command Center Actions

- `windo control execute-next` consumes one queued request and launches a visible executor.
- `windo control inspect <request-id>` shows request/result detail.
- `windo control cancel <request-id>` marks queued/running requests as cancelled.
- `windo control history` shows recent control-plane actions.
- Control requests now write result JSON beside request JSON.
- Tray actions include run-next, history, queue folder, and last result.

### 4.5.0 Signal Deck

- `windo signal` reports evidence-first diagnostic status.
- `windo signal timeline` correlates control requests, last elevation metadata, trust, audit chain, and surface readiness.
- `windo signal last` shows the latest signal.
- `windo signal export` writes local Signal Deck HTML.

### 4.6.0 Native Shell Polish

- `windo surface doctor` checks Windows Forms, STA launch, tray script, manifests, profile prompt, and motion policy.
- `windo surface repair` primes manifests and guards prompt init where needed.
- `windo surface open` starts the browser-independent tray surface.
- `native-companion/` scaffolds the future compiled-helper path without making it required.

### 5.0.0 Command Center Special Edition

- `windo center` becomes the V5 operator entrypoint.
- `windo center open|tray` starts the native command center.
- `windo center queue|run|history` wraps curated command-center actions.
- V5 unifies tray, control plane, Signal Deck, surface, motion, trust/source, recipes/modules/extras, audit, and export.
- Public copy focuses on the native-feeling Windows command center while keeping future companion-app internals reserved.

### 5.1.0 Exodus Limited Edition

- `windo edition status|open|html|pulse` adds the V5+ limited-edition visual surface.
- The edition console uses final brand assets, animated local HTML, Command Center status, curated action posture, and Exodus release identity.
- `windo control preview`, `windo control execute <request-id>`, `windo center actions`, `windo center preview`, `windo center execute-next`, and `windo signal open` make the command grammar explicit before future native expansion.
- Install/update, checksum, trust, extras, and README source references move from `Genesis` to `Exodus`.

### Future companion package

Reserved for a later special release. The compiled helper should render UI and call curated WINDO commands, not replace PowerShell as the trust/elevation/audit source of truth.

## CLI surface

Use `windo roadmap` or `windo roadmap --json` to inspect this release train from the installed profile. Use `windo center`, `windo signal`, `windo control`, `windo surface`, `windo motion`, `windo mesh workbench`, `windo trust`, `windo syntax doctor`, `windo explain`, and `windo source` to inspect the shipped foundation.
