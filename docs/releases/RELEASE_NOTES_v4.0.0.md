# Release notes - WINDO v4.0.0 Special Edition

Release date: 2026-05-04

## Summary

v4.0.0 is the Operator Mesh release. It promotes the shipped 3.x foundations into one coherent local workbench while keeping the future major package reserved.

## New: `windo mesh workbench`

`windo mesh workbench` organizes WINDO into workflow lanes:

- Trust and Source
- Network Recon
- Identity and Access
- System and Storage
- Services and Jobs
- WINDO Platform

Each lane combines existing recipes and WINDO commands into copy-ready cards. The workbench also embeds readiness, platform pieces, recommended flow, the Mesh Doctor payload, and the Mesh inventory payload.

```powershell
windo mesh workbench
windo mesh workbench --json
windo mesh workbench --html
windo mesh workbench --output "$HOME\Documents\windo\operator-mesh.html"
```

## Safety model

The v4 workbench is local-first and read-only. It does not fetch extras, run recipes, start launchpad, export bundles, register tasks, or elevate commands. It only presents reviewed next commands and local state.

## Native surface groundwork

The Mesh payload now includes a quiet native-surface capability map for Windows desktop readiness: tray support, Windows Forms availability, tray script path, brand/tray assets, and shell executable paths. This keeps the V4 workbench grounded while leaving larger native Windows platform work reserved for a future major release.

## Why v4 now

The remaining runway pieces are in place:

- Quiet Shell completion behavior
- Trust Console and source-of-truth validation
- Syntax Forge and Syntax Doctor
- Execution planning
- Mesh inventory, doctor, and cockpit
- Recipe Atlas
- native tray launchpad
- structured export support

That makes Operator Mesh a real platform layer instead of a label.

## Updated

- `windo roadmap` marks v4 Operator Mesh as shipped.
- `windo help mesh` documents workbench mode.
- Tab completion now suggests `workbench` under `windo mesh`.
- README, changelog, JSON schema, checksums, and version snapshot are updated for v4.0.0.
