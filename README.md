
# WINDO

**Choose elevation before execution.**

WINDO is a deliberate elevation bridge for PowerShell on Windows designed for administrators who understand that executing a command with elevated privileges is an intentional act.

Instead of relying on pop‑up prompts after a command has already been issued, WINDO allows administrators to **explicitly request elevation before execution**, restoring clarity and control to command workflows.

---

## Philosophy

Experienced operators understand that commands carry intent.

Elevation should not be accidental or hidden behind UI prompts that interrupt the workflow after execution begins.

WINDO introduces a different model:

command → choose elevation → execute with authority

This restores a predictable, auditable workflow that aligns with how administrators actually think about privileged execution.

---

## What WINDO Does

WINDO introduces a lightweight elevation bridge for PowerShell environments.

It allows administrators to run commands requiring elevated privileges from their existing shell while maintaining:

• command intent  
• audit traceability  
• security boundaries  
• operational clarity  

Instead of launching a separate administrative shell, WINDO executes commands through a scheduled task configured with **RunLevel Highest**.

This approach preserves the Windows security model while enabling a smoother CLI workflow.

---

## Example

```
PS C:\> windo powercfg -h off

[windo] Elevation requested
[windo] Status: SUCCESS
[windo] Duration: 81ms
```

Re‑run the last elevated command:

```
PS C:\> windo !!

[windo] Re‑executing previous elevated command
[windo] Status: SUCCESS
[windo] Duration: 72ms
```

---

## Core Features

• intentional elevation invocation  
• encrypted command history  
• integrity‑verified execution components  
• hash‑chained audit logs  
• self‑repairing task bridge  
• administrator‑focused diagnostics  

Commands:

```
windo <command...>
windo !!
windo doctor
windo integrity
windo verify
windo self-update
windo log -n 10
windo cleanup -w
```

---

## Security Model

WINDO does **not bypass Windows security boundaries**.

Elevation occurs through a scheduled task configured for the current user with **RunLevel Highest**.

The scheduled task launches a hidden execution runner responsible for performing the elevated operation.

Security protections include:

• DPAPI encrypted command history  
• SHA256 hash‑chained log entries  
• execution component integrity verification  
• tamper detection diagnostics  

Audit history is stored locally at:

```
%USERPROFILE%\.pwsh_secure\windo_history.enc
```

---

## Command Flow

WINDO introduces a clear execution circuit:

```
command issued
        │
        ▼
elevation requested
        │
        ▼
scheduled task bridge
        │
        ▼
elevated execution
        │
        ▼
encrypted audit log
```

Every elevated command passes through this controlled path.

---

## Installation

Open an elevated PowerShell session:

```
Set-ExecutionPolicy -Scope Process Bypass -Force
.\windo_install.ps1
```

Reload your shell profile:

```
. $PROFILE
```

Verify installation:

```
windo doctor
windo version
```

---

## Install

Run in PowerShell (administrator recommended):

```powershell
iex (irm https://raw.githubusercontent.com/l28bit/windo/Genisis/bootstrap.ps1)
```

The bootstrap loader will:

1. Download the installer
2. Execute it safely from a temporary location
3. Clean up automatically

After installation restart your terminal and run:

```
windo doctor
```

## Diagnostics

Validate system health:

```
windo doctor
```

Verify runner integrity:

```
windo integrity
```

Verify encrypted audit chain:

```
windo verify
```

---

## Log Inspection

View recent entries:

```
windo log -n 10
```

Archive and rotate history:

```
windo cleanup -w
```

---

## Installer Snapshot

The installer preserves a deployment snapshot for recovery:

```
%USERPROFILE%\Documents\windo\
```

Snapshot files include:

```
windo_install.ps1
windo_runner.ps1
windo_self_update.ps1
windo_manifest.json
```

This allows rapid redeployment or inspection of execution components.

---

## Credits

WINDO was conceived and built by Chris Jones to restore clarity and intentionality to command elevation workflows on Windows systems.

Development, refinement, and release hardening were carried out collaboratively with AI assistance, focusing on security, auditability, and creating a deliberate elevation model for administrators and operators.

---

## License

MIT License
