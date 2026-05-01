# WINDO Brand Asset Pack

WINDO is a PowerShell-first elevation helper for Windows: choose elevation before execution.

## Brand mark
The final mark combines a security shield, a PowerShell-style prompt, and Windows-style panes. Small tray sizes use a simplified chevron, while larger icon/logo sizes preserve the full `>_` terminal identity.

## Color system
- Dark navy: #07111F
- Deep navy: #0B1220
- Windows blue: #0078D4
- Electric blue: #00A8FF
- Cyan/elevated: #00C2D6
- Green/allowed: #22C55E
- Yellow/warning: #FFC400
- Red/denied: #E53935
- Silver/neutral: #A7B0BC
- White: #FFFFFF

## Naming
- `windo-logo-full-*` = full horizontal logo
- `windo-brand-mark-*` = standalone mark
- `windo-tray-*` = tray/app state icons
- `icon-*` = UI action icons
- `status-*` = compact circular status indicators
- `badge-*` = pill-style status labels

## Regeneration
Install Inkscape and ImageMagick, then run:
- `./export-assets.sh`
- `./export-assets.ps1`

ICO files are real Windows ICO files and include 16, 24, 32, 48, 64, 128, and 256 px images.
