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
| 5.0.0 | Command Center | A native-feeling Windows command center for deliberate elevation. | Shipped |
| 5.1.0 | Command Center Evolution | Add the unified surface, edition pulse, Exodus source move, and hardened command grammar. | Shipped |
| 5.1.1 | Surface Polish | Make dashboard, launchpad, tray popup, and status toast feel like one designed operator system. | Shipped |
| 5.2.0 | Native Surface Panel | Move the Command Center deeper into browser-independent Windows surfaces. | Shipped |
| 5.3.0 | Power Studio | Turn the native surface into guided Windows wizard workflows. | Shipped |
| 5.4.0 | Windows Integration Plane | Make WINDO feel like a current-user Windows system tool. | Shipped |
| 5.4.1 | Completion Recovery | Keep command discovery available when keybinding setup is skipped. | Shipped |
| 6.0.0 | Network Ops Plane | Local network posture, RDP/WSL/container helpers, and bounded net-scan probing. | Shipped |
| 7.0.0 | Sudo Shell | Shorter admin verbs (`do`, `recdo`, `upd`, `health`, `check`, `status`) with explicit elevation. | Shipped |
| 8.4.0 | Prometheus Contract | Single V8.4 installer identity, checksum manifest, and command center branding. | Shipped |
| 8.5.0 | Contract Posture | Actionable contract checks and audit history search. | Shipped |
| 8.5.1 | Profile Parse Guard | Refuse invalid generated profile writes during update. | Shipped |
| 8.5.2 | Profile Reliability Contract | Fail closed across bootstrap and managed profile refreshes. | Shipped |
| 8.5.3 | Bootstrap Reliability Contract | Deterministic strict-mode download and checksum helpers. | Shipped |
| 8.5.4 | Generated Profile Prelude | Guarantee generated command helpers exist before argument parsing can use them. | Shipped |
| 8.5.5 | Bootstrap Handoff Guard | Keep the verified bootstrap-to-elevated-installer handoff clear of common-parameter collisions. | Shipped |
| 8.5.6 | Dr. Run | Fortify task runner download, repair, config, and cleanup workflows. | Current |

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

### 5.0.0 Command Center

- `windo center` becomes the V5 operator entrypoint.
- `windo center open|tray` starts the native command center.
- `windo center queue|run|history` wraps curated command-center actions.
- V5 unifies tray, control plane, Signal Deck, surface, motion, trust/source, recipes/modules/extras, audit, and export.
- Public copy focuses on the native-feeling Windows command center while keeping future companion-app internals reserved.

### 5.1.0 Command Center Evolution

- `windo edition status|open|html|pulse` adds the V5+ visual command surface.
- The edition console uses final brand assets, animated local HTML, Command Center status, and curated action posture.
- `windo control preview`, `windo control execute <request-id>`, `windo center actions`, `windo center preview`, `windo center execute-next`, and `windo signal open` make the command grammar explicit before future native expansion.
- Install/update, checksum, trust, extras, and README source references move from `Genesis` to `Exodus`.

### 5.1.1 Surface Polish

- `windo dashboard --html` adopts the Exodus visual system and stronger operator report hierarchy.
- `windo launchpad --html` gets a polished Command Center layout with final brand assets and responsive sections.
- `windo launchpad --tray` gets a redesigned Windows Forms popup plus a local status-toast window.
- Visual polish stays local-only and does not change the explicit elevation or trust boundaries.

### 5.2.0 Native Surface Panel

- `windo surface panel` and `windo center panel` launch a browser-independent Windows Forms command surface.
- `surface-panel` joins the curated control-plane action catalog and tray popup action list.
- Status-aware tray icon resolution uses Enterprise ready, warning, denied, elevated, or neutral icons when available.
- Surface doctor now checks panel script freshness alongside tray script and manifest readiness.

### 5.3.0 Power Studio

- `windo studio` and `windo center studio` launch a modern Windows Forms wizard surface.
- Guided workflow tabs cover Start, Trust, Repair, Security, Developer, and Package operations.
- Each workflow row exposes Preview, Queue, and Run controls over curated action IDs.
- Power Studio stays local-only and opens visible PowerShell windows for execution.

### 5.4.0 Windows Integration Plane

- `windo integrate status|doctor|repair|shortcuts|startup|shim|open` manages current-user Windows shell integration.
- Start Menu, desktop, startup tray, startup script, and command shim wiring can be inspected and repaired explicitly.
- Control-plane actions add integration status, doctor, repair, open, shim, and startup flows.
- The integration plane stays current-user scoped and avoids machine-wide writes.

### 5.4.1 Completion Recovery

- Profile keybinding setup no longer exits before the argument completer block.
- `windo completion doctor` verifies completion registration and sample WINDO command results.
- `windo completion repair` re-registers the completer in the current session.
- Completion diagnostics become part of the Windows integration hardening path.

### 6.0.0 Network Ops Plane

- `windo net-scan` covers status, resolve, ARP, ping, probe, nmap, RDP/VNC apply controls, and WSL posture.
- `windo rdp`, `windo vnc`, `windo container`, and `windo wsl` provide structured JSON operator surfaces.
- `extras/samples/network-ops` adds curated `netops-*` helpers for subnet scan, firewall posture, and access workflows.
- Probing defaults stay bounded and local-first (`--host-limit`, short timeouts).

### 7.0.0 Sudo Shell

- `windo do` mirrors `windo run --recipe` for recipe elevation; `windo recdo` mirrors `windo recipes run`.
- Lifecycle aliases: `windo upd`, `windo up`, `windo health`, `windo check`, `windo status`.
- Install/self-update handoff uses explicit `[y/N]` prompts with non-interactive escape hatches.
- Global sudo-style flags (`-E`, `-n`, `-k`, `SUDO_TIMEOUT`) remain compatible with elevation routing.

### 8.4.0 Prometheus Contract

- Installer/bootstrap branding: `WINDO 8.4.0 V8.4`.
- Release **codename** *Prometheus Contract* (installer identity); published Git branch is **`Exodus`**.
- `windo version --contract` exposes edition, branch, schema, and branding in one view.
- Command center/control actions expand with folder open, health snapshot, network status, studio open, and upgrade history surfaces.
- Checksum manifest uses `releaseBranch=Exodus` with strict-mode optional verification.

### 8.5.0 Contract Posture

- Installer/bootstrap branding: `WINDO 8.5.0 V8.5` with dynamic edition labels from semver.
- `windo contract` and `windo contract doctor` combine contract metadata with local checks and optional published source alignment.
- `windo history search` and `windo history --contains` filter audit entries without a separate export step.
- `windo source` embeds contract fields in JSON for automation.
- README/bootstrap defaults and checksum tooling aligned to the real **`Exodus`** branch (legacy `Prometheus` env alias supported).

### 8.5.1 Profile Parse Guard

- Installer/bootstrap branding: `WINDO 8.5.1 V8.5`.
- Generated profile help-token parsing uses the valid `-ieq` operator form.
- Installer validates the full generated profile block with the PowerShell parser before writing `$PROFILE`.
- Logic tests now parse the generated profile block extracted from installer here-strings so profile-breaking syntax cannot hide inside installer text.

### 8.5.2 Profile Reliability Contract

- Installer/bootstrap branding: `WINDO 8.5.2 V8.5`.
- Bootstrap web fallback no longer assumes all exceptions expose a `Response` property under strict mode.
- The managed profile block carries v2 metadata between strong begin/end markers.
- User customizations are loaded from `Documents\windo\profile.d` and `.pwsh_secure\profile.d`, not edited into the managed WINDO block.
- Profile writes are backed up and fail closed if the existing profile cannot be read or repaired.

### 8.5.3 Bootstrap Reliability Contract

- Installer/bootstrap branding: `WINDO 8.5.3 V8.5`.
- Bootstrap helper functions use strict-mode-safe environment reads.
- Web helpers do not bind `-OutFile` unless a non-empty path is provided.
- Raw fallback downloads no longer depend on background jobs or parent-scope helper functions.
- Logic tests lock down missing env var, missing `Response`, and omitted `OutFile` behavior.

### 8.5.4 Generated Profile Prelude

- Installer/bootstrap branding: `WINDO 8.5.4 V8.5`.
- Generated `windo` profile functions define critical argument-parser helpers before any command path can call them.
- Runtime profile smoke coverage verifies installed-profile parsing and low-risk command invocation.

### 8.5.5 Bootstrap Handoff Guard

- Installer/bootstrap branding: `WINDO 8.5.5 V8.5`.
- Bootstrap process-launch wrapper avoids defining parameters with PowerShell common-parameter names.
- Launch-path tests lock down the elevated installer handoff wrapper before publish.

### 8.5.6 Dr. Run

- Installer/bootstrap branding: `WINDO 8.5.6 V8.5`.
- `windo runner` exposes task runner lifecycle, config, cleanup, and explicit repair planning.
- Runner cleanup is dry-run by default and constrained to known WINDO artifact patterns under `.pwsh_secure`.
- `windo doctor` and `windo config` surface runner lifecycle state for support and automation.

### Future companion package

Reserved for a later special release. The compiled helper should render UI and call curated WINDO commands, not replace PowerShell as the trust/elevation/audit source of truth.

## CLI surface

Use `windo roadmap` or `windo roadmap --json` to inspect this release train from the installed profile. Use `windo center`, `windo signal`, `windo control`, `windo integrate`, `windo surface`, `windo motion`, `windo mesh workbench`, `windo trust`, `windo syntax doctor`, `windo explain`, and `windo source` to inspect the shipped foundation.
