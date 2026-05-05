# Release notes - WINDO v4.5.0

v4.5.0 is the Signal Deck release. It adds evidence-first diagnostic views over the control plane and existing WINDO trust/audit posture.

## New: `windo signal`

```powershell
windo signal
windo signal timeline
windo signal last
windo signal export --open
```

Signal Deck correlates:

- control-plane requests and results
- last elevated request metadata
- audit-chain health
- trust posture
- native-surface readiness

`signal export` writes a local HTML evidence deck under `Documents\windo` unless `--output` is supplied.
