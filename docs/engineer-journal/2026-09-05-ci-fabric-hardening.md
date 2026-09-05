## 2026-09-05 — Turn the Actions wall of red into trustworthy engineering signal

**Category:** incident / architecture / tooling / security  
**Status:** active  
**Related:** PR #12, PR #13, Issue #10, Issue #11, workflow runs 33960446561, 33960495724, 33960640317

### Context / question

The Actions history showed many consecutive failures across Repair Lab, Engineer Journal, and Issue #8 workflows. The visible result looked like WINDO itself was broadly broken, but several failures were occurring before any runner job existed. The CI system therefore could not reliably distinguish malformed orchestration, failed experiments, branch races, and actual product defects.

The engineering question became broader than repairing individual YAML files: what properties must the WINDO CI platform enforce so that green and red signals remain trustworthy as the project grows?

### Evidence / observations

- Multiple historical Repair Lab and Engineer Journal runs completed as failures with zero jobs because malformed multiline script content escaped YAML `run: |` indentation.
- The corrected production-ready definitions stopped producing automatic pseudo-runs for workflows intended to be manual-only.
- `Validate PowerShell #180` completed successfully after the workflow-definition repairs, proving the previous wall of red was not equivalent to a broad WINDO runtime failure.
- Issue #8 Controlled Repair #7 passed the canonical repair, strict PS5.1 DPAPI proof, PowerShell 7 control, unsigned checksum synchronization, PreSign validation, Journal append, and diff restriction, then failed only at the final push because the source branch moved while the job was running.
- That non-fast-forward failure demonstrated that CI mutating the same branch it validates creates avoidable orchestration races.
- Issue #8 Repair Materializer #8 replaced the self-mutation model with immutable-source validation and an isolated automation branch. All technical/materialization steps passed and the isolated repair branch was created successfully.
- GitHub repository policy prevented the Actions `GITHUB_TOKEN` from creating a pull request. The workflow step had been intentionally made non-fatal, so its green status did not prove the PR existed. PR #9 was subsequently created through the authorized GitHub control plane and merged into the Issue #8 development branch.
- The first `WINDO Workflow Definition Guard` run caught a ShellCheck defect in the guard's own summary code. The defect was fixed instead of suppressed.
- The next guard run passed actionlint and exposed six mutable external Action references in legacy Prometheus workflows. Those dependencies were pinned to immutable commits.
- The subsequent guard run passed both actionlint and the WINDO-specific workflow policy.
- GitHub reports `jonex/windo-production-ready` as unprotected with required-status enforcement disabled.
- GitHub hosted runners warn that the older pinned checkout action targets Node 20 and is being forced onto Node 24.
- Current upstream `actions/checkout` v7.0.1 commit `3d3c42e5aac5ba805825da76410c181273ba90b1` and `actions/upload-artifact` v7.0.1 commit `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` explicitly declare Node 24 runtimes.

### Alternatives considered

- Ignore historical zero-job failures because later runs eventually became green.
- Delete or hide failed workflow history to make the Actions page look cleaner.
- Continue allowing repair CI to push directly back into the branch under test and add retry/rebase logic for races.
- Treat a successful shell step as proof an external side effect occurred without checking the resulting branch/PR/release.
- Keep workflow YAML as an unlinted configuration layer and rely on GitHub to reject malformed definitions after commit.
- Allow mutable Action tags for convenience and depend on upstream maintainers not to move them unexpectedly.
- Continue storing every future Engineer Journal entry in one monolithic file even as independent development lanes multiply.

### Decision / hypothesis

WINDO CI is treated as a product safety subsystem with explicit failure semantics.

Ordinary validation must be read-only. Repair automation validates an immutable source SHA and materializes deterministic results to an isolated automation branch or other dedicated destination. It must not push back into the source branch it is certifying.

Every external Action is pinned to an immutable 40-character commit SHA. Workflow definitions are validated by actionlint plus a WINDO-specific policy layer that inventories write-capable workflows, forbids known source-branch self-mutation and force pushes, and preserves manual-only roles for diagnostic workflows.

A green step that requests an external mutation is not sufficient evidence that the mutation occurred. The resulting branch, PR, release, or artifact must be independently observable or the workflow must report the side effect as unavailable.

Meaningful failed experiments remain part of engineering history. Zero-job parser noise and preventable orchestration races are treated as CI defects to eliminate, not as product failures to normalize.

The Engineer Journal is extended with one-file-per-entry records under `docs/engineer-journal/` so concurrent engineering lanes can remain append-only without turning the original journal into a chronic merge-conflict hotspot.

### Result

The Issue #8 repair path now uses immutable-source validation and isolated materialization. PR #9 carried the certified repair into the Issue #8 development branch, and PR #13 is the production-facing draft repair PR that triggers the strict PS5.1/PS7 × Windows Server 2022/2025 certification matrix.

PR #12 isolates CI-platform hardening from runtime repair work. The new Workflow Definition Guard has progressed from catching its own ShellCheck defect, to discovering six mutable dependencies, to passing the repaired workflow estate.

`docs/CI_ARCHITECTURE.md` now records workflow classes, failure semantics, signing boundaries, side-effect verification, branch-protection targets, privileged certification requirements, and the intended consolidation architecture.

Issue #10 tracks server-side protection for the production-ready lineage. Issue #11 tracks the privileged disposable-Windows certification lane required before public release.

### Follow-up

- Complete the Node-24-native Action migration and make the local workflow policy reject superseded Node-20 pins.
- Audit `validate.yml` and `windo-ci.yml` for duplicated coverage; consolidate only after equivalent coverage is demonstrated.
- Define a small stable set of aggregate required checks for branch protection.
- Retire legacy Prometheus writer/recovery workflows after proving their recovery lineage is no longer required.
- Complete Issue #8 strict matrix validation, then correct the two PS5.1 host-sensitive test assertions without weakening their security properties.
- Remove the temporary Issue #8 baseline waiver only after main PS5.1 validation is genuinely green.
- Configure and verify server-side branch protection under Issue #10.
- Build and prove the privileged disposable Windows certification lane under Issue #11 before publication.
