# WINDO brand assets

Source files:

- `winDO.png` - full square logo artwork.
- `WINDO_icon_banners_trayicon_avatar.png` - flattened contact sheet containing logos, icons, tray states, badges, and banners.
- `individual_and_Transparent.png` - alpha-capable transparent pack used for production-friendly tray/app assets.

Generated files:

- `assets/logos/` - logo crops and avatar panel.
- `assets/icons/` - individual command/action icon crops.
- `assets/tray/` - tray-state crops plus 32px PNG variants.
- `assets/badges/` - status badge crops.
- `assets/banners/` - header/banner crops.
- `assets/brand-elements/` - small reusable shield, chevrons, and progress elements.
- `assets/transparent/` - preferred transparent crops from `individual_and_Transparent.png`.
- `assets/transparent/ico/` - generated multi-size Windows `.ico` files for tray/app use.

Regenerate:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Split-BrandAssets.ps1
```

## Source quality note

The original contact sheet is a flattened 24-bit PNG without transparency or separate layers. Those crops are still useful for docs, local HTML dashboards, installer visuals, and dark-background UI.

For production tray/app visuals, prefer `assets/transparent/` and `assets/transparent/ico/`, generated from `individual_and_Transparent.png`.

## Best handoff format for future artwork

Ask the creator to provide:

- Individual transparent PNG files for every logo, icon, tray state, badge, and banner.
- SVG source for vector-safe logos and icons when possible.
- A multi-size `.ico` for Windows tray/app use with at least 16x16, 24x24, 32x32, 48x48, and 256x256 entries.
- Light and dark variants where an asset is expected to sit on both backgrounds.
- No labels baked into icon-only assets; provide labels as text in the app/docs.
- A source design file or export manifest with asset names, intended use, dimensions, and safe padding.

Recommended naming:

- `windo-logo-full-dark.png`
- `windo-logo-full-light.png`
- `windo-logo-mark-transparent.png`
- `windo-tray-ready.ico`
- `windo-tray-warning.ico`
- `windo-tray-denied.ico`
- `icon-elevate.svg`
- `badge-elevated.png`
