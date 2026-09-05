# WINDO CI Architecture

## Purpose

WINDO's CI system is a safety system, not a dashboard decoration. A green signal must correspond to a proven engineering property. A red signal must correspond to a real failed property or an intentionally detected policy violation. Workflow-definition noise, stale branch races, and ambiguous side-effect steps are defects in the CI platform itself.

This document defines the operating contract for `.github/workflows`.

## Core principles

1. **Validation is read-only.** Ordinary CI must never mutate the branch or commit it is validating.
2. **Writers are exceptional.** Any workflow with repository write permission must be explicitly allow-listed and must write only to a dedicated repair/release/journal destination.
3. **Repair is materialized, not self-applied.** A repair workflow validates an immutable source SHA and writes a deterministic result to an isolated automation branch or release object. It must not push back into the source branch under test.
4. **Red means evidence.** Zero-job parser failures, stale non-fast-forward races, and expected optional side-effect failures must be eliminated or represented explicitly rather than mixed with product-test failures.
5. **Green side effects are verified.** A step that invokes an external mutation is not considered proof that the mutation occurred unless the resulting branch, PR, release, or artifact is independently observable.
6. **External Actions are immutable dependencies.** Every external `uses:` reference is pinned to a full 40-character commit SHA.
7. **Workflow definitions are code.** Every workflow is parsed and linted with actionlint and checked against WINDO-specific policy before it can enter the clean lane.
8. **Private signing remains private.** Hosted Actions may build an unsigned release candidate and prove the PreSign contract, but they never receive the private release key and never manufacture `checksums/installer.sha256.sig`.
9. **Failures remain part of the engineering record.** Failed hypotheses and meaningful failed experiments are preserved in the Engineer Journal. Historical meaningless CI noise is not rewritten as success.
10. **Required checks are stable contracts.** Branch protection should depend on small, stable aggregate checks rather than transient matrix-job names.

## Workflow classes

### Required validation

These workflows are candidates for required branch checks. They are read-only and deterministic.

- `validate.yml` — compatibility-focused PowerShell validation. This currently overlaps `windo-ci.yml` and should be consolidated once Issue #8 removes the temporary PS5.1 baseline.
- `windo-ci.yml` — authoritative hosted source/trust/runtime matrix and aggregate CI result.
- `windo-journal-guard.yml` — enforces Engineer Journal policy for engineering changes.
- `windo-workflow-guard.yml` — validates GitHub Actions syntax, expressions, shell snippets, immutable action pins, write permissions, manual-only workflow roles, and forbidden branch self-mutation patterns.

### Manual diagnostics and laboratories

These workflows are intentionally not required push checks. They answer engineering questions and produce evidence.

- `prometheus-validation.yml`
- `windo-repair-lab.yml`
- `windo-flake-hunter.yml` when explicitly invoked for repeatability analysis
- `windo-regression-bisect.yml` when explicitly invoked for historical isolation

Manual diagnostic workflows must not appear as automatic red noise on unrelated pushes.

### Controlled writers / materializers

These workflows may create repository state only because their role requires it. They are security-sensitive and must remain on the explicit writer allow-list in `tools/Test-WindoWorkflowPolicy.ps1`.

- `prometheus-repair-sync.yml` — legacy recovery writer; should be retired after its recovery lineage is no longer needed.
- `prometheus-stage-repair.yml` — manual legacy staging writer; should be retired after recovery lineage cleanup.
- `windo-journal-entry.yml` — creates a reviewable Engineer Journal branch/PR when repository settings permit.
- `windo-regression-bisect.yml` — may materialize reviewable recovery evidence where configured.
- `windo-repair-lab.yml` — may create a deterministic generated-artifact repair PR only when explicitly requested.
- `windo-issue8-apply-repair.yml` on the Issue #8 branch — validates an immutable source SHA and materializes the certified repair to an isolated `automation/issue8-repair-<run>` branch. It must never push back into the source branch it validates.

Writer workflows are not general-purpose CI. Their success criterion includes both technical validation and independent verification of the resulting state.

### Observability / control plane

- `windo-failure-triage.yml` — consumes authoritative failures and provides diagnostic context. It must not turn every historical or optional workflow failure into a product incident.
- the default-branch workflow-run listener on `Exodus` exists only because GitHub requires `workflow_run` listeners on the repository default branch. It must remain thin and read-only.

### Release and canary

- `windo-release.yml` — release factory. Certification is read-only; publishing is an explicit privileged step. Hosted CI never owns the private signing key.
- `windo-public-canary.yml` — validates the public installation path after publication and must consume the same user-facing release asset that documentation advertises.

## Failure semantics

### Product / runtime failure

Examples:
- a PowerShell parser error in a shipping script;
- reserved-variable safety violation;
- generated artifact drift;
- DPAPI runtime round-trip failure;
- logic-test failure;
- release hash mismatch outside an intentional candidate-generation stage.

These should be red.

### Trust / policy failure

Examples:
- mutable external Action tag;
- workflow syntax or expression error;
- undeclared write permission;
- validation workflow attempts to push to its source branch;
- private signing boundary is violated.

These should be red and are CI-platform defects or security defects.

### Expected pre-sign state

A refreshed unsigned checksum manifest with an intentionally stale private signature is **not** a failure inside `PreSign`. PreSign must prove hashes, source contract, generated artifact integrity, parser/logic/analyzer gates, and trust root while reporting the signature as pending. Full validation requires the refreshed private signature.

### Optional side-effect unavailability

Example: GitHub repository policy can prohibit the Actions `GITHUB_TOKEN` from creating pull requests. A materializer may still successfully create its isolated branch. If automatic PR creation is unavailable, the workflow must surface that fact distinctly and the PR must be created through an authorized external control plane. The system must not describe the PR as created merely because the shell step returned success.

## Issue #8 reference architecture

The Issue #8 repair path demonstrates the desired model:

1. checkout immutable triggering SHA;
2. apply exact-match repair to canonical `windo_runner.ps1`;
3. regenerate derived runtime artifacts from canonical source;
4. prove the actual shipping helper with real CurrentUser DPAPI under Windows PowerShell 5.1;
5. prove PowerShell 7 control behavior;
6. regenerate the unsigned checksum candidate;
7. pass the hosted PreSign contract;
8. append the experiment/decision/result to the Engineer Journal;
9. restrict the diff to declared paths;
10. commit to an isolated automation branch;
11. create or externally materialize a reviewable PR;
12. run the complete PS5.1/PS7 × Windows Server 2022/2025 certification on the final repair PR;
13. privately sign only after the candidate is merge-ready;
14. run Full validation and privileged Windows certification before publication.

## Workflow definition guard

`WINDO Workflow Definition Guard` runs two layers:

- **actionlint**, pinned to an immutable upstream commit, validates GitHub Actions YAML, expressions, and embedded shell snippets;
- `tools/Test-WindoWorkflowPolicy.ps1` enforces WINDO-specific security and architecture rules.

The policy currently requires:

- no tab-indented workflow YAML;
- every external Action pinned to a 40-character SHA;
- repository-write permission only on explicit writer workflows;
- `git push` only on approved writer workflows;
- known direct pushes into authoritative/source branches forbidden;
- force pushes forbidden;
- Repair Lab and Journal Capture remain manual-only.

The policy is expected to become stricter as legacy recovery workflows are retired.

## Action runtime policy

GitHub's hosted runners are forcing older Node-20-based Actions onto Node 24. WINDO treats that warning as maintenance debt, not a harmless cosmetic warning.

Current migration targets validated on 2026-09-05:

- `actions/checkout` v7.0.1 commit `3d3c42e5aac5ba805825da76410c181273ba90b1` — declares `using: node24`.
- `actions/upload-artifact` v7.0.1 commit `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` — declares `using: node24`.

Once the estate migration is complete, the local workflow policy should reject the superseded Node-20 pins.

## Branch protection target

`jonex/windo-production-ready` is intended to be the authoritative release lineage but is currently not protected. The target repository policy is:

- require pull requests;
- prevent force pushes and deletion;
- require branch to be up to date before merge where practical;
- require stable aggregate CI checks rather than every matrix leaf;
- require Workflow Definition Guard;
- require Engineer Journal Guard for engineering changes;
- restrict direct pushes to the authoritative lineage.

Repository administration privileges may be required to configure these settings; the CI repository itself cannot substitute for server-side branch protection.

## Hosted versus privileged certification

Hosted Actions are suitable for source, parser, logic, trust, reproducibility, non-elevated runtime, and release-candidate validation. They are not sufficient proof of the complete WINDO user experience.

Before public release, a privileged Windows certification lane must prove on a controlled Windows machine:

- clean installation;
- real UAC/elevation behavior;
- command-line argument fidelity;
- stdout and stderr streaming fidelity;
- exit-code propagation;
- Ctrl+C/cancellation and process-tree cleanup;
- encrypted audit log creation and integrity behavior;
- self-repair behavior;
- uninstall and cleanup;
- Windows PowerShell 5.1 and PowerShell 7 behavior where applicable.

A public release is not considered certified until both hosted and privileged lanes pass against the exact signed candidate.

## Consolidation roadmap

The current estate contains more overlapping workflows than the desired steady state. The target is a smaller set with clear authority:

- **Workflow Definition Guard** — fast CI-platform gate.
- **WINDO Fast Gate** — parser, static trust, reserved variables, journal, lightweight logic.
- **WINDO Deep Certification** — Windows version × PowerShell version matrix, generated-runtime reproducibility, fail-closed trust boundaries.
- **Manual Diagnostics** — repair lab, flake hunter, bisect.
- **Release Factory** — explicit candidate/publish boundary.
- **Public Canary** — post-publication user-path health.

`validate.yml`, `windo-ci.yml`, and legacy Prometheus validation/recovery workflows should be consolidated or retired only after equivalent coverage is proven in the target architecture. Coverage is never removed simply to make the Actions page quieter.
