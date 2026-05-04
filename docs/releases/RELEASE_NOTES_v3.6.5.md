# Release notes - WINDO v3.6.5 Special Edition

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

**Theme:** Keep the runway quiet, make Syntax Forge more useful now.

v3.6.5 continues the V4 preparation track by tightening public roadmap language and adding a real Syntax Doctor for operator intent checks.

## New: `windo syntax doctor`

Syntax Doctor is read-only. It checks an intent before anything runs and reports whether the match is exact, fuzzy, ambiguous, or missing.

Examples:

```powershell
windo syntax doctor update
windo syntax doctor proof --json
windo syntax --doctor repair keys
```

Expected use:

- exact or single-match results show the command, preview command, risk, and next steps
- ambiguous results list the likely shortcuts so the operator can narrow the intent
- no-match results suggest nearby safe commands such as `windo source`, `windo trust --online`, `windo preflight`, or `windo explain`

## Quieter release runway

`windo roadmap`, README, JSON schema docs, and the roadmap document now focus on shipped 3.x work and V4 preparation. Future major-package details are intentionally reserved.

## Validation

```powershell
windo syntax doctor update
windo syntax doctor latest --json
windo roadmap
windo trust --online
```

Expected result:

- Syntax Doctor returns a safe next command for known intents.
- Roadmap output shows V4 preparation and reserved future details.
- Online trust passes after the commit is published and checksums are synced.
