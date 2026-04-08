# WINDO source fragments (optional)

End users install from **`windo_install.ps1`** at the repository root; no build is required.

This tree holds **maintainer-facing** snippets that mirror logic embedded in the installer-generated profile `windo` function. They are documentation and copy-paste sources; the shipping artifact remains the monolithic installer until an optional build pipeline is adopted.

| Path | Role |
|------|------|
| `snippets/JsonEnvelope.ps1` | JSON envelope helper aligned with `schemaVersion` **2.6** |
| `snippets/IntegrityLevels.ps1` | Integrity level helpers; must match `windo_install.ps1` embedded `_integrity_component_level` rules |
| (future) | Additional fragments as described in `docs/build.md` |

Installer **`$WindoBuiltinVerbs`** at the top of `windo_install.ps1` is the single source for built-in subcommand names (profile completer + `windo` last-command exclusions).

When changing behavior, update **both** the embedded block in `windo_install.ps1` and the matching fragment here (or regenerate via `tools/build.ps1 -Concat` for review-only concatenation).
