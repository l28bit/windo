# Windows PowerShell 5.1 Compatibility Findings

Status: **open compatibility blockers discovered by `WINDO CI Fabric`**

Validated against:

- GitHub-hosted Windows Server 2022 / Windows PowerShell 5.1.20348.5499
- GitHub-hosted Windows Server 2025 / Windows PowerShell 5.1.26100.33296
- PowerShell 7 on both runner generations as a control

PowerShell 7 passes the release validator, logic suite, PSScriptAnalyzer, and deep pre-sign validation on both Windows runner generations. Windows PowerShell 5.1 passes release validation and PSScriptAnalyzer but fails the full logic/deep path reproducibly on both runner generations.

## Finding 1: ProtectedData is not loaded in a fresh Windows PowerShell 5.1 process

A focused pre-test probe demonstrated the same behavior on Server 2022 and Server 2025:

- `[System.Security.Cryptography.ProtectedData]` cannot initially be resolved.
- `Type.GetType('System.Security.Cryptography.ProtectedData, System.Security.Cryptography.ProtectedData', false)` returns null.
- `Type.GetType('System.Security.Cryptography.ProtectedData, System.Security', false)` returns null.
- WINDO's current `Get-WindoProtectedDataType` therefore returns null.
- The full logic suite later fails when it expects `_dpapi_protect` to seal a fixture.

This is a compatibility problem in the current lookup strategy, not evidence that the signed release files are corrupt. `Validate-Windo.ps1 -RequireCurrentSnapshot` and the signed checksum verifier pass under Windows PowerShell 5.1 before the behavioral tests run.

### Repair direction

The Windows PowerShell 5.1 implementation should explicitly load the framework assembly that provides `ProtectedData` before performing type resolution, while preserving fail-closed behavior on unsupported hosts and retaining the existing PowerShell 7 path.

Any runtime repair must be propagated through the generated runner/installer artifacts and the release manifest must be regenerated and re-signed through the private signing environment. The private release key must not be added to GitHub-hosted CI.

## Finding 2: embedded uninstaller raw-text comparison is PS5.1-sensitive

The logic suite reports:

`installer embeds the maintained uninstaller without runtime drift`

as false under Windows PowerShell 5.1 on both runner generations. The same assertion passes under PowerShell 7, while release hashes and the signed release contract validate under Windows PowerShell 5.1.

### Repair direction

Treat this first as a test-harness compatibility issue. Compare canonical/published text rather than relying on host-dependent raw text decoding/line-ending behavior. The comparison should still detect real generated-artifact drift and must not be weakened into a substring or semantic-only test.

## Finding 3: unsafe quoted installer path fails earlier on PS5.1

The safety test intentionally passes an installer path containing a double quote. Windows PowerShell 5.1/.NET Framework rejects the path first with:

`Illegal characters in path.`

The test currently requires WINDO's later message containing `unsupported quote`, so the assertion fails even though the unsafe input was rejected.

### Repair direction

Assert the security property: the unsafe quoted path must be rejected. Accept the platform-native invalid-path failure as well as WINDO's explicit unsupported-quote failure, while continuing to fail if the path is accepted or converted into an executable argument line.

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

## Merge policy

Do not make the PS5.1 lane green by skipping DPAPI tests or removing the failing assertions. Repair the compatibility behavior or make the tests platform-correct while preserving the underlying security guarantees.
