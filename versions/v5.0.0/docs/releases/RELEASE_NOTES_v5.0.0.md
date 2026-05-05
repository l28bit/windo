# Release notes - WINDO v5.0.0

v5.0.0 is the Command Center Special Edition: a PowerShell-native Windows command center for deliberate elevation.

## New: `windo center`

```powershell
windo center
windo center open
windo center tray
windo center queue surface-prime
windo center run launchpad-tray
windo center history
```

Command Center unifies:

- tray
- control plane
- Signal Deck
- native surface
- motion
- trust/source
- recipes/modules/extras
- audit/export

The first V5 center is PowerShell-native and Windows Forms/tray based. A compiled companion helper is only scaffolded for a later special release.

## Boundaries

- No hidden arbitrary command execution.
- Curated action IDs remain the command-center execution contract.
- Existing WINDO trust, audit, and elevation boundaries remain authoritative.
