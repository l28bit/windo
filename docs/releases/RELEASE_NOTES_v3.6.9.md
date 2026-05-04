# Release notes - WINDO v3.6.9 Special Edition

Release date: 2026-05-04

## Summary

v3.6.9 turns recipes from a small example set into a real read-only operator atlas. This gives the V4 framework a broader workflow surface without adding mutable actions or remote code.

## New: Recipe Atlas

The bundled catalog now includes recipes across:

- identity and token posture
- local users, groups, shares, and sessions
- services and scheduled tasks
- networking, routes, ports, DNS, Wi-Fi, and proxy state
- firewall, audit policy, certificates, Defender, BitLocker, and recovery status
- OS build, uptime, volumes, disks, drivers, power, and time configuration
- optional local tool versions for Git, Node.js, Python, Docker, WinGet, PowerShell, and Ollama

Use the existing preview and dry-run paths before elevating:

```powershell
windo recipes
windo recipes preview whoami-all
windo recipes run network-routes --dry-run
windo run --recipe defender-status --dry-run
```

## Safety model

Recipes remain bundled data in the installer. They are reviewed, versioned with WINDO, and submitted through the same audited elevation path as normal `windo <command>` execution.

This release intentionally keeps recipes read-only. It does not add recipes that delete files, change configuration, restart services, install packages, write exports, or fetch remote content.

## Updated

- `windo recipes` lists the expanded catalog.
- `windo recipes <Tab>` now suggests the new recipe ids.
- `windo mesh` and the HTML cockpit automatically reflect the larger recipe count.
