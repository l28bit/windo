# Release notes - WINDO v4.6.0

v4.6.0 is the Native Shell Polish release. It hardens the browser-independent Windows-native surface before V5.

## Native surface commands

```powershell
windo surface doctor
windo surface repair
windo surface open
```

`doctor` checks Windows desktop/runtime readiness, Windows Forms, STA tray support, tray script freshness, surface/control manifests, profile prompt health, and motion policy.

`repair` primes surface and control manifests and guards prompt init where needed.

`open` starts the native tray command center.

## Companion scaffold

`native-companion/` is a placeholder for a future compiled Windows helper. V5 remains PowerShell-native and does not require a compiled binary.
