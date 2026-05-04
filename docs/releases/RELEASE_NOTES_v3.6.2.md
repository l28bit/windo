# Release notes - WINDO v3.6.2 Special Edition

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

**Theme:** Make published checksum validation resilient after sync.

v3.6.2 keeps the `windo explain` planner from v3.6.1 and hardens the online checksum path that proves the local installer snapshot matches the published release.

## Checksum source hardening

Bootstrap, `windo install-latest`, and `windo trust --online` now prefer the GitHub Contents API for:

```text
checksums/installer.sha256
```

If the API path is unavailable, WINDO falls back to the raw branch URL.

This matters because GitHub raw branch content can briefly serve stale data after a push. The Contents API reflected the updated file immediately during validation, while the raw branch URL still returned the previous release checksum. WINDO now uses the more authoritative path first.

## Trust Console detail

`windo trust --online` now shows the source used for the published checksum:

```text
source=github-api
```

or:

```text
source=raw-fallback
```

## Validation

```powershell
windo trust --online
windo explain install-latest
windo version
```

Expected result:

- `windo trust --online` reports matching local and published SHA256 values.
- `windo explain install-latest` shows checksum verification before elevated handoff.
- `windo version` reports `3.6.2`.
