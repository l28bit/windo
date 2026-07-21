# WINDO Native Companion Scaffold

This folder is a placeholder for a future compiled Windows companion app.

The WINDO V6 Command Center is PowerShell-native first. No compiled binary is required for install, update, tray, control-plane, Signal Deck, or center commands.

Future companion work should keep these boundaries:

- PowerShell remains the source of truth for elevation, audit, trust, and command execution.
- The companion app may render UI and call curated WINDO commands.
- The companion app must not bypass WINDO request validation or scheduled-task boundaries.
- Packaging/signing decisions belong to a later major release.
