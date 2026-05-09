# WINDO module: network-ops

Local module for host/network diagnostics and WSL integration helpers.

## Loader behavior

- Put this folder under `%USERPROFILE%\Documents\windo\modules`.
- `module.json` declares:
  - `entry` = `Load.ps1`
  - `requiresWindoVersion` = `5.0.0`
- After enabling, WINDO's generated profile loader block will load `Load.ps1` at shell startup.
- Commands are added with `wincmd` only if they do not already exist, so loading remains non-destructive.

## Installed commands

- `netops-resolve`  
  Resolve one or more hostnames to IP addresses.
- `netops-subnet-scan`  
  Expand and probe a subnet (for example `10.10.10.0/24`) with reachable checks.
- `netops-arp-map`  
  Show cached IPv4 ARP/neighbor entries.
- `netops-rdp-vnc`  
  Check (`-Mode check`) or apply (`-Mode apply`) RDP/VNC related posture.
- `netops-wsl`  
  Show WSL distro state (`-Mode status`) or query a distro eth0 address (`-Mode ip`).
- `netops-netcat-send`  
  Send one-shot (`-Mode apply`) or interactive (`-Interactive` with optional `-Mode apply`) TCP/UDP payloads with timeout control (`-TimeoutSeconds`) and optional JSON output (`-AsJson`). `-Mode check` performs allowlist validation only.
- `netops-netcat-recv`  
  Receive one-shot (`-Mode apply`) or interactive (`-Interactive` with optional `-Mode apply`) TCP/UDP traffic with timeout control (`-TimeoutSeconds`), loopback bind defaults, and optional JSON output (`-AsJson`). `-Mode check` collects identity and safety details without binding.

Netcat safety model supports allowlist control:
- `-AllowHosts` or `-AllowHostsFile` for explicit approved targets.
- `-AllowRemote` to bypass loopback restriction.
- Environment fallback: `WINDO_NETOPS_NETCAT_ALLOWLIST`.

## Safety notes

- `netops-rdp-vnc -Mode apply` requires an elevated PowerShell session.
- `netops-subnet-scan` uses `Test-Connection` with bounded timeout and defaults to host-count guard rails.
- `netops-netcat-*` defaults to loopback host/endpoint behavior and one-shot operation; interactive mode requires explicit `-Interactive` and is bounded by timeout/max-message controls.
- `netops-resolve` now performs reverse lookup fallback (`PTR`) for discovered IP addresses.
- Module functions are intentionally local-only; no external downloads are performed.

## Netcat examples

- Safety precheck for destination allowlist:

```powershell
netops-netcat-send -RemoteHost 10.10.10.20 -RemotePort 9000 -Mode check -AllowHostsFile .\allowlist.txt
```

- Safe apply after confirmation:

```powershell
netops-netcat-send -RemoteHost 127.0.0.1 -RemotePort 9000 -Mode apply -Confirm:$true
```

- One-shot message send with payload and JSON output:

```powershell
netops-netcat-send -RemoteHost 127.0.0.1 -RemotePort 9000 -Protocol tcp -Payload "hello" -TimeoutSeconds 5 -AsJson
```

- Interactive sender session with size caps:

```powershell
netops-netcat-send -RemoteHost 127.0.0.1 -RemotePort 9000 -Interactive -MaxPayloadBytes 512 -MaxInteractiveLines 25 -AsJson
```

- Safe receive precheck:

```powershell
netops-netcat-recv -LocalPort 9000 -Mode check -AllowHosts 127.0.0.1,localhost
```

- Receive once on loopback with JSON:

```powershell
netops-netcat-recv -LocalPort 9000 -AsJson
```

- Bounded interactive receive:

```powershell
netops-netcat-recv -LocalPort 9000 -Interactive -TimeoutSeconds 30 -MaxPayloadBytes 2048 -AsJson
```
