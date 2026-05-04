# Release notes - WINDO v3.6.7 Special Edition

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

**Theme:** Turn the Operator Mesh preview into a local cockpit.

v3.6.7 makes the V4-prep mesh more visual without making it more dangerous. The new cockpit writes a local HTML artifact from the same read-only inventory as `windo mesh`.

## New: `windo mesh --html`

Examples:

```powershell
windo mesh --html
windo mesh --open
windo mesh --output "$HOME\Documents\windo\mesh.html"
```

The cockpit includes:

- module and recipe counts
- tray and brand asset readiness
- copy-ready next commands
- recipe preview rows
- module discovery rows
- platform paths for modules, extras, exports, and brand assets

## Safety model

`windo mesh --html` only writes a local HTML file. It does not fetch extras, start the tray, export bundles, register tasks, or run elevated commands.

## Validation

```powershell
windo mesh
windo mesh --json
windo mesh --html
windo trust --online
```

Expected result:

- `windo mesh --html` prints the generated HTML path.
- JSON output includes `payload.htmlPath` when HTML output is requested.
- Online trust passes after the release is published and checksums are synced.
