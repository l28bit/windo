# WINDO Engineer Journal

This file is the durable engineering memory for WINDO.

It records not only **what** changed, but **why**: observations, hypotheses, alternatives considered, experiments, failed approaches, evidence, decisions, tradeoffs, security boundaries, follow-up work, and final outcomes.

## Journal contract

1. **Append; do not rewrite history.** Correct an older conclusion with a newer entry that references it.
2. **Record rejected options.** Knowing why an apparently attractive path was rejected prevents repeated work.
3. **Separate evidence from inference.** Logs, hashes, test results, and reproduced behavior are evidence. Architectural conclusions drawn from them are decisions or hypotheses.
4. **Preserve failures.** A failed experiment that narrows the search space is useful engineering work.
5. **Security decisions require rationale.** Trust boundaries, signing, elevation, permissions, and fail-closed behavior must include the reason for the chosen boundary.
6. **Generated code and release artifacts are part of the design.** Record how canonical source flows into generated artifacts and how parity is proven.
7. **Every material runtime, CI, release, security, or architecture PR updates this journal.** The `WINDO Engineer Journal Guard` enforces that contract.

## Entry template

```text
## YYYY-MM-DD — <title>

**Category:** decision | experiment | incident | architecture | release | security | tooling
**Status:** proposed | active | validated | superseded | resolved
**Related:** PR / issue / workflow run / commit

### Context / question
...

### Evidence / observations
...

### Alternatives considered
- ...

### Decision / hypothesis
...

### Result
...

### Follow-up
- ...
```

---

## 2026-09-04 — Establish hosted CI as a product safety system

**Category:** architecture / tooling / security  
**Status:** active  
**Related:** PR #6, branch `ci/hosted-runner-lab-20260903`

### Context / question

WINDO had validation scripts and specialized recovery workflows, but the production-ready lineage did not have a trustworthy, continuously executing hosted validation baseline. Several historical Actions runs failed before creating jobs, so a red badge did not reliably mean WINDO code had failed.

### Evidence / observations

- `validate.yml` could fail with zero jobs because the workflow selected `shell:` dynamically from a matrix.
- Existing local validation already covered substantial release, parser, signing, and logic behavior; the missing piece was dependable orchestration across real Windows runner generations and PowerShell hosts.
- `jonex/windo-production-ready` is the current public-facing lineage and descends directly from the Prometheus repair work.

### Alternatives considered

- Continue relying primarily on local validation.
- Keep one `windows-latest` / PowerShell 7 lane for speed.
- Build separate explicit compatibility lanes and treat hosted CI as a release contract.

### Decision / hypothesis

Use explicit Windows PowerShell 5.1 and PowerShell 7 jobs across Windows Server 2022 and 2025, plus independent trust, generated-artifact, negative-path, and workflow-security gates. Keep an aggregate `WINDO CI green` check so one clearly named signal represents the full contract.

The existing dynamic-shell matrix was replaced rather than worked around because a validation system that can fail before allocating a job is not trustworthy evidence.

### Result

The new CI fabric began executing real tests. PowerShell 7 became fully green across Server 2022 and 2025; the system also exposed reproducible Windows PowerShell 5.1 compatibility failures that had previously been hidden behind unreliable workflow failures.

### Follow-up

- Keep compatibility failures visible; do not weaken assertions merely to produce green CI.
- Add automated failure triage and a controlled repair laboratory.

---

## 2026-09-04 — Stable public installer should be a release asset, not branch plumbing

**Category:** release / security / architecture  
**Status:** active  
**Related:** PR #6

### Context / question

The public install experience should have a memorable, durable URL and should not expose internal branch names as the primary user interface.

### Evidence / observations

`bootstrap.ps1` already implements the important trust behavior: resolve the tracking branch to an immutable Git commit, download the installer, verify release metadata/checksums, and stop at the explicit UAC boundary. The large installer itself should not be piped directly through `Invoke-Expression`.

### Alternatives considered

- Keep publishing only a raw `bootstrap.ps1` branch URL.
- Create a second independent friendly bootstrap implementation.
- Publish the canonical bootstrap as a stable GitHub Release asset.

### Decision / hypothesis

The human-facing asset is `WINDO-Install-Latest.ps1`, intended to live at:

`https://github.com/l28bit/windo/releases/latest/download/WINDO-Install-Latest.ps1`

The release factory copies the exact canonical `bootstrap.ps1` into that asset rather than maintaining a second implementation. This preserves one trust implementation while giving users a stable name.

### Result

The release factory and public canary were designed around this stable asset name. The raw production branch remains useful for engineering/debugging, not as the preferred human-facing contract.

### Follow-up

- Publish only after the complete certification gate passes and private signing is complete.
- Canary-test the exact public URL after publication.

---

## 2026-09-04 — Separate hosted validation from privileged Windows certification

**Category:** security / architecture  
**Status:** validated  
**Related:** PR #6

### Context / question

WINDO is an elevation tool, but GitHub-hosted Windows runners cannot interactively approve UAC. The CI design needed to be exhaustive without pretending it could certify a boundary it cannot cross.

### Alternatives considered

- Treat hosted runners as sufficient end-to-end elevation certification.
- Disable UAC-sensitive tests entirely.
- Split continuous software validation from final privileged behavioral certification.

### Decision / hypothesis

Use two tiers:

1. **GitHub-hosted Windows:** parser, logic, trust chain, generated-artifact parity, failure paths, release packaging, and explicit validation through the expected UAC handoff boundary.
2. **Disposable/self-hosted Windows certification:** real `install -> elevate -> command -> stdout/stderr -> exit code -> Ctrl+C -> uninstall` behavior.

Hosted CI must explicitly prove that it stops at the correct elevation boundary rather than silently skipping it.

### Result

The negative-path lane successfully proves the hosted elevated-bootstrap boundary fails in the expected controlled manner.

### Follow-up

- Add a disposable Windows certification runner when the production release pipeline reaches that phase.

---

## 2026-09-04 — Release publication gets a narrower trust boundary than certification

**Category:** security / release  
**Status:** active  
**Related:** PR #6

### Context / question

A workflow that validates code should not automatically possess the same authority as a workflow that publishes a release.

### Alternatives considered

- Give the entire release workflow `contents: write`.
- Store the private release signing key in GitHub Actions and fully automate signing.
- Keep certification read-only and isolate the publishing capability.

### Decision / hypothesis

Certification remains read-only. Only the explicit publish job receives `contents: write`, publication defaults to off, and the publish job uses the exact commit emitted by certification so a moving branch cannot change the source between certify and publish.

The private signing key remains outside hosted GitHub Actions.

### Result

The release pipeline can produce and validate a candidate without granting unnecessary write authority or moving the private signing boundary into public CI.

### Follow-up

- Maintain SHA-pinning and minimal permissions on every new action.

---

## 2026-09-04 — Windows PowerShell 5.1 compatibility failures are real signal, not a reason to weaken CI

**Category:** incident / experiment  
**Status:** open  
**Related:** `docs/ps51-compatibility-findings.md`, PR #6

### Context / question

The new four-lane Windows matrix passed completely under PowerShell 7 but failed reproducibly under Windows PowerShell 5.1 on both Windows Server 2022 and 2025.

### Evidence / observations

Three repeatable findings were isolated:

1. A fresh PS5.1 process cannot initially resolve `System.Security.Cryptography.ProtectedData`; WINDO's current lookup therefore returns null and DPAPI fixture sealing fails.
2. The exact raw-text comparison between embedded and maintained uninstaller content is PS5.1-sensitive even while signed release hashes validate.
3. An intentionally invalid quoted installer path is rejected earlier by .NET Framework with `Illegal characters in path.` before WINDO reaches its preferred `unsupported quote` error.

PowerShell 7 passes the same deep release/logic validation on both runner generations. PS5.1 still passes parser/release validation, signed manifest verification, and PSScriptAnalyzer.

### Alternatives considered

- Skip DPAPI tests in PS5.1.
- Accept the PS7 result as sufficient.
- Make the tests platform-correct while preserving the underlying security properties, and repair actual PS5.1 runtime compatibility where required.

### Decision / hypothesis

Do not remove or bypass the failing security coverage. Explicitly load the required framework assembly before resolving `ProtectedData`; normalize canonical text for parity comparisons instead of relying on host-dependent decoding; and assert that unsafe paths are rejected regardless of whether the rejection originates in WINDO or the platform first.

Any runtime/generated-artifact repair must flow through regeneration and private release signing.

### Result

The production PR remains draft and blocked rather than being forced green. Forensic packs are now retained for both Windows runner generations.

### Follow-up

- Build targeted diagnostic automation to test proposed PS5.1 loading and normalization strategies.
- Repair PS5.1 compatibility in a separate, reviewable change.

---

## 2026-09-04 — Engineer Journal becomes a required engineering artifact

**Category:** process / architecture  
**Status:** active  
**Related:** PR #6

### Context / question

Important engineering reasoning had accumulated in conversations, commits, and individual documents, but no single durable chronology captured why decisions were made, what failed, or which alternatives had already been explored.

### Alternatives considered

- Rely on commit messages and PR descriptions.
- Store only final architecture documents.
- Maintain an append-only engineering journal alongside code and enforce updates for material changes.

### Decision / hypothesis

Adopt this Engineer Journal as a first-class repository artifact. Material runtime, tooling, CI, release, security, or architecture changes must update it. Automated failures may generate **journal-ready incident candidates**, but automation must not rewrite canonical engineering history without review.

Deterministic repair workflows may append their experiment/result to the repair branch because that journal entry is reviewed with the resulting patch.

### Result

The journal is now part of the WINDO engineering contract rather than optional documentation.

### Follow-up

- Add a PR journal guard.
- Add a manual journal-entry workflow for low-friction capture.
- Reuse this pattern as a standard starting point for future projects.
