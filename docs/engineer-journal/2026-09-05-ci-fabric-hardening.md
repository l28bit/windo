## 2026-09-05 — Turn the Actions wall of red into trustworthy engineering signal

**Category:** incident / architecture / tooling / security  
**Status:** active  
**Related:** PR #12, PR #13, Issue #10, Issue #11, workflow runs 33960446561, 33960495724, 33960640317, 33979447695, 33979527581, 33979646249, 33980171398

### Context / question

The Actions history showed many consecutive failures across Repair Lab, Engineer Journal, and Issue #8 workflows. The visible result looked like WINDO itself was broadly broken, but several failures occurred before any runner job existed. The CI system therefore could not reliably distinguish malformed orchestration, failed experiments, branch races, generated-byte drift, private-signing boundaries, and actual product defects.

The engineering question became broader than repairing individual YAML files: what properties must the WINDO CI platform enforce so that green and red signals remain trustworthy as the project grows, while keeping the Actions surface small enough for a human to understand?

### Evidence / observations

- Multiple historical Repair Lab and Engineer Journal runs failed with zero jobs because malformed multiline script content escaped YAML `run: |` indentation.
- Corrected manual-only workflow definitions stopped creating pseudo-runs on unrelated pushes.
- `Validate PowerShell #180` succeeded after definition repairs, proving the wall of red was not equivalent to broad WINDO runtime failure.
- Issue #8 Controlled Repair #7 passed canonical repair, strict PS5.1 DPAPI proof, PS7 control, checksum synchronization, PreSign, Journal append, and diff restriction, then lost only the final push because its source branch moved during the run.
- Replacing self-mutation with immutable-source isolated materialization removed that race. Issue #8 Repair Materializer #12 later passed every substantive step, including structural generated-artifact synchronization and isolated branch materialization.
- GitHub repository policy prevented Actions from creating a PR. A previously non-fatal PR-creation shell step could therefore be green without the PR existing. PR #9 was created through the authorized GitHub control plane instead. The materializer was subsequently changed to stop attempting PR creation entirely.
- The first `WINDO Workflow Definition Guard` run caught a ShellCheck defect in the guard itself. The defect was fixed rather than suppressed.
- The guard then discovered six historical mutable Action references and later identified nineteen remaining immutable-but-Node-20 Action references across the active estate.
- Current verified Node-24-native Actions are `actions/checkout` v7.0.1 commit `3d3c42e5aac5ba805825da76410c181273ba90b1` and `actions/upload-artifact` v7.0.1 commit `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`.
- After the full migration, Definition Guard run `33980171398` passed actionlint and every WINDO workflow-policy check. The policy now rejects regression to the superseded Node-20 pins.
- The original workflow estate contained fourteen definitions on the hardening branch. Three superseded Prometheus orchestration workflows and the standalone Engineer Journal Guard were retired after equivalent/current coverage was proven, reducing the estate to ten definitions.
- `validate.yml` had duplicated substantial runtime/release work from `windo-ci.yml`. It was replaced with a one-job `WINDO Fast Gate` rather than another matrix. Fast Gate run `33979527581` passed its first real PR proof, including PS5.1 parsing, reserved-variable safety, source logic, and the reusable Engineer Journal contract.
- `windo-ci.yml` was reshaped into `WINDO Deep Certification`: Node-24-native dependencies, one stable aggregate, no duplicate workflow-security job, and no obsolete development-lab branch trigger.
- Engineer Journal enforcement moved from YAML-only logic into `tools/Test-WindoJournalContract.ps1`. A reusable `tools/New-WindoJournalEntry.ps1` now creates modular entries under `docs/engineer-journal/`.
- Journal Capture no longer requests `pull-requests: write` or claims to open PRs. It may only create one isolated journal branch.
- Repair Laboratory was reduced from a mixed diagnostic/writer/PR workflow to a read-only laboratory that produces runtime, generated-patch, and trust evidence.
- The workflow writer allow-list is now only Journal Capture and Release Factory. `pull-requests: write` is forbidden by repository workflow policy.
- Issue #8 exposed two generated-byte defects unrelated to the DPAPI repair: host-sensitive installer newlines and an unpinned `tools/ChildExec.b64.txt` newline conversion. The generator is now LF-canonical and structurally synchronizes the large `RunnerContent` assignment through PowerShell AST rather than a giant regex; `.gitattributes` pins the generated payload to LF.
- Issue #8 strict certification run `33979646249` passed PS5.1 on Server 2022/2025, PS7 on Server 2022/2025, generated runtime/checksum reproducibility, PreSign validation, and the aggregate `WINDO Issue 8 runtime green` check.
- The remaining general CI red on Issue #8 is isolated to `Verify signed release manifest`. Parsing, source contract, reserved-variable checks, and ChildExec parity pass first; compatibility jobs are then skipped. This is the intended private-signature boundary after changing signed release bytes.
- GitHub reports `jonex/windo-production-ready` as unprotected with required-status enforcement disabled.

### Alternatives considered

- Ignore historical zero-job failures because later runs eventually became green.
- Delete or hide failed workflow history to make the Actions page look cleaner.
- Continue allowing repair CI to push directly into the branch under test and add retry/rebase logic around races.
- Treat an attempted external side effect as success without proving the resulting state exists.
- Keep workflow YAML as an unlinted configuration layer and rely on GitHub to reject malformed definitions after commit.
- Allow mutable tags or obsolete Action runtimes for convenience.
- Keep both `validate.yml` and `windo-ci.yml` as overlapping runtime/release matrices.
- Keep Repair Laboratory as a broad writer because deterministic regeneration sometimes produces a diff.
- Continue storing every future Engineer Journal entry in one monolithic file even as concurrent engineering lanes multiply.
- Remove security/reproducibility coverage merely to reduce the number of Actions boxes.

### Decision / hypothesis

WINDO CI is a product safety subsystem with explicit workflow roles and explicit failure semantics.

The automatic PR path is intentionally three layers: **Workflow Definition Guard → Fast Gate → Deep Certification**. Fast Gate answers cheap questions quickly. Deep Certification owns expensive Windows/runtime/trust/reproducibility evidence. Definition Guard proves the CI platform itself before trusting either.

Ordinary validation and laboratories are read-only. Repository mutation is exceptional: Journal Capture may create one isolated journal branch, and Release Factory may publish release state only from a certified exact commit. `pull-requests: write` is not granted to Actions.

Every external Action is pinned to an immutable 40-character SHA and must use the approved runtime generation. Workflow definitions are validated by actionlint plus WINDO policy covering dependency pins, write authority, force/direct pushes, and manual-only roles.

Generated release bytes are canonical across operating systems. Generators own normalization and structural synchronization; tests do not excuse host-dependent differences. Large PowerShell generated blocks are synchronized by AST structure when feasible rather than regex spanning thousands of lines.

A green step that requests an external mutation is not evidence that the mutation occurred. Either the durable result is observable or the workflow does not claim it.

Meaningful failed experiments remain part of engineering history. Zero-job parser noise and preventable orchestration races are CI defects to eliminate, not product failures to normalize.

The Engineer Journal uses append-only one-file-per-entry records under `docs/engineer-journal/` for concurrent work while preserving `docs/ENGINEER_JOURNAL.md` as historical memory.

### Result

The hardening branch has moved from fourteen overlapping workflow definitions to ten clearer definitions without removing current coverage simply for visual cleanliness.

The ordinary PR contract is now visibly shaped as Definition Guard, Fast Gate, and Deep Certification. Manual Flake Hunter, Regression Bisect, and Repair Laboratory remain separate because they answer different engineering questions without creating automatic PR noise.

The active workflow estate is standardized on Node-24-native immutable Action commits, and Definition Guard has proven the resulting estate satisfies syntax and WINDO policy.

Repair Laboratory is read-only. Journal Capture is a narrow modular-entry branch writer. Release Factory remains the only release writer. Failure Triage follows the new steady-state workflow names on the production lineage.

Issue #8 strict hosted certification is fully green through PreSign and deterministic regeneration. The normal signed-release contract stops exactly at the stale private signature, preserving the intended signing trust boundary.

`docs/CI_ARCHITECTURE.md` now describes the proven architecture rather than the earlier consolidation roadmap. Issue #10 tracks repository-side branch protection. Issue #11 tracks privileged disposable-Windows certification before public release.

### Follow-up

- Keep Issue #8 release bytes unchanged until the refreshed checksum manifest is privately signed outside hosted Actions.
- After the Issue #8 signed runtime lands, absorb its strict shipping-helper DPAPI proof into Deep Certification and remove the temporary PS5.1 baseline waiver.
- Retire Issue #8-specific certification/materializer workflows once their durable proof exists in the general platform.
- Update the thin default-branch `Exodus` failure listener to subscribe to `WINDO Workflow Definition Guard`, `WINDO Fast Gate`, and `WINDO Deep Certification`; retire the duplicate when the default branch moves.
- Make the tracked generated repair report deterministic or move volatile generation time into workflow evidence so timestamp-only branches cannot be materialized.
- Configure and verify server-side branch protection under Issue #10 using the stable aggregate checks.
- Build and prove the privileged disposable Windows certification lane under Issue #11 before publication.
