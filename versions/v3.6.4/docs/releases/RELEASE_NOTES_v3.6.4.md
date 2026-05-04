# Release notes - WINDO v3.6.4 Special Edition

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

**Theme:** Make the web installer and upgrade path use the same source of truth as trust validation.

v3.6.4 fixes the stale web install/upgrade path by moving installer downloads to the GitHub Contents API first, with raw branch content only as fallback.

## API-first installer download

`bootstrap.ps1` and `windo install-latest` now fetch `windo_install.ps1` through:

```text
https://api.github.com/repos/l28bit/windo/contents/windo_install.ps1?ref=Genisis
```

If that path is unavailable, WINDO falls back to:

```text
https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_install.ps1
```

The checksum check remains enforced unless `WINDO_SKIP_INSTALLER_SHA256` is set.

## New: `windo source`

`windo source` is a read-only source-of-truth check for the release train.

It reports:

- installed WINDO version
- published installer source (`github-api` or `raw-fallback`)
- published installer version
- published checksum source
- local snapshot path/version/hash
- whether the local snapshot matches the published checksum

Examples:

```powershell
windo source
windo source --json
windo explain source
```

## Validation

```powershell
windo source
windo trust --online
windo explain install-latest
```

Expected result:

- `windo source` shows `source=github-api`.
- `windo trust --online` is trusted after the commit is published.
- `windo explain install-latest` shows the API-first, checksum-verified update route.
