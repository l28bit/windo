# Release notes - WINDO v4.4.0

v4.4.0 is the Command Center Actions release. It makes the local control-plane queue inspectable, cancellable, and executable while keeping execution explicit and visible.

## New control lifecycle

```powershell
windo control queue surface-prime
windo control inspect <request-id>
windo control cancel <request-id>
windo control execute-next
windo control history
```

Requests now use explicit states: `queued`, `running`, `complete`, `failed`, and `cancelled`.

`execute-next` consumes one queued request, launches only curated WINDO actions in a visible PowerShell window, and writes result JSON beside the request under `.pwsh_secure\control\requests`.

## Tray actions

`windo launchpad --tray` now includes queue/history, run-next, queue folder, last-result, and Signal Deck actions.
