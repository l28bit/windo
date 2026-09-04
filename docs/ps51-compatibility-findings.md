# Windows PowerShell 5.1 Compatibility Findings

Status: **known signed-runtime debt tracked by Issue #8 with an exact CI baseline**

Tracking: https://github.com/l28bit/windo/issues/8

Validated against:

- GitHub-hosted Windows Server 2022 / Windows PowerShell 5.1.20348.5499
- GitHub-hosted Windows Server 2025 / Windows PowerShell 5.1.26100.33296
- PowerShell 7 on both runner generations as a control

PowerShell 7 passes the release validator, logic suite, PSScriptAnalyzer, and deep pre-sign validation on both Windows runner generations. Windows PowerShell 5.1 passes release validation, signed checksum verification, and PSScriptAnalyzer but fails the full logic/deep path reproducibly on both runner generations.

## Finding 1: ProtectedData is not loaded in a fresh Windows PowerShell 5.1 process

A focused pre-test probe demonstrated the same behavior on Server 2022 and Server 2025:

- `[System.Security.Cryptography.ProtectedData]` cannot initially be resolved.
- `Type.GetType('System.Security.Cryptography.ProtectedData, System.Security.Cryptography.ProtectedData', false)` returns null.
- `Type.GetType('System.Security.Cryptography.ProtectedData, System.Security', false)` returns null.
- WINDO's current `Get-WindoProtectedDataType` therefore returns null.
- The full logic suite later fails when it expects `_dpapi_protect` to seal a fixture.

This is a compatibility defect in the current shipping lookup strategy, not evidence that the signed release files are corrupt. `Validate-Windo.ps1 -RequireCurrentSnapshot` and the signed checksum verifier pass under Windows PowerShell 5.1 before the behavioral tests run.

The CI baseline validator independently proves that explicitly loading the .NET Framework `System.Security` assembly restores a CurrentUser DPAPI protect/unprotect round-trip. That proof deliberately occurs outside shipping runtime code; the runtime remains unchanged until the generated artifacts can be regenerated and the release can be re-signed through the private signing boundary.

### Repair direction

The Windows PowerShell 5.1 implementation should explicitly load the framework assembly that provides `ProtectedData` before performing type resolution, while preserving fail-closed behavior on unsupported hosts and retaining the existing PowerShell 7 path.

Any runtime repair must be propagated through the generated runner/installer artifacts and the release manifest must be regenerated and re-signed through the private signing environment. The private release key must not be added to GitHub-hosted CI.

## Finding 2: embedded uninstaller raw-text comparison is PS5.1-sensitive

The logic suite reports:

`installer embeds the maintained uninstaller without runtime drift`

as false under Windows PowerShell 5.1 on both runner generations. The same assertion passes under PowerShell 7, while release hashes and the signed release contract validate under Windows PowerShell 5.1.

### Repair direction

Treat this as a test-harness compatibility issue. Compare canonical/published text rather than relying on host-dependent raw text decoding/line-ending behavior. The comparison should still detect real generated-artifact drift and must not be weakened into a substring or semantic-only test.

## Finding 3: unsafe quoted installer path fails earlier on PS5.1

The safety test intentionally passes an installer path containing a double quote. Windows PowerShell 5.1/.NET Framework rejects the path first with:

`Illegal characters in path.`

The test currently requires WINDO's later message containing `unsupported quote`, so the assertion fails even though the unsafe input was rejected.

### Repair direction

Assert the security property: the unsafe quoted path must be rejected. Accept the platform-native invalid-path failure as well as WINDO's explicit unsupported-quote failure, while continuing to fail if the path is accepted or converted into an executable argument line.

## Exact known-baseline policy

`tools/Test-WindoKnownPs51Baseline.ps1` exists only to let the CI/journal/diagnostic platform land without pretending Issue #8 is repaired.

It is intentionally narrower than `continue-on-error`:

- release validation must still pass;
- PSScriptAnalyzer setup and scan must still pass;
- any unknown `FAIL:` line rejects the baseline;
- a failing logic/deep transcript must contain the known DPAPI fixture signature;
- a failing DPAPI probe must still show the exact fresh-process type-resolution signature;
- the validator then explicitly loads `System.Security` and requires a successful DPAPI encrypt/decrypt round-trip;
- if all PS5.1 tests become green, the baseline is not used at all.

The baseline is therefore a machine-verifiable statement of known debt, not permission for PS5.1 to fail generally.

## What remains green

The following gates are already passing independently of these PS5.1 findings:

- release-critical PowerShell parsing
- reserved automatic-variable guard
- ChildExec source/Base64 parity
- signed checksum-manifest verification
- production tracking/immutable-commit bootstrap contract
- generated ChildExec reproducibility
- tampered signed-manifest rejection
- hosted-runner elevated-bootstrap boundary rejection
- PSScriptAnalyzer error-level scan on PS5.1 and PS7
- full PS7 release/logic/deep validation on Windows Server 2022 and 2025
- workflow action SHA-pinning policy

## Merge and removal policy

PR #6 may merge only if the PS5.1 final gate recognizes exactly this documented baseline and every independent trust/release/PS7/reproducibility/security gate remains green.

The baseline must be removed by the signed Issue #8 repair. That repair is complete only after canonical source is fixed, generated artifacts are regenerated, the full PS5.1/PS7 Windows matrix is green without the waiver, release metadata is rebuilt, the private signature is refreshed outside hosted CI, and privileged Windows certification succeeds.
