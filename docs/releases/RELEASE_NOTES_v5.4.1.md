# WINDO v5.4.1 - Completion Recovery

WINDO v5.4.1 fixes a profile-load path where tab completion could fail to register.

## Fixed

The PSReadLine keybinding block no longer exits the profile before the WINDO argument completer is loaded.

That matters on hosts where:

- WINDO keybindings are disabled.
- `Alt+w` binding detection fails.
- PSReadLine behavior differs between Windows Terminal, ConsoleHost, Windows PowerShell, and PowerShell 7.

## New diagnostics

```powershell
windo completion doctor
windo completion repair
```

`doctor` checks the runtime completion state and samples `windo ` completion output.

`repair` re-registers the completer in the current session.

## Expected result

After installing and reloading the profile:

```powershell
windo <Tab>
```

should offer WINDO commands such as `doctor`, `help`, `install-latest`, and `integrate` instead of only current-directory file names.
