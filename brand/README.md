# WINDO brand assets

![WINDO logo](final/assets/logo/windo-logo-full-dark-512.png)

## Canonical Pack

Use `brand/final/` as the production asset pack.

- `brand/final/assets/logo/` - full logo PNG/SVG exports.
- `brand/final/assets/png/` - brand marks, status icons, and tray PNGs.
- `brand/final/assets/svg/` - scalable brand marks and status icons.
- `brand/final/assets/tray/` - tray state PNG/SVG assets.
- `brand/final/assets/ico/` - Windows tray/app ICO files with 16, 24, 32, 48, 64, 128, and 256 px entries.
- `brand/final/assets/ui-icons/` - UI action icons in PNG/SVG form.
- `brand/final/assets/badges/` - pill-style status badges.
- `brand/final/assets/manifest.json` - asset inventory and intended use.

The older `assets/` tree and `tools/Split-BrandAssets.ps1` are retained for historical source-sheet slicing, but new WINDO UI and docs should prefer `brand/final/`.

## Runtime Use

`windo launchpad --tray` resolves the clean ready-state icon from:

1. `WINDO_TRAY_ICON`
2. `Documents\GitHub\windo\brand\final\assets\ico\windo-tray-ready.ico`
3. `Documents\windo\brand\final\assets\ico\windo-tray-ready.ico`
4. `Documents\windo\assets\ico\windo-tray-ready.ico`

If none are present, WINDO falls back to the Windows shield icon.
