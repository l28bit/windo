# Release notes - WINDO v3.6.3 Special Edition

![WINDO banner](../../brand/assets/banners/banner-blue-left.png)

**Theme:** Make the CLI syntax true in the shell.

v3.6.3 fixes a help-dispatch ordering bug and expands tab completion so WINDO is more aware of its own command syntax.

## Fixed: `windo /?`

`windo /?` previously failed because global help parsing could call `_windo_show_help` before the profile function had executed the helper definition.

The fix defers global help rendering until the help catalog and exit-code helper are loaded.

Validated forms:

```powershell
windo /?
windo help
windo --help
windo trust /?
windo help trust
```

## Syntax-aware tab completion

The native argument completer now has a command-specific syntax table for WINDO built-ins. It still delegates external commands to PowerShell completion, but when the first token is a WINDO command it can suggest known subcommands and options.

Examples:

```powershell
windo trust <Tab>       # --online, --offline, --json
windo completion <Tab>  # native-first, hybrid, windo, off, reset
windo recipes <Tab>     # list, show, preview, run, --json, --dry-run
windo launchpad <Tab>   # --tray, --html, --open, --json
windo modules <Tab>     # list, enable, disable, doctor, verify
```

## Validation

```powershell
windo /?
windo trust /?
windo completion native-first
windo explain install-latest
windo trust --online
```
