# Release notes - WINDO v3.6.6 Special Edition

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

**Theme:** Start shaping the V4 platform layer without executing anything.

v3.6.6 adds the first Operator Mesh preview command. It is intentionally read-only: one command shows how the local platform pieces are lining up, but it does not fetch extras, start launchpad, write exports, or run elevated work.

## New: `windo mesh`

`windo mesh` inventories:

- local modules and enabled module ids
- built-in recipes and preview/run commands
- extras index URL and installed extras
- launchpad terminal/html/tray readiness
- detected tray icon and brand logo assets
- export bundle readiness and latest export zip

Examples:

```powershell
windo mesh
windo mesh --json
```

## Why it matters

This is the first visible bridge toward the V4 Operator Mesh. It gives operators one place to inspect modules, recipes, extras, launchpad, and support export readiness before those pieces become a more cohesive workflow layer.

## Validation

```powershell
windo mesh
windo mesh --json
windo roadmap
windo trust --online
```

Expected result:

- `windo mesh` prints a compact platform inventory.
- `windo mesh --json` returns `command=mesh` with `payload.exitCode=0`.
- `windo roadmap` still keeps future major-package details reserved.
- Online trust passes after the release is published and checksums are synced.
