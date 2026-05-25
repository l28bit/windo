# WINDO v8.4.0 - Unreleased

## Summary

This release unifies installer identity under **V8.4** while preserving upgrade behavior and audit boundaries:

- Canonical branch: `Prometheus` (published contract)
- Development integration branch: `Exodus` (active until next Special Edition)
- Installer semver: `8.4.0` with `V8.4` branding
- Installer metadata: `releaseBranch=Prometheus`, `releaseBranchRaw=Prometheus`

## Features in this release

### Version contract

- `windo version --contract` shows edition, branch, schema, and branding.
- JSON `version` payloads include a `contract` object for automation.

### Network ops (6.x lineage)

- `windo net-scan`, `windo rdp`, `windo wsl`, `windo container`, and `extras/network-ops`.

### Sudo-like shell (7.x lineage)

- Aliases: `do`, `recdo`, `upd`, `health`, `check`, `status`.
- Explicit install/self-update `[y/N]` handoff with non-interactive paths.

### Command center (8.4 polish)

- V8.4 HTML/branding across launchpad, edition, and installer surfaces.
- New control actions: `open-windo-folder`, `health-snapshot-html`, `net-scan-status`, `studio-open`, `upgrade-history-open`, `center-open`.

## Migration

V8.4 preserves existing commands and runtime semantics, so existing deployments can continue to run the same command set during upgrade.

### Operators coming from V6.x

- `WINDO_TRACKING_BRANCH` is still honored and overrides branch source exactly as before.
- `WINDO_RELEASE_COMMIT` is still honored to pin a specific installer commit.
- Existing upgrade and repair flows continue to work using:
  - `windo install-latest`
  - `windo upgrade`
  - checksum validation from `checksums/installer.sha256`
- Branch defaults have moved from prior contract wording to `Prometheus`, so explicit overrides for older branch assumptions are unnecessary unless your environment still pins to a legacy branch.

### Operators coming from V7.x

- The same rollback and self-repair guardrails remain intact.
- If you used explicit branch overrides for compatibility, verify they still point to desired legacy streams.
- For environment continuity, the same command-line interface and installer handoff format remain in place.

## Contract changes

- Installer version displayed and manifest profile: `8.4.0` (`V8.4` branding).
- Default source branch for installer download paths moved from `Exodus`/`v6` conventions to `Prometheus`.
- Documentation and checksum manifest references were updated to match the new canonical branch.

## Release artifacts

- Release checksum manifest expected content in this release:
  - `releaseBranch=Prometheus`
  - `releaseBranchRaw=Prometheus`

## Compatibility

- No behavioral installer contract changes beyond canonical branch normalization and version labeling were introduced in this release.
- Existing `WINDO_TRACKING_BRANCH` and `WINDO_RELEASE_COMMIT` override semantics are unchanged.
