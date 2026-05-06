# Release notes - WINDO v5.1.0

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

v5.1.0 is the Exodus Limited Edition pass for V5. It keeps the Command Center architecture PowerShell-native, then gives the release a branded local surface, tighter command grammar, and branch-source alignment.

## New: `windo edition`

```powershell
windo edition
windo edition open
windo edition pulse
```

`windo edition open` writes a local animated HTML console under `Documents\windo` and opens it. The surface uses the final brand assets, Command Center status, control-plane counts, motion policy, and Exodus release identity. It is local-only and does not run elevated work.

`windo edition pulse` adds a Limited Edition terminal animation that obeys the existing motion policy.

## Command Center grammar

- `windo control preview <action-id>` shows the curated command route before queueing or running.
- `windo control execute <request-id>` executes a specific queued request.
- `windo control next` aliases `execute-next`.
- `windo center actions`, `windo center preview`, `windo center execute-next`, `windo center execute`, and `windo center signal` make the V5 entrypoint more complete.
- `windo signal open` opens the local Signal Deck directly.

## Source branch

The live branch contract moves to `Exodus`:

- bootstrap
- install/update
- checksum validation
- trust/source lookups
- extras index
- README/build documentation

Historical release notes may still mention older branch names for the releases where that was true.

## Visuals

- Tray menu includes a Limited Edition Console action.
- The curated control-plane catalog includes `edition-open`.
- README and release docs point to the Limited Edition release copy.
