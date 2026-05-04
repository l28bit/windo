# Release notes - WINDO v3.6.8 Special Edition

Release date: 2026-05-04

## Summary

v3.6.8 adds a read-only Operator Mesh Doctor so the V4 platform runway has a concrete readiness signal before workflows get larger.

## New: `windo mesh doctor`

`windo mesh doctor` scores local readiness across:

- scheduled task bridge
- runner/updater integrity
- encrypted audit-chain verification
- built-in recipes
- local module discovery
- extras index configuration
- Enterprise brand/tray assets
- native tray support
- support export path

```powershell
windo mesh doctor
windo mesh doctor --json
```

The doctor does not fetch extras, start the launchpad, write exports, open the browser, run elevated commands, or mutate prefs. It only reads local state and prints next commands.

## JSON behavior

`windo mesh doctor --json` returns the standard `command=mesh` envelope with a doctor payload:

- `readinessLevel`: `READY`, `ATTENTION`, or `REPAIR`
- `score`: 0-100
- `checks`: detailed rows with fix commands
- `inventory`: embedded `windo mesh --json` inventory
- `recommendations`: next-step guidance
- `exitCode`: `0`, `3`, or `4`

## Updated

- `windo help mesh` now documents doctor mode.
- Tab completion now suggests `doctor` under `windo mesh`.
- The V4 roadmap now names Mesh Doctor as the readiness checkpoint.
