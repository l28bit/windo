# Release notes - WINDO v4.0.1

v4.0.1 tightens the V4 shell experience while quietly adding the next wiring layer for local developer workflows, package-manager handoff, and account-context launch.

## Fixed: external `-h` flags

`windo powercfg -h off` now passes `-h` through to `powercfg` instead of treating it as WINDO help.

WINDO still supports global help:

```powershell
windo -h
windo --help
windo /?
windo help powercfg
```

After a target command is present, WINDO only consumes `-h`, `--help`, and `-?` for known WINDO built-ins.

## Compact output

Elevated external commands now default to a compact result line:

```text
[windo] OK 147ms :: powercfg /h off :: no output
```

Operators who prefer the previous multi-line layout can enable it:

```powershell
windo output legacy
```

Available modes:

```powershell
windo output compact
windo output quiet
windo output legacy
windo output reset
```

`WINDO_OUTPUT_MODE` overrides the saved preference for the current process.

## Account handoff

`windo - <username> [command...]` starts a new PowerShell process as another local/domain account using Windows credentials:

```powershell
windo - CONTOSO\AdminUser
windo - .\localadmin whoami /all
```

This is a Windows credential handoff. It is not a Linux-style passwordless `su`, and it does not silently bypass UAC.

## Python virtual environments

New local developer helper:

```powershell
windo venv create
windo venv activate
windo venv status
windo venv deactivate
windo venv remove .\.venv --force
```

Activation dot-sources `Scripts\Activate.ps1` into the current shell. The venv helper does not use scheduled-task elevation.

## Package-manager handoff

New package-manager surface:

```powershell
windo pkg status
windo pkg winget install Microsoft.PowerShell
windo pkg choco install git -y
windo pkg scoop install ripgrep
```

`winget` and `choco` commonly need elevation for machine-wide installs. `scoop` is usually user-scoped, so WINDO warns that elevated context can differ from the normal user shell.

## Validation

Use:

```powershell
windo output
windo powercfg -h off
windo venv status --json
windo pkg status --json
windo source
windo trust --online
```
