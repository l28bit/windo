# WINDO CI and Release Contract

WINDO now has two distinct validation tiers.

## Continuous hosted validation

`WINDO CI Fabric` runs on pull requests to `jonex/windo-production-ready`, pushes to the production-ready branch, the hosted-runner lab branch, and manual dispatches.

It verifies:

- PowerShell parsing of release-critical scripts.
- Reserved automatic-variable safety.
- ChildExec source/Base64 parity.
- The production branch and immutable-commit bootstrap contract.
- The signed checksum manifest.
- Windows PowerShell 5.1 and PowerShell 7 on Windows Server 2022 and 2025 hosted runners.
- `Validate-Windo.ps1 -RequireCurrentSnapshot`.
- The full logic suite.
- PSScriptAnalyzer error-severity checks.
- Prometheus pre-sign contract validation in worker mode.
- Generated ChildExec reproducibility.
- Fail-closed behavior for an impossible immutable release commit.
- Commit-SHA pinning for actions used by the new WINDO workflows.
- Failure forensic artifacts when a compatibility lane fails.

The hosted runners intentionally stop at the UAC boundary. GitHub-hosted automation cannot approve an interactive UAC prompt, so a successful hosted run proves everything up to the privileged handoff rather than pretending to prove the handoff itself.

## Privileged behavioral certification

The final end-to-end certification remains a disposable Windows machine or isolated self-hosted runner that can exercise:

`install -> UAC/elevate -> command -> stdout/stderr -> exit code -> Ctrl+C -> uninstall`

That machine must not carry the private release-signing key unless it is explicitly the signing environment.

## Human-facing installer

The stable public installer name is:

`WINDO-Install-Latest.ps1`

The stable public URL is:

`https://github.com/l28bit/windo/releases/latest/download/WINDO-Install-Latest.ps1`

The Release Factory creates that asset by copying the exact canonical `bootstrap.ps1` from `jonex/windo-production-ready`. This prevents a friendly filename from becoming a second implementation that can drift.

The full `windo_install.ps1` is still downloaded by the bootstrap and is not piped directly through `Invoke-Expression`.

## Release Factory

`WINDO Release Factory` is manual and defaults to **not publishing**.

The certify job is read-only. It checks out `jonex/windo-production-ready`, runs full validation including the existing signature verifier, creates the release bundle, and uploads the exact candidate as a GitHub Actions artifact.

Publishing is a separate job with `contents: write`, enabled only when the operator explicitly sets `publish=true`. It creates or updates the requested GitHub Release and uploads the stable installer plus the signed manifest, signature, public key, commit marker, checksums, and ZIP bundle.

The publish job checks out the exact commit emitted by the certification job, so a branch update cannot replace the tested source between certification and publication.

No private signing key is stored in the public repository or required by hosted CI.

## Published canary

`WINDO Published Release Canary` runs daily and can also be dispatched manually. It downloads the same `/releases/latest/download/WINDO-Install-Latest.ps1` URL a stranger would use, parses it under Windows PowerShell 5.1 and PowerShell 7, and requires it to match the current production branch's canonical bootstrap.

A repository that is green while the published asset is stale or broken is therefore treated as a release failure rather than a success.
