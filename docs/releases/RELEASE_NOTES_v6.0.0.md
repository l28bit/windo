# WINDO v6.0.0 - Unreleased

## Scope

- Canonical runtime source remains **`v6`** for bootstrap/install-update/checksum paths.
- Installer strict-mode and self-update repair behavior are now stabilized and shared across install and update surfaces.

## Added

- _None in this release._

## Changed

- Installer and repair source contract is now fixed to the canonical **`v6`** branch in release guidance and helper snippets.

## Fixed

- _No functional fixes added this release; contract text is now stabilized for operational consistency._

## Stabilized

- Installer integrity diagnostics now use a consistent contract:
  - Non-strict mode keeps compatibility paths as warnings.
  - `WINDO_STRICT_INSTALLER_VERIFICATION=1` promotes checksum/source/branch divergence to hard failures.
- Self-update repair remains interactive by default and now consistently returns repair guidance when running non-interactively.

## Contract notes

- `WINDO_STRICT_INSTALLER_VERIFICATION=1` changes installer behavior from compatibility warnings to fail-fast when checksum path, hash value, or branch/source checks diverge.
- `windo self-update` keeps installer repair interactive by default: interactive sessions prompt before repair launch, while non-interactive mode returns repair guidance without a confirmation prompt.
