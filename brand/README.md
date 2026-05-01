# WINDO brand assets

![WINDO logo](Enterprise/assets/logo/windo-logo-full-dark-512.png)

## Canonical Pack

Use `brand/Enterprise/` as the production asset pack.

- `brand/Enterprise/assets/logo/` - full logo PNG/SVG exports.
- `brand/Enterprise/assets/png/` - brand marks and tray PNGs.
- `brand/Enterprise/assets/svg/` - scalable contained brand marks.
- `brand/Enterprise/assets/tray/` - tray state PNG/SVG assets.
- `brand/Enterprise/assets/ico/` - Windows tray/app ICO files with 16, 24, 32, 48, 64, 128, and 256 px entries.
- `brand/Enterprise/assets/status/` - compact status icons.
- `brand/Enterprise/assets/ui-icons/` - UI action icons in PNG/SVG form.
- `brand/Enterprise/assets/badges/` - pill-style status badges.
- `brand/Enterprise/assets/manifest.json` - asset inventory and intended use.

The older `assets/`, `assets/transparent/`, and `tools/Split-BrandAssets.ps1` paths are retained only for historical source-sheet slicing and previous iterations. New WINDO UI and docs should prefer `brand/Enterprise/`.

## Runtime Use

`windo launchpad --tray` resolves the clean ready-state icon from:

1. `WINDO_TRAY_ICON`
2. `Documents\GitHub\windo\brand\Enterprise\assets\ico\windo-tray-ready.ico`
3. `Documents\windo\brand\Enterprise\assets\ico\windo-tray-ready.ico`
4. `Documents\windo\assets\ico\windo-tray-ready.ico`

If none are present, WINDO falls back to the Windows shield icon.
