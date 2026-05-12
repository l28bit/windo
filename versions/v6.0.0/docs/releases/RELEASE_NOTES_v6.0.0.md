# WINDO v6.0.0 - Unreleased

## Scope

- Canonical runtime source remains **`Exodus`** for bootstrap/install-update/checksum paths.
- Installer strict-mode and self-update repair behavior are now stabilized and shared across install and update surfaces.

## Added

- _None in this release._

## Changed

- Installer and repair source contract is fixed to the canonical **`Exodus`** branch in release guidance and helper snippets, with explicit `WINDO_TRACKING_BRANCH` / `WINDO_RELEASE_COMMIT` overrides for roadmap-aligned environments.

## Fixed

- _No functional fixes added this release; contract text is now stabilized for operational consistency._

## Stabilized

- Installer integrity diagnostics now use a consistent contract:
  - Non-strict mode keeps compatibility paths as warnings.
  - `WINDO_STRICT_INSTALLER_VERIFICATION=1` promotes checksum/source/branch divergence to hard failures.
- Self-update repair remains interactive by default and now consistently returns repair guidance when running non-interactively.

## V8.4 roadmap alignment

- Onboarding docs, terminal demos, and command help now emphasize the canonical branch/commit contract and handoff prompt behavior before and after bootstrap/install actions.
- Legacy prompt recovery guidance for `SUDO_PROMPT`/`Input content` is now documented in installer runbooks.

## Contract notes

- `WINDO_STRICT_INSTALLER_VERIFICATION=1` changes installer behavior from compatibility warnings to fail-fast when checksum path, hash value, or branch/source checks diverge.
- `windo self-update` keeps installer repair interactive by default: interactive sessions prompt before repair launch, while non-interactive mode returns repair guidance without a confirmation prompt.
