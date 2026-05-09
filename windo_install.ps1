<# =====================================================================
WINDO V6 Installer
Run once in an elevated PowerShell session.

Installs:
- $HOME\.pwsh_secure\
- windo_runner.ps1
- windo_self_update.ps1
- windo_uninstall.ps1
- windo_manifest.json
- Scheduled tasks:
    - WindoElevatedRunner
    - WindoSelfUpdate
- WINDO profile block in $PROFILE (windo function + PSReadLine keybindings + delegated tab completion)
- Snapshot copies under $HOME\Documents\windo\

Maintainer: new windo subcommands must be added to $WindoBuiltinVerbs (single source for profile completer + last-command exclusions).
===================================================================== #>

$ErrorActionPreference = "Stop"

$WindoVersion = "6.0.0"

# Single source of truth for embedded profile: completer skip-list (plus '!!') and windo last-command first-token exclusions.
$WindoBuiltinVerbs = @(
    'help', 'last', 'stats', 'history', 'report', 'dashboard', 'preflight', 'launchpad', 'export', 'self-update', 'version',
    'doctor', 'integrity', 'verify', 'trust', 'source', 'explain', 'log', 'cleanup', 'config', 'backups', 'context', 'trace', 'replay',
    'theme', 'output', 'motion', 'surface', 'integrate', 'control', 'signal', 'center', 'studio', 'edition', 'upgrade', 'install-latest', 'uninstall', 'remove', 'profile', 'keybindings', 'completion', 'roadmap', 'syntax', 'mesh',
        'modules', 'recipes', 'prompt', 'extras', 'dev', 'session', 'ai', 'repair', 'scan', 'vault', 'sshx', 'crypto', 'venv', 'pkg', 'net-scan', 'rdp', 'vnc', 'container', 'wsl', 'run'
)
$WindoBuiltinVerbsArrayLiteral = ($WindoBuiltinVerbs | ForEach-Object { "'$_'" }) -join ','
$TaskMain     = "WindoElevatedRunner"
$TaskUpdate   = "WindoSelfUpdate"

$SecureDir    = Join-Path $HOME ".pwsh_secure"
$RunnerPath   = Join-Path $SecureDir "windo_runner.ps1"
$UpdateScript = Join-Path $SecureDir "windo_self_update.ps1"
$UninstallPath = Join-Path $SecureDir "windo_uninstall.ps1"
$RunnerLast   = Join-Path $SecureDir "windo_runner_last.txt"
$UpdateLast   = Join-Path $SecureDir "windo_self_update_last.txt"
$LogFile      = Join-Path $SecureDir "windo_history.enc"
$ManifestFile = Join-Path $SecureDir "windo_manifest.json"
$SnapshotDir  = Join-Path (Join-Path $HOME "Documents") "windo"

$BeginMarker  = "# >>> WINDO-BEGIN >>>"
$EndMarker    = "# <<< WINDO-END <<<"

function Write-WindoEditionBanner {
    param([string]$Phase = "install")
    Write-Host ""
    Write-Host "  __        _____ _   _ ____   ___" -ForegroundColor Cyan
    Write-Host "  \ \      / /_ _| \ | |  _ \ / _ \" -ForegroundColor Cyan
    Write-Host "   \ \ /\ / / | ||  \| | | | | | | |" -ForegroundColor Cyan
    Write-Host "    \ V  V /  | || |\  | |_| | |_| |" -ForegroundColor Cyan
    Write-Host "     \_/\_/  |___|_| \_|____/ \___/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  WINDO {0}  V6  ::  {1}" -f $WindoVersion, $Phase.ToUpperInvariant()) -ForegroundColor White
    Write-Host "  deliberate elevation | audit chain | security tools | operator visuals" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-WindoInstallStep {
    param(
        [Parameter(Mandatory=$true)][string]$Status,
        [Parameter(Mandatory=$true)][string]$Label,
        [string]$Detail = "",
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    $mark = switch ($Status.ToLowerInvariant()) {
        "ok" { "[OK]" }
        "warn" { "[!!]" }
        "run" { "[..]" }
        "skip" { "[--]" }
        default { "[**]" }
    }
    Write-Host ("  {0} {1}" -f $mark, $Label) -ForegroundColor $Color
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host ("       {0}" -f $Detail) -ForegroundColor DarkGray
    }
}

Write-WindoEditionBanner -Phase "installer"

function Ensure-DirLockedToCurrentUser {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
    try {
        $acl = Get-Acl $Path
        $acl.SetAccessRuleProtection($true, $false) | Out-Null
        foreach ($r in @($acl.Access)) { $null = $acl.RemoveAccessRule($r) }

        $user = New-Object System.Security.Principal.NTAccount("$env:USERDOMAIN\$env:USERNAME")
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $user,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.AddAccessRule($rule) | Out-Null
        Set-Acl -Path $Path -AclObject $acl
    } catch {
        Write-Warning ("WINDO: Could not tighten ACLs on " + $Path + "; continuing with existing permissions. Re-run installer elevated once if you want strict per-user directory locking. " + $_.Exception.Message)
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Ensure-ProfileExists {
    if (!(Test-Path $PROFILE)) {
        $dir = Split-Path $PROFILE -Parent
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        New-Item -ItemType File -Path $PROFILE | Out-Null
    }
}

function Remove-ExistingWindoBlockFromProfile {
    Ensure-ProfileExists
    $text = Get-Content -Raw $PROFILE
    $repaired = Repair-WindoProfileText -Text $text
    if ($repaired -ne $text) {
        Write-Utf8NoBomFile -Path $PROFILE -Content ($repaired.TrimEnd() + "`r`n")
    }
}

function Repair-WindoProfileText {
    param(
        [Parameter(Mandatory=$true)][string]$Text
    )

    $anchorPattern = '(?ms)(?:^|\r?\n)(?:"\s*\r?\n|function\s+Invoke-WindoBundledUninstall\b|function\s+windo\b|\s*\$WindoVersion\s*=|\s*if\s*\(\!\(Test-Path\s+\$SecureDir\)\))'
    $beginLinePattern = '(?m)^[ \t]*' + [regex]::Escape($BeginMarker) + '[ \t]*\r?$'
    $endLinePattern = '(?m)^[ \t]*' + [regex]::Escape($EndMarker) + '[ \t]*\r?$'

    $firstBeginMatch = [regex]::Match($Text, $beginLinePattern)
    while ($firstBeginMatch.Success) {
        $prefix = $Text.Substring(0, $firstBeginMatch.Index)
        $matches = [regex]::Matches($prefix, $anchorPattern)
        if ($matches.Count -eq 0) { break }

        $start = $matches[$matches.Count - 1].Index
        if ($Text[$start] -eq "`r") {
            $start++
            if ($start -lt $Text.Length -and $Text[$start] -eq "`n") { $start++ }
        } elseif ($Text[$start] -eq "`n") {
            $start++
        }
        $Text = $Text.Remove($start, $firstBeginMatch.Index - $start)
        $firstBeginMatch = [regex]::Match($Text, $beginLinePattern)
    }

    $wellFormedBlockPattern = '(?ms)^[ \t]*' + [regex]::Escape($BeginMarker) + '[ \t]*\r?\n.*?^[ \t]*' + [regex]::Escape($EndMarker) + '[ \t]*\r?\n?'
    $Text = [regex]::Replace($Text, $wellFormedBlockPattern, '')

    $firstBeginMatch = [regex]::Match($Text, $beginLinePattern)
    $firstEndMatch = [regex]::Match($Text, $endLinePattern)
    while ($firstEndMatch.Success -and (-not $firstBeginMatch.Success -or $firstEndMatch.Index -lt $firstBeginMatch.Index)) {
        $prefix = $Text.Substring(0, $firstEndMatch.Index)
        $matches = [regex]::Matches($prefix, $anchorPattern)
        if ($matches.Count -eq 0) { break }

        $start = $matches[$matches.Count - 1].Index
        if ($Text[$start] -eq "`r") {
            $start++
            if ($start -lt $Text.Length -and $Text[$start] -eq "`n") { $start++ }
        } elseif ($Text[$start] -eq "`n") {
            $start++
        }
        $end = $firstEndMatch.Index + $firstEndMatch.Length
        if ($end -lt $Text.Length -and $Text[$end] -eq "`r") { $end++ }
        if ($end -lt $Text.Length -and $Text[$end] -eq "`n") { $end++ }
        $Text = $Text.Remove($start, $end - $start)

        $firstBeginMatch = [regex]::Match($Text, $beginLinePattern)
        $firstEndMatch = [regex]::Match($Text, $endLinePattern)
    }

    return ($Text -replace "(\r?\n){3,}", "`r`n`r`n")
}

function Get-NoWindowActionArgs {
    param([Parameter(Mandatory=$true)][string]$ScriptPath)

    $pwshwCmd = Get-Command "pwshw.exe" -ErrorAction SilentlyContinue
    if ($pwshwCmd) {
        return @{
            Execute = $pwshwCmd.Source
            Argument = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
        }
    }

    return @{
        Execute = "powershell.exe"
        Argument = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
    }
}

function Get-FileHashString {
    param([Parameter(Mandatory=$true)][string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

Write-WindoInstallStep -Status run -Label "Loading ScheduledTasks module" -Detail "required for the elevated runner and self-update tasks"
Import-Module ScheduledTasks -ErrorAction Stop
Write-WindoInstallStep -Status ok -Label "ScheduledTasks module ready" -Color Green
Write-WindoInstallStep -Status run -Label "Hardening secure directory" -Detail $SecureDir
Ensure-DirLockedToCurrentUser -Path $SecureDir
Write-WindoInstallStep -Status ok -Label "Secure directory ready" -Color Green

$RunnerContent = @'
$ErrorActionPreference = "Stop"

$SecureDir  = Join-Path $HOME ".pwsh_secure"
$RunnerLast = Join-Path $SecureDir "windo_runner_last.txt"
$MutexName  = "Global\WindoRunnerMutex"

if (-not ("WindoRunner.ChildExec" -as [type])) {
    $cs = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
        'dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uRGlhZ25vc3RpY3M7CnVzaW5nIFN5c3RlbS5JTzsKdXNpbmcgU3lzdGVtLlRleHQ7CnVzaW5nIFN5c3RlbS5UaHJlYWRpbmcuVGFza3M7CgpuYW1lc3BhY2UgV2luZG9SdW5uZXIKewogICAgcHVibGljIHN0YXRpYyBjbGFzcyBDaGlsZEV4ZWMKICAgIHsKICAgICAgICBwdWJsaWMgc3RhdGljIHN0cmluZyBSZWFkU3RyZWFtVG9NYXgoU3RyZWFtUmVhZGVyIHIsIGludCBtYXhDaGFycywgUHJvY2VzcyBwKQogICAgICAgIHsKICAgICAgICAgICAgdmFyIHNiID0gbmV3IFN0cmluZ0J1aWxkZXIoKTsKICAgICAgICAgICAgdmFyIGJ1ZiA9IG5ldyBjaGFyWzgxOTJdOwogICAgICAgICAgICBpbnQgdG90YWwgPSAwOwogICAgICAgICAgICB3aGlsZSAodG90YWwgPCBtYXhDaGFycykKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgaW50IG4gPSByLlJlYWQoYnVmLCAwLCBNYXRoLk1pbihidWYuTGVuZ3RoLCBtYXhDaGFycyAtIHRvdGFsKSk7CiAgICAgICAgICAgICAgICBpZiAobiA8PSAwKSBicmVhazsKICAgICAgICAgICAgICAgIHNiLkFwcGVuZChidWYsIDAsIG4pOwogICAgICAgICAgICAgICAgdG90YWwgKz0gbjsKICAgICAgICAgICAgfQogICAgICAgICAgICBpZiAodG90YWwgPj0gbWF4Q2hhcnMpCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgIHRyeSB7IGlmICghcC5IYXNFeGl0ZWQpIHAuS2lsbCgpOyB9IGNhdGNoIHsgfQogICAgICAgICAgICAgICAgdHJ5IHsgcC5XYWl0Rm9yRXhpdCgxNTAwMCk7IH0gY2F0Y2ggeyB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgcmV0dXJuIHNiLlRvU3RyaW5nKCk7CiAgICAgICAgfQoKICAgICAgICBwdWJsaWMgc3RhdGljIHZvaWQgUnVuQ21kKAogICAgICAgICAgICBzdHJpbmcgYXJndW1lbnRzLAogICAgICAgICAgICBpbnQgdGltZW91dE1zLAogICAgICAgICAgICBpbnQgbWF4Q2hhcnNQZXJTdHJlYW0sCiAgICAgICAgICAgIG91dCBzdHJpbmcgc3Rkb3V0LAogICAgICAgICAgICBvdXQgc3RyaW5nIHN0ZGVyciwKICAgICAgICAgICAgb3V0IGJvb2wgdGltZWRPdXQsCiAgICAgICAgICAgIG91dCBib29sIHRydW5jYXRlZCwKICAgICAgICAgICAgb3V0IGludCBleGl0Q29kZSkKICAgICAgICB7CiAgICAgICAgICAgIHRpbWVkT3V0ID0gZmFsc2U7CiAgICAgICAgICAgIHRydW5jYXRlZCA9IGZhbHNlOwogICAgICAgICAgICBleGl0Q29kZSA9IDE7CiAgICAgICAgICAgIHN0ZG91dCA9ICIiOwogICAgICAgICAgICBzdGRlcnIgPSAiIjsKICAgICAgICAgICAgdmFyIHBzaSA9IG5ldyBQcm9jZXNzU3RhcnRJbmZvKCk7CiAgICAgICAgICAgIHBzaS5GaWxlTmFtZSA9ICJjbWQuZXhlIjsKICAgICAgICAgICAgcHNpLkFyZ3VtZW50cyA9ICIvYyAiICsgYXJndW1lbnRzOwogICAgICAgICAgICBwc2kuUmVkaXJlY3RTdGFuZGFyZE91dHB1dCA9IHRydWU7CiAgICAgICAgICAgIHBzaS5SZWRpcmVjdFN0YW5kYXJkRXJyb3IgPSB0cnVlOwogICAgICAgICAgICBwc2kuVXNlU2hlbGxFeGVjdXRlID0gZmFsc2U7CiAgICAgICAgICAgIHBzaS5DcmVhdGVOb1dpbmRvdyA9IHRydWU7CiAgICAgICAgICAgIHVzaW5nICh2YXIgcCA9IFByb2Nlc3MuU3RhcnQocHNpKSkKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgdmFyIHRPdXQgPSBUYXNrLlJ1bigoKSA9PiBSZWFkU3RyZWFtVG9NYXgocC5TdGFuZGFyZE91dHB1dCwgbWF4Q2hhcnNQZXJTdHJlYW0sIHApKTsKICAgICAgICAgICAgICAgIHZhciB0RXJyID0gVGFzay5SdW4oKCkgPT4gUmVhZFN0cmVhbVRvTWF4KHAuU3RhbmRhcmRFcnJvciwgbWF4Q2hhcnNQZXJTdHJlYW0sIHApKTsKICAgICAgICAgICAgICAgIGJvb2wgZmluaXNoZWQgPSBwLldhaXRGb3JFeGl0KHRpbWVvdXRNcyk7CiAgICAgICAgICAgICAgICBpZiAoIWZpbmlzaGVkKQogICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgIHRpbWVkT3V0ID0gdHJ1ZTsKICAgICAgICAgICAgICAgICAgICB0cnkgeyBpZiAoIXAuSGFzRXhpdGVkKSBwLktpbGwoKTsgfSBjYXRjaCB7IH0KICAgICAgICAgICAgICAgICAgICB0cnkgeyBwLldhaXRGb3JFeGl0KDE1MDAwKTsgfSBjYXRjaCB7IH0KICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIHN0ZG91dCA9IHRPdXQuUmVzdWx0OwogICAgICAgICAgICAgICAgc3RkZXJyID0gdEVyci5SZXN1bHQ7CiAgICAgICAgICAgICAgICBpZiAoc3Rkb3V0Lkxlbmd0aCA+PSBtYXhDaGFyc1BlclN0cmVhbSB8fCBzdGRlcnIuTGVuZ3RoID49IG1heENoYXJzUGVyU3RyZWFtKQogICAgICAgICAgICAgICAgICAgIHRydW5jYXRlZCA9IHRydWU7CiAgICAgICAgICAgICAgICB0cnkKICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICBleGl0Q29kZSA9IHAuSGFzRXhpdGVkID8gcC5FeGl0Q29kZSA6IC0xOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgY2F0Y2gKICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICBleGl0Q29kZSA9IC0xOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgaWYgKHRpbWVkT3V0KQogICAgICAgICAgICAgICAgICAgIGV4aXRDb2RlID0gLTE7CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9Cn0K'
    ))
    Add-Type -TypeDefinition $cs -Language CSharp
}

function Get-WindoRunnerTimeoutMs {
    $d = 7200000
    $raw = $env:WINDO_RUNNER_TIMEOUT_MS
    if ([string]::IsNullOrWhiteSpace($raw)) { return $d }
    try {
        $v = [long]$raw
        if ($v -lt 1) { return $d }
        if ($v -gt 86400000) { return 86400000 }
        return [int]$v
    } catch { return $d }
}

function Get-WindoRunnerMaxCharsPerStream {
    $d = 2097152
    $raw = $env:WINDO_RUNNER_MAX_OUTPUT_BYTES
    if ([string]::IsNullOrWhiteSpace($raw)) { return $d }
    try {
        $v = [long]$raw
        if ($v -lt 4096) { return [int][Math]::Max(512, $v / 2) }
        if ($v -gt 67108864) { return 33554432 }
        return [int]($v / 2)
    } catch { return $d }
}

function Get-WindoMaxCommandChars {
    $d = 8191
    $raw = $env:WINDO_MAX_COMMAND_CHARS
    if ([string]::IsNullOrWhiteSpace($raw)) { return $d }
    try {
        $v = [int]$raw
        if ($v -lt 1) { return $d }
        if ($v -gt 8191) { return 8191 }
        return $v
    } catch { return $d }
}

function Test-WindoCommandLine([string]$cmdLine) {
    $max = Get-WindoMaxCommandChars
    if ($null -eq $cmdLine) { return "Command is missing." }
    if ($cmdLine.Length -gt $max) { return "Command exceeds max length ($max)." }
    foreach ($ch in $cmdLine.ToCharArray()) {
        $c = [int][char]$ch
        if ($c -eq 9) { continue }
        if ($c -lt 32) { return "Command contains disallowed control characters." }
    }
    return $null
}

function Test-WindoResultPath([string]$outPath, [string]$secureDir) {
    if ([string]::IsNullOrWhiteSpace($outPath)) { return "OutPath is missing." }
    try {
        $full = [System.IO.Path]::GetFullPath($outPath)
        $root = [System.IO.Path]::GetFullPath($secureDir)
        if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return "OutPath must be under SecureDir." }
        $name = [System.IO.Path]::GetFileName($full)
        if ($name -notmatch '^windo_res\.[a-f0-9]+\.json$') { return "OutPath file name is invalid." }
    } catch { return "OutPath is invalid." }
    return $null
}

function Invoke-WindoPreserveEnvironment {
    param([object]$Snapshot)
    $restored = @{}
    if ($null -eq $Snapshot) { return $restored }

    $items = @()
    if ($Snapshot -is [System.Collections.IDictionary]) {
        $items = @($Snapshot.GetEnumerator())
    } elseif ($Snapshot.PSObject -and $Snapshot.PSObject.Properties) {
        $items = @($Snapshot.PSObject.Properties)
    } else {
        return $restored
    }

    foreach ($entry in $items) {
        if ($Snapshot -is [System.Collections.IDictionary]) {
            $name = [string]$entry.Key
            $value = $entry.Value
        } else {
            $name = [string]$entry.Name
            $value = $entry.Value
        }
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
        try { $restored[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') } catch { $restored[$name] = $null }
        try {
            if ($null -eq $value) {
                [Environment]::SetEnvironmentVariable($name, $null, 'Process')
            } else {
                [Environment]::SetEnvironmentVariable($name, [string]$value, 'Process')
            }
        } catch { }
    }
    return $restored
}

function Restore-WindoPreserveEnvironment {
    param([hashtable]$State)
    if ($null -eq $State -or $State.Count -eq 0) { return }
    foreach ($entry in $State.GetEnumerator()) {
        try {
            [Environment]::SetEnvironmentVariable([string]$entry.Key, $entry.Value, 'Process')
        } catch { }
    }
}

function _windo_get_member_value([object]$Object, [string]$Name) {
    if ($null -eq $Object) { return $null }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        $matched = @($Object.Keys | Where-Object { $_ -ieq $Name } | Select-Object -First 1)
        if ($matched.Count -gt 0) { return $Object[$matched[0]] }
        return $null
    }

    if (-not $Object.PSObject -or -not $Object.PSObject.Properties) { return $null }
    $prop = $Object.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($prop) { return $prop.Value }
    return $null
}

function _windo_unprotect_text([string]$EncryptedText) {
    if ([string]::IsNullOrWhiteSpace($EncryptedText)) { return $null }
    try {
        $enc = [Convert]::FromBase64String($EncryptedText)
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return $null
    }
}

function _windo_resolve_preserve_environment([object]$Payload) {
    if ($null -eq $Payload) { return $null }

    if ($Payload -is [string]) {
        try { return $Payload | ConvertFrom-Json } catch { return $null }
    }

    $payloadType = _windo_get_member_value $Payload "Type"
    $payloadData = _windo_get_member_value $Payload "Data"
    if (-not [string]::IsNullOrWhiteSpace([string]$payloadType) -and -not [string]::IsNullOrWhiteSpace([string]$payloadData)) {
        if ([string]$payloadType -ieq "dpapi-json") {
            $json = _windo_unprotect_text [string]$payloadData
            if ($null -ne $json) {
                try { return $json | ConvertFrom-Json } catch { return $null }
            }
            return $null
        }
    }

    return $Payload
}

"RUNNER START: $([DateTime]::Now.ToString('s'))" | Set-Content -Path $RunnerLast -Encoding UTF8

$createdNew = $false
$m = New-Object System.Threading.Mutex($false, $MutexName, [ref]$createdNew)

try {
    if (-not $m.WaitOne(30000)) {
        "EXIT 9: mutex wait timeout" | Add-Content -Path $RunnerLast -Encoding UTF8
        exit 9
    }

    $req = Get-ChildItem -Path $SecureDir -Filter "windo_req.*.json" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime |
           Select-Object -First 1

    if (-not $req) {
        "NO WORK: no pending request files" | Add-Content -Path $RunnerLast -Encoding UTF8
        exit 0
    }

    try {
        $pending = Get-Content -Raw -Path $req.FullName | ConvertFrom-Json
    } catch {
        "BAD REQUEST JSON: $($req.FullName) :: $($_.Exception.Message)" | Add-Content -Path $RunnerLast -Encoding UTF8
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        exit 3
    }

    $cmdLine = [string]$pending.Command
    $outPath = [string]$pending.OutPath
    $reqId   = [string]$pending.RequestId
    $timeoutMsOverride = $null
    if ($pending.PSObject.Properties.Name -contains "TimeoutOverrideMs") { $timeoutMsOverride = $pending.TimeoutOverrideMs }
    $preserveEnvironment = $null
    if ($pending.PSObject.Properties.Name -contains "PreserveEnvironment") {
        $preserveEnvironment = _windo_resolve_preserve_environment $pending.PreserveEnvironment
    }

    "PROCESS: RequestId=$reqId  OutPath=$outPath" | Add-Content -Path $RunnerLast -Encoding UTF8
    "CMD: $cmdLine" | Add-Content -Path $RunnerLast -Encoding UTF8

    $badOut = Test-WindoResultPath $outPath $SecureDir
    if ($badOut) {
        "VALIDATION FAILED (OutPath): $badOut" | Add-Content -Path $RunnerLast -Encoding UTF8
        try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}
        "RUNNER END: $([DateTime]::Now.ToString('s'))" | Add-Content -Path $RunnerLast -Encoding UTF8
        exit 5
    }

    $badCmd = Test-WindoCommandLine $cmdLine
    if ($badCmd) {
        "VALIDATION FAILED (Command): $badCmd" | Add-Content -Path $RunnerLast -Encoding UTF8
        $end = Get-Date
        $result = @{
            Timestamp  = $end.ToString("yyyy-MM-dd HH:mm:ss")
            Command    = $cmdLine
            Output     = "<WINDO VALIDATION FAILED: $badCmd>"
            ExitCode   = -3
            DurationMs = 0
            RequestId  = $reqId
            RunnerTimedOut = $false
            OutputTruncated = $false
        }
        try {
            $result | ConvertTo-Json -Compress | Set-Content -Path $outPath -Encoding UTF8
        } catch {
            "EXIT 4: failed to write validation result: $($_.Exception.Message)" | Add-Content -Path $RunnerLast -Encoding UTF8
            exit 4
        }
        try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}
        "RUNNER END: $([DateTime]::Now.ToString('s'))" | Add-Content -Path $RunnerLast -Encoding UTF8
        exit 0
    }

    $start = Get-Date
    $timeoutMs = Get-WindoRunnerTimeoutMs $timeoutMsOverride
    $maxPer = Get-WindoRunnerMaxCharsPerStream
    $stdout = [string]$null
    $stderr = [string]$null
    $timedOut = $false
    $truncated = $false
    $exitCode = 0

    $envState = @{}
    try {
        $envState = Invoke-WindoPreserveEnvironment -Snapshot $preserveEnvironment
        try {
            [WindoRunner.ChildExec]::RunCmd(
                $cmdLine,
                $timeoutMs,
                $maxPer,
                [ref]$stdout,
                [ref]$stderr,
                [ref]$timedOut,
                [ref]$truncated,
                [ref]$exitCode
            )
        } catch {
            $stdout = ""
            $stderr = ($_ | Out-String).TrimEnd()
            $exitCode = 1
            $timedOut = $false
            $truncated = $false
        }
    } finally {
        Restore-WindoPreserveEnvironment -State $envState
    }

    if ($null -eq $stdout) { $stdout = "" }
    if ($null -eq $stderr) { $stderr = "" }

    $output = ($stdout + $stderr).TrimEnd()
    if ($timedOut) {
        $output = ($output + "`n<WINDO: child process exceeded WINDO_RUNNER_TIMEOUT_MS>").TrimEnd()
    }
    if ($truncated) {
        $output = ($output + "`n<WINDO: output truncated; see WINDO_RUNNER_MAX_OUTPUT_BYTES>").TrimEnd()
    }

    $end = Get-Date
    $durationMs = [int](($end - $start).TotalMilliseconds)

    $result = @{
        Timestamp  = $end.ToString("yyyy-MM-dd HH:mm:ss")
        Command    = $cmdLine
        Output     = $output
        ExitCode   = [int]$exitCode
        DurationMs = $durationMs
        RequestId  = $reqId
        RunnerTimedOut = [bool]$timedOut
        OutputTruncated = [bool]$truncated
    }

    try {
        $result | ConvertTo-Json -Compress | Set-Content -Path $outPath -Encoding UTF8
        "WROTE RESULT: ExitCode=$exitCode DurationMs=$durationMs TimedOut=$timedOut Truncated=$truncated" | Add-Content -Path $RunnerLast -Encoding UTF8
    } catch {
        "EXIT 4: failed to write result JSON: $($_.Exception.Message)" | Add-Content -Path $RunnerLast -Encoding UTF8
        exit 4
    }

    try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}

    "RUNNER END: $([DateTime]::Now.ToString('s'))" | Add-Content -Path $RunnerLast -Encoding UTF8
    exit 0
}
finally {
    try { $m.ReleaseMutex() } catch {}
    try { $m.Dispose() } catch {}
}

'@
Write-Utf8NoBomFile -Path $RunnerPath -Content $RunnerContent

$UserId = "$env:USERDOMAIN\$env:USERNAME"

$SelfUpdateContent = @'
$ErrorActionPreference = "Stop"

$RunnerPath = "__RUNNER_PATH__"
$StampFile  = "__STAMP_FILE__"
$TaskName   = "WindoElevatedRunner"
$UserId     = "__USER_ID__"

function Write-Trace {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Add-Content -Path $StampFile -Encoding UTF8
}

"SELF-UPDATE START" | Set-Content -Path $StampFile -Encoding UTF8

try {
    Import-Module ScheduledTasks -ErrorAction Stop
    Write-Trace "Imported ScheduledTasks"

    $PwshwCmd = Get-Command "pwshw.exe" -ErrorAction SilentlyContinue
    if ($PwshwCmd) {
        $Exe = $PwshwCmd.Source
        $Arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $RunnerPath + '"'
        Write-Trace ("Using pwshw.exe: " + $Exe)
    } else {
        $Exe = "powershell.exe"
        $Arg = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $RunnerPath + '"'
        Write-Trace "Using powershell.exe hidden fallback"
    }

    $Action = New-ScheduledTaskAction -Execute $Exe -Argument $Arg

    try {
        Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null
        Set-ScheduledTask -TaskName $TaskName -Action $Action | Out-Null
        Write-Trace ("Updated main task action -> " + $Exe + " " + $Arg)
    } catch {
        $Principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Highest
        $Settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings -Force | Out-Null
        Write-Trace ("Recreated main task -> " + $Exe + " " + $Arg)
    }

    Write-Trace "SELF-UPDATE END"
    exit 0
}
catch {
    Write-Trace ("FATAL: " + $_.Exception.Message)
    try { Write-Trace ("TYPE: " + $_.Exception.GetType().FullName) } catch {}
    exit 1
}

'@
$SelfUpdateContent = $SelfUpdateContent.Replace("__RUNNER_PATH__", $RunnerPath)
$SelfUpdateContent = $SelfUpdateContent.Replace("__STAMP_FILE__", $UpdateLast)
$SelfUpdateContent = $SelfUpdateContent.Replace("__USER_ID__", $UserId)
Write-Utf8NoBomFile -Path $UpdateScript -Content $SelfUpdateContent

$UninstallContent = @'
<# =====================================================================
WINDO uninstall â€” removes scheduled tasks, profile block, and WINDO data.

Run elevated (recommended) so scheduled tasks unregister reliably:
  powershell.exe -ExecutionPolicy Bypass -File .\windo_uninstall.ps1 -Confirm

Or interactively (script will prompt):
  .\windo_uninstall.ps1

Removes WINDO marker blocks from known current-user PowerShell profiles
(pwsh and Windows PowerShell) without touching all-users profiles.
===================================================================== #>

param(
    [switch]$Confirm,
    [switch]$KeepSnapshots
)

$ErrorActionPreference = "Stop"

$BeginMarker = "# >>> WINDO-BEGIN >>>"
$EndMarker   = "# <<< WINDO-END <<<"
$TaskMain    = "WindoElevatedRunner"
$TaskUpdate  = "WindoSelfUpdate"
$SecureDir   = Join-Path $HOME ".pwsh_secure"
$SnapshotDir = Join-Path (Join-Path $HOME "Documents") "windo"

function Write-Utf8NoBomFile {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-WindoProfilePathList {
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $addOne = {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        try {
            $full = [System.IO.Path]::GetFullPath($Path)
            [void]$set.Add($full)
        } catch { }
    }

    try {
        if ($PROFILE) {
            & $addOne $PROFILE.CurrentUserCurrentHost
            & $addOne $PROFILE.CurrentUserAllHosts
        }
    } catch {
        & $addOne ([string]$PROFILE)
    }

    foreach ($candidate in @(
        (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $HOME 'Documents\PowerShell\Profile.ps1'),
        (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $HOME 'Documents\WindowsPowerShell\Profile.ps1')
    )) {
        & $addOne $candidate
    }

    return @($set)
}

function Remove-WindoProfileBlockFromPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        Write-Host "[windo uninstall] Profile not present: $Path" -ForegroundColor DarkGray
        return $false
    }

    try {
        $text = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
    } catch {
        Write-Warning ("Could not read profile " + $Path + ": " + $_.Exception.Message)
        return $false
    }

    $pattern = "(?ms)" + [regex]::Escape($BeginMarker) + ".*?" + [regex]::Escape($EndMarker) + "\r?\n?"
    if ($text -notmatch $pattern) {
        Write-Host "[windo uninstall] No WINDO block found in profile: $Path" -ForegroundColor DarkYellow
        return $false
    }

    $updated = [regex]::Replace($text, $pattern, "")
    $updated = $updated -replace "(\r?\n){3,}", "`r`n`r`n"
    if ([string]::IsNullOrWhiteSpace($updated)) {
        Write-Utf8NoBomFile -Path $Path -Content ""
    } else {
        Write-Utf8NoBomFile -Path $Path -Content ($updated.TrimEnd() + "`r`n")
    }
    Write-Host "[windo uninstall] Removed WINDO block from profile: $Path" -ForegroundColor Green
    return $true
}

function Remove-WindoProfileBlocks {
    $removed = 0
    foreach ($path in @(Get-WindoProfilePathList)) {
        if (Remove-WindoProfileBlockFromPath -Path $path) { $removed++ }
    }
    return $removed
}

Write-Host ""
Write-Host "WINDO uninstall" -ForegroundColor Cyan
Write-Host "  Tasks: $TaskMain, $TaskUpdate"
Write-Host "  Profiles (current user):"
foreach ($profilePath in @(Get-WindoProfilePathList)) {
    Write-Host "    $profilePath"
}
Write-Host "  Secure dir: $SecureDir"
Write-Host "  Documents snapshot: $SnapshotDir $(if ($KeepSnapshots) { '(keeping)' } else { '(removing)' })"
Write-Host ""

if (-not $Confirm) {
    $choice = $Host.UI.PromptForChoice(
        "",
        "Remove WINDO tasks, profile blocks, and data from this user?",
        @("&Yes", "&No"),
        1
    )
    if ($choice -ne 0) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

foreach ($tn in @($TaskMain, $TaskUpdate)) {
    try {
        Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Host "[windo uninstall] Unregistered task: $tn" -ForegroundColor Green
    } catch {
        Write-Host "[windo uninstall] Task not present or could not remove: $tn" -ForegroundColor DarkYellow
    }
}

$removedProfiles = Remove-WindoProfileBlocks
Write-Host "[windo uninstall] Profile cleanup complete. Removed WINDO blocks from $removedProfiles file(s)." -ForegroundColor Cyan

if (Test-Path $SecureDir) {
    Get-ChildItem -Path $SecureDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "windo*" } | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            Write-Host "[windo uninstall] Removed: $($_.Name)" -ForegroundColor DarkGray
        } catch {
            Write-Warning "Could not remove $($_.FullName): $($_.Exception.Message)"
        }
    }
    $remaining = @(Get-ChildItem -Path $SecureDir -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        try {
            Remove-Item -Path $SecureDir -Force -ErrorAction Stop
            Write-Host "[windo uninstall] Removed empty directory: $SecureDir" -ForegroundColor Green
        } catch {
            Write-Warning "Could not remove directory $SecureDir : $($_.Exception.Message)"
        }
    } else {
        $nonWindo = $remaining | Where-Object { $_.Name -notlike "windo*" }
        if ($nonWindo.Count -gt 0) {
            Write-Host "[windo uninstall] Secure dir still contains non-WINDO items; left in place: $SecureDir" -ForegroundColor Yellow
        }
    }
}

if (-not $KeepSnapshots -and (Test-Path $SnapshotDir)) {
    try {
        Remove-Item -Path $SnapshotDir -Recurse -Force -ErrorAction Stop
        Write-Host "[windo uninstall] Removed: $SnapshotDir" -ForegroundColor Green
    } catch {
        Write-Warning "Could not remove snapshot dir: $($_.Exception.Message)"
    }
} elseif ($KeepSnapshots) {
    Write-Host "[windo uninstall] Kept Documents snapshot folder (--KeepSnapshots)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "WINDO uninstall finished. Open a new shell; 'windo' should be undefined until reinstalled." -ForegroundColor Cyan
exit 0
'@
Write-Utf8NoBomFile -Path $UninstallPath -Content $UninstallContent

$MainActionArgs   = Get-NoWindowActionArgs -ScriptPath $RunnerPath
$UpdateActionArgs = Get-NoWindowActionArgs -ScriptPath $UpdateScript

$taskRegistrationSucceeded = $true
Write-WindoInstallStep -Status run -Label "Registering elevated scheduled tasks" -Detail "$TaskMain / $TaskUpdate"
try {
    try { Unregister-ScheduledTask -TaskName $TaskMain -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Unregister-ScheduledTask -TaskName $TaskUpdate -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

    $Principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Highest
    $Settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask -TaskName $TaskMain `
        -Action (New-ScheduledTaskAction -Execute $MainActionArgs.Execute -Argument $MainActionArgs.Argument) `
        -Principal $Principal -Settings $Settings -Force -ErrorAction Stop | Out-Null

    Register-ScheduledTask -TaskName $TaskUpdate `
        -Action (New-ScheduledTaskAction -Execute $UpdateActionArgs.Execute -Argument $UpdateActionArgs.Argument) `
        -Principal $Principal -Settings $Settings -Force -ErrorAction Stop | Out-Null
    Write-WindoInstallStep -Status ok -Label "Scheduled tasks registered" -Color Green
} catch {
    $taskRegistrationSucceeded = $false
    Write-WindoInstallStep -Status warn -Label "Scheduled task registration deferred" -Detail "re-run elevated to restore task automation" -Color Yellow
    Write-Warning ("WINDO: Could not register scheduled tasks; continuing with profile and snapshot refresh. Re-run installer elevated once to restore task automation. " + $_.Exception.Message)
}

Write-WindoInstallStep -Status run -Label "Writing integrity manifest" -Detail $ManifestFile
$Manifest = [ordered]@{
    version = $WindoVersion
    taskRegistrationSucceeded = [bool]$taskRegistrationSucceeded
    files = [ordered]@{
        runner = [ordered]@{
            path = $RunnerPath
            sha256 = Get-FileHashString -Path $RunnerPath
        }
        self_update = [ordered]@{
            path = $UpdateScript
            sha256 = Get-FileHashString -Path $UpdateScript
        }
        uninstall = [ordered]@{
            path = $UninstallPath
            sha256 = Get-FileHashString -Path $UninstallPath
        }
    }
    generated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}
$Manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestFile -Encoding UTF8
Write-WindoInstallStep -Status ok -Label "Integrity manifest written" -Color Green

Write-WindoInstallStep -Status run -Label "Refreshing PowerShell profile block" -Detail $PROFILE
Remove-ExistingWindoBlockFromProfile
Ensure-ProfileExists

$WindoFunctionBody = @'
function Invoke-WindoBundledUninstall {
    [CmdletBinding()]
    param(
        [switch]$Confirm,
        [switch]$KeepSnapshots,
        [switch]$DownloadFresh
    )

    $SecureDir = Join-Path $HOME ".pwsh_secure"
    $BundledUninstallPath = Join-Path $SecureDir "windo_uninstall.ps1"
    $SnapshotUninstallPath = Join-Path (Join-Path $HOME "Documents") "windo\windo_uninstall.ps1"
    $UnUrl = "https://raw.githubusercontent.com/l28bit/windo/v6/windo_uninstall.ps1"
    $TempUn = $null
    $ScriptPath = $null

    try {
        if (-not $DownloadFresh) {
            if (Test-Path -LiteralPath $BundledUninstallPath) {
                $ScriptPath = $BundledUninstallPath
            } elseif (Test-Path -LiteralPath $SnapshotUninstallPath) {
                $ScriptPath = $SnapshotUninstallPath
            }
        }

        if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
            $TempUn = Join-Path $env:TEMP ("windo_uninstall_" + [Guid]::NewGuid().ToString("n") + ".ps1")
            Write-Host "[windo] Downloading uninstaller..." -ForegroundColor Cyan
            Invoke-RestMethod -Uri $UnUrl -OutFile $TempUn
            if (!(Test-Path -LiteralPath $TempUn)) { throw "Download failed." }
            if ((Get-Item -LiteralPath $TempUn).Length -lt 400) { throw "Uninstaller file size looks invalid." }
            $ScriptPath = $TempUn
        }

        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
        if ($Confirm) { $argList += '-Confirm' }
        if ($KeepSnapshots) { $argList += '-KeepSnapshots' }

        Write-Host "[windo] Starting elevated uninstall (UAC). Approve the prompt to remove tasks, profile blocks, and WINDO data." -ForegroundColor Yellow
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList -Wait
    } catch {
        Write-Host "[windo] uninstall: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Run manually (elevated): powershell -ExecutionPolicy Bypass -File path\to\windo_uninstall.ps1" -ForegroundColor DarkGray
    } finally {
        if ($TempUn -and (Test-Path -LiteralPath $TempUn)) {
            Remove-Item -LiteralPath $TempUn -Force -ErrorAction SilentlyContinue
        }
    }
}

function windo-uninstall {
    [CmdletBinding()]
    param(
        [switch]$Confirm,
        [switch]$KeepSnapshots,
        [switch]$DownloadFresh
    )

    Invoke-WindoBundledUninstall -Confirm:$Confirm -KeepSnapshots:$KeepSnapshots -DownloadFresh:$DownloadFresh
}

Set-Alias -Name windoremove -Value windo-uninstall -Scope Global -ErrorAction SilentlyContinue

function windo {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Command
    )

    $ErrorActionPreference = "Stop"

    $WindoVersion = "__VERSION__"
    $TaskName     = "WindoElevatedRunner"
    $TaskUpdate   = "WindoSelfUpdate"
    $SecureDir    = Join-Path $HOME ".pwsh_secure"
    $LogFile      = Join-Path $SecureDir "windo_history.enc"
    $RunnerLast   = Join-Path $SecureDir "windo_runner_last.txt"
    $UpdateLast   = Join-Path $SecureDir "windo_self_update_last.txt"
    $RunnerPath   = Join-Path $SecureDir "windo_runner.ps1"
    $UpdatePath   = Join-Path $SecureDir "windo_self_update.ps1"
    $LastCmdFile  = Join-Path $SecureDir "windo_last_command.txt"
    $LastMetaFile = Join-Path $SecureDir "windo_last_meta.json"
    $PrefsFile    = Join-Path $SecureDir "windo_prefs.json"
    $ManifestFile = Join-Path $SecureDir "windo_manifest.json"
    $SchemaVersion = "3.0"
    $ProfileBlockBegin = "# >>> WINDO-BEGIN >>>"
    $ProfileBlockEnd = "# <<< WINDO-END <<<"
    $WindoBuiltins = @(__WINDO_BUILTIN_ARRAY__)

    if (!(Test-Path $SecureDir)) { New-Item -ItemType Directory -Path $SecureDir | Out-Null }
    $JsonOutput = $false
    $DryRun = $false
    $NonInteractive = $false
    $PreserveEnvAll = $false
    $PreserveEnvNames = @()
    $CommandTimeoutOverrideMs = $null
    $HelpRequested = $false
    $HelpTopic = $null
    if ($Command -and $Command.Count -gt 0) {
        $rawCommand = [System.Collections.ArrayList]@($Command)
        $leading = 0
        while ($leading -lt $rawCommand.Count) {
            $tx = [string]$rawCommand[$leading]
            if ($tx -eq '/?') {
                $HelpRequested = $true
                if (($leading + 1) -lt $rawCommand.Count) {
                    $next = [string]$rawCommand[$leading + 1]
                    if ($next -notlike '-*' -and $next -ne '/?') {
                        $HelpTopic = $next
                        $leading += 2
                        continue
                    }
                }
                $leading++
                continue
            }
            if ($tx -eq '--') { $leading++; break }
            if ($tx -notlike '-*' -or $tx -eq '-') { break }

            if ($tx -eq '--json' -or $tx -eq '-Json') {
                $JsonOutput = $true
                $leading++
                continue
            }
            if ($tx -eq '--dry-run' -or $tx -eq '-DryRun') {
                $DryRun = $true
                $leading++
                continue
            }
            if ($tx -eq '--help' -or $tx -eq '-h' -or $tx -eq '-?') {
                $HelpRequested = $true
                if (($leading + 1) -lt $rawCommand.Count) {
                    $next = [string]$rawCommand[$leading + 1]
                    if ($next -notlike '-*' -and $next -ne '/?') {
                        $HelpTopic = $next
                        $leading += 2
                        continue
                    }
                }
                $leading++
                continue
            }
            if ($tx -eq '--non-interactive' -or $tx -eq '-n') {
                if ($tx -eq '-n' -and ($leading + 1) -lt $rawCommand.Count) {
                    $lookahead = [string]$rawCommand[$leading + 1]
                    if ($lookahead -in @('log', 'history')) {
                        break
                    }
                }
                $NonInteractive = $true
                $leading++
                continue
            }
            if ($tx -eq '--preserve-env' -or $tx -eq '-E') {
                if ($tx -eq '-E') {
                    $PreserveEnvAll = $true
                    $leading++
                    continue
                }
                if ($leading + 1 -ge $rawCommand.Count) {
                    Write-Host "[windo] --preserve-env requires a value of env var names or use -E for all." -ForegroundColor Yellow
                    _windo_set_exit 2
                    return
                }
                $rawEnvSpec = [string]$rawCommand[$leading + 1]
                if (-not [string]::IsNullOrWhiteSpace($rawEnvSpec)) {
                    if ($rawEnvSpec -match '^(?i)all$') {
                        $PreserveEnvAll = $true
                        $PreserveEnvNames = @()
                    } else {
                        $PreserveEnvNames = @($rawEnvSpec -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    }
                }
                $leading += 2
                continue
            }
            if ($tx -like '--preserve-env=*') {
                $rawEnvSpec = $tx.Substring(16)
                if (-not [string]::IsNullOrWhiteSpace($rawEnvSpec)) {
                    if ($rawEnvSpec -match '^(?i)all$') {
                        $PreserveEnvAll = $true
                        $PreserveEnvNames = @()
                    } else {
                        $PreserveEnvNames = @($rawEnvSpec -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    }
                }
                $leading++
                continue
            }
            if ($tx -eq '--timeout' -or $tx -eq '-t') {
                if ($leading + 1 -ge $rawCommand.Count) {
                    Write-Host "[windo] $tx requires a numeric timeout value." -ForegroundColor Yellow
                    _windo_set_exit 2
                    return
                }
                $rawTimeout = [string]$rawCommand[$leading + 1]
                $parsedTimeout = _windo_parse_timeout_override_ms $rawTimeout
                if ($null -eq $parsedTimeout -or $parsedTimeout -lt 1) {
                    Write-Host "[windo] Invalid timeout value: $rawTimeout. Use seconds or ms (e.g. 10, 10s, 500ms)." -ForegroundColor Yellow
                    _windo_set_exit 2
                    return
                }
                if ($parsedTimeout -gt 86400000) { $parsedTimeout = 86400000 }
                $CommandTimeoutOverrideMs = [int]$parsedTimeout
                $leading += 2
                continue
            }
            if ($tx -like '--timeout=*' -or $tx -like '-t=*') {
                $idx = $tx.IndexOf('=')
                $rawTimeout = $tx.Substring($idx + 1)
                $parsedTimeout = _windo_parse_timeout_override_ms $rawTimeout
                if ($null -eq $parsedTimeout -or $parsedTimeout -lt 1) {
                    Write-Host "[windo] Invalid timeout value: $rawTimeout. Use seconds or ms (e.g. 10, 10s, 500ms)." -ForegroundColor Yellow
                    _windo_set_exit 2
                    return
                }
                if ($parsedTimeout -gt 86400000) { $parsedTimeout = 86400000 }
                $CommandTimeoutOverrideMs = [int]$parsedTimeout
                $leading++
                continue
            }
            break
        }
        $Command = if ($leading -eq 0) { @($rawCommand) } elseif ($leading -ge $rawCommand.Count) { @() } else { @($rawCommand[$leading..($rawCommand.Count - 1)]) }
        if ($Command.Count -ge 1 -and $Command[-1] -eq '/?') {
            $trimmed = @($Command[0..($Command.Count - 2)])
            $HelpRequested = $true
            if ([string]::IsNullOrWhiteSpace($HelpTopic)) {
                if ($trimmed.Count -gt 1 -and ($trimmed[0] -ieq 'help')) { $HelpTopic = [string]$trimmed[1] }
                elseif ($trimmed.Count -ge 1) { $HelpTopic = [string]$trimmed[0] }
            }
            $Command = @($trimmed)
        }

        if ($null -eq $CommandTimeoutOverrideMs -and -not [string]::IsNullOrWhiteSpace($env:SUDO_TIMEOUT)) {
            $sudoTimeout = _windo_parse_timeout_override_ms ([string]$env:SUDO_TIMEOUT)
            if ($null -ne $sudoTimeout -and $sudoTimeout -ge 1) {
                if ($sudoTimeout -gt 86400000) { $sudoTimeout = 86400000 }
                $CommandTimeoutOverrideMs = [int]$sudoTimeout
            }
        }

        if ($Command.Count -gt 0) {
            $cl = [System.Collections.ArrayList]@($Command)
            $hasCmd = $false
            $cmd = ""
            if ($cl.Count -gt 0) {
                $cmd = [string]$cl[0].ToLowerInvariant()
                $hasCmd = $true
            }
            $allowTimeoutLikeFlags = $hasCmd -and $cmd -notin @('history', 'log')
            $i = 0
            while ($i -lt $cl.Count) {
                $tx = [string]$cl[$i]
                if ($tx -eq '--') { break }

                if ($tx -eq '--json' -or $tx -eq '-Json') {
                    $JsonOutput = $true
                    $null = $cl.RemoveAt($i)
                    continue
                }
                if ($tx -eq '--dry-run' -or $tx -eq '-DryRun') {
                    $DryRun = $true
                    $null = $cl.RemoveAt($i)
                    continue
                }

                $isBuiltinHelpTarget = $hasCmd -and ($cmd -eq 'help' -or $WindoBuiltins -contains $cmd)
                if ($tx -eq '/?' -or (($tx -eq '--help' -or $tx -eq '-h' -or $tx -eq '-?') -and $isBuiltinHelpTarget)) {
                    $HelpRequested = $true
                    if ([string]::IsNullOrWhiteSpace($HelpTopic)) {
                        if ($hasCmd -and $cmd -eq 'help' -and ($i + 1) -lt $cl.Count) {
                            $HelpTopic = [string]$cl[$i + 1]
                        } else {
                            $HelpTopic = $cmd
                        }
                    }
                    $null = $cl.RemoveAt($i)
                    continue
                }

                if ($allowTimeoutLikeFlags -and ($tx -eq '--non-interactive' -or $tx -eq '-n')) {
                    if ($tx -eq '-n' -and ($i + 1) -lt $cl.Count) {
                        $lookahead = [string]$cl[$i + 1]
                        if ($lookahead -in @('log', 'history')) {
                            break
                        }
                    }
                    $NonInteractive = $true
                    $null = $cl.RemoveAt($i)
                    continue
                }

                if ($allowTimeoutLikeFlags -and ($tx -eq '--preserve-env' -or $tx -eq '-E')) {
                    if ($tx -eq '-E') {
                        $PreserveEnvAll = $true
                        $null = $cl.RemoveAt($i)
                        continue
                    }
                    if (($i + 1) -ge $cl.Count) {
                        Write-Host "[windo] --preserve-env requires a value of env var names or use -E for all." -ForegroundColor Yellow
                        _windo_set_exit 2
                        return
                    }
                    $rawEnvSpec = [string]$cl[$i + 1]
                    if (-not [string]::IsNullOrWhiteSpace($rawEnvSpec)) {
                        if ($rawEnvSpec -match '^(?i)all$') {
                            $PreserveEnvAll = $true
                            $PreserveEnvNames = @()
                        } else {
                            $PreserveEnvNames = @($rawEnvSpec -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        }
                    }
                    $null = $cl.RemoveAt($i + 1)
                    $null = $cl.RemoveAt($i)
                    continue
                }
                if ($allowTimeoutLikeFlags -and ($tx -like '--preserve-env=*')) {
                    $rawEnvSpec = $tx.Substring(16)
                    if (-not [string]::IsNullOrWhiteSpace($rawEnvSpec)) {
                        if ($rawEnvSpec -match '^(?i)all$') {
                            $PreserveEnvAll = $true
                            $PreserveEnvNames = @()
                        } else {
                            $PreserveEnvNames = @($rawEnvSpec -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        }
                    }
                    $null = $cl.RemoveAt($i)
                    continue
                }

                if ($allowTimeoutLikeFlags -and ($tx -eq '--timeout' -or $tx -eq '-t')) {
                    if (($i + 1) -ge $cl.Count) {
                        Write-Host "[windo] $tx requires a numeric timeout value." -ForegroundColor Yellow
                        _windo_set_exit 2
                        return
                    }
                    $rawTimeout = [string]$cl[$i + 1]
                    $parsedTimeout = _windo_parse_timeout_override_ms $rawTimeout
                    if ($null -eq $parsedTimeout -or $parsedTimeout -lt 1) {
                        Write-Host "[windo] Invalid timeout value: $rawTimeout. Use seconds or ms (e.g. 10, 10s, 500ms)." -ForegroundColor Yellow
                        _windo_set_exit 2
                        return
                    }
                    if ($parsedTimeout -gt 86400000) { $parsedTimeout = 86400000 }
                    $CommandTimeoutOverrideMs = [int]$parsedTimeout
                    $null = $cl.RemoveAt($i + 1)
                    $null = $cl.RemoveAt($i)
                    continue
                }

                if ($allowTimeoutLikeFlags -and ($tx -like '--timeout=*' -or $tx -like '-t=*')) {
                    $idx = $tx.IndexOf('=')
                    $rawTimeout = $tx.Substring($idx + 1)
                    $parsedTimeout = _windo_parse_timeout_override_ms $rawTimeout
                    if ($null -eq $parsedTimeout -or $parsedTimeout -lt 1) {
                        Write-Host "[windo] Invalid timeout value: $rawTimeout. Use seconds or ms (e.g. 10, 10s, 500ms)." -ForegroundColor Yellow
                        _windo_set_exit 2
                        return
                    }
                    if ($parsedTimeout -gt 86400000) { $parsedTimeout = 86400000 }
                    $CommandTimeoutOverrideMs = [int]$parsedTimeout
                    $null = $cl.RemoveAt($i)
                    continue
                }

                $i++
            }
            $Command = @($cl)
        }
    }

    $global:WINDO_EXIT_CODE = 0
    function _windo_set_exit([int]$Code) {
        $global:WINDO_EXIT_CODE = $Code
        try { $global:LASTEXITCODE = $Code } catch { }
    }

    function _windo_is_process_elevated {
        try {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $pr = [Security.Principal.WindowsPrincipal]$id
            return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch {
            return $false
        }
    }

    function _windo_ai_ollama_host_advisory {
        $h = [Environment]::GetEnvironmentVariable('OLLAMA_HOST', 'Process')
        if ([string]::IsNullOrWhiteSpace($h)) { $h = [Environment]::GetEnvironmentVariable('OLLAMA_HOST', 'User') }
        if ([string]::IsNullOrWhiteSpace($h)) { $h = [Environment]::GetEnvironmentVariable('OLLAMA_HOST', 'Machine') }
        if ([string]::IsNullOrWhiteSpace($h)) {
            return "Ollama: OLLAMA_HOST is unset â€” server defaults to 127.0.0.1:11434 (local only)."
        }
        $t = $h.Trim()
        $tl = $t.ToLowerInvariant()
        if ($tl -match '^(https?://)?(127\.0\.0\.1|localhost)(:|/|$)' -or $tl -match '^127\.0\.0\.1:\d+$' -or $tl -match '^localhost:\d+$') {
            return $null
        }
        if ($tl -match '^(https?://)?0\.0\.0\.0(:|/|$)' -or $tl -match '^0\.0\.0\.0:\d+$') {
            return "Ollama: OLLAMA_HOST binds all interfaces â€” confirm firewall rules and intentional LAN exposure."
        }
        return "Ollama: OLLAMA_HOST may point off loopback â€” confirm intentional network exposure and firewall rules."
    }

    function _windo_ai_credential_env_snapshot {
        $cloudApiNames = @(
            'OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'AZURE_OPENAI_API_KEY', 'AZURE_OPENAI_ENDPOINT',
            'OPENAI_API_BASE', 'COHERE_API_KEY', 'MISTRAL_API_KEY', 'GOOGLE_API_KEY', 'GEMINI_API_KEY',
            'WINDO_AI_KEY_FILE', 'OPENAI_ORG_ID'
        )
        $ollamaNames = @(
            'OLLAMA_HOST', 'OLLAMA_MODELS', 'OLLAMA_ORIGINS', 'OLLAMA_NUM_PARALLEL', 'OLLAMA_MAX_LOADED_MODELS', 'OLLAMA_KEEP_ALIVE'
        )
        $names = @($cloudApiNames + $ollamaNames | Select-Object -Unique)
        $proc = [ordered]@{}
        $user = [ordered]@{}
        $machine = [ordered]@{}
        foreach ($n in $names) {
            $pv = [Environment]::GetEnvironmentVariable($n, 'Process')
            $proc[$n] = -not [string]::IsNullOrWhiteSpace($pv)
            try {
                $uv = [Environment]::GetEnvironmentVariable($n, 'User')
                $user[$n] = -not [string]::IsNullOrWhiteSpace($uv)
            } catch { $user[$n] = $false }
            try {
                $mv = [Environment]::GetEnvironmentVariable($n, 'Machine')
                $machine[$n] = -not [string]::IsNullOrWhiteSpace($mv)
            } catch { $machine[$n] = $false }
        }
        $anyProcCloud = $false
        foreach ($n in $cloudApiNames) { if ($proc.Contains($n) -and $proc[$n]) { $anyProcCloud = $true; break } }
        $anyUserCloud = $false
        foreach ($n in $cloudApiNames) { if ($user.Contains($n) -and $user[$n]) { $anyUserCloud = $true; break } }
        $anyMachCloud = $false
        foreach ($n in $cloudApiNames) { if ($machine.Contains($n) -and $machine[$n]) { $anyMachCloud = $true; break } }
        $ollamaActive = [System.Collections.ArrayList]@()
        foreach ($on in $ollamaNames) {
            if (($proc[$on] -or $user[$on] -or $machine[$on])) { [void]$ollamaActive.Add($on) }
        }
        @{
            elevated              = (_windo_is_process_elevated)
            processHasSecret      = $anyProcCloud
            userScopeHasSecret    = $anyUserCloud
            machineScopeHasSecret = $anyMachCloud
            processSetNames       = @($names | Where-Object { $proc[$_] } | Sort-Object)
            userSetNames          = @($names | Where-Object { $user[$_] } | Sort-Object)
            machineSetNames       = @($names | Where-Object { $machine[$_] } | Sort-Object)
            process               = $proc
            user                  = $user
            machine               = $machine
            ollamaSetNames        = @($ollamaActive | Sort-Object)
        }
    }

    function _dpapi_protect([string]$s) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
        $enc = [System.Security.Cryptography.ProtectedData]::Protect(
            $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [Convert]::ToBase64String($enc)
    }

    function _dpapi_unprotect([string]$b64) {
        $enc = [Convert]::FromBase64String($b64)
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    function _sha256_hex([string]$s) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
        ([BitConverter]::ToString($hashBytes) -replace '-','')
    }

    function _file_hash([string]$Path) {
        if (!(Test-Path $Path)) { return "(missing)" }
        try { (Get-FileHash -Path $Path -Algorithm SHA256).Hash } catch { "(hash-error)" }
    }

    function _windo_published_text_file_sha256([string]$Path) {
        if (!(Test-Path -LiteralPath $Path)) { return "(missing)" }
        try {
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $normalized = [System.Collections.Generic.List[byte]]::new()
            for ($i = 0; $i -lt $bytes.Length; $i++) {
                if ($bytes[$i] -eq 13 -and ($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { continue }
                [void]$normalized.Add($bytes[$i])
            }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hashBytes = $sha.ComputeHash($normalized.ToArray())
                return (-join ($hashBytes | ForEach-Object { $_.ToString("X2") }))
            } finally {
                $sha.Dispose()
            }
        } catch {
            return "(hash-error)"
        }
    }

    function _expected_hash([string]$Key) {
        if (!(Test-Path $ManifestFile)) { return "(manifest-missing)" }
        try {
            $m = Get-Content -Raw -Path $ManifestFile | ConvertFrom-Json
            if ($Key -eq "runner") { return [string]$m.files.runner.sha256 }
            if ($Key -eq "self_update") { return [string]$m.files.self_update.sha256 }
            return "(unknown-key)"
        } catch { return "(manifest-error)" }
    }

    function _is_sha256_hex([string]$s) {
        if ($null -eq $s -or $s.Length -ne 64) { return $false }
        $s -match '^[0-9A-Fa-f]{64}$'
    }

    function _integrity_component_level([string]$actual, [string]$expected) {
        if ($actual -eq "(missing)" -or $actual -eq "(hash-error)") { return "UNKNOWN" }
        if ($expected -match '^\(manifest' -or $expected -eq "(unknown-key)") { return "UNKNOWN" }
        if ($actual -eq $expected) { return "OK" }
        if (_is_sha256_hex $actual -and _is_sha256_hex $expected) { return "TAMPERED" }
        return "DRIFT"
    }

    function _integrity_status {
        $runnerActual = _file_hash $RunnerPath
        $runnerExpect = _expected_hash "runner"
        $updateActual = _file_hash $UpdatePath
        $updateExpect = _expected_hash "self_update"
        $rl = _integrity_component_level $runnerActual $runnerExpect
        $ul = _integrity_component_level $updateActual $updateExpect
        $overall = "OK"
        if ($rl -eq "UNKNOWN" -or $ul -eq "UNKNOWN") { $overall = "UNKNOWN" }
        elseif ($rl -eq "TAMPERED" -or $ul -eq "TAMPERED") { $overall = "TAMPERED" }
        elseif ($rl -eq "DRIFT" -or $ul -eq "DRIFT") { $overall = "DRIFT" }
        [pscustomobject]@{
            RunnerMatch = ($runnerActual -eq $runnerExpect)
            RunnerActual = $runnerActual
            RunnerExpected = $runnerExpect
            RunnerLevel = $rl
            UpdaterMatch = ($updateActual -eq $updateExpect)
            UpdaterActual = $updateActual
            UpdaterExpected = $updateExpect
            UpdaterLevel = $ul
            OverallLevel = $overall
        }
    }

    function _read_windo_prefs {
        if (!(Test-Path -LiteralPath $PrefsFile)) { return $null }
        try { Get-Content -Raw -Path $PrefsFile | ConvertFrom-Json } catch { $null }
    }

    function _windo_parse_bool_value {
        param(
            [object]$Raw,
            [bool]$Default = $false
        )
        if ($null -eq $Raw) { return $Default }
        $value = [string]$Raw
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        switch ($value.Trim().ToLowerInvariant()) {
            '1' { return $true }
            'true' { return $true }
            'yes' { return $true }
            'on' { return $true }
            'enabled' { return $true }
            '0' { return $false }
            'false' { return $false }
            'no' { return $false }
            'off' { return $false }
            'disabled' { return $false }
            default { return $Default }
        }
    }

    function _windo_read_windo_prefs_map {
        $pref = _read_windo_prefs
        $map = [ordered]@{}
        if ($null -eq $pref -or -not ($pref.PSObject.Properties.Count -gt 0)) { return $map }
        foreach ($property in $pref.PSObject.Properties) {
            $map[$property.Name] = $property.Value
        }
        return $map
    }

    function _windo_save_windo_prefs {
        param([hashtable]$Source)
        $payload = [ordered]@{}
        if ($null -ne $Source) {
            foreach ($key in $Source.Keys) {
                $payload[$key] = $Source[$key]
            }
        }
        if (-not $payload.Contains('schemaVersion')) { $payload.schemaVersion = "1.0" }
        $payload.updatedAt = (Get-Date -Format "o")
        try {
            ($payload | ConvertTo-Json -Depth 12) | Set-Content -Path $PrefsFile -Encoding UTF8
            return $true
        } catch {
            return $false
        }
    }

    function _windo_modules_root { Join-Path (Join-Path $HOME "Documents") "windo\modules" }
    function _windo_extras_install_root { Join-Path (Join-Path $HOME "Documents") "windo\extras" }

    function _windo_parse_semver_loose([string]$v) {
        if ([string]::IsNullOrWhiteSpace($v)) { return $null }
        $t = $v.Trim()
        if ($t -match '^(\d+)(?:\.(\d+))?(?:\.(\d+))?') {
            $ma = [int]$Matches[1]
            $mi = 0
            $pa = 0
            if ($Matches[2]) { $mi = [int]$Matches[2] }
            if ($Matches[3]) { $pa = [int]$Matches[3] }
            return [version]::new($ma, [Math]::Max(0, $mi), [Math]::Max(0, $pa))
        }
        return $null
    }

    function _windo_meets_requires_windo([string]$requires) {
        if ([string]::IsNullOrWhiteSpace($requires)) { return $true }
        $need = _windo_parse_semver_loose $requires
        $have = _windo_parse_semver_loose $WindoVersion
        if ($null -eq $need -or $null -eq $have) { return $true }
        return ($have -ge $need)
    }

    function _windo_get_enabled_module_ids {
        $map = _windo_read_windo_prefs_map
        $ids = [System.Collections.ArrayList]@()
        if ($map.Contains('enabledModules') -and $null -ne $map['enabledModules']) {
            $raw = $map['enabledModules']
            if ($raw -is [System.Collections.IEnumerable] -and $raw -isnot [string]) {
                foreach ($x in @($raw)) {
                    $sx = [string]$x
                    if (-not [string]::IsNullOrWhiteSpace($sx)) { [void]$ids.Add($sx.Trim()) }
                }
            }
        }
        return @($ids | Select-Object -Unique)
    }

    function _windo_set_enabled_module_ids([string[]]$Ids) {
        $map = _windo_read_windo_prefs_map
        $clean = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
        $map['enabledModules'] = $clean
        return [bool](_windo_save_windo_prefs $map)
    }

    function _windo_read_module_manifest([string]$ModuleDir) {
        $mj = Join-Path $ModuleDir "module.json"
        if (!(Test-Path -LiteralPath $mj)) { return $null }
        try { Get-Content -Raw -LiteralPath $mj -ErrorAction Stop | ConvertFrom-Json } catch { return $null }
    }

    function _windo_discover_module_directories {
        $root = _windo_modules_root
        if (!(Test-Path -LiteralPath $root)) { return @() }
        @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)
    }

    function _windo_modules_discover_rows {
        param([string[]]$EnabledIds)
        $en = @()
        if ($null -ne $EnabledIds) { $en = @($EnabledIds) }
        $rows = [System.Collections.ArrayList]@()
        foreach ($d in @(_windo_discover_module_directories)) {
            $mf = _windo_read_module_manifest $d.FullName
            $name = $d.Name
            if ($mf -and $mf.PSObject.Properties.Name -contains 'name' -and -not [string]::IsNullOrWhiteSpace([string]$mf.name)) { $name = [string]$mf.name }
            $ver = $null
            if ($mf -and $mf.PSObject.Properties.Name -contains 'version') { $ver = [string]$mf.version }
            $entry = "Load.ps1"
            if ($mf -and $mf.PSObject.Properties.Name -contains 'entry' -and -not [string]::IsNullOrWhiteSpace([string]$mf.entry)) { $entry = [string]$mf.entry }
            $req = $null
            if ($mf -and $mf.PSObject.Properties.Name -contains 'requiresWindoVersion') { $req = [string]$mf.requiresWindoVersion }
            [void]$rows.Add([ordered]@{
                id = $d.Name
                path = $d.FullName
                manifestName = $name
                version = $ver
                entry = $entry
                requiresWindoVersion = $req
                enabled = [bool]($en -contains $d.Name)
            })
        }
        return @($rows)
    }

    function _windo_builtin_recipes {
        @{
            'arp-cache'                 = @{ description = 'Show the local ARP cache.'; command = 'arp.exe -a' }
            'audit-policy'              = @{ description = 'Show audit policy by category.'; command = 'auditpol.exe /get /category:*' }
            'bitlocker-status'          = @{ description = 'Show BitLocker volume protection status.'; command = 'manage-bde.exe -status' }
            'boot-config'               = @{ description = 'Show boot configuration entries.'; command = 'bcdedit.exe /enum' }
            'cert-my-store'             = @{ description = 'List local computer personal certificate store.'; command = 'certutil.exe -store my' }
            'cert-root-store'           = @{ description = 'List local computer trusted root certificate store.'; command = 'certutil.exe -store root' }
            'defender-preferences'      = @{ description = 'Show selected Microsoft Defender preference settings.'; command = 'powershell.exe -NoProfile -Command "Get-MpPreference | Select-Object DisableRealtimeMonitoring,PUAProtection,MAPSReporting,SubmitSamplesConsent,ScanScheduleDay,ScanScheduleTime"' }
            'defender-status'           = @{ description = 'Show selected Microsoft Defender health signals.'; command = 'powershell.exe -NoProfile -Command "Get-MpComputerStatus | Select-Object AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IoavProtectionEnabled,NISEnabled,AntispywareSignatureLastUpdated,AntivirusSignatureLastUpdated"' }
            'disk-free'                 = @{ description = 'Show logical disk capacity and free space.'; command = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID,DriveType,VolumeName,FileSystem,Size,FreeSpace"' }
            'dns-client-cache'          = @{ description = 'Display DNS client cache entries.'; command = 'ipconfig.exe /displaydns' }
            'driverquery'               = @{ description = 'List installed drivers.'; command = 'driverquery.exe /v' }
            'driverquery-signed'        = @{ description = 'List installed signed driver inventory.'; command = 'driverquery.exe /si' }
            'environment-os'            = @{ description = 'Show basic OS environment variables only.'; command = 'powershell.exe -NoProfile -Command "Get-ChildItem Env:OS,Env:PROCESSOR_ARCHITECTURE,Env:COMPUTERNAME,Env:USERDOMAIN | Select-Object Name,Value"' }
            'firewall-current-profile'  = @{ description = 'Show current Windows Firewall profile configuration.'; command = 'netsh.exe advfirewall show currentprofile' }
            'firewall-profiles'         = @{ description = 'Show Windows Firewall profile states (netsh).'; command = 'netsh.exe advfirewall show allprofiles state' }
            'rdp-check'                 = @{ description = 'Inspect local RDP enablement, registry config, and related firewall rules.'; command = 'windo rdp status --json' }
            'rdp-firewall'              = @{ description = 'Inspect RDP inbound firewall rules for desktop ports.'; command = 'windo rdp firewall status --json' }
            'rdp-troubleshoot'          = @{ description = 'Collect practical RDP troubleshooting state and connectivity checks.'; command = 'windo rdp troubleshoot --host localhost --ports 3389 --json' }
            'rdp-configure'             = @{ description = 'Enable/disable RDP and set NLA preference with optional service restart.'; command = 'windo rdp config --enable --nla on --json' }
            'vnc-check'                 = @{ description = 'Inspect common VNC services, registry presence, and listener/listen ports.'; command = 'windo vnc status --json' }
            'vnc-firewall'              = @{ description = 'Inspect VNC inbound firewall rules for 5900/5901.'; command = 'windo vnc firewall status --json' }
            'vnc-test'                  = @{ description = 'Probe VNC ports on a target host or localhost.'; command = 'windo vnc test --host localhost --ports 5900,5901 --json' }
            'vnc-troubleshoot'          = @{ description = 'Collect practical VNC troubleshooting state and port checks.'; command = 'windo vnc troubleshoot --host localhost --ports 5900,5901 --json' }
            'fsutil-drives'             = @{ description = 'Show mounted drive letters.'; command = 'fsutil.exe fsinfo drives' }
            'fsutil-trim'               = @{ description = 'Show TRIM behavior setting.'; command = 'fsutil.exe behavior query DisableDeleteNotify' }
            'gpresult-summary'          = @{ description = 'Show Group Policy result summary for the current context.'; command = 'gpresult.exe /r' }
            'hostname'                  = @{ description = 'Print host name.'; command = 'hostname.exe' }
            'ipconfig-all'              = @{ description = 'Detailed IP configuration.'; command = 'ipconfig.exe /all' }
            'ipconfig-brief'            = @{ description = 'Basic IP configuration (ipconfig, no switches).'; command = 'ipconfig.exe' }
            'local-admins'              = @{ description = 'Show local Administrators group membership.'; command = 'net.exe localgroup administrators' }
            'local-groups'              = @{ description = 'List local groups.'; command = 'net.exe localgroup' }
            'local-users'               = @{ description = 'List local user accounts.'; command = 'net.exe user' }
            'net-accounts'              = @{ description = 'Show local account and password policy.'; command = 'net.exe accounts' }
            'net-sessions'              = @{ description = 'Show active SMB sessions when available.'; command = 'net.exe session' }
            'net-shares'                = @{ description = 'Show local shares.'; command = 'net.exe share' }
            'net-use'                   = @{ description = 'Show current network connections.'; command = 'net.exe use' }
            'netstat-ports'             = @{ description = 'Show active connections and listening ports with process ids.'; command = 'netstat.exe -ano' }
            'network-adapters'          = @{ description = 'Show network adapter summary.'; command = 'powershell.exe -NoProfile -Command "Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,LinkSpeed,MacAddress"' }
            'network-dns-servers'       = @{ description = 'Show DNS server addresses by interface.'; command = 'powershell.exe -NoProfile -Command "Get-DnsClientServerAddress | Select-Object InterfaceAlias,AddressFamily,ServerAddresses"' }
            'network-ip-config'         = @{ description = 'Show IP interface configuration via netsh.'; command = 'netsh.exe interface ip show config' }
            'network-ipv6-interfaces'   = @{ description = 'Show IPv6 interfaces.'; command = 'netsh.exe interface ipv6 show interfaces' }
            'network-routes'            = @{ description = 'Show route table.'; command = 'route.exe print' }
            'network-wifi'              = @{ description = 'Show Wi-Fi interface state when WLAN is present.'; command = 'netsh.exe wlan show interfaces' }
            'ollama-list'               = @{ description = 'List local Ollama models (ollama list).'; command = 'ollama.exe list' }
            'ollama-ps'                 = @{ description = 'Ollama running models snapshot (ollama ps).'; command = 'ollama.exe ps' }
            'ollama-version'            = @{ description = 'Ollama CLI version (read-only; requires ollama on PATH).'; command = 'ollama.exe --version' }
            'os-build'                  = @{ description = 'Show Windows caption, version, build, and install date.'; command = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,InstallDate,LastBootUpTime"' }
            'os-version'                = @{ description = 'Print Windows version string (ver).'; command = 'cmd.exe /c ver' }
            'physical-disks'            = @{ description = 'Show physical disk health where Storage cmdlets are available.'; command = 'powershell.exe -NoProfile -Command "Get-PhysicalDisk | Select-Object FriendlyName,MediaType,HealthStatus,OperationalStatus,Size"' }
            'pnputil-drivers'           = @{ description = 'Enumerate driver packages in the driver store.'; command = 'pnputil.exe /enum-drivers' }
            'power-availability'        = @{ description = 'Show available sleep states.'; command = 'powercfg.exe /a' }
            'power-device-wake'         = @{ description = 'List devices that can wake the computer.'; command = 'powercfg.exe /devicequery wake_armed' }
            'power-lastwake'            = @{ description = 'Show last wake source.'; command = 'powercfg.exe /lastwake' }
            'power-requests'            = @{ description = 'Show current power requests.'; command = 'powercfg.exe /requests' }
            'processes-services'        = @{ description = 'Show process list with hosted services.'; command = 'tasklist.exe /svc' }
            'processes-verbose'         = @{ description = 'Show verbose task list.'; command = 'tasklist.exe /v' }
            'recovery-info'             = @{ description = 'Show Windows Recovery Environment status.'; command = 'reagentc.exe /info' }
            'scheduled-tasks'           = @{ description = 'Show scheduled tasks in table form.'; command = 'schtasks.exe /query /fo TABLE' }
            'scheduled-tasks-verbose'   = @{ description = 'Show verbose scheduled task inventory.'; command = 'schtasks.exe /query /fo LIST /v' }
            'service-bits-config'       = @{ description = 'Show BITS service configuration.'; command = 'sc.exe qc bits' }
            'service-bits-query'        = @{ description = 'Query the Background Intelligent Transfer Service (sc.exe).'; command = 'sc.exe query bits' }
            'service-spooler-query'     = @{ description = 'Query Print Spooler service state.'; command = 'sc.exe query spooler' }
            'service-winrm-query'       = @{ description = 'Query WinRM service state.'; command = 'sc.exe query winrm' }
            'services-all'              = @{ description = 'Query all services.'; command = 'sc.exe query state= all' }
            'services-drivers'          = @{ description = 'Query kernel and file-system drivers.'; command = 'sc.exe query type= driver state= all' }
            'shares-open-files'         = @{ description = 'Show remotely opened shared files when available.'; command = 'openfiles.exe /query' }
            'systeminfo'                = @{ description = 'Show system summary from systeminfo.'; command = 'systeminfo.exe' }
            'time-status'               = @{ description = 'Show Windows Time service status.'; command = 'w32tm.exe /query /status' }
            'time-configuration'        = @{ description = 'Show Windows Time service configuration.'; command = 'w32tm.exe /query /configuration' }
            'time-peers'                = @{ description = 'Show Windows Time service peers.'; command = 'w32tm.exe /query /peers' }
            'tool-docker-version'       = @{ description = 'Docker CLI version when docker is on PATH.'; command = 'docker.exe --version' }
            'tool-git-version'          = @{ description = 'Git CLI version when git is on PATH.'; command = 'git.exe --version' }
            'tool-node-version'         = @{ description = 'Node.js version when node is on PATH.'; command = 'node.exe --version' }
            'tool-powershell-path'      = @{ description = 'Show powershell.exe and pwsh.exe locations when present.'; command = 'powershell.exe -NoProfile -Command "Get-Command powershell.exe,pwsh.exe -ErrorAction SilentlyContinue | Select-Object Name,Source,Version"' }
            'tool-python-version'       = @{ description = 'Python version when python is on PATH.'; command = 'python.exe --version' }
            'tool-winget-version'       = @{ description = 'WinGet version when winget is available.'; command = 'winget.exe --version' }
            'uptime'                    = @{ description = 'Show last boot time and calculated uptime.'; command = 'powershell.exe -NoProfile -Command "$os=Get-CimInstance Win32_OperatingSystem; [pscustomobject]@{LastBootUpTime=$os.LastBootUpTime; Uptime=(Get-Date)-$os.LastBootUpTime}"' }
            'volumes'                   = @{ description = 'Show volume health and capacity.'; command = 'powershell.exe -NoProfile -Command "Get-Volume | Select-Object DriveLetter,FileSystemLabel,FileSystem,HealthStatus,SizeRemaining,Size"' }
            'whoami-all'                = @{ description = 'Show current token, groups, claims, and privileges.'; command = 'whoami.exe /all' }
            'whoami-groups'             = @{ description = 'Show current token group memberships.'; command = 'whoami.exe /groups' }
            'whoami-privileges'         = @{ description = 'Show current token privileges.'; command = 'whoami.exe /priv' }
            'winhttp-proxy'             = @{ description = 'Show WinHTTP proxy configuration.'; command = 'netsh.exe winhttp show proxy' }
            'winrm-config'              = @{ description = 'Show WinRM listener and service configuration.'; command = 'winrm.cmd get winrm/config' }
            'windows-update-services'   = @{ description = 'Show key Windows Update related service states.'; command = 'powershell.exe -NoProfile -Command "Get-Service wuauserv,bits,cryptsvc,msiserver | Select-Object Name,Status,StartType"' }
        }
    }

    function _windo_normalize_output_mode([string]$Mode) {
        if ([string]::IsNullOrWhiteSpace($Mode)) { return "compact" }
        switch ($Mode.Trim().ToLowerInvariant()) {
            "short" { return "compact" }
            "compact" { return "compact" }
            "sudo" { return "compact" }
            "quiet" { return "quiet" }
            "minimal" { return "quiet" }
            "legacy" { return "legacy" }
            "verbose" { return "legacy" }
            "classic" { return "legacy" }
            default { return "compact" }
        }
    }

    function _windo_resolve_output_policy {
        $pref = _read_windo_prefs
        $prefMode = $null
        if ($pref -and $pref.PSObject.Properties.Name -contains 'outputMode') { $prefMode = [string]$pref.outputMode }
        $envMode = [string]$env:WINDO_OUTPUT_MODE
        $source = "default"
        $raw = $null
        if (-not [string]::IsNullOrWhiteSpace($envMode)) {
            $source = "environment"
            $raw = $envMode
        } elseif (-not [string]::IsNullOrWhiteSpace($prefMode)) {
            $source = "prefs"
            $raw = $prefMode
        }
        $mode = _windo_normalize_output_mode $raw
        $desc = switch ($mode) {
            "legacy" { "multi-line status, duration, and output labels" }
            "quiet" { "only command output and errors" }
            default { "single compact status line plus command output when present" }
        }
        [pscustomobject]@{
            mode = $mode
            source = $source
            environmentValue = $(if ($envMode) { $envMode } else { $null })
            preferenceValue = $(if ($prefMode) { $prefMode } else { $null })
            prefsFile = $PrefsFile
            description = $desc
        }
    }

    function _windo_quote_argument([string]$Value) {
        if ($null -eq $Value) { return "''" }
        if ($Value -eq "") { return "''" }
        if ($Value -notmatch '[\s''"`$&|<>;()]') { return $Value }
        return "'" + ($Value -replace "'", "''") + "'"
    }

    function _windo_vault_path { Join-Path $SecureDir "windo_vault.json" }

    function _windo_vault_read_map {
        $path = _windo_vault_path
        $map = [ordered]@{}
        if (!(Test-Path -LiteralPath $path)) { return $map }
        try {
            $raw = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json
            if ($raw -and $raw.entries) {
                foreach ($p in $raw.entries.PSObject.Properties) { $map[$p.Name] = $p.Value }
            }
        } catch { }
        return $map
    }

    function _windo_vault_save_map($Map) {
        $entries = [ordered]@{}
        if ($Map) {
            foreach ($k in ($Map.Keys | Sort-Object)) { $entries[$k] = $Map[$k] }
        }
        $payload = [ordered]@{
            schemaVersion = "1.0"
            protectedBy = "DPAPI CurrentUser"
            updatedAt = (Get-Date -Format "o")
            entries = $entries
        }
        try {
            ($payload | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (_windo_vault_path) -Encoding UTF8
            return $true
        } catch {
            return $false
        }
    }

    function _windo_scan_one_file([System.IO.FileInfo]$File, [int64]$MaxBytes, [bool]$Hash) {
        $findings = [System.Collections.ArrayList]@()
        $ext = $File.Extension.ToLowerInvariant()
        if ($ext -in @('.ps1', '.psm1', '.psd1', '.bat', '.cmd', '.vbs', '.js', '.jse', '.wsf', '.hta', '.reg')) {
            [void]$findings.Add([ordered]@{ id = "script-extension"; severity = "info"; detail = "script-capable extension $ext" })
        }
        if ($ext -in @('.exe', '.dll', '.scr', '.msi', '.ps1', '.bat', '.cmd')) {
            [void]$findings.Add([ordered]@{ id = "executable-content"; severity = "info"; detail = "executable or launchable file type $ext" })
        }
        $ads = $null
        try { $ads = Get-Item -LiteralPath $File.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue } catch { $ads = $null }
        if ($ads) { [void]$findings.Add([ordered]@{ id = "mark-of-the-web"; severity = "warn"; detail = "Zone.Identifier alternate data stream present" }) }
        if ($File.Length -le $MaxBytes -and $ext -in @('.ps1', '.psm1', '.psd1', '.bat', '.cmd', '.vbs', '.js', '.hta', '.txt', '.config', '.json', '.xml')) {
            try {
                $text = Get-Content -Raw -LiteralPath $File.FullName -ErrorAction Stop
                $patterns = @(
                    @{ id = "encoded-command"; severity = "warn"; regex = '(?i)(-|/)enc(odedcommand)?\s+[A-Za-z0-9+/=]{20,}' },
                    @{ id = "download-execute"; severity = "warn"; regex = '(?i)(Invoke-WebRequest|iwr|Invoke-RestMethod|irm|WebClient|DownloadString|DownloadFile).{0,120}(Invoke-Expression|iex|Start-Process|powershell|pwsh)' },
                    @{ id = "execution-policy-bypass"; severity = "warn"; regex = '(?i)ExecutionPolicy\s+Bypass' },
                    @{ id = "hidden-window"; severity = "info"; regex = '(?i)(WindowStyle\s+Hidden|-w\s+hidden)' },
                    @{ id = "plain-secret-token"; severity = "warn"; regex = '(?i)(api[_-]?key|client[_-]?secret|password|token)\s*[:=]\s*["''][^"'']{8,}' }
                )
                foreach ($p in $patterns) {
                    if ($text -match $p.regex) { [void]$findings.Add([ordered]@{ id = $p.id; severity = $p.severity; detail = "pattern matched" }) }
                }
            } catch {
                [void]$findings.Add([ordered]@{ id = "read-error"; severity = "info"; detail = $_.Exception.Message })
            }
        }
        $sha = $null
        if ($Hash) { try { $sha = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash } catch { $sha = $null } }
        [pscustomobject]@{
            path = $File.FullName
            sizeBytes = [int64]$File.Length
            sha256 = $sha
            findingCount = $findings.Count
            findings = @($findings)
        }
    }

    function _windo_scan_paths([string[]]$Paths, [bool]$Recurse, [int]$MaxMb, [bool]$Hash) {
        $rows = [System.Collections.ArrayList]@()
        $errors = [System.Collections.ArrayList]@()
        $maxBytes = [int64]([Math]::Max(1, $MaxMb) * 1MB)
        foreach ($p in @($Paths)) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            if (!(Test-Path -LiteralPath $p)) {
                [void]$errors.Add([ordered]@{ path = $p; error = "path not found" })
                continue
            }
            $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            if ($item -is [System.IO.DirectoryInfo]) {
                foreach ($f in @(Get-ChildItem -LiteralPath $item.FullName -File -Force -Recurse:$Recurse -ErrorAction SilentlyContinue)) {
                    [void]$rows.Add((_windo_scan_one_file $f $maxBytes $Hash))
                }
            } elseif ($item -is [System.IO.FileInfo]) {
                [void]$rows.Add((_windo_scan_one_file $item $maxBytes $Hash))
            }
        }
        $findingFiles = @($rows | Where-Object { [int]$_.findingCount -gt 0 })
        [pscustomobject]@{
            scannedAt = (Get-Date -Format "o")
            recurse = $Recurse
            maxTextScanMb = $MaxMb
            hash = $Hash
            fileCount = $rows.Count
            findingFileCount = $findingFiles.Count
            errorCount = $errors.Count
            files = @($rows)
            errors = @($errors)
            exitCode = $(if ($errors.Count -gt 0) { 2 } elseif ($findingFiles.Count -gt 0) { 3 } else { 0 })
        }
    }

    function _windo_net_scan_is_ipv4([string]$Address) {
        $ip = $null
        if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
        if (-not [System.Net.IPAddress]::TryParse([string]$Address, [ref]$ip)) { return $false }
        return $ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
    }

    function _windo_net_scan_expand_subnet([string]$Cidr, [int]$HostLimit) {
        $trimmed = [string]$Cidr.Trim()
        if (-not $trimmed -match '^(?<network>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(?<prefix>\d{1,2})$') {
            throw "Invalid CIDR format. Use A.B.C.D/Prefix."
        }
        $prefix = [int]$Matches.prefix
        if ($prefix -lt 8 -or $prefix -gt 30) { throw "Prefix $prefix is unsupported for local scans; use /8..30." }
        $network = $Matches.network
        $addr = $null
        if (-not [System.Net.IPAddress]::TryParse($network, [ref]$addr)) { throw "Invalid CIDR network: $network" }
        $bytes = $addr.GetAddressBytes()
        [Array]::Reverse($bytes)
        $networkInt = [BitConverter]::ToUInt32($bytes, 0)
        $hostBits = 32 - $prefix
        $hostCount = [Math]::Pow(2, $hostBits) - 2
        if ($hostCount -lt 1) { throw "CIDR prefix is too narrow for host enumeration." }
        if ($hostCount -gt $HostLimit) { throw "Subnet scan would produce $hostCount hosts; exceeds host limit $HostLimit. Use --host-limit or a narrower subnet." }
        $start = $networkInt + 1
        $end = $networkInt + [uint32]$hostCount
        $results = [System.Collections.ArrayList]@()
        for ($i = $start; $i -le $end; $i++) {
            $ipBytes = [BitConverter]::GetBytes([uint32]$i)
            [Array]::Reverse($ipBytes)
            [void]$results.Add(([System.Net.IPAddress]::new($ipBytes)).ToString())
        }
        return @($results)
    }

    function _windo_net_scan_parse_ports([string]$PortsRaw) {
        if ([string]::IsNullOrWhiteSpace($PortsRaw)) { return @() }
        $parts = $PortsRaw -split '[,;]\s*' | Where-Object { $_ -ne "" }
        $out = [System.Collections.ArrayList]@()
        foreach ($p in $parts) {
            $portCandidate = [string]$p.Trim()
            if ([string]::IsNullOrWhiteSpace($portCandidate)) { continue }
            $n = 0
            if (-not [int]::TryParse($portCandidate, [ref]$n)) { throw "Invalid port '$portCandidate'." }
            if ($n -lt 1 -or $n -gt 65535) { throw "Port must be 1..65535: $n." }
            if (@($out) -notcontains [int]$n) { [void]$out.Add([int]$n) }
        }
        [void]$out.Sort()
        return @($out)
    }

    function _windo_net_scan_probe_icmp([string]$Target, [int]$TimeoutSeconds) {
        try {
            $reply = Test-Connection -ComputerName $Target -Count 1 -TimeoutSeconds $TimeoutSeconds -ErrorAction Stop
            if ($null -eq $reply) {
                return @{ reachable = $false; rttMs = $null; error = $null }
            }
            $first = @($reply)[0]
            $rawMs = $null
            if ($first.PSObject.Properties.Name -contains 'ResponseTime') { $rawMs = $first.ResponseTime }
            if ($null -ne $rawMs -and $rawMs -ge 0) {
                return @{ reachable = $true; rttMs = [int][math]::Round([double]$rawMs); error = $null }
            }
            return @{ reachable = $true; rttMs = $null; error = $null }
        } catch {
            return @{ reachable = $false; rttMs = $null; error = $_.Exception.Message }
        }
    }

    function _windo_net_scan_probe_tcp([string]$Host, [int]$Port, [int]$TimeoutSeconds) {
        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $task = $client.ConnectAsync($Host, $Port)
            if (-not $task.Wait($TimeoutSeconds * 1000)) { return @{ open = $false; error = $null } }
            if ($task.Status -ne 'RanToCompletion' -or $task.IsFaulted) {
                return @{ open = $false; error = "TCP connect not completed." }
            }
            return @{ open = $true; error = $null }
        } catch {
            return @{ open = $false; error = $_.Exception.Message }
        } finally {
            if ($client) { $client.Close() }
        }
    }

    function _windo_net_scan_has_nmap {
        return [bool](Get-Command nmap -ErrorAction SilentlyContinue)
    }

    function _windo_net_scan_nmap_reachable([string[]]$Targets, [int]$TimeoutSeconds) {
        if (-not (_windo_net_scan_has_nmap)) { return $null }
        $args = @(
            "-sn", "-n", "--max-retries", "1", "--scan-delay", "0",
            "--host-timeout", "$TimeoutSeconds" + "s",
            "--min-rate", "500", "-T4", "-oG", "-"
        )
        $args += @($Targets)
        $reachable = @{}
        try {
            $raw = & nmap @args 2>$null
            if (-not $raw) { return $null }
            foreach ($line in @($raw)) {
                $text = [string]$line
                if ($text -match 'Host:\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s+Status:\s+Up') {
                    $reachable[$Matches[1]] = $true
                    continue
                }
                if ($text -match 'Host:\s+([^\s]+)\s+\(([0-9]{1,3}(?:\.[0-9]{1,3}){3})\)\s+Status:\s+Up') {
                    $reachable[$Matches[2]] = $true
                }
            }
            if ($reachable.Count -gt 0) { return $reachable } else { return @{} }
        } catch {
            return $null
        }
    }

    function _windo_net_scan_status() {
        $adapters = [System.Collections.ArrayList]@()
        $errors = [System.Collections.ArrayList]@()
        try {
            $items = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
            foreach ($adapter in @($items)) {
                $cfg = $null
                try { $cfg = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue } catch { $cfg = $null }
                $ipv4 = @()
                $ipv6 = @()
                $gateways = @()
                $dnsServers = @()
                if ($cfg) {
                    if ($cfg.IPv4Address) { $ipv4 = @($cfg.IPv4Address | ForEach-Object { [string]$_.IPAddress } | Where-Object { $_ }) }
                    if ($cfg.IPv6Address) { $ipv6 = @($cfg.IPv6Address | ForEach-Object { [string]$_.IPAddress } | Where-Object { $_ }) }
                    if ($cfg.IPv4DefaultGateway) { $gateways = @($cfg.IPv4DefaultGateway | ForEach-Object { [string]$_.NextHop } | Where-Object { $_ }) }
                    if ($cfg.DNSServer) {
                        try {
                            $dnsServers = @($cfg.DNSServer.ServerAddresses | ForEach-Object { [string]$_ } | Where-Object { $_ })
                        } catch { $dnsServers = @() }
                    }
                }
                [void]$adapters.Add([ordered]@{
                    alias = [string]$adapter.Name
                    ipv4 = @($ipv4)
                    ipv6 = @($ipv6)
                    gateway = $(if ($gateways.Count -gt 0) { $gateways[0] } else { $null })
                    dnsServers = @($dnsServers)
                    macAddress = $(if ($adapter.MacAddress) { [string]$adapter.MacAddress } else { $null })
                    linkSpeed = $(if ($adapter.LinkSpeed) { [string]$adapter.LinkSpeed } else { $null })
                })
            }
            return [pscustomobject]@{ adapters = @($adapters); errors = @($errors); exitCode = $(if ($errors.Count -gt 0) { 3 } else { 0 }) }
        } catch {
            return [pscustomobject]@{ adapters = @(); errors = @([ordered]@{ path = "Get-NetAdapter"; error = $_.Exception.Message }); exitCode = 3 }
        }
    }

    function _windo_net_scan_arp_from_cli([string]$Interface, [bool]$IncludeStale) {
        $rows = [System.Collections.ArrayList]@()
        $lines = @()
        try {
            $raw = & arp.exe -a 2>$null
            if ($raw) { $lines = @($raw) } else { return @{ neighbors = @(); exitCode = 0; source = "arp.exe -a"; errors = @() } }
        } catch {
            return @{ neighbors = @(); exitCode = 3; source = "arp.exe -a"; errors = @(@{ path = "arp.exe -a"; error = $_.Exception.Message }) }
        }
        $currentInterface = $null
        $targetInterface = if ([string]::IsNullOrWhiteSpace($Interface)) { $null } else { [string]$Interface.ToLowerInvariant() }
        $seen = @{}
        foreach ($line in @($lines)) {
            $text = [string]$line
            if ($text -match '^\s*Interface:\s+\S+\s+---\s+(?<interface>.+?)\s*$') {
                $currentInterface = [string]$Matches['interface'].Trim()
                continue
            }
            if ($text -match '^\s*Internet Address') { continue }
            if ($text -match '^(?<ip>\d{1,3}(?:\.\d{1,3}){3})\s+(?<mac>[0-9A-Fa-f-]{17}|<incomplete>)\s+(?<state>\S+)') {
                $state = [string]$Matches['state'].ToLowerInvariant()
                if (-not $IncludeStale -and $state -in @('incomplete', 'invalid', 'unreachable')) { continue }
                if ($targetInterface -and $currentInterface -and ($currentInterface.ToLowerInvariant() -notlike "*$targetInterface*")) { continue }
                $ip = [string]$Matches['ip']
                $mac = [string]$Matches['mac']
                $dedupeKey = "$ip|$mac|$currentInterface"
                if ($seen.ContainsKey($dedupeKey)) { continue }
                $seen[$dedupeKey] = $true
                [void]$rows.Add([ordered]@{
                    ip = $ip
                    mac = $mac
                    state = if ($state -eq "static") { "Permanent" } elseif ($state -eq "dynamic") { "Reachable" } else { ([string]$state).ToUpperInvariant() }
                    interfaceAlias = $currentInterface
                })
            }
        }
        return @{ neighbors = @($rows); exitCode = 0; source = "arp.exe -a"; errors = @() }
    }

    function _windo_net_scan_arp([string]$Interface, [bool]$IncludeStale) {
        try {
            $neighbors = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop
            if ($Interface) {
                $neighbors = @($neighbors | Where-Object { [string]$_.InterfaceAlias -ieq [string]$Interface })
            }
            if (-not $IncludeStale) {
                $neighbors = @($neighbors | Where-Object { $_.State -notin @('Unreachable', 'Incomplete', 'Invalid') })
            }
            $rows = [System.Collections.ArrayList]@()
            foreach ($n in @($neighbors)) {
                [void]$rows.Add([ordered]@{
                    ip = if ($null -ne $n.IPAddress) { [string]$n.IPAddress } else { $null }
                    mac = if ($null -ne $n.LinkLayerAddress) { [string]$n.LinkLayerAddress } else { $null }
                    state = if ($null -ne $n.State) { [string]$n.State } else { $null }
                    interfaceAlias = if ($null -ne $n.InterfaceAlias) { [string]$n.InterfaceAlias } else { $null }
                })
            }
            return @{ neighbors = @($rows); exitCode = 0; source = "Get-NetNeighbor"; errors = @() }
        } catch {
            return _windo_net_scan_arp_from_cli $Interface $IncludeStale
        }
    }

    function _windo_net_scan_resolve([string[]]$HostList, [array]$TagRules = @()) {
        $rows = [System.Collections.ArrayList]@()
        $errors = [System.Collections.ArrayList]@()
        $resolvedCount = 0
        foreach ($h in @($HostList)) {
            $trimmed = [string]$h.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            $addresses = @()
            $err = $null
            $method = $null
            try {
                $resolved = Resolve-DnsName -Name $trimmed -ErrorAction Stop | Where-Object { $_.Type -eq 'A' -or $_.Type -eq 'AAAA' } | Select-Object -ExpandProperty IPAddress
                $method = "Resolve-DnsName"
                if ($resolved) { $addresses = @($resolved | ForEach-Object { [string]$_ } | Sort-Object -Unique) }
            } catch {
                try {
                    $fallback = [System.Net.Dns]::GetHostAddresses($trimmed)
                    $method = "System.Net.Dns::GetHostAddresses"
                    if ($fallback) { $addresses = @($fallback | ForEach-Object { $_.ToString() } | Sort-Object -Unique) }
                } catch {
                    $err = $_.Exception.Message
                }
            }
            if ($addresses.Count -eq 0) {
                if (-not $err) { $err = "No address found." }
                [void]$errors.Add([ordered]@{ host = $trimmed; error = $err })
            } else {
                $resolvedCount++
            }
            $hostIdRows = [System.Collections.ArrayList]@()
            $identityTags = [System.Collections.ArrayList]@()
            foreach ($ip in @($addresses)) {
                $rev = @()
                try { $rev = Resolve-DnsName -Name ([string]$ip) -Type PTR -ErrorAction Stop | Where-Object { $_.NameHost } | Select-Object -ExpandProperty NameHost -Unique } catch { }
                if (-not $rev -or $rev.Count -eq 0) {
                    try {
                        $host = [System.Net.Dns]::GetHostEntry([string]$ip)
                        if ($host.HostName) { $rev = @([string]$host.HostName) }
                    } catch { }
                }
                $hostIdRows.Add(@($rev))
                if ($TagRules -and $TagRules.Count -gt 0) {
                    $matched = _windo_net_scan_apply_host_tags -Ip $ip -HostNames @($rev) -Type "resolved" -TagRules $TagRules
                    if ($matched.Count -gt 0) {
                        [void]$identityTags.Add([ordered]@{
                            ip = [string]$ip
                            names = @($rev)
                            tags = @($matched)
                        })
                    }
                }
            }
            [void]$rows.Add([ordered]@{
                host = $trimmed
                addresses = @($addresses)
                addressCount = $addresses.Count
                reverseHostnames = [array]$hostIdRows
                method = $method
                identityTags = @($identityTags)
                error = $err
            })
        }
        return [pscustomobject]@{ hosts = @($rows); resolvedCount = [int]$resolvedCount; errorCount = $errors.Count; exitCode = $(if ($errors.Count -gt 0) { 3 } else { 0 }); errors = @($errors); methods = @("Resolve-DnsName", "System.Net.Dns::GetHostAddresses") }
    }

    function _windo_net_scan_resolve_reverse_dns([string]$IpAddress) {
        $names = [System.Collections.ArrayList]@()
        try {
            $ptr = Resolve-DnsName -Name $IpAddress -Type PTR -ErrorAction Stop | Where-Object { $_.NameHost } | Select-Object -ExpandProperty NameHost -Unique
            foreach ($n in @($ptr)) { [void]$names.Add([string]$n) }
        } catch {
        }
        if ($names.Count -gt 0) { return @($names) }
        try {
            $host = [System.Net.Dns]::GetHostEntry($IpAddress)
            if ($host.HostName) { [void]$names.Add([string]$host.HostName) }
        } catch {
        }
        return @($names)
    }

    function _windo_net_scan_load_host_tags([string]$TagFilePath) {
        $path = $TagFilePath
        if (-not $path -or [string]::IsNullOrWhiteSpace($path)) {
            $path = [string]$env:WINDO_NET_SCAN_HOST_TAGS
        }
        if (-not $path -or [string]::IsNullOrWhiteSpace($path)) { return @() }
        if (-not (Test-Path -LiteralPath $path)) { throw "Host tag file not found: $path" }
        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            $payload = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Failed to parse host tag JSON: $($_.Exception.Message)"
        }
        if (-not ($payload -is [System.Collections.IEnumerable]) -or ($payload -is [string])) {
            throw "Host tag JSON must be an array of objects."
        }
        $rows = [System.Collections.ArrayList]@()
        foreach ($entry in @($payload)) {
            if ($null -eq $entry) { continue }
            if ($entry -is [string]) {
                [void]$rows.Add([ordered]@{ label = [string]$entry; pattern = [string]$entry; field = 'ip'; type = ''; note = ''; meta = $null })
                continue
            }
            $label = if ($entry.PSObject.Properties.Name -contains 'label') { [string]$entry.label } else { '' }
            $pattern = if ($entry.PSObject.Properties.Name -contains 'pattern') { [string]$entry.pattern } else { '' }
            if ([string]::IsNullOrWhiteSpace($label) -and -not [string]::IsNullOrWhiteSpace($pattern)) { $label = $pattern }
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            [void]$rows.Add([ordered]@{
                label = [string]$label
                pattern = [string]$pattern
                field = if ($entry.PSObject.Properties.Name -contains 'field') { [string]$entry.field } else { 'ip' }
                type = if ($entry.PSObject.Properties.Name -contains 'type') { [string]$entry.type } else { '' }
                note = if ($entry.PSObject.Properties.Name -contains 'note') { [string]$entry.note } else { '' }
                meta = if ($entry.PSObject.Properties.Name -contains 'meta') { $entry.meta } else { $null }
            })
        }
        return @($rows)
    }

    function _windo_net_scan_apply_host_tags([string]$Ip, [string[]]$HostNames, [string]$Mac, [string]$InterfaceAlias, [string]$Type, [array]$TagRules) {
        $identity = [System.Collections.ArrayList]@()
        $ipLower = if ([string]::IsNullOrWhiteSpace($Ip)) { '' } else { [string]$Ip.ToLowerInvariant() }
        $macLower = if ([string]::IsNullOrWhiteSpace($Mac)) { '' } else { [string]$Mac.ToLowerInvariant() }
        $ifaceLower = if ([string]::IsNullOrWhiteSpace($InterfaceAlias)) { '' } else { [string]$InterfaceAlias.ToLowerInvariant() }
        foreach ($t in @($TagRules)) {
            if (-not $t) { continue }
            $field = if ($t.field) { [string]$t.field.ToLowerInvariant() } else { 'ip' }
            $pattern = if ($t.pattern) { [string]$t.pattern.ToLowerInvariant() } else { '' }
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            $matched = $false
            switch ($field) {
                'ip' {
                    if ($ipLower -like $pattern) { $matched = $true }
                }
                'hostname' {
                    foreach ($h in @($HostNames)) { if (([string]$h.ToLowerInvariant()) -like $pattern) { $matched = $true; break } }
                }
                'mac' {
                    if ($macLower -like $pattern) { $matched = $true }
                }
                'interface' {
                    if ($ifaceLower -like $pattern) { $matched = $true }
                }
                'type' {
                    if (($Type.ToLowerInvariant()) -like $pattern) { $matched = $true }
                }
                default { }
            }
            if ($matched) {
                [void]$identity.Add([ordered]@{
                    field = [string]$field
                    pattern = [string]$pattern
                    label = if ($t.label) { [string]$t.label } else { [string]$pattern }
                    type = if ($t.type) { [string]$t.type } else { $null }
                    note = if ($t.note) { [string]$t.note } else { $null }
                    meta = $t.meta
                })
            }
        }
        return @($identity)
    }

    function _windo_net_scan_ping_report([object]$Payload, [bool]$JsonOutput) {
        if ($null -eq $Payload) {
            if ($JsonOutput) {
                _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "internal ping payload missing"; exitCode = 2 }
            } else {
                Write-Host "[windo] net-scan ping: internal payload missing." -ForegroundColor Red
            }
            return
        }
        if ($JsonOutput) {
            _emit_json "net-scan" $Payload
            return
        }
        Write-Host "[windo] net-scan ping" -ForegroundColor Cyan
        if ($Payload.discovery) {
            $discoveryMethods = @()
            if ($Payload.discovery.methods) { $discoveryMethods = @($Payload.discovery.methods) }
            if ($discoveryMethods.Count -gt 0) { Write-Host ("  Discovery methods: {0}" -f ($discoveryMethods -join ", ")) -ForegroundColor DarkGray }
            if ($Payload.discovery.note) { Write-Host ("  Note: {0}" -f $Payload.discovery.note) -ForegroundColor DarkGray }
        }
        if ($Payload.cidr) {
            Write-Host ("  CIDR: {0}" -f $Payload.cidr) -ForegroundColor DarkGray
        }
        if ($Payload.targets) {
            Write-Host ("  Targets: {0}" -f ($Payload.targets -join ", ")) -ForegroundColor DarkGray
        }
        if ($Payload.ports -and $Payload.ports.Count -gt 0) {
            Write-Host ("  Ports: {0}" -f ($Payload.ports -join ", ")) -ForegroundColor DarkGray
        }
        Write-Host ("  Probed: {0}, reachable: {1}, unreachable: {2}, errors: {3}" -f $Payload.probedCount, $Payload.reachableCount, $Payload.unreachableCount, $Payload.errorCount) -ForegroundColor DarkGray
        foreach ($h in @($Payload.hosts)) {
            Write-Host ("  {0,-16} reachable={1,-5} rtt={2}" -f $h.ip, $h.reachable, $(if ($null -eq $h.rttMs) { "n/a" } else { [string]$h.rttMs })) -ForegroundColor $(if ($h.reachable) { "Green" } else { "Yellow" })
            if ($h.hostnames -and $h.hostnames.Count -gt 0) {
                Write-Host ("    hostnames: {0}" -f ($h.hostnames -join ", ")) -ForegroundColor DarkGray
            }
            if ($h.identityTags -and $h.identityTags.Count -gt 0) {
                Write-Host ("    tags: {0}" -f ($h.identityTags | ForEach-Object { [string]$_.label } -join ", ")) -ForegroundColor DarkGray
            }
            if ($h.ports.Count -gt 0) {
                foreach ($pk in $h.ports.Keys) { Write-Host ("    {0,-5}: {1}" -f $pk, $h.ports[$pk]) -ForegroundColor DarkGray }
            }
        }
        if ($Payload.errors -and $Payload.errors.Count -gt 0) {
            Write-Host "  Errors:" -ForegroundColor Red
            foreach ($e in @($Payload.errors)) { Write-Host ("    {0}: {1}" -f $e.ip, $e.error) -ForegroundColor Red }
        }
    }

    function _windo_tool_state([string]$Name) {
        $c = Get-Command $Name -ErrorAction SilentlyContinue
        [pscustomobject]@{ name = $Name; available = [bool]$c; path = $(if ($c) { [string]$c.Source } else { $null }) }
    }

    function _windo_service_state([string]$ServiceName) {
        try {
            $svc = Get-Service -Name $ServiceName -ErrorAction Stop
            return [pscustomobject]@{
                name = [string]$ServiceName
                exists = $true
                status = [string]$svc.Status
                startType = [string]$svc.StartType
                canStop = [bool]$svc.CanStop
                canPause = [bool]$svc.CanPauseAndContinue
                canShutdown = [bool]$svc.CanShutdown
                exitCode = 0
            }
        } catch {
            return [pscustomobject]@{
                name = [string]$ServiceName
                exists = $false
                status = "Missing"
                startType = $null
                canStop = $false
                canPause = $false
                canShutdown = $false
                error = $_.Exception.Message
                exitCode = 3
            }
        }
    }

    function _windo_parse_ports_raw([string]$RawPorts) {
        if ([string]::IsNullOrWhiteSpace($RawPorts)) { return @() }
        $parts = $RawPorts -split '[,;]\s*' | Where-Object { $_ -and $_.Trim() -ne "" }
        $ports = [System.Collections.ArrayList]@()
        foreach ($raw in @($parts)) {
            $value = [string]$raw.Trim()
            if ($value -eq "any") { return @(-1) }
            if ($value -match '^\s*(\d+)\s*-\s*(\d+)\s*$') {
                $start = [int]$Matches[1]
                $end = [int]$Matches[2]
                if ($start -gt $end) { throw "Invalid port range '$value'." }
                if ($start -lt 1 -or $start -gt 65535 -or $end -lt 1 -or $end -gt 65535) { throw "Port range '$value' out of range (1..65535)." }
                for ($p = $start; $p -le $end; $p++) {
                    if (@($ports) -notcontains $p) { [void]$ports.Add($p) }
                }
                continue
            }
            $port = 0
            if (-not [int]::TryParse($value, [ref]$port)) { throw "Invalid port '$value'." }
            if ($port -lt 1 -or $port -gt 65535) { throw "Port must be 1..65535: $port." }
            if (@($ports) -notcontains $port) { [void]$ports.Add($port) }
        }
        [void]$ports.Sort()
        return @($ports)
    }

    function _windo_firewall_rules_for_patterns([string[]]$Patterns, [int[]]$Ports = @()) {
        $rules = [System.Collections.ArrayList]@()
        try {
            $items = Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled Any -ErrorAction Stop
            foreach ($rule in @($items)) {
                $display = [string]$rule.DisplayName
                $name = [string]$rule.Name
                $group = if ($rule.Group) { [string]$rule.Group } else { "" }
                $line = "$display $name $group"
                $match = $false
                foreach ($pattern in @($Patterns)) {
                    if ($line -match [regex]::Escape([string]$pattern)) { $match = $true; break }
                }
                if (-not $match) { continue }

                $portValues = [System.Collections.ArrayList]@()
                try {
                    $filter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop
                    if ($filter.LocalPort) {
                        $rawPortList = @([string]$filter.LocalPort) -split ','
                        foreach ($rp in $rawPortList) {
                            $rp = $rp.Trim()
                            if ($rp -eq "Any") {
                                [void]$portValues.Add("Any")
                                continue
                            }
                            if ($rp -match '^(\d+)-(\d+)$') {
                                for ($i = [int]$Matches[1]; $i -le [int]$Matches[2]; $i++) { [void]$portValues.Add([int]$i) }
                                continue
                            }
                            $n = 0
                            if ([int]::TryParse($rp, [ref]$n)) { [void]$portValues.Add($n) }
                        }
                    }
                } catch { }
                if ($Ports.Count -gt 0 -and $Ports -notcontains -1) {
                    $intersects = $false
                    foreach ($p in $Ports) {
                        if ($p -eq -1) { $intersects = $true; break }
                        if ($portValues.Count -eq 0) { continue }
                        if ($portValues.Contains("Any")) { $intersects = $true; break }
                        if ($portValues.Contains($p)) { $intersects = $true; break }
                    }
                    if (-not $intersects) { continue }
                }

                [void]$rules.Add([ordered]@{
                    name = $name
                    displayName = $display
                    group = $group
                    description = if ($rule.Description) { [string]$rule.Description } else { $null }
                    enabled = [bool]$rule.Enabled
                    profile = if ($rule.Profile) { [string]$rule.Profile } else { $null }
                    protocol = $filter.Protocol
                    localPort = if ($portValues.Count -eq 0) { $null } else { @($portValues) }
                    action = [string]$rule.Action
                    edgeTraversal = [bool]$rule.EdgeTraversalPolicy
                })
            }
            return @($rules)
        } catch {
            return @()
        }
    }

    function _windo_firewall_apply_rules([string[]]$RuleNames, [bool]$Enable) {
        $updated = [System.Collections.ArrayList]@()
        foreach ($name in @($RuleNames)) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            try {
                if ($Enable) {
                    Enable-NetFirewallRule -Name $name -ErrorAction Stop
                } else {
                    Disable-NetFirewallRule -Name $name -ErrorAction Stop
                }
                $current = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
                [void]$updated.Add([ordered]@{
                    name = [string]$name
                    action = $(if ($Enable) { "enabled" } else { "disabled" })
                    status = if ($current) { [bool]$current.Enabled } else { $Enable }
                    success = $true
                })
            } catch {
                [void]$updated.Add([ordered]@{
                    name = [string]$name
                    action = $(if ($Enable) { "enabled" } else { "disabled" })
                    success = $false
                    error = $_.Exception.Message
                })
            }
        }
        return @($updated)
    }

    function _windo_remote_rdp_config_snapshot {
        $tsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
        $tcpPath = Join-Path $tsPath "WinStations\RDP-Tcp"
        $deny = $null
        $nla = $null
        $securityLayer = $null
        try { $deny = Get-ItemProperty -Path $tsPath -Name fDenyTSConnections -ErrorAction Stop | Select-Object -ExpandProperty fDenyTSConnections } catch { }
        try { $nla = Get-ItemProperty -Path $tsPath -Name UserAuthentication -ErrorAction Stop | Select-Object -ExpandProperty UserAuthentication } catch { }
        try { $securityLayer = Get-ItemProperty -Path $tcpPath -Name SecurityLayer -ErrorAction Stop | Select-Object -ExpandProperty SecurityLayer } catch { }
        $svc = _windo_service_state "TermService"
        return [ordered]@{
            registry = [ordered]@{
                terminalServerPath = $tsPath
                terminalServerFq = if ($null -ne $deny) { [int]$deny } else { $null }
                userAuthentication = if ($null -ne $nla) { [int]$nla } else { $null }
                securityLayer = if ($null -ne $securityLayer) { [int]$securityLayer } else { $null }
            }
            service = $svc
        }
    }

    function _windo_remote_set_rdp_config {
        param(
            [Nullable[bool]]$Enable,
            [Nullable[bool]]$Nla,
            [Nullable[int]]$SecurityLayer,
            [switch]$RestartService
        )

        $tsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
        $tcpPath = Join-Path $tsPath "WinStations\RDP-Tcp"
        $changes = [System.Collections.ArrayList]@()

        try {
            if ($Enable -ne $null) {
                $target = if ($Enable) { 0 } else { 1 }
                Set-ItemProperty -Path $tsPath -Name fDenyTSConnections -Value $target -Type DWord
                [void]$changes.Add([ordered]@{ key = "fDenyTSConnections"; action = "set"; value = $target })
                if ($target -eq 0) {
                    try { Set-ItemProperty -Path $tsPath -Name "fDenyTSConnections" -Value 0 -Type DWord } catch { }
                }
            }
            if ($Nla -ne $null) {
                $target = if ($Nla) { 1 } else { 0 }
                Set-ItemProperty -Path $tsPath -Name UserAuthentication -Value $target -Type DWord
                [void]$changes.Add([ordered]@{ key = "UserAuthentication"; action = "set"; value = $target })
            }
            if ($SecurityLayer -ne $null) {
                if ($SecurityLayer -notin 0..2) { throw "SecurityLayer must be 0, 1, or 2." }
                Set-ItemProperty -Path $tcpPath -Name SecurityLayer -Value [int]$SecurityLayer -Type DWord
                [void]$changes.Add([ordered]@{ key = "SecurityLayer"; action = "set"; value = [int]$SecurityLayer })
            }
            if ($RestartService -and (Get-Service -Name TermService -ErrorAction SilentlyContinue)) {
                try {
                    Restart-Service -Name TermService -ErrorAction Stop
                    $restartAction = "restarted"
                } catch {
                    $restartAction = "restart-failed"
                }
            } else {
                $restartAction = "not-requested"
            }
            $snapshot = _windo_remote_rdp_config_snapshot
            return @{
                success = $true
                restart = $restartAction
                changes = @($changes)
                snapshot = $snapshot
            }
        } catch {
            return @{
                success = $false
                restart = "failed"
                changes = @($changes)
                error = $_.Exception.Message
            }
        }
    }

    function _windo_remote_vnc_services {
        $servicePatterns = @("vnc", "uvnc", "winvnc", "tvnserver", "tightvnc", "ultravnc", "realvnc", "x11", "vncserver")
        $services = [System.Collections.ArrayList]@()
        try {
            $all = Get-Service -ErrorAction SilentlyContinue
            foreach ($svc in @($all)) {
                $source = ([string]$svc.Name + " " + [string]$svc.DisplayName).ToLowerInvariant()
                $matched = $false
                foreach ($pattern in @($servicePatterns)) {
                    if ($source -like "*$pattern*") { $matched = $true; break }
                }
                if (-not $matched) { continue }
                [void]$services.Add([ordered]@{
                    name = [string]$svc.Name
                    displayName = if ($svc.DisplayName) { [string]$svc.DisplayName } else { [string]$svc.Name }
                    status = [string]$svc.Status
                    startType = [string]$svc.StartType
                    canStop = [bool]$svc.CanStop
                })
            }
        } catch { }
        return @($services)
    }

    function _windo_remote_credential_preview([string]$VaultName) {
        $empty = @{
            exists = $false
            name = [string]$VaultName
            username = $null
            passwordPreview = $null
        }
        if ([string]::IsNullOrWhiteSpace($VaultName)) { return $empty }
        $map = _windo_vault_read_map
        if (-not $map.ContainsKey([string]$VaultName)) { return $empty }

        $entry = $map[[string]$VaultName]
        $plain = $null
        try {
            if ($entry -is [string]) {
                $plain = _dpapi_unprotect $entry
            } elseif ($entry -is [pscustomobject] -or ($entry -is [hashtable])) {
                $protected = $null
                if ($entry -is [hashtable]) {
                    if ($entry.ContainsKey("protected")) { $protected = $entry["protected"] }
                    elseif ($entry.ContainsKey("encrypted")) { $protected = $entry["encrypted"] }
                    elseif ($entry.ContainsKey("value")) { $protected = $entry["value"] }
                } else {
                    if ($entry.PSObject.Properties.Name -contains "protected") { $protected = $entry.protected }
                    elseif ($entry.PSObject.Properties.Name -contains "encrypted") { $protected = $entry.encrypted }
                    elseif ($entry.PSObject.Properties.Name -contains "value") { $protected = $entry.value }
                    elseif ($entry.PSObject.Properties.Name -contains "user" -and $entry.PSObject.Properties.Name -contains "password") {
                        $plain = [string]$entry.user + ":" + [string]$entry.password
                    }
                }
                if ($null -ne $protected) {
                    $plain = _dpapi_unprotect [string]$protected
                }
            } else {
                return @{
                    exists = $false
                    name = [string]$VaultName
                    error = "Unsupported vault item format."
                }
            }
        } catch {
            return @{
                exists = $false
                name = [string]$VaultName
                error = $_.Exception.Message
            }
        }

        $username = $null
        if ($plain -match '^(?<user>[^:]+):(?<pwd>.*)$') {
            $username = $Matches.user
            $pw = $Matches.pwd
        } elseif ($plain) {
            $username = $plain
            $pw = ""
        } else {
            $pw = ""
        }
        if ([string]::IsNullOrEmpty($pw)) { $preview = $null } else { $preview = $pw.Substring(0, [Math]::Min(2, $pw.Length)) + "****" }
        return @{
            exists = $true
            name = [string]$VaultName
            username = $username
            passwordPreview = $preview
        }
    }

    function _windo_get_recipe_command_line([string]$RecipeId) {
        $r = _windo_builtin_recipes
        if ([string]::IsNullOrWhiteSpace($RecipeId)) { return $null }
        $key = $RecipeId.Trim()
        if (-not $r.ContainsKey($key)) {
            foreach ($k in @($r.Keys)) { if ($k -ieq $key) { $key = $k; break } }
        }
        if (-not $r.ContainsKey($key)) { return $null }
        return [string]$r[$key].command
    }

    function _windo_get_recipe_preview([string]$RecipeId) {
        $r = _windo_builtin_recipes
        if ([string]::IsNullOrWhiteSpace($RecipeId)) { return $null }
        $key = $RecipeId.Trim()
        if (-not $r.ContainsKey($key)) {
            foreach ($k in @($r.Keys)) { if ($k -ieq $key) { $key = $k; break } }
        }
        if (-not $r.ContainsKey($key)) { return $null }
        [pscustomobject]@{
            name = $key
            description = [string]$r[$key].description
            command = [string]$r[$key].command
            elevatedCommand = [string]$r[$key].command
            runCommand = "windo recipes run $key"
            previewCommand = "windo recipes preview $key"
            dryRunCommand = "windo recipes run $key --dry-run"
            risk = "elevated read-only recipe"
            dryRun = $true
        }
    }

    function _windo_native_surface_state {
        $isWindowsDesktop = $false
        try { $isWindowsDesktop = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) } catch {}

        $formsAvailable = $false
        if ($isWindowsDesktop) {
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                $formsAvailable = $true
            } catch {
                $formsAvailable = $false
            }
        }

        $trayIconPath = _windo_resolve_tray_icon "ready"

        $brandLogoPath = $null
        foreach ($candidateLogoPath in @(
            (Join-Path $HOME "Documents\GitHub\windo\brand\Enterprise\assets\logo\windo-logo-full-dark-512.png"),
            (Join-Path $HOME "Documents\windo\brand\Enterprise\assets\logo\windo-logo-full-dark-512.png"),
            (Join-Path $HOME "Documents\windo\brand\assets\banners\banner-blue-left.png")
        )) {
            if (Test-Path -LiteralPath $candidateLogoPath) { $brandLogoPath = $candidateLogoPath; break }
        }

        $pwshPath = $null
        $powershellPath = $null
        try { $pwshPath = [string](Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source) } catch {}
        try { $powershellPath = [string](Get-Command powershell.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source) } catch {}
        $trayScriptPath = Join-Path $SecureDir "windo_launchpad_tray.ps1"
        $panelScriptPath = Join-Path $SecureDir "windo_surface_panel.ps1"
        $studioScriptPath = Join-Path $SecureDir "windo_power_studio.ps1"

        [pscustomobject]@{
            status = $(if ($isWindowsDesktop -and $formsAvailable) { "ready" } elseif ($isWindowsDesktop) { "attention" } else { "unavailable" })
            windowsDesktop = [bool]$isWindowsDesktop
            windowsFormsAvailable = [bool]$formsAvailable
            traySupported = [bool]($isWindowsDesktop -and $formsAvailable)
            trayScriptPath = $trayScriptPath
            trayScriptExists = [bool](Test-Path -LiteralPath $trayScriptPath)
            panelScriptPath = $panelScriptPath
            panelScriptExists = [bool](Test-Path -LiteralPath $panelScriptPath)
            studioScriptPath = $studioScriptPath
            studioScriptExists = [bool](Test-Path -LiteralPath $studioScriptPath)
            trayIconPath = $trayIconPath
            brandLogoPath = $brandLogoPath
            pwshPath = $pwshPath
            powershellPath = $powershellPath
            commands = [ordered]@{
                tray = "windo launchpad --tray"
                panel = "windo surface panel"
                studio = "windo center studio"
                workbench = "windo mesh workbench --html"
                launchpad = "windo launchpad --html"
            }
        }
    }

    function _windo_mesh_inventory {
        $enabled = @(_windo_get_enabled_module_ids)
        $modules = @(_windo_modules_discover_rows $enabled)
        $recipeMap = _windo_builtin_recipes
        $recipes = @($recipeMap.GetEnumerator() | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                id = [string]$_.Name
                description = [string]$_.Value.description
                previewCommand = "windo recipes preview $($_.Name)"
                runCommand = "windo recipes run $($_.Name)"
            }
        })
        $extrasRoot = _windo_extras_install_root
        $extrasInstalled = @()
        if (Test-Path -LiteralPath $extrasRoot) {
            $extrasInstalled = @(Get-ChildItem -LiteralPath $extrasRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
                [pscustomobject]@{ id = $_.Name; path = $_.FullName }
            })
        }
        $snapshotDir = Join-Path (Join-Path $HOME "Documents") "windo"
        $exportRoot = Join-Path $snapshotDir "exports"
        $latestExport = $null
        if (Test-Path -LiteralPath $exportRoot) {
            $latestExport = @(Get-ChildItem -LiteralPath $exportRoot -Filter "*.zip" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        }
        $nativeSurface = _windo_native_surface_state

        return [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            status = "preview"
            counts = [ordered]@{
                modules = $modules.Count
                enabledModules = @($modules | Where-Object { $_.enabled }).Count
                recipes = $recipes.Count
                installedExtras = $extrasInstalled.Count
            }
            modules = [ordered]@{
                root = (_windo_modules_root)
                enabledIds = @($enabled)
                rows = @($modules)
            }
            recipes = @($recipes)
            extras = [ordered]@{
                indexUrl = (_windo_extras_index_url)
                installRoot = $extrasRoot
                installed = @($extrasInstalled)
            }
            launchpad = [ordered]@{
                terminalCommand = "windo launchpad"
                htmlCommand = "windo launchpad --html"
                trayCommand = "windo launchpad --tray"
                traySupported = [bool]$nativeSurface.traySupported
                trayIconPath = $nativeSurface.trayIconPath
                brandLogoPath = $nativeSurface.brandLogoPath
            }
            nativeSurface = $nativeSurface
            export = [ordered]@{
                command = "windo export --redact"
                exportRoot = $exportRoot
                latestZip = $(if ($latestExport) { [string]$latestExport.FullName } else { $null })
            }
            htmlPath = $null
            nextCommands = @("windo modules doctor", "windo recipes", "windo extras search", "windo launchpad", "windo export --redact")
            exitCode = 0
        }
    }

    function _windo_mesh_doctor {
        $inventory = _windo_mesh_inventory
        $checks = [System.Collections.ArrayList]@()
        $recommendations = [System.Collections.ArrayList]@()
        $score = 100

        function _windo_mesh_add_check([string]$Id, [string]$Label, [bool]$Ok, [string]$Detail, [string]$FixCommand = "", [string]$Severity = "info") {
            [void]$checks.Add((_windo_new_check_row $Id $Label $Ok $Detail $FixCommand $Severity))
        }

        $mt = $false; $ut = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mt = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $ut = $true } catch {}
        _windo_mesh_add_check "tasks" "Scheduled task bridge" ($mt -and $ut) $(if ($mt -and $ut) { "main/update tasks present" } else { "main=$mt, update=$ut" }) ".\windo_install.ps1" $(if ($mt -and $ut) { "info" } elseif ($mt) { "warn" } else { "critical" })

        $ix = _integrity_status
        _windo_mesh_add_check "integrity" "Runner and updater integrity" ($ix.OverallLevel -eq "OK") "overall=$($ix.OverallLevel), runner=$($ix.RunnerLevel), updater=$($ix.UpdaterLevel)" "windo integrity" $(if ($ix.OverallLevel -eq "OK") { "info" } else { "critical" })

        $vf = _windo_verify_log_state
        _windo_mesh_add_check "audit-chain" "Audit chain" ([bool]$vf.verifyOk) $(if ($vf.verifyOk) { "chain OK, physical lines=$($vf.physicalLines)" } else { "$($vf.error), line=$($vf.failureLine)" }) "windo verify" $(if ($vf.verifyOk) { "info" } else { "warn" })

        _windo_mesh_add_check "recipes" "Recipe catalog" ($inventory.counts.recipes -gt 0) "$($inventory.counts.recipes) built-in recipes" "windo recipes" $(if ($inventory.counts.recipes -gt 0) { "info" } else { "warn" })
        _windo_mesh_add_check "modules" "Module discovery" ($null -ne $inventory.modules.root) "root=$($inventory.modules.root), discovered=$($inventory.counts.modules), enabled=$($inventory.counts.enabledModules)" "windo modules doctor" "info"
        _windo_mesh_add_check "extras" "Extras index" (-not [string]::IsNullOrWhiteSpace([string]$inventory.extras.indexUrl)) "index=$($inventory.extras.indexUrl), installed=$($inventory.counts.installedExtras)" "windo extras search" "info"
        $brandOk = ((-not [string]::IsNullOrWhiteSpace([string]$inventory.launchpad.brandLogoPath)) -and (-not [string]::IsNullOrWhiteSpace([string]$inventory.launchpad.trayIconPath)))
        _windo_mesh_add_check "brand-assets" "Brand and tray assets" $brandOk "brand=$($inventory.launchpad.brandLogoPath); tray=$($inventory.launchpad.trayIconPath)" "windo mesh --html" $(if ($brandOk) { "info" } else { "warn" })
        _windo_mesh_add_check "tray-support" "Native tray support" ([bool]$inventory.launchpad.traySupported) "traySupported=$($inventory.launchpad.traySupported)" "windo launchpad --tray" $(if ($inventory.launchpad.traySupported) { "info" } else { "warn" })
        _windo_mesh_add_check "export" "Support export path" (-not [string]::IsNullOrWhiteSpace([string]$inventory.export.exportRoot)) "root=$($inventory.export.exportRoot), latest=$($inventory.export.latestZip)" "windo export --redact" "info"

        if ($inventory.counts.modules -eq 0) { [void]$recommendations.Add("Scaffold a local workflow module when ready: windo dev init-module my-mod") }
        if ($inventory.counts.installedExtras -eq 0) { [void]$recommendations.Add("Review optional workflow packs: windo extras search") }
        if ([string]::IsNullOrWhiteSpace([string]$inventory.export.latestZip)) { [void]$recommendations.Add("Create a support bundle when you need handoff evidence: windo export --redact") }
        [void]$recommendations.Add("Open the cockpit: windo mesh --html")

        foreach ($c in @($checks | Where-Object { -not $_.ok })) {
            if ($c.severity -eq "critical") { $score -= 25 }
            elseif ($c.severity -eq "warn") { $score -= 10 }
            else { $score -= 3 }
        }
        if ($score -lt 0) { $score = 0 }
        $critical = @($checks | Where-Object { -not $_.ok -and $_.severity -eq "critical" })
        $warn = @($checks | Where-Object { -not $_.ok -and $_.severity -ne "critical" })
        $level = if ($critical.Count -gt 0) { "REPAIR" } elseif ($warn.Count -gt 0 -or $score -lt 90) { "ATTENTION" } else { "READY" }
        $exit = if ($level -eq "REPAIR") { 4 } elseif ($level -eq "ATTENTION") { 3 } else { 0 }

        return [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            readinessLevel = $level
            score = [int]$score
            checks = @($checks)
            inventory = $inventory
            recommendations = @($recommendations.ToArray())
            exitCode = $exit
        }
    }

    function _windo_mesh_workbench {
        $inventory = _windo_mesh_inventory
        $doctor = _windo_mesh_doctor
        $recipeRows = @($inventory.recipes)

        function _windo_mesh_lane([string]$Id, [string]$Title, [string]$Summary, [string[]]$RecipeIds, [string[]]$Commands) {
            $cards = [System.Collections.ArrayList]@()
            foreach ($rid in @($RecipeIds)) {
                $match = @($recipeRows | Where-Object { $_.id -eq $rid } | Select-Object -First 1)
                if ($match.Count -gt 0) {
                    [void]$cards.Add([pscustomobject]@{
                        type = "recipe"
                        id = [string]$match[0].id
                        label = [string]$match[0].description
                        preview = [string]$match[0].previewCommand
                        run = [string]$match[0].runCommand
                    })
                }
            }
            foreach ($cmd in @($Commands)) {
                if (-not [string]::IsNullOrWhiteSpace($cmd)) {
                    [void]$cards.Add([pscustomobject]@{
                        type = "command"
                        id = (($cmd -replace '[^A-Za-z0-9]+','-').Trim('-').ToLowerInvariant())
                        label = $cmd
                        preview = "windo explain $cmd"
                        run = $cmd
                    })
                }
            }
            [pscustomobject]@{
                id = $Id
                title = $Title
                summary = $Summary
                cardCount = $cards.Count
                cards = @($cards)
            }
        }

        $lanes = @(
            (_windo_mesh_lane "trust" "Trust and Source" "Prove the local install before privileged work." @("whoami-all", "audit-policy", "defender-status", "cert-root-store") @("windo trust --online", "windo source", "windo integrity", "windo verify")),
            (_windo_mesh_lane "network" "Network Recon" "Inspect interfaces, routes, ports, DNS, proxy, and firewall state." @("ipconfig-all", "network-routes", "network-adapters", "network-dns-servers", "netstat-ports", "firewall-profiles", "winhttp-proxy") @("windo recipes preview network-routes")),
            (_windo_mesh_lane "identity" "Identity and Access" "Inspect local users, groups, shares, sessions, token groups, and privileges." @("local-users", "local-groups", "local-admins", "net-shares", "net-sessions", "whoami-groups", "whoami-privileges") @("windo explain whoami /all")),
            (_windo_mesh_lane "system" "System and Storage" "Inspect OS build, uptime, volumes, disks, drivers, recovery, and boot state." @("os-build", "uptime", "volumes", "disk-free", "physical-disks", "driverquery-signed", "recovery-info", "boot-config") @("windo dashboard --html")),
            (_windo_mesh_lane "services" "Services and Jobs" "Inspect services, scheduled tasks, update services, WinRM, BITS, and process/service mapping." @("services-all", "scheduled-tasks", "windows-update-services", "service-winrm-query", "service-bits-query", "processes-services") @("windo preflight")),
            (_windo_mesh_lane "platform" "WINDO Platform" "Operate the mesh layer: modules, extras, launchpad, exports, and evidence." @("tool-powershell-path", "tool-git-version", "tool-winget-version", "ollama-list") @("windo modules doctor", "windo extras search", "windo launchpad --tray", "windo export --redact"))
        )

        $platform = @(
            [pscustomobject]@{ name = "Modules"; count = [int]$inventory.counts.modules; ready = ($null -ne $inventory.modules.root); command = "windo modules doctor"; path = [string]$inventory.modules.root },
            [pscustomobject]@{ name = "Recipes"; count = [int]$inventory.counts.recipes; ready = ($inventory.counts.recipes -gt 0); command = "windo recipes"; path = $null },
            [pscustomobject]@{ name = "Extras"; count = [int]$inventory.counts.installedExtras; ready = (-not [string]::IsNullOrWhiteSpace([string]$inventory.extras.indexUrl)); command = "windo extras search"; path = [string]$inventory.extras.installRoot },
            [pscustomobject]@{ name = "Launchpad"; count = 1; ready = [bool]$inventory.launchpad.traySupported; command = "windo launchpad --tray"; path = [string]$inventory.launchpad.trayIconPath },
            [pscustomobject]@{ name = "Native Surface"; count = $(if ($inventory.nativeSurface.trayScriptExists) { 1 } else { 0 }); ready = [bool]$inventory.nativeSurface.traySupported; command = "windo launchpad --tray"; path = [string]$inventory.nativeSurface.trayScriptPath },
            [pscustomobject]@{ name = "Exports"; count = $(if ($inventory.export.latestZip) { 1 } else { 0 }); ready = (-not [string]::IsNullOrWhiteSpace([string]$inventory.export.exportRoot)); command = "windo export --redact"; path = [string]$inventory.export.exportRoot }
        )

        $flows = @(
            [pscustomobject]@{ order = 1; name = "Prove trust"; command = "windo trust --online"; why = "Confirm source, checksum, tasks, integrity, and audit chain." },
            [pscustomobject]@{ order = 2; name = "Open workbench"; command = "windo mesh workbench --html"; why = "See workflows, platform pieces, and next commands together." },
            [pscustomobject]@{ order = 3; name = "Preview before run"; command = "windo recipes preview <name>"; why = "Review exact elevated command before task handoff." },
            [pscustomobject]@{ order = 4; name = "Use launchpad"; command = "windo launchpad --tray"; why = "Keep the local command center available without a browser." },
            [pscustomobject]@{ order = 5; name = "Export evidence"; command = "windo export --redact"; why = "Create a support-ready bundle when diagnosis needs handoff." }
        )

        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            mode = "operator-mesh-workbench"
            readinessLevel = $doctor.readinessLevel
            score = [int]$doctor.score
            counts = $inventory.counts
            platform = @($platform)
            lanes = @($lanes)
            recommendedFlow = @($flows)
            nativeSurface = $inventory.nativeSurface
            doctor = $doctor
            inventory = $inventory
            htmlPath = $null
            exitCode = 0
        }
    }

    function _windo_write_mesh_workbench_html([object]$Workbench, [string]$OutputPath, [bool]$Open) {
        $sb = [System.Text.StringBuilder]::new()
        $brandImg = ""
        if (-not [string]::IsNullOrWhiteSpace([string]$Workbench.inventory.launchpad.brandLogoPath)) {
            $brandImg = "<img class='brand' alt='WINDO' src='$(_html_escape ([uri]$Workbench.inventory.launchpad.brandLogoPath).AbsoluteUri)'>"
        }
        $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO Operator Mesh Workbench</title>')
        $null = $sb.AppendLine('<style>body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#0f172a;color:#e5e7eb}.wrap{max-width:1320px;margin:0 auto;padding:28px}.hero{border-bottom:1px solid #334155;padding-bottom:18px}.brand{max-width:360px;width:100%;height:auto;margin-bottom:8px}.title{font-size:36px;font-weight:800}.sub{color:#94a3b8}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:14px;margin:18px 0}.card{background:#111827;border:1px solid #334155;border-radius:8px;padding:14px}.k{font-size:12px;text-transform:uppercase;color:#94a3b8}.v{font-size:30px;font-weight:800}.ok{color:#22c55e}.warn{color:#f59e0b}.bad{color:#ef4444}.muted{color:#94a3b8}.lane{margin-top:20px}.row{display:grid;grid-template-columns:minmax(170px,1fr) minmax(220px,2fr) auto;gap:10px;align-items:center;border-top:1px solid #1f2937;padding:10px 0}button{background:#2563eb;color:white;border:0;border-radius:6px;padding:7px 10px;cursor:pointer}code{background:#020617;border:1px solid #334155;border-radius:5px;padding:3px 5px;color:#bfdbfe}h2{margin-top:26px}</style></head><body><div class="wrap">')
        $levelClass = if ($Workbench.readinessLevel -eq "READY") { "ok" } elseif ($Workbench.readinessLevel -eq "ATTENTION") { "warn" } else { "bad" }
        $null = $sb.AppendLine(("<div class='hero'>{0}<div class='title'>WINDO Operator Mesh Workbench</div><div class='sub'>v{1} generated {2}. Local-only, read-only, no fetch, no elevation.</div></div>" -f $brandImg, (_html_escape $Workbench.windoVersion), (_html_escape (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))))
        $null = $sb.AppendLine("<div class='grid'>")
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Readiness</div><div class='v {0}'>{1}</div><div class='muted'>{2}/100</div></div>" -f $levelClass, (_html_escape $Workbench.readinessLevel), [int]$Workbench.score))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Recipes</div><div class='v'>{0}</div><div class='muted'>read-only command cards</div></div>" -f [int]$Workbench.counts.recipes))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Modules</div><div class='v'>{0}/{1}</div><div class='muted'>enabled / discovered</div></div>" -f [int]$Workbench.counts.enabledModules, [int]$Workbench.counts.modules))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Extras</div><div class='v'>{0}</div><div class='muted'>installed locally</div></div>" -f [int]$Workbench.counts.installedExtras))
        $null = $sb.AppendLine("</div><h2>Recommended flow</h2>")
        foreach ($f in @($Workbench.recommendedFlow)) {
            $safeCmd = _html_escape ([string]$f.command)
            $jsCmd = _html_escape (([string]$f.command) -replace "'", "\'")
            $null = $sb.AppendLine(("<div class='row'><div>{0}. {1}</div><div class='muted'>{2}</div><div><code>{3}</code> <button onclick=""copyCmd('{4}')"">Copy</button></div></div>" -f [int]$f.order, (_html_escape $f.name), (_html_escape $f.why), $safeCmd, $jsCmd))
        }
        $null = $sb.AppendLine("<h2>Workflow lanes</h2>")
        foreach ($lane in @($Workbench.lanes)) {
            $null = $sb.AppendLine(("<div class='lane'><h3>{0}</h3><div class='muted'>{1}</div>" -f (_html_escape $lane.title), (_html_escape $lane.summary)))
            foreach ($card in @($lane.cards)) {
                $safeRun = _html_escape ([string]$card.run)
                $jsRun = _html_escape (([string]$card.run) -replace "'", "\'")
                $null = $sb.AppendLine(("<div class='row'><div>{0}</div><div class='muted'>{1}</div><div><code>{2}</code> <button onclick=""copyCmd('{3}')"">Copy</button></div></div>" -f (_html_escape $card.id), (_html_escape $card.label), $safeRun, $jsRun))
            }
            $null = $sb.AppendLine("</div>")
        }
        $null = $sb.AppendLine("<h2>Platform pieces</h2>")
        foreach ($p in @($Workbench.platform)) {
            $pc = if ($p.ready) { "ok" } else { "warn" }
            $null = $sb.AppendLine(("<div class='row'><div class='{0}'>{1}</div><div class='muted'>{2}</div><div><code>{3}</code></div></div>" -f $pc, (_html_escape $p.name), (_html_escape ([string]$p.path)), (_html_escape $p.command)))
        }
        $null = $sb.AppendLine("<script>function copyCmd(t){ if(navigator.clipboard){navigator.clipboard.writeText(t);} else { prompt('Copy command:', t); } }</script></div></body></html>")
        $dir = Split-Path -Parent $OutputPath
        if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
        if ($Open) { Start-Process -FilePath $OutputPath | Out-Null }
        return $OutputPath
    }

    function _windo_extras_index_url {
        $raw = [string]$env:WINDO_EXTRAS_INDEX_URL
        if (-not [string]::IsNullOrWhiteSpace($raw)) { return $raw.Trim() }
        return "https://raw.githubusercontent.com/l28bit/windo/v6/extras/index.json"
    }

    function _windo_fetch_text_url([string]$Uri) {
        $prev = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            return [string](Invoke-RestMethod -Uri $Uri -TimeoutSec 40 -ErrorAction Stop)
        } finally {
            $ProgressPreference = $prev
        }
    }

    function _windo_prompt_bridge_text {
        @"
# WINDO + Oh My Posh (bridge)

Oh My Posh can read process environment variables set after each elevated WINDO run.

Recommended env (set by WINDO after successful elevation):
  WINDO_LAST_REQUEST_ID   last completed RequestId (audit correlation)
  WINDO_VERSION           WINDO CLI / profile version ($WindoVersion)

Example segment (JSON) â€” map fields to your theme's env segment or a custom script block:
{
  "type": "text",
  "style": "diamond",
  "foreground": "#569cd6",
  "background": "#1e1e1e",
  "leading_diamond": " ",
  "trailing_diamond": "",
  "template": " WINDO {{ if .Env.WINDO_VERSION }}v{{ .Env.WINDO_VERSION }}{{ end }}{{ if .Env.WINDO_LAST_REQUEST_ID }} Â· {{ .Env.WINDO_LAST_REQUEST_ID }}{{ end }} "
}

Use: windo prompt --json   (machine-readable bundle)
     windo prompt --export <path>   (write snippet to a file)
"@
    }

    function _windo_resolve_json_envelope {
        $envRaw = $env:WINDO_JSON_ENVELOPE
        $fromFile = $null
        if (Test-Path -LiteralPath $PrefsFile) {
            try {
                $p = Get-Content -Raw -Path $PrefsFile | ConvertFrom-Json
                if ($p.PSObject.Properties.Name -contains 'jsonEnvelope') { $fromFile = [string]$p.jsonEnvelope }
            } catch { }
        }
        $mode = 'auto'
        if (-not [string]::IsNullOrWhiteSpace($envRaw)) {
            $mode = $envRaw.Trim().ToLowerInvariant()
        } elseif (-not [string]::IsNullOrWhiteSpace($fromFile)) {
            $mode = $fromFile.Trim().ToLowerInvariant()
        }
        switch ($mode) {
            'classic' { return [pscustomobject]@{ schemaLabel = '2.6'; includeMeta = $false } }
            'modern' { return [pscustomobject]@{ schemaLabel = '3.0'; includeMeta = $true } }
            'auto' { return [pscustomobject]@{ schemaLabel = $SchemaVersion; includeMeta = ($SchemaVersion -eq '3.0') } }
            default { return [pscustomobject]@{ schemaLabel = $SchemaVersion; includeMeta = ($SchemaVersion -eq '3.0') } }
        }
    }

    function _windo_resolve_keybinding_policy {
        $pref = _read_windo_prefs
        $prefChord = $null
        $prefDisabled = $null
        if ($pref -and $pref.PSObject.Properties.Name -contains 'keybindingPrefixChord') { $prefChord = [string]$pref.keybindingPrefixChord }
        if ($pref -and $pref.PSObject.Properties.Name -contains 'keybindingDisabled') { $prefDisabled = $pref.keybindingDisabled }

        $envDisable = [string]$env:WINDO_DISABLE_PSREADLINE_BINDINGS
        $envChord = [string]$env:WINDO_PREFIX_CHORD
        $disabled = $false
        $disabledSource = $null
        if (-not [string]::IsNullOrWhiteSpace($envDisable)) {
            $disabled = _windo_parse_bool_value -Raw $envDisable -Default $false
            if ($disabled) { $disabledSource = "env" }
        } elseif ($null -ne $prefDisabled) {
            $disabled = _windo_parse_bool_value -Raw $prefDisabled -Default $false
            if ($disabled) { $disabledSource = "prefs" }
        }

        $chord = $null
        $chordSource = "auto"
        if (-not [string]::IsNullOrWhiteSpace($envChord)) {
            $chord = $envChord.Trim()
            $chordSource = "env"
        } elseif (-not [string]::IsNullOrWhiteSpace($prefChord)) {
            $chord = $prefChord.Trim()
            $chordSource = "prefs"
        } else {
            $chord = "Alt+w"
            $chordSource = "auto"
        }

        if ($disabled) {
            $chord = $null
            $chordSource = $null
        }

        $autoDetectAlt = [string]$env:WINDO_AUTO_DETECT_ALT_BINDINGS
        $autoDetectAltEnabled = $true
        if (-not [string]::IsNullOrWhiteSpace($autoDetectAlt)) {
            $autoDetectAltEnabled = _windo_parse_bool_value -Raw $autoDetectAlt -Default $true
        }

        $fallbackChord = [string]$env:WINDO_KEYBINDING_FALLBACK_CHORD
        if ([string]::IsNullOrWhiteSpace($fallbackChord)) { $fallbackChord = "Alt+;" } else { $fallbackChord = $fallbackChord.Trim() }

        [pscustomobject]@{
            enabled = [bool](-not $disabled)
            disabled = [bool]$disabled
            disabledSource = $disabledSource
            autoDetectAlt = [bool]$autoDetectAltEnabled
            fallbackChord = $fallbackChord
            requestedChord = $chord
            requestedSource = $chordSource
            chord = $chord
            chordSource = $chordSource
            prefChord = $prefChord
            envChord = $(if ([string]::IsNullOrWhiteSpace($envChord)) { $null } else { $envChord.Trim() })
            autoDetected = $false
            autoDetectedReason = $null
            appliedChord = $null
        }
    }

    function _windo_normalize_completion_mode([string]$Mode) {
        if ([string]::IsNullOrWhiteSpace($Mode)) { return "native-first" }
        switch ($Mode.Trim().ToLowerInvariant()) {
            "native" { return "native-first" }
            "stealth" { return "native-first" }
            "native-first" { return "native-first" }
            "hybrid" { return "hybrid" }
            "windo" { return "windo" }
            "builtin" { return "windo" }
            "builtins" { return "windo" }
            "off" { return "off" }
            "disabled" { return "off" }
            default { return "native-first" }
        }
    }

    function _windo_resolve_completion_policy {
        $pref = _read_windo_prefs
        $prefMode = $null
        if ($pref -and $pref.PSObject.Properties.Name -contains 'completionMode') { $prefMode = [string]$pref.completionMode }

        $envMode = [string]$env:WINDO_COMPLETION_MODE
        $source = "default"
        $raw = "native-first"
        if (-not [string]::IsNullOrWhiteSpace($prefMode)) {
            $raw = $prefMode
            $source = "prefs"
        }
        if (-not [string]::IsNullOrWhiteSpace($envMode)) {
            $raw = $envMode
            $source = "env"
        }

        $mode = _windo_normalize_completion_mode $raw
        [pscustomobject]@{
            mode = $mode
            source = $source
            environmentValue = $(if ([string]::IsNullOrWhiteSpace($envMode)) { $null } else { $envMode.Trim() })
            preferenceValue = $(if ([string]::IsNullOrWhiteSpace($prefMode)) { $null } else { $prefMode.Trim() })
            prefsFile = $PrefsFile
            description = $(switch ($mode) {
                "native-first" { "Delegate non-WINDO arguments to native PowerShell completion; WINDO built-ins still complete by name." }
                "hybrid" { "Offer WINDO built-ins and native PowerShell command names at command start, then delegate non-builtins." }
                "windo" { "Only complete WINDO built-ins; do not delegate to native command completion." }
                "off" { "Disable WINDO argument completer registration." }
            })
        }
    }

    function _windo_roadmap_releases {
        return @(
            [pscustomobject]@{
                version = "3.4.0"
                codename = "Quiet Shell"
                theme = "Make WINDO disappear until it is useful."
                focus = @("native-first completion", "completion policy", "profile repair hardening", "config visibility")
                status = "shipped"
                operatorValue = "The shell keeps normal PowerShell muscle memory while WINDO remains available as an escalation wrapper."
            },
            [pscustomobject]@{
                version = "3.5.0"
                codename = "Trust Console"
                theme = "Make trust state explicit before elevation."
                focus = @("windo trust", "policy summary", "installer provenance", "profile and task drift repair", "clear remediation commands")
                status = "shipped"
                operatorValue = "Operators can see whether the local install is trusted, current, and repairable before running privileged work."
            },
            [pscustomobject]@{
                version = "3.6.0"
                codename = "Syntax Forge"
                theme = "Make common elevation workflows shorter and safer."
                focus = @("windo syntax", "command aliases", "recipe parameters", "dry-run previews", "syntax doctor", "execution planning")
                status = "shipped"
                operatorValue = "High-frequency commands become easier to express without loosening validation or audit trails."
            },
            [pscustomobject]@{
                version = "4.0.0"
                codename = "Operator Mesh"
                theme = "Turn modules, recipes, extras, prompt, and launchpad into one coherent platform layer."
                focus = @("windo mesh workbench", "workflow lanes", "readiness score", "recipe atlas", "launchpad handoff", "structured evidence")
                status = "shipped"
                operatorValue = "WINDO becomes a composable local operations platform, not just an elevation helper."
            },
            [pscustomobject]@{
                version = "4.0.1"
                codename = "Quiet Runway"
                theme = "Tighten command syntax, compact output, developer helpers, and package handoff."
                focus = @("external flag pass-through", "compact output policy", "account handoff", "python venv helper", "package-manager handoff")
                status = "shipped"
                operatorValue = "Common shell work gets quieter and clearer while the next native platform layer gains practical wiring."
            },
            [pscustomobject]@{
                version = "4.1.1"
                codename = "Security Foundry"
                theme = "Bring local scanning, secret storage, SSH, and crypto helpers into the operator shell."
                focus = @("windo scan", "DPAPI vault", "SSH helpers", "OpenSSL/certutil helpers", "security completion")
                status = "shipped"
                operatorValue = "Security tasks become one-command, local-first workflows without weakening elevation boundaries."
            },
            [pscustomobject]@{
                version = "4.2.0"
                codename = "Native Surface Prep"
                theme = "Harden profile startup and wire the local native surface layer."
                focus = @("profile prompt doctor", "oh-my-posh guard repair", "motion policy", "surface manifest", "tray readiness signals")
                status = "shipped"
                operatorValue = "Operators can keep profile load resilient while WINDO quietly prepares richer Windows-native surfaces."
            },
            [pscustomobject]@{
                version = "4.3.0"
                codename = "Control Plane Wiring"
                theme = "Connect tray, surface, motion, and command launch into a local Windows control plane."
                focus = @("windo control", "action catalog", "request queue", "control manifest", "visible-shell executor", "tray action expansion")
                status = "shipped"
                operatorValue = "Native surfaces get a real local manifest and action queue while execution stays explicit and visible."
            },
            [pscustomobject]@{
                version = "4.4.0"
                codename = "Command Center Actions"
                theme = "Make the control-plane queue executable and inspectable."
                focus = @("execute-next", "request inspect", "request cancel", "control history", "result JSON", "tray queue actions")
                status = "shipped"
                operatorValue = "Operators can queue, inspect, cancel, and visibly execute curated local actions from the command center path."
            },
            [pscustomobject]@{
                version = "4.5.0"
                codename = "Signal Deck"
                theme = "Make diagnosis and audit evidence faster to consume."
                focus = @("windo signal", "timeline views", "request correlation", "health cards", "local Signal Deck HTML")
                status = "shipped"
                operatorValue = "Troubleshooting shifts from raw logs to explainable, shareable operational evidence."
            },
            [pscustomobject]@{
                version = "4.6.0"
                codename = "Native Shell Polish"
                theme = "Harden tray, surface, motion, and native readiness before V6."
                focus = @("surface doctor", "surface repair", "surface open", "status-aware tray path", "compiled-helper scaffold")
                status = "shipped"
                operatorValue = "The Windows-native surface becomes easier to inspect, repair, and open without exposing future companion-app internals."
            },
            [pscustomobject]@{
                version = "5.0.0"
                codename = "Command Center"
                theme = "A native-feeling Windows command center for deliberate elevation."
                focus = @("windo center", "tray", "control plane", "signal deck", "surface", "motion", "trust", "recipes")
                status = "shipped"
                operatorValue = "WINDO becomes a PowerShell-native command center that unifies deliberate elevation, local evidence, and Windows-native operator surfaces."
            },
            [pscustomobject]@{
                version = "5.1.0"
                codename = "Command Center"
                theme = "Make the V6 command center feel complete and consistent, not just a command surface."
                focus = @("windo edition", "command center console", "brand assets", "HTML animation", "edition pulse", "Release branch")
                status = "shipped"
                operatorValue = "Operators get a branded local edition console plus stronger command grammar for previewing and executing curated actions."
            },
            [pscustomobject]@{
                version = "5.1.1"
                codename = "Surface Polish"
                theme = "Make dashboard, launchpad, tray popup, and status toast feel like one designed operator system."
                focus = @("dashboard html", "launchpad html", "tray popup", "status toast", "operator hierarchy")
                status = "shipped"
                operatorValue = "The most visible local surfaces become easier to scan, more consistent, and more respectable for repeated admin use."
            },
            [pscustomobject]@{
                version = "5.2.0"
                codename = "Native Surface Panel"
                theme = "Move the Command Center deeper into browser-independent Windows surfaces."
                focus = @("windo surface panel", "windo center panel", "status-aware icons", "curated visual actions", "native readiness")
                status = "shipped"
                operatorValue = "Operators get a real Windows Forms panel for curated WINDO actions while output remains explicit and visible."
            },
            [pscustomobject]@{
                version = "5.3.0"
                codename = "Power Studio"
                theme = "Turn the native surface into guided Windows wizard workflows."
                focus = @("windo center studio", "windo studio", "guided workflows", "preview queue run", "Windows 11 visual system")
                status = "shipped"
                operatorValue = "Operators get a modern wizard-style native control room for trust, repair, security, developer, and package workflows."
            },
            [pscustomobject]@{
                version = "5.4.0"
                codename = "Windows Integration Plane"
                theme = "Make WINDO feel like a current-user Windows system tool."
                focus = @("windo integrate", "Start Menu shortcuts", "startup tray wiring", "command shim", "integration doctor", "control-plane repair actions")
                status = "shipped"
                operatorValue = "Operators can install, inspect, and repair WINDO's Windows shell integration without machine-wide writes or hidden execution."
            },
            [pscustomobject]@{
                version = "5.4.1"
                codename = "Completion Recovery"
                theme = "Keep WINDO command discovery available even when keybinding setup is skipped."
                focus = @("profile completion registration", "completion doctor", "completion repair", "keybinding early-exit hardening", "integration completion checks")
                status = "shipped"
                operatorValue = "Operators can validate and repair tab completion from the shell instead of discovering a silent path-completion fallback."
            }
        )
    }

    function _windo_syntax_shortcuts {
        return @(
            [pscustomobject]@{
                id = "update"
                aliases = @("up", "upgrade", "latest", "install latest", "self update")
                category = "Lifecycle"
                summary = "Install or update WINDO from the published branch."
                command = "windo install-latest"
                preview = "windo trust --online"
                risk = "network + UAC"
                notes = "Run from a normal non-elevated shell so checksum verification happens before the elevated handoff."
            },
            [pscustomobject]@{
                id = "trust"
                aliases = @("proof", "checksum", "verify installer", "provenance", "safe")
                category = "Security"
                summary = "Validate local trust posture and compare installer snapshot to the published checksum."
                command = "windo trust --online"
                preview = "windo trust"
                risk = "read-only network"
                notes = "Online checksum validation is blocked from elevated shells by policy."
            },
            [pscustomobject]@{
                id = "source"
                aliases = @("published", "latest", "origin", "web installer", "bootstrap")
                category = "Lifecycle"
                summary = "Inspect the published installer source, version, and checksum path."
                command = "windo source"
                preview = "windo trust --online"
                risk = "read-only network"
                notes = "Use when web install or install-latest appears stale; source prefers GitHub API and falls back to raw."
            },
            [pscustomobject]@{
                id = "health"
                aliases = @("doctor", "check", "preflight", "ready", "status")
                category = "Diagnostics"
                summary = "Run the local readiness checklist with remediation commands."
                command = "windo preflight"
                preview = "windo dashboard"
                risk = "read-only"
                notes = "Use before install-latest, support handoff, or troubleshooting."
            },
            [pscustomobject]@{
                id = "repair-keys"
                aliases = @("keys", "keybindings", "stuck key", "tab repair", "prefix repair")
                category = "Shell Experience"
                summary = "Reset WINDO PSReadLine bindings to the safe configured chord."
                command = "windo keybindings safe-reset"
                preview = "windo keybindings doctor"
                risk = "profile/session keybinding change"
                notes = "Use when prefix chords or completion behavior feel stuck in the current shell."
            },
            [pscustomobject]@{
                id = "support"
                aliases = @("bundle", "export", "handoff", "evidence", "support bundle")
                category = "Evidence"
                summary = "Create a support-ready local evidence bundle."
                command = "windo export"
                preview = "windo session"
                risk = "local file write"
                notes = "Export redacts protected payloads and is useful for issue reports."
            },
            [pscustomobject]@{
                id = "recipes"
                aliases = @("templates", "examples", "commands", "cookbook")
                category = "Workflow"
                summary = "List built-in elevated command recipes."
                command = "windo recipes"
                preview = "windo recipes preview <name>"
                risk = "read-only"
                notes = "Review exact commands with windo recipes preview <name> or windo recipes run <name> --dry-run before executing."
            },
            [pscustomobject]@{
                id = "launch"
                aliases = @("launchpad", "tray", "window", "command center")
                category = "Visuals"
                summary = "Open the WINDO launchpad or native tray command center."
                command = "windo launchpad --tray"
                preview = "windo launchpad"
                risk = "starts local tray helper"
                notes = "Use windo launchpad --html for a browser artifact instead."
            },
            [pscustomobject]@{
                id = "control-plane"
                aliases = @("control", "surface queue", "visual orchestrator", "native control", "executor")
                category = "Visuals"
                summary = "Prime the local Windows control plane for tray/native orchestration."
                command = "windo control prime"
                preview = "windo control actions"
                risk = "local manifest write"
                notes = "Use windo control queue <action-id> for explicit request files or windo control run <action-id> to launch a curated action visibly."
            },
            [pscustomobject]@{
                id = "rdp"
                aliases = @("rdp", "remote desktop", "rdp status", "rdp firewall", "rdp troubleshoot", "rdp config")
                category = "Remote Access"
                summary = "Inspect RDP registry and service posture, firewall rules, and troubleshooting state."
                command = "windo rdp status --json"
                preview = "windo rdp troubleshoot --host localhost --json"
                risk = "elevation for config/apply changes"
                notes = "Use status only commands before elevating; enable/disable/config may need Administrator and are planned through the WINDO runner."
            },
            [pscustomobject]@{
                id = "vnc"
            aliases = @("vnc", "vnc status", "vnc firewall", "vnc stop", "vnc test", "vnc troubleshoot")
                category = "Remote Access"
                summary = "Inspect VNC services and listeners, plus port reachability checks."
                command = "windo vnc status --json"
                preview = "windo vnc test --host localhost --ports 5900,5901 --json"
                risk = "elevation for service stop operations"
                notes = "Vault entries are optional and only previewed as username + masked password for safe operator context."
            },
            [pscustomobject]@{
                id = "integration"
                aliases = @("install shell", "start menu", "startup", "shortcut", "shim", "windows integration")
                category = "Windows"
                summary = "Install or repair current-user Windows integration for WINDO."
                command = "windo integrate repair"
                preview = "windo integrate doctor"
                risk = "current-user shortcuts, startup entry, and user PATH update"
                notes = "No machine-wide writes are required; the integration plane creates Start Menu/Desktop shortcuts, a startup tray shortcut, and a user command shim."
            }
        )
    }

    function _windo_syntax_matches([string]$Query) {
        $all = @(_windo_syntax_shortcuts)
        if ([string]::IsNullOrWhiteSpace($Query)) { return $all }
        $q = $Query.Trim().ToLowerInvariant()
        return @($all | Where-Object {
            ([string]$_.id).ToLowerInvariant() -like "*$q*" -or
            ([string]$_.summary).ToLowerInvariant() -like "*$q*" -or
            ([string]$_.category).ToLowerInvariant() -like "*$q*" -or
            (@($_.aliases) | Where-Object { ([string]$_).ToLowerInvariant() -like "*$q*" }).Count -gt 0
        })
    }

    function _windo_syntax_doctor([string]$Query) {
        $all = @(_windo_syntax_shortcuts)
        $queryText = $(if ([string]::IsNullOrWhiteSpace($Query)) { "" } else { $Query.Trim() })
        $q = $queryText.ToLowerInvariant()
        $matches = @(_windo_syntax_matches $queryText)
        $exact = @()
        if (-not [string]::IsNullOrWhiteSpace($q)) {
            $exact = @($all | Where-Object {
                ([string]$_.id).ToLowerInvariant() -eq $q -or
                (@($_.aliases) | Where-Object { ([string]$_).ToLowerInvariant() -eq $q }).Count -gt 0
            })
        }

        $recommendations = [System.Collections.ArrayList]@()
        $best = $null
        $status = "ready"
        $message = "Syntax Forge is ready. Provide an intent to check the safest WINDO command."
        $exitCode = 0

        if ([string]::IsNullOrWhiteSpace($q)) {
            [void]$recommendations.Add("Try: windo syntax doctor update")
            [void]$recommendations.Add("Try: windo syntax doctor proof")
            [void]$recommendations.Add("Try: windo syntax doctor repair keys")
        } elseif ($exact.Count -eq 1) {
            $best = $exact[0]
            $status = "exact"
            $message = "Intent maps exactly to a known Syntax Forge shortcut."
            [void]$recommendations.Add("Run: $($best.command)")
            [void]$recommendations.Add("Preview: $($best.preview)")
            [void]$recommendations.Add("Plan: windo explain $($best.command)")
        } elseif ($matches.Count -eq 1) {
            $best = $matches[0]
            $status = "single-match"
            $message = "Intent maps to one likely shortcut."
            [void]$recommendations.Add("Run: $($best.command)")
            [void]$recommendations.Add("Preview: $($best.preview)")
            [void]$recommendations.Add("Plan: windo explain $($best.command)")
        } elseif ($matches.Count -gt 1) {
            $status = "ambiguous"
            $message = "Intent matches more than one shortcut; choose the narrower command before running anything."
            $exitCode = 3
            foreach ($m in @($matches | Select-Object -First 5)) {
                [void]$recommendations.Add("$($m.id): $($m.command)")
            }
        } else {
            $status = "no-match"
            $message = "No Syntax Forge shortcut matched this intent."
            $exitCode = 3
            if ($q -match "install|upgrade|update|latest") {
                [void]$recommendations.Add("update: windo install-latest")
                [void]$recommendations.Add("source: windo source")
            } elseif ($q -match "hash|checksum|safe|trust|proof|provenance") {
                [void]$recommendations.Add("trust: windo trust --online")
                [void]$recommendations.Add("source: windo source")
            } elseif ($q -match "tab|key|binding|chord") {
                [void]$recommendations.Add("repair-keys: windo keybindings safe-reset")
                [void]$recommendations.Add("health: windo preflight")
            } elseif ($q -match "recipe|template|cookbook|dry") {
                [void]$recommendations.Add("recipes: windo recipes")
                [void]$recommendations.Add("preview: windo recipes preview <name>")
            } else {
                [void]$recommendations.Add("List known intents: windo syntax")
                [void]$recommendations.Add("Explain a command: windo explain <command...>")
                [void]$recommendations.Add("Check health: windo preflight")
            }
        }

        return [pscustomobject]@{
            query = $(if ([string]::IsNullOrWhiteSpace($queryText)) { $null } else { $queryText })
            status = $status
            message = $message
            count = $matches.Count
            bestMatch = $best
            matches = @($matches)
            recommendations = @($recommendations.ToArray())
            exitCode = $exitCode
        }
    }

    function _windo_quote_plan_part([string]$Part) {
        if ($null -eq $Part) { return "''" }
        if ($Part -match '^[A-Za-z0-9_./:\\=-]+$') { return $Part }
        return "'" + ($Part -replace "'", "''") + "'"
    }

    function _windo_join_plan_command([object[]]$Parts) {
        if ($null -eq $Parts -or $Parts.Count -eq 0) { return "" }
        return ((@($Parts) | ForEach-Object { _windo_quote_plan_part ([string]$_) }) -join " ")
    }

    function _windo_parse_bool_value {
        param([object]$Raw, [bool]$Default = $false)
        if ($null -eq $Raw) { return $Default }
        $value = [string]$Raw
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        switch ($value.Trim().ToLowerInvariant()) {
            "1" { return $true }
            "true" { return $true }
            "yes" { return $true }
            "on" { return $true }
            "enabled" { return $true }
            "0" { return $false }
            "false" { return $false }
            "no" { return $false }
            "off" { return $false }
            "disabled" { return $false }
            default { return $Default }
        }
    }

    function _windo_motion_classification {
        param([object[]]$Parts)
        $parts = @($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($parts.Count -gt 0 -and ([string]$parts[0]).ToLowerInvariant() -eq "windo") {
            $parts = if ($parts.Count -gt 1) { @($parts[1..($parts.Count - 1)]) } else { @() }
        }
        $verb = if ($parts.Count -gt 0) { ([string]$parts[0]).ToLowerInvariant() } else { "" }
        $sub = if ($parts.Count -gt 1) { ([string]$parts[1]).ToLowerInvariant() } else { "" }

        $durationClass = "short"
        $profileHint = "subtle"
        $context = $(if ([string]::IsNullOrWhiteSpace($verb)) { "empty" } else { "short" })

        switch -Regex ($verb) {
            "^((install-latest)|(upgrade)|(self-update)|uninstall)$" {
                $durationClass = "long"
                $profileHint = "standard"
                $context = "installer-update"
            }
            "^pkg$" {
                $durationClass = if ($sub -eq "status") { "short" } else { "long" }
                $profileHint = if ($durationClass -eq "long") { "standard" } else { "subtle" }
                $context = "pkg"
            }
            "^recipes$" {
                if ($sub -eq "run") {
                    $durationClass = "long"
                    $profileHint = "standard"
                    $context = "recipe-run"
                } else {
                    $durationClass = "short"
                    $context = "recipe"
                }
            }
            "^run$" {
                $durationClass = "long"
                $profileHint = "standard"
                $context = "recipe-run"
            }
            "^source$" {
                $durationClass = "short"
                $context = "source"
            }
            "^integrate$" {
                $durationClass = "medium"
                $profileHint = "standard"
                $context = "integration"
            }
            "^surface$|^control$|^motion$|^edition$|^studio$|^center$" {
                $durationClass = "long"
                $profileHint = "standard"
                $context = $verb
            }
            "^windi$|^syntax$|^help$|^version$|^config$|^context$|^doctor$|^log$|^verify$|^integrity$|^history$|^stats$|^profile$|^motion$" {
                $durationClass = "short"
                $profileHint = "subtle"
                $context = $verb
            }
            default { }
        }

        [pscustomobject]@{
            estimatedDurationClass = $durationClass
            motionProfileHint = $profileHint
            motionContext = $context
        }
    }

    function _windo_new_command_plan([object[]]$Parts) {
        $target = @($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($target.Count -gt 0 -and ([string]$target[0]).ToLowerInvariant() -eq "windo") {
            $target = if ($target.Count -gt 1) { @($target[1..($target.Count - 1)]) } else { @() }
        }

        $commandLine = _windo_join_plan_command $target
        $verb = if ($target.Count -gt 0) { ([string]$target[0]).ToLowerInvariant() } else { "" }
        $sub = if ($target.Count -gt 1) { ([string]$target[1]).ToLowerInvariant() } else { "" }
        $motionProfile = _windo_motion_classification $target
        $artifacts = [System.Collections.ArrayList]@()
        $preflight = [System.Collections.ArrayList]@("windo trust", "windo preflight")
        $next = [System.Collections.ArrayList]@()
        $warnings = [System.Collections.ArrayList]@()

        $plan = [ordered]@{
            windoVersion = $WindoVersion
            target = @($target)
            commandLine = $commandLine
            route = "none"
            category = "Planning"
            privilegeBoundary = "none"
            network = $false
            writesLocalFiles = $false
            createsAuditEntry = $false
            checksumValidation = "not applicable"
            artifacts = @()
            preflight = @()
            nextCommands = @()
            warnings = @()
            estimatedDurationClass = [string]$motionProfile.estimatedDurationClass
            motionContext = [string]$motionProfile.motionContext
            motionProfileHint = [string]$motionProfile.motionProfileHint
            exitCode = 0
        }

        if ($target.Count -eq 0) {
            $plan.route = "usage"
            $plan.warnings = @("Provide a target command to explain, for example: windo explain install-latest")
            $plan.nextCommands = @("windo explain install-latest", "windo explain -- Get-Service Spooler")
            $plan.exitCode = 2
            return [pscustomobject]$plan
        }

        switch ($verb) {
            { $_ -in @("install-latest", "upgrade", "self-update") } {
                $plan.route = "published installer update"
                $plan.category = "Lifecycle"
                $plan.privilegeBoundary = "network download, checksum verification, then elevated installer handoff"
                $plan.network = $true
                $plan.writesLocalFiles = $true
                $plan.createsAuditEntry = $false
                $plan.checksumValidation = "downloads installer and compares SHA256 to published checksums/installer.sha256 before running"
                [void]$artifacts.Add($SecureDir)
                [void]$artifacts.Add((Join-Path (Join-Path $HOME "Documents") "windo"))
                [void]$artifacts.Add($PROFILE)
                [void]$artifacts.Add("Scheduled tasks: $TaskName, $TaskUpdate")
                [void]$preflight.Insert(0, "windo trust --online")
                [void]$next.Add("windo install-latest")
                break
            }
            "trust" {
                $plan.route = "trust console"
                $plan.category = "Security"
                $plan.privilegeBoundary = "read-only local checks; --online fetch is blocked when elevated"
                $plan.network = (@($target) -contains "--online")
                $plan.checksumValidation = $(if ($plan.network) { "compares local installer snapshot to published checksum" } else { "local snapshot hash only; add --online to compare published checksum" })
                [void]$next.Add($(if ($plan.network) { "windo trust --online" } else { "windo trust" }))
                break
            }
            "integrate" {
                $plan.route = "Windows integration plane"
                $plan.category = "Windows"
                $plan.privilegeBoundary = "current-user shell integration only; no machine-wide Program Files or HKLM writes"
                $plan.writesLocalFiles = $true
                $plan.checksumValidation = "not applicable; local shortcut/shim repair"
                [void]$artifacts.Add((Join-Path $SecureDir "integration"))
                [void]$artifacts.Add((Join-Path $SecureDir "bin\windo.cmd"))
                [void]$artifacts.Add("Start Menu: WINDO")
                [void]$artifacts.Add("Startup: WINDO Command Center Tray")
                [void]$next.Add("windo integrate doctor")
                [void]$next.Add("windo integrate repair")
                break
            }
            "source" {
                $plan.route = "published source inspection"
                $plan.category = "Lifecycle"
                $plan.privilegeBoundary = "read-only network; blocked nowhere but safest from a normal shell"
                $plan.network = $true
                $plan.checksumValidation = "compares local snapshot hash to the published checksum source and reports installer source/version"
                [void]$next.Add("windo source")
                [void]$next.Add("windo trust --online")
                break
            }
            "syntax" {
                $plan.route = "syntax catalog"
                $plan.category = "Planning"
                $plan.privilegeBoundary = "read-only"
                [void]$next.Add($commandLine)
                break
            }
            "recipes" {
                $plan.category = "Workflow"
                if ($sub -eq "run") {
                    $recipeId = if ($target.Count -gt 2) { [string]$target[2] } else { "" }
                    $preview = if ($recipeId) { _windo_get_recipe_preview $recipeId } else { $null }
                    $plan.route = "recipe elevation"
                    $plan.privilegeBoundary = "scheduled task runner unless --dry-run is used"
                    $plan.writesLocalFiles = $true
                    $plan.createsAuditEntry = $true
                    $plan.checksumValidation = "recipe is bundled data in the signed/versioned installer; no network fetch"
                    [void]$artifacts.Add("request/result files under $SecureDir")
                    [void]$artifacts.Add($LogFile)
                    if ($preview) {
                        [void]$next.Add($preview.previewCommand)
                        [void]$next.Add($preview.dryRunCommand)
                        [void]$next.Add($preview.runCommand)
                    } else {
                        [void]$warnings.Add("Recipe id was not found in the bundled catalog.")
                        [void]$next.Add("windo recipes")
                    }
                } else {
                    $plan.route = "recipe catalog"
                    $plan.privilegeBoundary = "read-only"
                    [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo recipes" }))
                }
                break
            }
            "run" {
                $recipeId = $null
                for ($ri = 1; $ri -lt $target.Count; $ri++) {
                    $rv = [string]$target[$ri]
                    if ($rv -eq "--recipe" -and ($ri + 1) -lt $target.Count) { $recipeId = [string]$target[$ri + 1]; break }
                    if ($rv -like "--recipe=*") { $recipeId = $rv.Substring(9); break }
                }
                if ($recipeId) {
                    $preview = _windo_get_recipe_preview $recipeId
                    $plan.route = "recipe elevation"
                    $plan.category = "Workflow"
                    $plan.privilegeBoundary = "scheduled task runner unless --dry-run is used"
                    $plan.writesLocalFiles = $true
                    $plan.createsAuditEntry = $true
                    $plan.checksumValidation = "recipe is bundled data in the signed/versioned installer; no network fetch"
                    [void]$artifacts.Add("request/result files under $SecureDir")
                    [void]$artifacts.Add($LogFile)
                    if ($preview) {
                        [void]$next.Add($preview.previewCommand)
                        [void]$next.Add($preview.dryRunCommand)
                    } else {
                        [void]$warnings.Add("Recipe id was not found in the bundled catalog.")
                    }
                } else {
                    $plan.route = "external elevated command"
                    $plan.category = "Elevation"
                    $plan.privilegeBoundary = "scheduled task runner"
                    $plan.writesLocalFiles = $true
                    $plan.createsAuditEntry = $true
                    $plan.checksumValidation = "runner/updater integrity is checked from the local manifest; target command is not checksummed"
                    [void]$artifacts.Add("request/result files under $SecureDir")
                    [void]$artifacts.Add($LogFile)
                    [void]$next.Add("windo $commandLine")
                }
                break
            }
            "launchpad" {
                $plan.route = $(if (@($target) -contains "--tray") { "native tray launchpad" } elseif (@($target) -contains "--html") { "html launchpad artifact" } else { "terminal launchpad" })
                $plan.category = "Visuals"
                $plan.privilegeBoundary = "local desktop APIs; no elevation"
                $plan.writesLocalFiles = (@($target) -contains "--tray") -or (@($target) -contains "--html") -or (@($target) -contains "--open")
                $plan.createsAuditEntry = $false
                $plan.checksumValidation = "not applicable; uses local installed assets and manifest-backed runner state"
                if (@($target) -contains "--tray") { [void]$artifacts.Add((Join-Path $SecureDir "windo_launchpad_tray.ps1")) }
                if (@($target) -contains "--html" -or @($target) -contains "--open") { [void]$artifacts.Add("launchpad html under Documents\\windo") }
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo launchpad" }))
                break
            }
            "venv" {
                $plan.route = "local developer environment"
                $plan.category = "Developer"
                $plan.privilegeBoundary = "current user shell; no scheduled task elevation"
                $plan.writesLocalFiles = $true
                $plan.createsAuditEntry = $false
                $plan.checksumValidation = "not applicable; uses local Python venv tooling"
                [void]$artifacts.Add(".venv or selected virtual environment path")
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo venv status" }))
                break
            }
            "pkg" {
                $plan.route = "package-manager elevated handoff"
                $plan.category = "Packages"
                $plan.privilegeBoundary = "winget/choco/scoop via WINDO runner when manager args are supplied"
                $plan.writesLocalFiles = $true
                $plan.createsAuditEntry = $true
                $plan.checksumValidation = "WINDO runner integrity is checked; package trust is delegated to the selected package manager"
                [void]$preflight.Add("windo pkg status")
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo pkg status" }))
                break
            }
            "container" {
                $plan.route = "local container runtime handoff"
                $plan.category = "Operators"
                $plan.privilegeBoundary = "local shell only; no scheduled task used"
                $plan.writesLocalFiles = $false
                $plan.createsAuditEntry = $false
                $plan.checksumValidation = "not applicable; dispatch is limited to local docker/podman binaries"
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo container ps" }))
                break
            }
            "scan" {
                $plan.route = "local security posture scan"
                $plan.category = "Security"
                $plan.privilegeBoundary = "current user file reads; no elevation"
                $plan.writesLocalFiles = $false
                $plan.createsAuditEntry = $false
                $plan.checksumValidation = "calculates SHA256 for scanned files when hashing is enabled"
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo scan ." }))
                break
            }
            "net-scan" {
                $plan.route = "local network posture scan"
                $plan.category = "Security"
                $plan.privilegeBoundary = "read-only unless rdp/vnc apply subcommands are supplied; those require elevation"
                $plan.writesLocalFiles = $false
                $plan.createsAuditEntry = $false
                $plan.checksumValidation = "not applicable; local network inspection only"
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo net-scan status" }))
                break
            }
            "rdp" {
                if ($sub -in @("status", "")) {
                    $plan.route = "RDP posture read-only"
                    $plan.category = "Remote Access"
                    $plan.privilegeBoundary = "current user local reads"
                    $plan.writesLocalFiles = $false
                    $plan.createsAuditEntry = $false
                    $plan.checksumValidation = "not applicable; registry read-through and service state only"
                } elseif ($sub -in @("firewall", "config", "troubleshoot")) {
                    $plan.route = "RDP apply/diagnostics"
                    $plan.category = "Remote Access"
                    $plan.privilegeBoundary = "scheduled task runner unless --dry-run is used"
                    $plan.writesLocalFiles = $false
                    $plan.createsAuditEntry = $true
                    $plan.checksumValidation = "not applicable; runner/updater integrity is checked before execution"
                } else {
                    $plan.route = "remote access command"
                    $plan.category = "Remote Access"
                    $plan.privilegeBoundary = "read-only; unknown subcommand handled at runtime"
                }
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo rdp status" }))
                break
            }
            "vnc" {
                if ($sub -in @("status", "")) {
                    $plan.route = "VNC posture read-only"
                    $plan.category = "Remote Access"
                    $plan.privilegeBoundary = "current user local reads"
                    $plan.writesLocalFiles = $false
                    $plan.createsAuditEntry = $false
                    $plan.checksumValidation = "not applicable; service probes and firewall reads only"
                } elseif ($sub -in @("firewall", "test", "troubleshoot", "stop")) {
                    $plan.route = "VNC apply/diagnostics"
                    $plan.category = "Remote Access"
                    $plan.privilegeBoundary = "scheduled task runner unless --dry-run is used"
                    $plan.writesLocalFiles = $false
                    $plan.createsAuditEntry = $true
                    $plan.checksumValidation = "not applicable; runner/updater integrity is checked before execution"
                } else {
                    $plan.route = "remote access command"
                    $plan.category = "Remote Access"
                    $plan.privilegeBoundary = "read-only; unknown subcommand handled at runtime"
                }
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo vnc status" }))
                break
            }
            "vault" {
                $plan.route = "DPAPI current-user vault"
                $plan.category = "Security"
                $plan.privilegeBoundary = "current Windows user DPAPI context"
                $plan.writesLocalFiles = $true
                $plan.createsAuditEntry = $false
                $plan.checksumValidation = "not applicable; secrets are DPAPI-protected, not checksummed"
                [void]$artifacts.Add((_windo_vault_path))
                [void]$next.Add($(if ($commandLine) { $commandLine } else { "windo vault status" }))
                break
            }
            { $_ -in @("sshx", "crypto") } {
                $plan.route = "local security tool wrapper"
                $plan.category = "Security"
                $plan.privilegeBoundary = "current user tool execution; no WINDO elevation"
                $plan.writesLocalFiles = ($verb -eq "sshx" -and (@($target) -match "keygen|config").Count -gt 0)
                $plan.createsAuditEntry = $false
                $plan.checksumValidation = $(if ($verb -eq "crypto") { "crypto hash calculates SHA256; cert/key commands delegate validation to local tools" } else { "not applicable; SSH tool state only" })
                [void]$next.Add($commandLine)
                break
            }
            { $_ -in @("version", "config", "context", "profile", "roadmap", "preflight", "dashboard", "integrity", "verify", "session", "log", "history", "stats", "backups", "modules", "extras", "prompt", "ai", "help", "motion", "surface", "control", "signal", "center") } {
                $plan.route = "local built-in command"
                $plan.category = "Readiness"
                $plan.privilegeBoundary = "read-only unless a mutating subcommand is supplied"
                $plan.checksumValidation = "manifest-backed runner/updater integrity where relevant"
                if ($verb -in @("dashboard", "export", "prompt", "extras", "backups", "modules", "control", "surface", "signal", "center") -and (@($target) -match "fetch|enable|disable|prune|--html|--export|prime|queue|run|clear|repair|open|execute-next|cancel|tray").Count -gt 0) {
                    $plan.writesLocalFiles = $true
                }
                [void]$next.Add($commandLine)
                break
            }
            { $_ -in @("repair", "keybindings", "completion", "theme", "output") } {
                $plan.route = "local configuration change"
                $plan.category = "Shell Experience"
                $plan.privilegeBoundary = "current user profile/preferences; no elevation"
                $plan.writesLocalFiles = $true
                $plan.checksumValidation = "not applicable; inspect with windo trust after changes"
                [void]$artifacts.Add($PrefsFile)
                [void]$artifacts.Add($PROFILE)
                [void]$next.Add($commandLine)
                break
            }
            default {
                $plan.route = "external elevated command"
                $plan.category = "Elevation"
                $plan.privilegeBoundary = "scheduled task runner"
                $plan.writesLocalFiles = $true
                $plan.createsAuditEntry = $true
                $plan.checksumValidation = "runner/updater integrity is checked from the local manifest; target command is not checksummed"
                [void]$artifacts.Add("request/result files under $SecureDir")
                [void]$artifacts.Add($LogFile)
                [void]$next.Add("windo $commandLine")
            }
        }

        $plan.artifacts = @($artifacts.ToArray())
        $plan.preflight = @($preflight.ToArray() | Select-Object -Unique)
        $plan.nextCommands = @($next.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        $plan.warnings = @($warnings.ToArray())
        return [pscustomobject]$plan
    }

    function _windo_apply_runtime_keybindings {
        if (!(Get-Command Get-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) { return $false }
        if (!(Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) { return $false }
        if (!(Get-Command Remove-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) { return $false }
        try {
            Import-Module PSReadLine -ErrorAction Stop
            $null = [Microsoft.PowerShell.PSConsoleReadLine]
        } catch { return $false }

        $policy = _windo_resolve_keybinding_policy
        $legacyChords = @('w', 'w,w', 'Alt+w', 'Shift+Enter', 'Alt+Enter')
        foreach ($legacyChord in $legacyChords) {
            try { Remove-PSReadLineKeyHandler -Chord $legacyChord -ErrorAction SilentlyContinue } catch { }
        }
        if (-not $policy.enabled) { return $true }
        if ([string]::IsNullOrWhiteSpace($policy.chord)) { return $true }

        $windoPrefixOnly = {
            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            $m = [regex]::Match($line, '^(\\s*)(.*)$')
            $rest = $m.Groups[2].Value
            if ($rest -match '^(?i)windo(\\s|$)') { return }
            $indent = $m.Groups[1].Value
            $newLine = $indent + 'windo ' + $rest
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $newLine)
        }

        $windoPrefixRun = {
            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            $m = [regex]::Match($line, '^(\\s*)(.*)$')
            $rest = $m.Groups[2].Value
            if ($rest -notmatch '^(?i)windo(\\s|$)') {
                $indent = $m.Groups[1].Value
                $newLine = $indent + 'windo ' + $rest
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $newLine)
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }

        $requestedChord = $policy.chord
        $prefixCandidates = [System.Collections.ArrayList]@()
        [void]$prefixCandidates.Add($requestedChord)
        if ($policy.autoDetectAlt -and ($requestedChord -like 'Alt+*') -and ([string]::IsNullOrWhiteSpace($policy.fallbackChord) -eq $false) -and ($policy.fallbackChord -ne $requestedChord)) {
            [void]$prefixCandidates.Add($policy.fallbackChord)
        }

        $selectedPrefixChord = $null
        foreach ($candidate in ($prefixCandidates | Select-Object -Unique)) {
            try {
                Set-PSReadLineKeyHandler -Chord $candidate -ScriptBlock $windoPrefixOnly -ErrorAction Stop
                $handler = Get-PSReadLineKeyHandler -Chord $candidate -ErrorAction Stop
                if ($null -ne $handler) {
                    $selectedPrefixChord = $candidate
                    break
                }
            } catch {
                try { Remove-PSReadLineKeyHandler -Chord $candidate -ErrorAction SilentlyContinue } catch { }
            }
        }
        if ($null -eq $selectedPrefixChord) { return }
        if ($selectedPrefixChord -ne $requestedChord) {
            $policy.chord = $selectedPrefixChord
            $policy.chordSource = "auto-fallback"
            $policy.autoDetected = $true
            $policy.autoDetectedReason = "alt binding did not bind, fallback to '$selectedPrefixChord'"
        } else {
            $policy.appliedChord = $selectedPrefixChord
        }

        try { Set-PSReadLineKeyHandler -Chord 'Shift+Enter' -ScriptBlock $windoPrefixRun } catch { }
        try { Set-PSReadLineKeyHandler -Chord 'Alt+Enter' -ScriptBlock $windoPrefixRun } catch { }
        return $true
    }

    function _windo_keybinding_inspect_chord_for_doctor {
        param(
            [string]$Chord,
            [ValidateSet('prefix', 'run')]
            [string]$Role
        )
        $row = [ordered]@{
            chord                 = $Chord
            role                  = $Role
            handlerPresent        = $false
            looksLikeWindoBinding = $false
            scriptPreview         = $null
            advisory              = $null
        }
        if ([string]::IsNullOrWhiteSpace($Chord)) {
            $row.advisory = "empty chord"
            return [pscustomobject]$row
        }
        if (!(Get-Command Get-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
            $row.advisory = "PSReadLine key handler API not available"
            return [pscustomobject]$row
        }
        $h = $null
        try {
            $h = Get-PSReadLineKeyHandler -Chord $Chord -ErrorAction Stop
        } catch {
            $row.advisory = "no handler registered (or chord not bound in this host)"
            return [pscustomobject]$row
        }
        if ($null -eq $h) {
            $row.advisory = "no handler registered"
            return [pscustomobject]$row
        }
        $row.handlerPresent = $true
        $script = ""
        try {
            if ($null -ne $h.ScriptBlock) {
                $script = $h.ScriptBlock.ToString()
            } elseif ($null -ne $h.Function -and -not [string]::IsNullOrWhiteSpace([string]$h.Function)) {
                $script = "Function: " + [string]$h.Function
            }
        } catch {
            $script = "(could not stringify handler)"
        }
        $max = 420
        if ($script.Length -gt $max) { $row.scriptPreview = $script.Substring(0, $max) + "..." } else { $row.scriptPreview = $script }

        if ($Role -eq 'prefix') {
            $row.looksLikeWindoBinding = [bool]($script -match '(?i)windo')
        } else {
            $row.looksLikeWindoBinding = [bool](($script -match '(?i)windo') -and ($script -match 'AcceptLine'))
        }
        if (-not $row.looksLikeWindoBinding) {
            $row.advisory = "Handler does not match WINDO heuristics for this role; another module may have claimed this chord."
        }
        return [pscustomobject]$row
    }

    function _json_envelope([string]$commandName, $payload) {
        $r = _windo_resolve_json_envelope
        if (-not $r.includeMeta) {
            [ordered]@{
                schemaVersion = $r.schemaLabel
                windoVersion = $WindoVersion
                command = $commandName
                generatedAt = (Get-Date -Format "o")
                payload = $payload
            }
        } else {
            $osDesc = ""
            try { $osDesc = [System.Environment]::OSVersion.VersionString } catch { $osDesc = "unknown" }
            [ordered]@{
                schemaVersion = $r.schemaLabel
                windoVersion = $WindoVersion
                command = $commandName
                generatedAt = (Get-Date -Format "o")
                meta = @{
                    psEdition = [string]$PSVersionTable.PSEdition
                    psVersion = $PSVersionTable.PSVersion.ToString()
                    osVersion = $osDesc
                }
                payload = $payload
            }
        }
    }

    function _emit_json([string]$commandName, $payload) {
        (_json_envelope $commandName $payload) | ConvertTo-Json -Depth 14 | Write-Host
    }

    function _windo_start_downloaded_installer([string]$ScriptPath) {
        $runnerExe = "powershell.exe"
        $pwshExe = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwshExe -and $pwshExe.Source) { $runnerExe = $pwshExe.Source }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
        $shouldElevate = [Environment]::UserInteractive -and -not $env:CI

        if ($shouldElevate) {
            Write-Host "[windo] Requesting elevation for installer..." -ForegroundColor Yellow
            try {
                Start-Process -FilePath $runnerExe -Verb RunAs -ArgumentList $argList -Wait | Out-Null
                return
            } catch [System.ComponentModel.Win32Exception] {
                if ($_.Exception.NativeErrorCode -eq 1223) {
                    throw "Installer elevation was canceled. Re-run install-latest and approve the UAC prompt, or run the installer from an elevated PowerShell session."
                }
                throw
            }
        }

        Write-Host "[windo] Running installer without elevation (non-interactive or CI session)." -ForegroundColor DarkYellow
        & $runnerExe @argList
    }

    function _windo_run_genisis_installer {
        param(
            [switch]$ForceContinue,
            [switch]$NonInteractive
        )
        if (_windo_is_process_elevated) {
            Write-Host "[windo] install-latest: download is not performed while running as Administrator." -ForegroundColor Yellow
            Write-Host "  This avoids fetching remote code in a high-privilege session. Open a normal (non-elevated)" -ForegroundColor DarkGray
            Write-Host "  PowerShell window and run:  windo install-latest" -ForegroundColor DarkGray
            Write-Host "  You will get a verified download there, then a prompt before the installer runs (UAC may follow)." -ForegroundColor DarkGray
            _windo_set_exit 2
            return
        }
        $TempInst = Join-Path $env:TEMP ("windo_install_" + [Guid]::NewGuid().ToString("n") + ".ps1")
        try {
            Write-Host "[windo] Downloading latest installer from v6 (GitHub API first, raw fallback)..." -ForegroundColor Cyan
            $publishedInstaller = _windo_save_published_installer -Path $TempInst
            Write-Host "[windo] Installer source: $($publishedInstaller.source)  version=$($publishedInstaller.version)" -ForegroundColor DarkGray
            if (!(Test-Path $TempInst)) { throw "Download failed." }
            _windo_verify_installer_sha256_optional $TempInst
            if ((Get-Item $TempInst).Length -lt 5000) { throw "Installer file size looks invalid." }
            Write-Host "[windo] Download finished; checksum verified when published on v6." -ForegroundColor Green
            $runNow = $false
            if ($ForceContinue -or $env:WINDO_INSTALL_NONINTERACTIVE -or $env:CI) {
                $runNow = $true
                if ($env:WINDO_INSTALL_NONINTERACTIVE -or $env:CI) {
                    Write-Host "[windo] Proceeding without prompt (WINDO_INSTALL_NONINTERACTIVE or CI set)." -ForegroundColor DarkGray
                }
            } elseif ($NonInteractive) {
                Write-Host "[windo] install-latest: non-interactive mode blocks confirmation prompts. Add --force to proceed." -ForegroundColor Yellow
                Remove-Item -LiteralPath $TempInst -Force -ErrorAction SilentlyContinue
                _windo_set_exit 2
                return
            } elseif (-not [Environment]::UserInteractive) {
                Write-Host "[windo] Non-interactive session: re-run with --force or set WINDO_INSTALL_NONINTERACTIVE=1" -ForegroundColor Yellow
                Remove-Item -LiteralPath $TempInst -Force -ErrorAction SilentlyContinue
                _windo_set_exit 2
                return
            } else {
                $prompt = "Run the installer now? (UAC may prompt for elevation to register tasks.) [y/N]"
                if (-not [string]::IsNullOrWhiteSpace($env:SUDO_PROMPT)) { $prompt = [string]$env:SUDO_PROMPT }
                if ($prompt -notmatch '(?i)\[y\/n\]') { $prompt = "$prompt [y/N]" }
                Write-Host "[windo] The installer is ready. You can review the file before continuing: $TempInst" -ForegroundColor Cyan
                $ans = Read-Host $prompt
                if ($ans -eq 'y' -or $ans -eq 'Y' -or $ans -eq 'yes') { $runNow = $true }
            }
            if (-not $runNow) {
                Write-Host "[windo] Cancelled; temporary installer removed." -ForegroundColor DarkYellow
                Remove-Item -LiteralPath $TempInst -Force -ErrorAction SilentlyContinue
                _windo_set_exit 0
                return
            }
            Write-Host "[windo] Starting installer. When it finishes, reload: . `$PROFILE" -ForegroundColor Yellow
            _windo_start_downloaded_installer -ScriptPath $TempInst
        } catch {
            Write-Host "[windo] Could not install from v6: $($_.Exception.Message)" -ForegroundColor Red
            _windo_set_exit 1
        } finally {
            if (Test-Path -LiteralPath $TempInst) { Remove-Item -LiteralPath $TempInst -Force -ErrorAction SilentlyContinue }
        }
    }

    function _read_last_meta {
        if (!(Test-Path $LastMetaFile)) { return $null }
        try { Get-Content -Raw -Path $LastMetaFile | ConvertFrom-Json } catch { $null }
    }

    function _write_last_meta([string]$cmdLine, [string]$requestId) {
        $meta = @{
            schemaVersion = "1.0"
            commandLine = $cmdLine
            storedAt = (Get-Date -Format "o")
            lastRequestId = $requestId
        } | ConvertTo-Json -Compress
        Set-Content -Path $LastMetaFile -Value $meta -Encoding UTF8
    }

    function _get_last_hash() {
        if (!(Test-Path $LogFile)) { return "" }
        $last = Get-Content -Path $LogFile -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ([string]::IsNullOrWhiteSpace($last)) { return "" }
        $parts = $last.Split(":", 2)
        if ($parts.Count -lt 2) { return "" }
        $parts[0]
    }

    function _append_log([hashtable]$entry) {
        $entry.PreviousHash = _get_last_hash
        $json = ($entry | ConvertTo-Json -Compress)
        $entryHash = _sha256_hex $json
        $encB64 = _dpapi_protect $json
        [System.IO.File]::AppendAllText($LogFile, ($entryHash + ":" + $encB64 + "`r`n"))
    }

    function _suggest_if_denied([int]$exitCode, [string]$output) {
        $low = ($output | Out-String).ToLowerInvariant()
        if ($exitCode -eq 5 -or $exitCode -eq 740 -or $low -match 'access is denied|denied\.|requires elevation|must be run from|privilege') {
            Write-Host "[windo] Hint: Access was denied or blocked. Check paths and ACLs; run 'windo doctor'. If tasks are missing, re-run the installer elevated once. Elevation remains deliberate â€” WINDO does not auto-elevate your interactive shell." -ForegroundColor DarkYellow
        }
    }

    function _pretty_print([string]$cmdLine, [int]$exitCode, [string]$output, [int]$durationMs) {
        $output = ($output | Out-String).TrimEnd()
        $policy = _windo_resolve_output_policy
        if ($policy.mode -eq "quiet") {
            if (-not [string]::IsNullOrWhiteSpace($output)) { Write-Host $output }
            _suggest_if_denied $exitCode $output
            return
        }
        if ($policy.mode -eq "legacy") {
            Write-Host "[windo v$WindoVersion] $cmdLine" -ForegroundColor Cyan
            if ($exitCode -eq 0) { Write-Host "[windo] Status: SUCCESS" -ForegroundColor Green }
            else { Write-Host "[windo] Status: ERROR ($exitCode)" -ForegroundColor Red }
            Write-Host "[windo] Duration: ${durationMs}ms" -ForegroundColor DarkGray
            if ([string]::IsNullOrWhiteSpace($output)) { Write-Host "[windo] Output: <no output>" -ForegroundColor DarkGray }
            else { Write-Host "[windo] Output:" -ForegroundColor Yellow; Write-Host $output }
            _suggest_if_denied $exitCode $output
            return
        }
        $status = if ($exitCode -eq 0) { "OK" } else { "ERR $exitCode" }
        $color = if ($exitCode -eq 0) { "Green" } else { "Red" }
        $outTag = if ([string]::IsNullOrWhiteSpace($output)) { "no output" } else { "output follows" }
        Write-Host ("[windo] {0} {1}ms :: {2} :: {3}" -f $status, $durationMs, $cmdLine, $outTag) -ForegroundColor $color
        if (-not [string]::IsNullOrWhiteSpace($output)) { Write-Host $output }
        _suggest_if_denied $exitCode $output
    }

    function _html_escape([string]$s) {
        if ($null -eq $s) { return '' }
        ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
    }

    function _parse_log_entries {
        $list = [System.Collections.ArrayList]@()
        if (!(Test-Path $LogFile)) { return @() }
        foreach ($line in @(Get-Content -Path $LogFile)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Split(":", 2)
            if ($parts.Count -lt 2) { continue }
            try {
                $json = _dpapi_unprotect $parts[1]
                $obj = $json | ConvertFrom-Json
                [void]$list.Add($obj)
            } catch { }
        }
        return @($list)
    }

    function _warn_if_tampered {
        $i = _integrity_status
        if ($i.OverallLevel -ne "OK") {
            Write-Host "[windo] WARNING: integrity state: $($i.OverallLevel)" -ForegroundColor Red
            Write-Host "  runner : $($i.RunnerLevel)  self-update : $($i.UpdaterLevel)" -ForegroundColor Red
            Write-Host "  Run: windo integrity" -ForegroundColor Yellow
        }
    }

    # Injected by installer: same verb list as $WindoBuiltinVerbs in windo_install.ps1 (completer adds '!!' separately).
    function _windo_builtin_subcommands {
        [string[]]@(__WINDO_BUILTIN_ARRAY__)
    }

    function _windo_log_line_count([string]$path) {
        if (!(Test-Path $path)) { return 0 }
        $n = 0
        $sr = [System.IO.StreamReader]::new($path)
        try { while ($null -ne $sr.ReadLine()) { $n++ } } finally { $sr.Close() }
        return $n
    }

    function _redact_export_string([string]$s) {
        if ([string]::IsNullOrEmpty($s)) { return $s }
        $x = $s -replace '(?i)(?<![\w.])([a-z]:\\(?:[^\\/:*?"<>|\x00-\x1F]+\\)*[^\\/:*?"<>|\x00-\x1F]+)', '[PATH]'
        $x = $x -replace '(?i)(\\\\[^\s;|]+)', '[PATH]'
        return $x
    }

    function _redact_export_deep($o) {
        if ($null -eq $o) { return $null }
        if ($o -is [string]) { return (_redact_export_string $o) }
        if ($o -is [hashtable]) {
            $n = @{}
            foreach ($k in $o.Keys) { $n[$k] = _redact_export_deep $o[$k] }
            return $n
        }
        if ($o -is [System.Collections.IList] -and $o -isnot [string]) {
            $a = [System.Collections.ArrayList]@()
            foreach ($it in $o) { [void]$a.Add((_redact_export_deep $it)) }
            return @($a)
        }
        if ($o -is [pscustomobject]) {
            $h = [ordered]@{}
            foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = _redact_export_deep $p.Value }
            return [pscustomobject]$h
        }
        return $o
    }

    function _windo_max_command_chars {
        $d = 8191
        $raw = $env:WINDO_MAX_COMMAND_CHARS
        if ([string]::IsNullOrWhiteSpace($raw)) { return $d }
        try {
            $v = [int]$raw
            if ($v -lt 1) { return $d }
            if ($v -gt 8191) { return 8191 }
            return $v
        } catch { return $d }
    }

    function _windo_parse_timeout_override_ms {
        param([string]$Raw)
        if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
        $normalized = $Raw.Trim()
        $m = [regex]::Match($normalized, '^(?<value>\d+(?:\.\d+)?)\s*(?<unit>ms|s)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $m.Success) { return $null }
        try {
            $val = [double]$m.Groups['value'].Value
            $unit = $m.Groups['unit'].Value.ToLowerInvariant()
            if ($unit -eq 'ms') { return [int][Math]::Round($val) }
            return [int][Math]::Round($val * 1000)
        } catch { return $null }
    }

    function _windo_collect_env_snapshot {
        param([string[]]$Names)
        $snapshot = [ordered]@{}
        $namesOut = @()
        if ($null -eq $Names -or $Names.Count -eq 0) {
            foreach ($envRow in (Get-ChildItem Env:)) {
                if ($envRow.Name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
                    $snapshot[$envRow.Name] = [string]$envRow.Value
                }
            }
            return $snapshot
        }
        foreach ($name in $Names) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $namesOut += [string]$name
        }
        if ($namesOut.Count -eq 0) { return $snapshot }
        $seen = @{}
        foreach ($name in $namesOut) {
            $trimmed = $name.Trim()
            if ($trimmed -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
            if ($seen.ContainsKey($trimmed)) { continue }
            $seen[$trimmed] = $true
            $rawVal = [Environment]::GetEnvironmentVariable($trimmed, 'Process')
            if ($null -ne $rawVal) { $snapshot[$trimmed] = [string]$rawVal }
        }
        return $snapshot
    }

    function _windo_build_preserve_environment_payload {
        param([object]$Snapshot)
        if ($null -eq $Snapshot) { return $null }
        try {
            $json = $Snapshot | ConvertTo-Json -Depth 20 -Compress
            return [ordered]@{
                Version = 1
                Type    = "dpapi-json"
                Data    = _dpapi_protect $json
            }
        } catch {
            return $null
        }
    }

    # Keep aligned with windo_runner.ps1 and src/windo/snippets/WindoConfigEffective.ps1
    function _windo_effective_runner_timeout_ms {
        $d = 7200000
        $raw = $env:WINDO_RUNNER_TIMEOUT_MS
        if ([string]::IsNullOrWhiteSpace($raw)) { return $d }
        try {
            $v = [long]$raw
            if ($v -lt 1) { return $d }
            if ($v -gt 86400000) { return 86400000 }
            return [int]$v
        } catch { return $d }
    }

    function _windo_effective_runner_max_chars_per_stream {
        $d = 2097152
        $raw = $env:WINDO_RUNNER_MAX_OUTPUT_BYTES
        if ([string]::IsNullOrWhiteSpace($raw)) { return $d }
        try {
            $v = [long]$raw
            if ($v -lt 4096) { return [int][Math]::Max(512, $v / 2) }
            if ($v -gt 67108864) { return 33554432 }
            return [int]($v / 2)
        } catch { return $d }
    }

    function _windo_normalize_motion_mode([string]$Mode) {
        if ([string]::IsNullOrWhiteSpace($Mode)) { return "auto" }
        switch ($Mode.Trim().ToLowerInvariant()) {
            "auto" { return "auto" }
            "on" { return "on" }
            "enabled" { return "on" }
            "full" { return "on" }
            "off" { return "off" }
            "disabled" { return "off" }
            "quiet" { return "quiet" }
            "minimal" { return "quiet" }
            default { return "auto" }
        }
    }

    function _windo_normalize_motion_profile([string]$Profile) {
        if ([string]::IsNullOrWhiteSpace($Profile)) { return "auto" }
        switch ($Profile.Trim().ToLowerInvariant()) {
            "auto" { return "auto" }
            "off" { return "off" }
            "none" { return "off" }
            "subtle" { return "subtle" }
            "steady" { return "steady" }
            "standard" { return "standard" }
            "rich" { return "rich" }
            "ambient" { return "ambient" }
            "quiet" { return "ambient" }
            "minimal" { return "ambient" }
            "burst" { return "burst" }
            "cinematic" { return "cinematic" }
            "full" { return "rich" }
            default { return "auto" }
        }
    }

    function _windo_motion_profile_definition([string]$Profile) {
        switch (_windo_normalize_motion_profile $Profile) {
            "off" { return @{ frames = @(); intervalMs = 0; colors = @(); clearWidth = 0; usesColor = $false } }
            "ambient" { return @{ frames = @(".", " "); intervalMs = 170; colors = @("DarkGray"); clearWidth = 84; usesColor = $false } }
            "subtle" { return @{ frames = @(".", "o", "O", "o"); intervalMs = 140; colors = @("Gray", "DarkGray"); clearWidth = 90; usesColor = $false } }
            "steady" { return @{ frames = @("|", "-", "|", "-", "=", "-", "|", "-", "/"); intervalMs = 180; colors = @("Gray", "DarkGray"); clearWidth = 102; usesColor = $false } }
            "standard" { return @{ frames = @("|", "/", "-", "\"); intervalMs = 110; colors = @("Cyan"); clearWidth = 112; usesColor = $false } }
            "rich" { return @{ frames = @("|", "/", "-", "\", "=", "â‰¡"); intervalMs = 80; colors = @("Cyan", "Blue", "Magenta", "DarkCyan"); clearWidth = 118; usesColor = $true } }
            "burst" { return @{ frames = @(">", ">>", ">>>", " >>", "  >", " >"); intervalMs = 70; colors = @("Cyan", "Blue", "Cyan", "White", "Blue"); clearWidth = 120; usesColor = $true } }
            "cinematic" { return @{ frames = @("[=    ]", "[ =   ]", "[  =  ]", "[   = ]", "[    =]", "[   = ]", "[  =  ]", "[ =   ]"); intervalMs = 75; colors = @("Cyan", "Blue", "DarkCyan", "Cyan", "DarkCyan", "Blue", "Cyan", "White"); clearWidth = 132; usesColor = $true } }
            default { return @{ frames = @("|", "/", "-", "\"); intervalMs = 110; colors = @("Cyan"); clearWidth = 112; usesColor = $false } }
        }
    }

    function _windo_motion_frames([string]$Profile) {
        return @(_windo_motion_profile_definition $Profile).frames
    }

    function _windo_motion_interval_ms([string]$Profile) {
        return [int](_windo_motion_profile_definition $Profile).intervalMs
    }

    function _windo_resolve_motion_profile_name {
        param(
            [pscustomobject]$Plan,
            [string]$Context = "dispatch",
            [string]$RequestedProfile = "auto"
        )
        $policy = _windo_resolve_motion_policy
        if (-not [bool]$policy.enabled) { return "off" }

        if ([string]::IsNullOrWhiteSpace($RequestedProfile)) { $RequestedProfile = "auto" }
        $requested = _windo_normalize_motion_profile $RequestedProfile
        if ($requested -ne "auto") { return $requested }

        $hint = if ($Plan -and [string]::IsNullOrWhiteSpace([string]$Plan.motionProfileHint) -eq $false) { [string]$Plan.motionProfileHint } else { "auto" }
        $hintProfile = _windo_normalize_motion_profile $hint
        if ($hintProfile -ne "auto") { return $hintProfile }

        $isLong = $false
        if ($Context -in @("self-update", "elevated-result", "installer-update")) { $isLong = $true }
        if ($Plan -and [string]$Plan.estimatedDurationClass -eq "long") { $isLong = $true }
        if ($Plan -and [string]$Plan.motionContext -eq "installer-update") { $isLong = $true }

        if ($isLong) { return "standard" }

        switch ($Context.ToLowerInvariant()) {
            "surface" { return "burst" }
            "control" { return "burst" }
            "studio" { return "burst" }
            "center" { return "standard" }
            "motion" { return "rich" }
            "edition" { return "standard" }
            "installer-update" { return "cinematic" }
            default { return "ambient" }
        }
    }

    function _windo_resolve_motion_policy {
        $pref = _read_windo_prefs
        $prefMode = $null
        if ($pref -and $pref.PSObject.Properties.Name -contains 'motionMode') { $prefMode = [string]$pref.motionMode }
        $prefProfile = $null
        if ($pref -and $pref.PSObject.Properties.Name -contains 'motionProfile') { $prefProfile = [string]$pref.motionProfile }
        $envMode = [string]$env:WINDO_MOTION
        $envProfile = [string]$env:WINDO_MOTION_PROFILE
        $reducedMotionRaw = [string]$env:WINDO_REDUCED_MOTION
        $raw = "auto"
        $source = "default"
        if (-not [string]::IsNullOrWhiteSpace($prefMode)) {
            $raw = $prefMode
            $source = "prefs"
        }
        if (-not [string]::IsNullOrWhiteSpace($envMode)) {
            $raw = $envMode
            $source = "env"
        }
        $mode = _windo_normalize_motion_mode $raw
        $profileRaw = "auto"
        $profileSource = "default"
        if (-not [string]::IsNullOrWhiteSpace($prefProfile)) {
            $profileRaw = $prefProfile
            $profileSource = "prefs"
        }
        if (-not [string]::IsNullOrWhiteSpace($envProfile)) {
            $profileRaw = $envProfile
            $profileSource = "env"
        }
        $motionProfile = _windo_normalize_motion_profile $profileRaw
        $interactive = $false
        try { $interactive = (-not [Console]::IsOutputRedirected) } catch { $interactive = $false }
        $enabled = $false
        if ($mode -eq "on") { $enabled = $true }
        elseif ($mode -eq "auto") { $enabled = ($interactive -and -not $env:CI -and -not $env:WINDO_NO_SPINNER -and -not (_windo_parse_bool_value $reducedMotionRaw $false)) }
        elseif ($mode -eq "quiet") { $enabled = $false }
        $effectiveProfile = $motionProfile
        if (-not $enabled) { $effectiveProfile = "off" }
        if ($mode -eq "off") { $effectiveProfile = "off" }
        [pscustomobject]@{
            mode = $mode
            source = $source
            enabled = [bool]$enabled
            interactive = [bool]$interactive
            environmentValue = $(if ([string]::IsNullOrWhiteSpace($envMode)) { $null } else { $envMode.Trim() })
            preferenceValue = $(if ([string]::IsNullOrWhiteSpace($prefMode)) { $null } else { $prefMode.Trim() })
            motionProfile = [string]$effectiveProfile
            motionProfileRequested = [string]$motionProfile
            motionProfileSource = [string]$profileSource
            prefsFile = $PrefsFile
            reducedMotion = [bool](_windo_parse_bool_value $reducedMotionRaw $false)
            description = $(switch ($mode) {
                "auto" { "Animate interactive terminal waits only; disabled for CI, redirected output, and WINDO_NO_SPINNER." }
                "on" { "Use terminal motion when possible, while still respecting non-interactive host failures." }
                "quiet" { "Keep compact output but suppress decorative terminal motion." }
                "off" { "Disable WINDO terminal motion." }
            })
        }
    }

    function _windo_motion_animate([string]$Label = "[windo] motion", [int]$Milliseconds = 850, [string]$Profile = "ambient", [bool]$UseColors = $false) {
        $policy = _windo_resolve_motion_policy
        if (-not $policy.enabled) { return $false }
        if ([string]::IsNullOrWhiteSpace($Label) -or $Milliseconds -le 0) { return $false }

        $effective = _windo_resolve_motion_profile_name -RequestedProfile $Profile
        $spec = _windo_motion_profile_definition $effective
        $frames = @($spec.frames)
        if ($frames.Count -eq 0) { return $false }

        $colors = @($spec.colors)
        $interval = [Math]::Max(40, [Math]::Min(200, [int]$spec.intervalMs))
        $clearWidth = [Math]::Max(16, [Math]::Min([int]$spec.clearWidth, 140))
        if (-not $UseColors) { $UseColors = ($spec.usesColor -and $colors.Count -gt 0) }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $i = 0
        while ($sw.ElapsedMilliseconds -lt $Milliseconds) {
            $frame = [string]$frames[$i % $frames.Count]
            if ($UseColors) { Write-Host -NoNewline ("`r{0} {1} " -f $Label, $frame) -ForegroundColor [string]$colors[$i % $colors.Count] }
            else { [Console]::Write(("`r{0} {1} " -f $Label, $frame)) }
            $i++
            Start-Sleep -Milliseconds $interval
        }

        [Console]::Write("`r$(' ' * $clearWidth)`r")
        return $true
    }

    function _windo_motion_pulse([string]$Label = "[windo] motion", [int]$Milliseconds = 850, [string]$Profile = "ambient") {
        return _windo_motion_animate -Label $Label -Milliseconds $Milliseconds -Profile $Profile -UseColors $false
    }

    function _windo_motion_edition([string]$Label = "[windo] command center", [int]$Milliseconds = 1400) {
        return _windo_motion_animate -Label $Label -Milliseconds $Milliseconds -Profile "cinematic" -UseColors $true
    }

    function _windo_validate_elevated_command([string]$cmdLine) {
        $max = _windo_max_command_chars
        if ([string]::IsNullOrWhiteSpace($cmdLine)) { return "Command is empty." }
        if ($cmdLine.Length -gt $max) { return "Command exceeds max length ($max) (see WINDO_MAX_COMMAND_CHARS)." }
        foreach ($ch in $cmdLine.ToCharArray()) {
            $c = [int][char]$ch
            if ($c -eq 9) { continue }
            if ($c -lt 32) { return "Command contains disallowed control characters." }
        }
        return $null
    }

    function _windo_spinner_enabled {
        $policy = _windo_resolve_motion_policy
        return ([bool]$policy.enabled -and [string]$policy.motionProfile -ne "off")
    }

    function _windo_clear_spinner_line([int]$Width) {
        if (-not (_windo_spinner_enabled)) { return }
        $w = [Math]::Max(20, [Math]::Min($Width, 120))
        [Console]::Write("`r$(' ' * $w)`r")
    }

    function _windo_spinner_line([string]$Label, [int]$Frame, [string]$Profile = "auto") {
        if (-not (_windo_spinner_enabled)) { return }
        $effective = _windo_resolve_motion_profile_name -RequestedProfile $Profile
        if ($effective -eq "off") { return }
        $def = _windo_motion_profile_definition $effective
        $frames = @($def.frames)
        if ($frames.Count -eq 0) { return }
        $c = $frames[$Frame % $frames.Count]
        if ($def.usesColor -and $def.colors.Count -gt 0) {
            Write-Host -NoNewline ("`r{0} {1} " -f $Label, $c) -ForegroundColor [string]$def.colors[$Frame % $def.colors.Count]
        } else {
            [Console]::Write("`r${Label} ${c} ")
        }
    }

    function _windo_invoke_rest_with_spinner {
        param(
            [Parameter(Mandatory)][string]$Uri,
            [Parameter(Mandatory)][string]$OutFile,
            [Parameter(Mandatory)][string]$Label,
            [string]$Profile = "standard",
            [string]$Context = "download"
        )
        $baseLabel = "[windo] $Label"
        $effectiveProfile = _windo_resolve_motion_profile_name -Context $Context -RequestedProfile $Profile

        if (-not (_windo_spinner_enabled) -or $effectiveProfile -eq "off") {
            Write-Host $baseLabel -ForegroundColor Cyan
            Invoke-RestMethod -Uri $Uri -OutFile $OutFile
            return
        }

        $job = $null
        try {
            $job = Start-Job -ScriptBlock {
                param($u, $o)
                $ErrorActionPreference = "Stop"
                Invoke-RestMethod -Uri $u -OutFile $o
            } -ArgumentList $Uri, $OutFile
        } catch {
            $job = $null
        }

        if ($null -eq $job) {
            Write-Host $baseLabel -ForegroundColor Cyan
            Invoke-RestMethod -Uri $Uri -OutFile $OutFile
            return
        }

        $frame = 0
        while ((Get-Job -Id $job.Id -ErrorAction SilentlyContinue).State -eq "Running") {
            _windo_spinner_line $baseLabel $frame $effectiveProfile
            $frame = ($frame + 1) % 4
            Start-Sleep -Milliseconds (_windo_motion_interval_ms $effectiveProfile)
        }

        _windo_clear_spinner_line ($baseLabel.Length + 4)

        try {
            Receive-Job $job -ErrorAction Stop | Out-Null
        } catch {
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            throw
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }

    function _windo_release_branch {
        if (-not [string]::IsNullOrWhiteSpace($env:WINDO_TRACKING_BRANCH)) { return [string]$env:WINDO_TRACKING_BRANCH }
        return "v6"
    }

    function _windo_is_retryable_web_error {
        param([System.Management.Automation.ErrorRecord]$ErrorRecord)
        if ($null -eq $ErrorRecord) { return $false }
        $msg = $ErrorRecord.Exception.Message
        if ($msg -match 'timeout|timed out|name resolution|Could not establish trust relationship|name not known|No such host|connection was aborted|The remote name could not be resolved') { return $true }
        $resp = $ErrorRecord.Exception.Response
        if ($null -ne $resp) {
            try {
                $status = [int]$resp.StatusCode
                return ($status -in @(429, 500, 502, 503, 504))
            } catch { }
        }
        return $false
    }

    $script:_windo_retry_delays_ms = @(250, 850, 2200)

    function _windo_installer_raw_url {
        $branch = _windo_release_branch
        return "https://raw.githubusercontent.com/l28bit/windo/$branch/windo_install.ps1"
    }

    function _windo_installer_api_url {
        $branch = _windo_release_branch
        return "https://api.github.com/repos/l28bit/windo/contents/windo_install.ps1?ref=$branch"
    }

    function _windo_extract_installer_version([string]$Text) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        $m = [regex]::Match($Text, '\$WindoVersion\s*=\s*"(?<v>\d+\.\d+\.\d+)"')
        if ($m.Success) { return $m.Groups['v'].Value }
        return $null
    }

    function _windo_get_published_installer_text {
        $apiUrl = _windo_installer_api_url
        $apiError = $null

        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $resp = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 35 -ErrorAction Stop
                $obj = $resp.Content | ConvertFrom-Json -ErrorAction Stop
                if ($obj.content) {
                    $bytes = [Convert]::FromBase64String(([string]$obj.content -replace '\s', ''))
                    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                    return [pscustomobject]@{ status = "available"; source = "github-api"; url = $apiUrl; text = $text; bytes = $bytes; version = (_windo_extract_installer_version $text); error = $null; attempt = $attempt }
                }
                throw "Installer API response did not include file content."
            } catch {
                $apiError = $_.Exception.Message
                if (-not (_windo_is_retryable_web_error $_) -or $attempt -ge 3) {
                    break
                }
                Start-Sleep -Milliseconds $script:_windo_retry_delays_ms[[Math]::Min($attempt - 1, 2)]
            }
        }

        $rawUrl = _windo_installer_raw_url
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $tmpFile = Join-Path $env:TEMP ("windo_install_raw_" + [Guid]::NewGuid().ToString("n") + ".ps1")
            try {
                Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 35 -OutFile $tmpFile -ErrorAction Stop
                $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                return [pscustomobject]@{ status = "available"; source = "raw-fallback"; url = $rawUrl; text = $text; bytes = $bytes; version = (_windo_extract_installer_version $text); error = $apiError; attempt = $attempt }
            } catch {
                if (-not (_windo_is_retryable_web_error $_) -or $attempt -ge 3) {
                    $msg = $_.Exception.Message
                    if ($apiError) { $msg = "github-api: $apiError; raw: $msg" }
                    return [pscustomobject]@{ status = "unavailable"; source = "none"; url = $rawUrl; text = $null; bytes = $null; version = $null; error = $msg; attempt = $attempt }
                }
                Start-Sleep -Milliseconds $script:_windo_retry_delays_ms[[Math]::Min($attempt - 1, 2)]
            } finally {
                if (Test-Path -LiteralPath $tmpFile -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
            }
        }

        return [pscustomobject]@{ status = "unavailable"; source = "none"; url = $rawUrl; text = $null; bytes = $null; version = $null; error = "failed to download installer metadata."; attempt = 3 }
    }

    function _windo_save_published_installer {
        param([Parameter(Mandatory)][string]$Path)
        $published = _windo_get_published_installer_text
        if ($published.status -ne "available" -or $null -eq $published.bytes) {
            throw "Published installer was not available. $($published.error)"
        }
        [System.IO.File]::WriteAllBytes($Path, [byte[]]$published.bytes)
        return $published
    }

    function _windo_normalize_published_installer_sha256([string]$Text) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        $candidates = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($Text -split "`r?`n")) {
            $trim = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) { continue }

            if ($trim -match '^[^=]+?=([A-Fa-f0-9]{64})$') {
                $null = $candidates.Add($matches[1].ToUpperInvariant())
                continue
            }
            if ($trim -match '^([A-Fa-f0-9]{64})\s*$') {
                $null = $candidates.Add($matches[1].ToUpperInvariant())
                continue
            }
            if ($trim -match '^([A-Fa-f0-9]{64})\s+\S+$') {
                $null = $candidates.Add($matches[1].ToUpperInvariant())
                continue
            }
            if ($trim -match '^\S+\s+([A-Fa-f0-9]{64})$') {
                $null = $candidates.Add($matches[1].ToUpperInvariant())
                continue
            }

            if ($trim -match '[A-Fa-f0-9]{64}') { return $null }
        }

        if ($candidates.Count -eq 1) { return $candidates[0].ToUpperInvariant() }
        return $null
    }

    function _windo_installer_checksum_raw_url {
        $branch = _windo_release_branch
        return "https://raw.githubusercontent.com/l28bit/windo/$branch/checksums/installer.sha256"
    }

    function _windo_installer_checksum_api_url {
        $branch = _windo_release_branch
        return "https://api.github.com/repos/l28bit/windo/contents/checksums/installer.sha256?ref=$branch"
    }

    function _windo_read_checksum_from_github_contents([string]$Url) {
        $apiError = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
                $obj = $resp.Content | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $obj -or [string]::IsNullOrWhiteSpace([string]$obj.content)) { return $null }
                $base64 = ([string]$obj.content -replace '\s', '')
                $text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
                return (_windo_normalize_published_installer_sha256 $text)
            } catch {
                $apiError = $_.Exception.Message
                if (-not (_windo_is_retryable_web_error $_) -or $attempt -ge 3) { break }
                Start-Sleep -Milliseconds $script:_windo_retry_delays_ms[[Math]::Min($attempt - 1, 2)]
            }
        }
        throw $apiError
    }

    function _windo_get_published_installer_sha256 {
        $apiUrl = _windo_installer_checksum_api_url
        try {
            $sha = _windo_read_checksum_from_github_contents $apiUrl
            if (_is_sha256_hex $sha) {
                return [pscustomobject]@{ status = "available"; source = "github-api"; url = $apiUrl; sha256 = $sha; error = $null }
            }
            return [pscustomobject]@{ status = "invalid"; source = "github-api"; url = $apiUrl; sha256 = $sha; error = "published checksum was reachable but did not contain a valid SHA256" }
        } catch {
            $apiError = $_.Exception.Message
        }

        $rawUrl = _windo_installer_checksum_raw_url
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $resp = Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
                $sha = _windo_normalize_published_installer_sha256 ([string]$resp.Content)
                if (_is_sha256_hex $sha) {
                    return [pscustomobject]@{ status = "available"; source = "raw-fallback"; url = $rawUrl; sha256 = $sha; error = $null }
                }
                return [pscustomobject]@{ status = "invalid"; source = "raw-fallback"; url = $rawUrl; sha256 = $sha; error = "published checksum was reachable but did not contain a valid SHA256" }
            } catch {
                if (-not (_windo_is_retryable_web_error $_) -or $attempt -ge 3) {
                    $msg = $_.Exception.Message
                    if ($apiError) { $msg = "github-api: $apiError; raw: $msg" }
                    return [pscustomobject]@{ status = "unavailable"; source = "none"; url = $rawUrl; sha256 = $null; error = $msg }
                }
                Start-Sleep -Milliseconds $script:_windo_retry_delays_ms[[Math]::Min($attempt - 1, 2)]
            }
        }
        return [pscustomobject]@{ status = "unavailable"; source = "none"; url = $rawUrl; sha256 = $null; error = $apiError }
    }

    function _windo_verify_installer_sha256_optional([string]$Path) {
        if (_windo_parse_bool_value $env:WINDO_SKIP_INSTALLER_SHA256 -Default $false) { return }
        if (!(Test-Path $Path)) { return }
        $published = _windo_get_published_installer_sha256
        $expect = $published.sha256
        if ($null -eq $expect) { return }
        $got = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($got -cne $expect) {
            throw "Installer SHA256 does not match published checksum (branch $(_windo_release_branch)). Set `$env:WINDO_SKIP_INSTALLER_SHA256=1 to skip. Expected=$expect Got=$got"
        }
    }

    function _windo_keybindings_safe_reset_apply {
        $map = _windo_read_windo_prefs_map
        $map['keybindingPrefixChord'] = "Alt+w"
        $map['keybindingDisabled'] = $false
        if (-not (_windo_save_windo_prefs $map)) {
            return @{ ok = $false; error = "could not update $PrefsFile" }
        }
        _windo_apply_runtime_keybindings | Out-Null
        return @{ ok = $true; policy = (_windo_resolve_keybinding_policy) }
    }

    # Time filter: keep in sync with src/windo/snippets/StatsTimeFilter.ps1 (Test-WindoLogic covers the snippet).
    function _windo_filter_entries_by_time($entries, $sinceDate, $lastDays) {
        $cutoff = $null
        if ($null -ne $sinceDate) {
            $cutoff = $sinceDate.Date
        } elseif ($null -ne $lastDays -and [int]$lastDays -gt 0) {
            $cutoff = (Get-Date).Date.AddDays(-[int]$lastDays)
        }
        if ($null -eq $cutoff) { return ,@($entries) }
        $out = [System.Collections.ArrayList]@()
        foreach ($e in $entries) {
            try {
                $ts = [DateTime]::Parse([string]$e.Timestamp, [System.Globalization.CultureInfo]::InvariantCulture)
                if ($ts -ge $cutoff) { [void]$out.Add($e) }
            } catch { }
        }
        return ,@($out)
    }

    function _windo_audit_category($entry) {
        try { $ec = [int]$entry.ExitCode } catch { $ec = -999 }
        if ($entry.PSObject.Properties.Name -contains 'Elevation' -and [string]$entry.Elevation -eq 'FAILED') { return 'ELEVATION_FAILED' }
        if ($ec -eq 0) { return 'SUCCESS' }
        if ($ec -ne -999) { return 'NONZERO' }
        return 'OTHER'
    }

    function _windo_text_bar([int]$Value, [int]$Max, [int]$Width = 24) {
        if ($Width -lt 1) { $Width = 1 }
        if ($Max -lt 1) { $Max = 1 }
        if ($Value -lt 0) { $Value = 0 }
        $filled = [Math]::Min($Width, [Math]::Round(($Value / [double]$Max) * $Width))
        return ('#' * $filled).PadRight($Width, '.')
    }

    function _windo_verify_log_state {
        if (!(Test-Path $LogFile)) {
            return [pscustomobject]@{ verifyOk = $false; physicalLines = 0; exitCode = 2; error = "no log file"; failureLine = $null }
        }
        $lines = @(Get-Content -Path $LogFile)
        if ($lines.Count -eq 0) {
            return [pscustomobject]@{ verifyOk = $false; physicalLines = 0; exitCode = 2; error = "log empty"; failureLine = $null }
        }
        $ok = $true
        $prevStoredHash = ""
        $err = $null
        $failureLine = $null
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Split(":", 2)
            if ($parts.Count -lt 2) { $ok = $false; $err = "invalid format"; $failureLine = $i + 1; break }
            $storedHash = $parts[0]
            $b64 = $parts[1]
            try { $json = _dpapi_unprotect $b64 } catch { $ok = $false; $err = "decrypt failed"; $failureLine = $i + 1; break }
            $calc = _sha256_hex $json
            if ($calc -ne $storedHash) { $ok = $false; $err = "hash mismatch"; $failureLine = $i + 1; break }
            try { $obj = $json | ConvertFrom-Json } catch { $obj = $null }
            if ($i -gt 0) {
                if (-not $obj -or -not ($obj.PSObject.Properties.Name -contains "PreviousHash")) { $ok = $false; $err = "missing PreviousHash"; $failureLine = $i + 1; break }
                if ([string]$obj.PreviousHash -ne $prevStoredHash) { $ok = $false; $err = "chain break"; $failureLine = $i + 1; break }
            }
            $prevStoredHash = $storedHash
        }
        $vfExit = 0
        if (-not $ok) { $vfExit = 4 }
        return [pscustomobject]@{ verifyOk = $ok; physicalLines = $lines.Count; exitCode = $vfExit; error = $err; failureLine = $failureLine }
    }

    function _windo_new_check_row([string]$Id, [string]$Label, [bool]$Ok, [string]$Detail, [string]$FixCommand = "", [string]$Severity = "info") {
        return [pscustomobject]@{
            id = $Id
            label = $Label
            ok = [bool]$Ok
            severity = $Severity
            detail = $Detail
            fixCommand = $FixCommand
        }
    }

    function _windo_preflight_rows {
        $rows = [System.Collections.ArrayList]@()
        $isElev = _windo_is_process_elevated
        [void]$rows.Add((_windo_new_check_row "shell-elevation" "Current shell is non-elevated" (-not $isElev) $(if ($isElev) { "High-privilege shell; remote update downloads are blocked by policy." } else { "Good for install-latest/bootstrap download safety." }) "Start a normal PowerShell window, then run: windo install-latest" $(if ($isElev) { "warn" } else { "info" })))

        $psMajor = 0
        try { $psMajor = [int]$PSVersionTable.PSVersion.Major } catch {}
        [void]$rows.Add((_windo_new_check_row "powershell-version" "PowerShell runtime" ($psMajor -ge 5) ("$($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)") "Install PowerShell 7 for best terminal experience: winget install Microsoft.PowerShell" $(if ($psMajor -ge 5) { "info" } else { "critical" })))

        $mt = $false; $ut = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mt = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $ut = $true } catch {}
        [void]$rows.Add((_windo_new_check_row "task-main" "Elevated runner task" $mt $(if ($mt) { "Task present: $TaskName" } else { "Missing task: $TaskName" }) "Run installer from an elevated PowerShell session: .\windo_install.ps1" $(if ($mt) { "info" } else { "critical" })))
        [void]$rows.Add((_windo_new_check_row "task-update" "Self-update task" $ut $(if ($ut) { "Task present: $TaskUpdate" } else { "Missing task: $TaskUpdate" }) "Run installer from an elevated PowerShell session: .\windo_install.ps1" $(if ($ut) { "info" } else { "warn" })))

        $ix = _integrity_status
        [void]$rows.Add((_windo_new_check_row "integrity" "Runner integrity" ($ix.OverallLevel -eq 'OK') ("overall=$($ix.OverallLevel), runner=$($ix.RunnerLevel), updater=$($ix.UpdaterLevel)") "windo integrity" $(if ($ix.OverallLevel -eq 'OK') { "info" } else { "critical" })))

        $vf = _windo_verify_log_state
        [void]$rows.Add((_windo_new_check_row "audit-chain" "Audit chain" ([bool]$vf.verifyOk) $(if ($vf.verifyOk) { "chain OK, physical lines=$($vf.physicalLines)" } else { "$($vf.error), line=$($vf.failureLine)" }) "windo verify" $(if ($vf.verifyOk) { "info" } else { "warn" })))

        $profStatus = _windo_read_profile_windo_status ([string]$PROFILE)
        [void]$rows.Add((_windo_new_check_row "profile-block" "Current profile has WINDO block" ([bool]$profStatus.hasWindoBlock) $(if ($profStatus.hasWindoBlock) { "profile block found: $PROFILE" } else { "no WINDO block found in current profile" }) ". `$PROFILE; windo install-latest" $(if ($profStatus.hasWindoBlock) { "info" } else { "warn" })))

        $trust = _windo_trust_posture $false
        [void]$rows.Add((_windo_new_check_row "trust-posture" "Trust posture" ($trust.trustLevel -ne "REPAIR") ("level=$($trust.trustLevel), score=$($trust.score)") "windo trust" $(if ($trust.trustLevel -eq "TRUSTED") { "info" } elseif ($trust.trustLevel -eq "ATTENTION") { "warn" } else { "critical" })))

        $policy = _windo_resolve_keybinding_policy
        [void]$rows.Add((_windo_new_check_row "keybindings" "Keybinding policy" ([bool]$policy.enabled) $(if ($policy.enabled) { "enabled chord=$($policy.chord), fallback=$($policy.fallbackChord)" } else { "disabled" }) "windo keybindings safe-reset" $(if ($policy.enabled) { "info" } else { "warn" })))

        return @($rows.ToArray())
    }

    function _windo_installer_checksum_url {
        return (_windo_installer_checksum_api_url)
    }

    function _windo_trust_posture([bool]$Online) {
        $score = 100
        $recommendations = [System.Collections.ArrayList]@()
        $checks = [System.Collections.ArrayList]@()
        $isElev = _windo_is_process_elevated

        if ($isElev) {
            $score -= 10
            [void]$recommendations.Add("Use a normal non-elevated PowerShell window for install-latest and online checksum checks.")
        }
        [void]$checks.Add((_windo_new_check_row "shell-elevation" "Current shell is non-elevated" (-not $isElev) $(if ($isElev) { "elevated shell" } else { "non-elevated shell" }) "Start a normal PowerShell window" $(if ($isElev) { "warn" } else { "info" })))

        $mt = $false; $ut = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mt = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $ut = $true } catch {}
        if (-not $mt) { $score -= 25; [void]$recommendations.Add("Repair the elevated runner task by running the installer from an elevated PowerShell session.") }
        if (-not $ut) { $score -= 10; [void]$recommendations.Add("Repair the self-update task by running the installer from an elevated PowerShell session.") }
        [void]$checks.Add((_windo_new_check_row "task-main" "Elevated runner task" $mt $(if ($mt) { "present: $TaskName" } else { "missing: $TaskName" }) ".\windo_install.ps1" $(if ($mt) { "info" } else { "critical" })))
        [void]$checks.Add((_windo_new_check_row "task-update" "Self-update task" $ut $(if ($ut) { "present: $TaskUpdate" } else { "missing: $TaskUpdate" }) ".\windo_install.ps1" $(if ($ut) { "info" } else { "warn" })))

        $ix = _integrity_status
        if ($ix.OverallLevel -ne "OK") {
            if ($ix.OverallLevel -eq "TAMPERED") { $score -= 40 } else { $score -= 25 }
            [void]$recommendations.Add("Run windo integrity and reinstall if runner/updater hashes do not match the local manifest.")
        }
        [void]$checks.Add((_windo_new_check_row "runner-integrity" "Runner/updater integrity" ($ix.OverallLevel -eq "OK") ("overall=$($ix.OverallLevel), runner=$($ix.RunnerLevel), updater=$($ix.UpdaterLevel)") "windo integrity" $(if ($ix.OverallLevel -eq "OK") { "info" } elseif ($ix.OverallLevel -eq "TAMPERED") { "critical" } else { "warn" })))

        $vf = _windo_verify_log_state
        if (-not [bool]$vf.verifyOk) {
            $score -= 15
            [void]$recommendations.Add("Run windo verify and inspect audit-chain drift before relying on historical output.")
        }
        [void]$checks.Add((_windo_new_check_row "audit-chain" "Audit chain" ([bool]$vf.verifyOk) $(if ($vf.verifyOk) { "chain OK, physical lines=$($vf.physicalLines)" } else { "$($vf.error), line=$($vf.failureLine)" }) "windo verify" $(if ($vf.verifyOk) { "info" } else { "warn" })))

        $profStatus = _windo_read_profile_windo_status ([string]$PROFILE)
        if (-not [bool]$profStatus.hasWindoBlock) {
            $score -= 10
            [void]$recommendations.Add("Reload or reinstall the profile block so this host loads the current WINDO function.")
        }
        [void]$checks.Add((_windo_new_check_row "profile-block" "Current profile has WINDO block" ([bool]$profStatus.hasWindoBlock) $(if ($profStatus.hasWindoBlock) { "profile block found" } else { "profile block missing" }) ". `$PROFILE" $(if ($profStatus.hasWindoBlock) { "info" } else { "warn" })))

        $snapshotDir = Join-Path (Join-Path $HOME "Documents") "windo"
        $snapshotInstaller = Join-Path $snapshotDir "windo_install.ps1"
        $snapshotHash = $null
        $snapshotPresent = Test-Path -LiteralPath $snapshotInstaller
        if ($snapshotPresent) {
            $snapshotHash = _windo_published_text_file_sha256 $snapshotInstaller
        } else {
            $score -= 8
            [void]$recommendations.Add("Install or repair WINDO so Documents\windo\windo_install.ps1 exists as the local snapshot.")
        }

        $published = [pscustomobject]@{
            requested = [bool]$Online
            status = $(if ($Online) { "pending" } else { "not-requested" })
            url = (_windo_installer_checksum_url)
            source = $null
            sha256 = $null
            matchesSnapshot = $null
            error = $null
        }
        if ($Online) {
            if ($isElev) {
                $published.status = "blocked-elevated"
                $score -= 5
                [void]$recommendations.Add("Online checksum validation is blocked while elevated; rerun windo trust --online from a normal shell.")
            } else {
                $fetched = _windo_get_published_installer_sha256
                $published.status = $fetched.status
                $published.url = $fetched.url
                $published.source = $fetched.source
                $published.sha256 = $fetched.sha256
                $published.error = $fetched.error
                if ($published.status -eq "available" -and (_is_sha256_hex $published.sha256) -and $snapshotHash -and (_is_sha256_hex $snapshotHash)) {
                    $published.matchesSnapshot = ($snapshotHash -eq $published.sha256)
                    if (-not $published.matchesSnapshot) {
                        $score -= 35
                        [void]$recommendations.Add("Snapshot installer hash does not match the published checksum; run windo install-latest from a normal shell.")
                    }
                } elseif ($published.status -eq "available") {
                    $score -= 8
                    [void]$recommendations.Add("Published checksum was reachable but could not be normalized or compared to the local snapshot.")
                } else {
                    $score -= 5
                    [void]$recommendations.Add("Published checksum was not reachable; retry when network access is available.")
                }
            }
        }

        [void]$checks.Add((_windo_new_check_row "installer-snapshot" "Local installer snapshot" $snapshotPresent $(if ($snapshotPresent) { "publishedTextSha256=$snapshotHash" } else { "missing: $snapshotInstaller" }) "windo install-latest" $(if ($snapshotPresent) { "info" } else { "warn" })))
        if ($Online) {
            $checksumOk = ($published.status -eq "available" -and $published.matchesSnapshot -eq $true)
            [void]$checks.Add((_windo_new_check_row "published-checksum" "Published installer checksum" $checksumOk ("status=$($published.status), matchesSnapshot=$($published.matchesSnapshot)") "windo trust --online" $(if ($checksumOk) { "info" } elseif ($published.matchesSnapshot -eq $false) { "critical" } else { "warn" })))
        }

        if ($score -lt 0) { $score = 0 }
        $trustLevel = "TRUSTED"
        $exitCode = 0
        if ($score -lt 70 -or $ix.OverallLevel -eq "TAMPERED" -or ($published.matchesSnapshot -eq $false)) {
            $trustLevel = "REPAIR"
            $exitCode = 4
        } elseif ($score -lt 90 -or $ix.OverallLevel -ne "OK" -or (-not $mt)) {
            $trustLevel = "ATTENTION"
            $exitCode = 3
        }

        [pscustomobject]@{
            windoVersion = $WindoVersion
            trustLevel = $trustLevel
            score = $score
            exitCode = $exitCode
            online = [bool]$Online
            isElevated = $isElev
            checks = @($checks.ToArray())
            tasks = [pscustomobject]@{ main = $mt; update = $ut; mainName = $TaskName; updateName = $TaskUpdate }
            integrity = $ix
            audit = $vf
            profile = $profStatus
            completionPolicy = (_windo_resolve_completion_policy)
            installerSnapshot = [pscustomobject]@{ path = $snapshotInstaller; present = $snapshotPresent; sha256 = $snapshotHash }
            publishedChecksum = $published
            recommendations = @($recommendations.ToArray())
        }
    }

    function _windo_operator_actions {
        return @(
            [pscustomobject]@{ title = "Refresh profile"; command = ". `$PROFILE"; note = "Load the newest WINDO function in this shell." },
            [pscustomobject]@{ title = "Preflight"; command = "windo preflight"; note = "Readiness scan with fix commands." },
            [pscustomobject]@{ title = "Trust Console"; command = "windo trust"; note = "Local trust posture and checksum readiness." },
            [pscustomobject]@{ title = "Dashboard HTML"; command = "windo dashboard --html"; note = "Local visual health report." },
            [pscustomobject]@{ title = "Launchpad"; command = "windo launchpad --open"; note = "Open the V6 command center." },
            [pscustomobject]@{ title = "Integrity"; command = "windo integrity"; note = "Runner and updater file integrity." },
            [pscustomobject]@{ title = "Audit verify"; command = "windo verify"; note = "DPAPI audit line hash and chain verification." },
            [pscustomobject]@{ title = "Keybinding repair"; command = "windo repair"; note = "Safe-reset stuck prefix/keybinding state." },
            [pscustomobject]@{ title = "Safe upgrade"; command = "windo install-latest"; note = "Non-elevated verified download, then UAC install." }
        )
    }

    function _windo_source_status {
        $published = _windo_get_published_installer_text
        $checksum = _windo_get_published_installer_sha256
        $snapshotPath = Join-Path (Join-Path (Join-Path $HOME "Documents") "windo") "windo_install.ps1"
        $snapshotHash = $null
        $snapshotVersion = $null
        $snapshotPresent = Test-Path -LiteralPath $snapshotPath
        if ($snapshotPresent) {
            $snapshotHash = _windo_published_text_file_sha256 $snapshotPath
            try { $snapshotVersion = _windo_extract_installer_version (Get-Content -LiteralPath $snapshotPath -Raw -ErrorAction Stop) } catch { $snapshotVersion = $null }
        }
        $matchesPublished = $null
        if (_is_sha256_hex $snapshotHash -and _is_sha256_hex $checksum.sha256) {
            $matchesPublished = ($snapshotHash -eq $checksum.sha256)
        }
        $exit = if ($published.status -eq "available" -and $checksum.status -eq "available" -and $matchesPublished -ne $false) { 0 } else { 3 }
        [pscustomobject]@{
            windoVersion = $WindoVersion
            installedVersion = $WindoVersion
            publishedInstaller = [pscustomobject]@{
                status = $published.status
                source = $published.source
                url = $published.url
                version = $published.version
                error = $published.error
            }
            publishedChecksum = [pscustomobject]@{
                status = $checksum.status
                source = $checksum.source
                url = $checksum.url
                sha256 = $checksum.sha256
                error = $checksum.error
            }
            localSnapshot = [pscustomobject]@{
                path = $snapshotPath
                present = $snapshotPresent
                version = $snapshotVersion
                sha256 = $snapshotHash
                matchesPublishedChecksum = $matchesPublished
            }
            recommendation = $(if ($matchesPublished -eq $false) { "Run windo install-latest from a normal shell after published checksum updates." } elseif ($published.status -ne "available") { "Published installer was not reachable; retry network source check." } else { "Published source and local snapshot are aligned." })
            exitCode = $exit
        }
    }

    function _windo_brand_assets {
        $repoBrand = Join-Path $HOME "Documents\GitHub\windo\brand"
        $docBrand = Join-Path $HOME "Documents\windo\brand"
        $candidates = [ordered]@{
            banner = @(
                (Join-Path $repoBrand "assets\banners\banner-blue-left.png"),
                (Join-Path $docBrand "assets\banners\banner-blue-left.png")
            )
            logo = @(
                (Join-Path $repoBrand "Enterprise\assets\logo\windo-logo-full-dark-512.png"),
                (Join-Path $repoBrand "winDO.png"),
                (Join-Path $docBrand "Enterprise\assets\logo\windo-logo-full-dark-512.png"),
                (Join-Path $docBrand "winDO.png")
            )
            avatar = @(
                (Join-Path $repoBrand "assets\logos\transparent-github-avatar-panel.png"),
                (Join-Path $docBrand "assets\logos\transparent-github-avatar-panel.png")
            )
            mark = @(
                (Join-Path $repoBrand "Enterprise\assets\svg\windo-brand-mark-contained-dark.svg"),
                (Join-Path $docBrand "Enterprise\assets\svg\windo-brand-mark-contained-dark.svg")
            )
            iconReady = @(
                (Join-Path $repoBrand "Enterprise\assets\ico\windo-tray-ready.ico"),
                (Join-Path $docBrand "Enterprise\assets\ico\windo-tray-ready.ico")
            )
            iconWarning = @(
                (Join-Path $repoBrand "Enterprise\assets\ico\windo-tray-warning.ico"),
                (Join-Path $docBrand "Enterprise\assets\ico\windo-tray-warning.ico")
            )
            iconDenied = @(
                (Join-Path $repoBrand "Enterprise\assets\ico\windo-tray-denied.ico"),
                (Join-Path $docBrand "Enterprise\assets\ico\windo-tray-denied.ico")
            )
            iconElevated = @(
                (Join-Path $repoBrand "Enterprise\assets\ico\windo-tray-elevated.ico"),
                (Join-Path $docBrand "Enterprise\assets\ico\windo-tray-elevated.ico")
            )
            iconNeutral = @(
                (Join-Path $repoBrand "Enterprise\assets\ico\windo-tray-neutral.ico"),
                (Join-Path $docBrand "Enterprise\assets\ico\windo-tray-neutral.ico")
            )
            editionBadge = @(
                (Join-Path $repoBrand "assets\transparent\badges\wordmark-plate.png"),
                (Join-Path $repoBrand "assets\transparent\badges\brand-light.png"),
                (Join-Path $docBrand "assets\transparent\badges\wordmark-plate.png"),
                (Join-Path $docBrand "assets\transparent\badges\brand-light.png")
            )
        }
        $out = [ordered]@{}
        foreach ($key in $candidates.Keys) {
            $value = $null
            foreach ($p in @($candidates[$key])) {
                if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) { $value = $p; break }
            }
            $out[$key] = $value
        }
        return [pscustomobject]$out
    }

    function _windo_resolve_tray_icon([string]$Status = "ready") {
        if (-not [string]::IsNullOrWhiteSpace([string]$env:WINDO_TRAY_ICON) -and (Test-Path -LiteralPath ([string]$env:WINDO_TRAY_ICON))) {
            return [string]$env:WINDO_TRAY_ICON
        }
        $assets = _windo_brand_assets
        $key = switch -Regex ([string]$Status) {
            '^(ready|ok|success)$' { "iconReady"; break }
            '^(warn|warning|attention)$' { "iconWarning"; break }
            '^(fail|failed|error|repair|denied|critical)$' { "iconDenied"; break }
            '^(elevated|admin)$' { "iconElevated"; break }
            default { "iconNeutral" }
        }
        $value = [string]$assets.$key
        if (-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -LiteralPath $value)) { return $value }
        foreach ($fallback in @([string]$assets.iconReady, [string]$assets.iconWarning, [string]$assets.iconNeutral)) {
            if (-not [string]::IsNullOrWhiteSpace($fallback) -and (Test-Path -LiteralPath $fallback)) { return $fallback }
        }
        return $null
    }

    function _windo_html_img([string]$Path, [string]$Class, [string]$Alt) {
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return "" }
        return "<img class='$Class' alt='$(_html_escape $Alt)' src='$(_html_escape ([uri]$Path).AbsoluteUri)'>"
    }

    function _windo_edition_state {
        $assets = _windo_brand_assets
        $center = _windo_center_state
        [pscustomobject]@{
            windoVersion = $WindoVersion
            edition = "WINDO Command Center"
            generatedAt = (Get-Date).ToString("o")
            branch = "v6"
            assets = $assets
            center = $center
            control = $center.control
            signal = $center.signal
            motion = (_windo_resolve_motion_policy)
            commands = @("windo surface panel", "windo edition open", "windo center open", "windo center actions", "windo signal open", "windo control preview surface-panel")
            exitCode = $center.exitCode
        }
    }

    function _windo_write_edition_html([object]$Edition, [string]$OutputPath, [bool]$Open) {
        $sb = [System.Text.StringBuilder]::new()
        $banner = _windo_html_img ([string]$Edition.assets.banner) "banner" "WINDO banner"
        $logo = _windo_html_img ([string]$Edition.assets.logo) "logo" "WINDO logo"
        $avatar = _windo_html_img ([string]$Edition.assets.avatar) "avatar" "WINDO avatar"
        $badge = _windo_html_img ([string]$Edition.assets.editionBadge) "badge" "WINDO command center"
        $null = $sb.AppendLine("<!doctype html><html><head><meta charset='utf-8'><title>WINDO Command Center</title>")
        $null = $sb.AppendLine("<style>body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#070b14;color:#e5e7eb;overflow-x:hidden}.stage{max-width:1320px;margin:0 auto;padding:26px 24px 42px}.hero{position:relative;min-height:330px;border-bottom:1px solid #22314f;display:grid;grid-template-columns:minmax(280px,1fr) 330px;gap:28px;align-items:center}.hero:before{content:'';position:absolute;inset:0;background:linear-gradient(110deg,rgba(14,165,233,.18),transparent 48%,rgba(34,197,94,.10));pointer-events:none}.hero:after{content:'';position:absolute;left:0;right:0;top:0;height:2px;background:linear-gradient(90deg,transparent,#38bdf8,#22c55e,transparent);animation:sweep 2.8s linear infinite}.banner{max-width:760px;width:100%;height:auto;display:block}.logo{max-width:520px;width:82%;height:auto;margin-top:16px}.avatar{max-width:300px;width:100%;height:auto;filter:drop-shadow(0 0 24px rgba(56,189,248,.25))}.badge{max-width:210px;width:62%;height:auto;margin-top:14px}.eyebrow{color:#38bdf8;text-transform:uppercase;font-size:12px;letter-spacing:.12em}.title{font-size:46px;line-height:1.05;font-weight:800;margin:8px 0}.sub{max-width:760px;color:#a7b4c8;font-size:17px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;margin-top:24px}.card{background:#0f172a;border:1px solid #24324e;border-radius:8px;padding:16px;position:relative;overflow:hidden}.card:before{content:'';position:absolute;inset:0;border-top:1px solid rgba(56,189,248,.38);opacity:.65}.k{font-size:11px;color:#94a3b8;text-transform:uppercase}.v{font-size:28px;font-weight:800;margin-top:4px}.ok{color:#22c55e}.warn{color:#f59e0b}.muted{color:#94a3b8}.lane{margin-top:24px}.row{display:grid;grid-template-columns:180px 1fr;gap:12px;border-top:1px solid #1f2937;padding:10px 0}.cmd{font-family:Consolas,monospace;color:#bfdbfe;background:#020617;border:1px solid #24324e;border-radius:6px;padding:6px 8px;display:inline-block}@keyframes sweep{0%{transform:translateX(-100%)}100%{transform:translateX(100%)}}@media(max-width:820px){.hero{grid-template-columns:1fr}.title{font-size:34px}.avatar{max-width:190px}.row{grid-template-columns:1fr}}</style></head><body><div class='stage'>")
        $null = $sb.AppendLine(("<section class='hero'><div><div class='eyebrow'>{0}</div>{1}{2}<div class='title'>Command Center</div><div class='sub'>A local command surface for deliberate elevation, visible action routing, Signal Deck evidence, and native Windows tray flow.</div></div><div>{3}{4}</div></section>" -f (_html_escape $Edition.edition), $banner, $logo, $avatar, $badge))
        $statusClass = if ($Edition.center.status -eq "ready") { "ok" } else { "warn" }
        $null = $sb.AppendLine("<section class='grid'>")
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Center</div><div class='v {0}'>{1}</div><div class='muted'>queue {2} / requests {3}</div></div>" -f $statusClass, (_html_escape $Edition.center.status), $Edition.control.queuedCount, $Edition.control.requestCount))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Actions</div><div class='v'>{0}</div><div class='muted'>curated visible-shell commands</div></div>" -f @($Edition.control.actions).Count))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Motion</div><div class='v'>{0}</div><div class='muted'>enabled={1}</div></div>" -f (_html_escape $Edition.motion.mode), $Edition.motion.enabled))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Branch</div><div class='v'>v6</div><div class='muted'>v{0}</div></div>" -f (_html_escape $Edition.windoVersion)))
        $null = $sb.AppendLine("</section><section class='lane'><h2>Edition Commands</h2>")
        foreach ($cmd in @($Edition.commands)) { $null = $sb.AppendLine(("<div class='row'><div class='muted'>ready</div><div><span class='cmd'>{0}</span></div></div>" -f (_html_escape $cmd))) }
        $null = $sb.AppendLine("</section></div></body></html>")
        $dir = Split-Path -Parent $OutputPath
        if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
        if ($Open) { Start-Process -FilePath $OutputPath | Out-Null }
        return $OutputPath
    }

    function _windo_surface_panel_script_text {
        $text = @"
`$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
`$version = "__WINDO_VERSION__"
`$iconPath = "__WINDO_ICON_PATH__"
`$actions = @(
    @{ Title = "Center Status"; Command = "windo center status"; Tone = "cyan"; Note = "Current command-center posture." },
    @{ Title = "Open Tray"; Command = "windo center tray"; Tone = "cyan"; Note = "Start the persistent tray surface." },
    @{ Title = "Edition Console"; Command = "windo edition open"; Tone = "blue"; Note = "Open the command-center visual console." },
    @{ Title = "Dashboard HTML"; Command = "windo dashboard --html --open"; Tone = "blue"; Note = "Generate the local operator dashboard." },
    @{ Title = "Signal Deck"; Command = "windo signal open"; Tone = "green"; Note = "Open evidence-first diagnostics." },
    @{ Title = "Control Actions"; Command = "windo control actions"; Tone = "green"; Note = "List curated command-center actions." },
    @{ Title = "Control History"; Command = "windo control history"; Tone = "green"; Note = "Review request lifecycle history." },
    @{ Title = "Run Next Queued"; Command = "windo control execute-next"; Tone = "warn"; Note = "Explicitly launch the next queued action." },
    @{ Title = "Surface Doctor"; Command = "windo surface doctor"; Tone = "warn"; Note = "Check native readiness and profile health." },
    @{ Title = "Surface Repair"; Command = "windo surface repair"; Tone = "warn"; Note = "Refresh manifests and guarded prompt init." },
    @{ Title = "Motion Pulse"; Command = "windo motion pulse"; Tone = "blue"; Note = "Render motion when policy allows it." },
    @{ Title = "Install Latest"; Command = "windo install-latest"; Tone = "danger"; Note = "Run the verified update handoff." }
)
function Start-WindoPanelCommand([string]`$Command) {
    `$exe = "powershell.exe"
    `$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (`$pwsh -and `$pwsh.Source) { `$exe = `$pwsh.Source }
    Start-Process -FilePath `$exe -ArgumentList @("-NoExit", "-Command", `$Command) | Out-Null
}
function New-WindoLabel([string]`$Text, [int]`$X, [int]`$Y, [int]`$W, [int]`$H, [int]`$Size, [System.Drawing.Color]`$Color, [bool]`$Bold = `$false) {
    `$label = New-Object System.Windows.Forms.Label
    `$label.Text = `$Text
    `$label.Location = New-Object System.Drawing.Point(`$X, `$Y)
    `$label.Size = New-Object System.Drawing.Size(`$W, `$H)
    `$label.ForeColor = `$Color
    `$style = if (`$Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    `$label.Font = New-Object System.Drawing.Font("Segoe UI", `$Size, `$style)
    return `$label
}
function New-WindoButton([string]`$Text, [string]`$Command, [int]`$X, [int]`$Y, [int]`$W, [System.Drawing.Color]`$Color) {
    `$btn = New-Object System.Windows.Forms.Button
    `$btn.Text = `$Text
    `$btn.Tag = `$Command
    `$btn.Location = New-Object System.Drawing.Point(`$X, `$Y)
    `$btn.Size = New-Object System.Drawing.Size(`$W, 32)
    `$btn.BackColor = `$Color
    `$btn.ForeColor = [System.Drawing.Color]::White
    `$btn.FlatStyle = "Flat"
    `$btn.Add_Click({ Start-WindoPanelCommand ([string]`$this.Tag) })
    return `$btn
}
function Get-WindoTone([string]`$Tone) {
    switch (`$Tone) {
        "green" { return [System.Drawing.Color]::FromArgb(34, 197, 94) }
        "warn" { return [System.Drawing.Color]::FromArgb(245, 158, 11) }
        "danger" { return [System.Drawing.Color]::FromArgb(239, 68, 68) }
        "blue" { return [System.Drawing.Color]::FromArgb(37, 99, 235) }
        default { return [System.Drawing.Color]::FromArgb(14, 165, 233) }
    }
}
`$form = New-Object System.Windows.Forms.Form
`$form.Text = "WINDO Surface Panel"
`$form.Size = New-Object System.Drawing.Size(980, 740)
`$form.MinimumSize = New-Object System.Drawing.Size(860, 650)
`$form.StartPosition = "CenterScreen"
`$form.BackColor = [System.Drawing.Color]::FromArgb(7, 11, 20)
`$form.ForeColor = [System.Drawing.Color]::White
if (-not [string]::IsNullOrWhiteSpace(`$iconPath) -and (Test-Path -LiteralPath `$iconPath)) { `$form.Icon = New-Object System.Drawing.Icon(`$iconPath) }
`$form.Controls.Add((New-WindoLabel "WINDO Surface Panel" 28 20 560 42 24 ([System.Drawing.Color]::White) `$true))
`$form.Controls.Add((New-WindoLabel "WINDO Command Center - native Windows command surface - v`$version" 32 64 620 24 10 ([System.Drawing.Color]::FromArgb(56, 189, 248)) `$false))
`$form.Controls.Add((New-WindoLabel "Curated actions only. Commands open in visible PowerShell windows for inspectable output." 32 90 820 24 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$statusPanel = New-Object System.Windows.Forms.Panel
`$statusPanel.Location = New-Object System.Drawing.Point(28, 126)
`$statusPanel.Size = New-Object System.Drawing.Size(900, 86)
`$statusPanel.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
`$form.Controls.Add(`$statusPanel)
`$statusPanel.Controls.Add((New-WindoLabel "Native" 18 14 120 20 10 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$statusPanel.Controls.Add((New-WindoLabel "READY" 18 36 130 30 19 ([System.Drawing.Color]::FromArgb(34, 197, 94)) `$true))
`$statusPanel.Controls.Add((New-WindoLabel "Control" 200 14 120 20 10 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$statusPanel.Controls.Add((New-WindoLabel "EXPLICIT" 200 36 160 30 18 ([System.Drawing.Color]::FromArgb(56, 189, 248)) `$true))
`$statusPanel.Controls.Add((New-WindoLabel "Signal" 410 14 120 20 10 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$statusPanel.Controls.Add((New-WindoLabel "VISIBLE" 410 36 150 30 18 ([System.Drawing.Color]::FromArgb(191, 219, 254)) `$true))
`$statusPanel.Controls.Add((New-WindoLabel "Boundary" 620 14 120 20 10 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$statusPanel.Controls.Add((New-WindoLabel "CURATED" 620 36 170 30 18 ([System.Drawing.Color]::FromArgb(245, 158, 11)) `$true))
`$panel = New-Object System.Windows.Forms.FlowLayoutPanel
`$panel.Location = New-Object System.Drawing.Point(28, 232)
`$panel.Size = New-Object System.Drawing.Size(900, 410)
`$panel.AutoScroll = `$true
`$panel.FlowDirection = "TopDown"
`$panel.WrapContents = `$false
`$panel.BackColor = [System.Drawing.Color]::FromArgb(11, 18, 32)
`$form.Controls.Add(`$panel)
`$i = 0
foreach (`$a in `$actions) {
    `$row = New-Object System.Windows.Forms.Panel
    `$row.Width = 852
    `$row.Height = 66
    `$row.Margin = New-Object System.Windows.Forms.Padding(8, 8, 8, 0)
    `$row.BackColor = if ((`$i % 2) -eq 0) { [System.Drawing.Color]::FromArgb(15, 23, 42) } else { [System.Drawing.Color]::FromArgb(17, 29, 50) }
    `$row.Controls.Add((New-WindoLabel `$a.Title 16 8 210 22 11 ([System.Drawing.Color]::White) `$true))
    `$row.Controls.Add((New-WindoLabel `$a.Note 16 30 360 18 8 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
    `$cmd = New-WindoLabel `$a.Command 392 23 330 20 8 ([System.Drawing.Color]::FromArgb(191, 219, 254)) `$false
    `$cmd.Font = New-Object System.Drawing.Font("Consolas", 8)
    `$row.Controls.Add(`$cmd)
    `$row.Controls.Add((New-WindoButton "Run" `$a.Command 744 17 78 (Get-WindoTone `$a.Tone)))
    `$panel.Controls.Add(`$row)
    `$i++
}
`$footer = New-WindoLabel "Panel generated under .pwsh_secure. Close the window whenever you are done; no background executor stays hidden from this panel." 32 664 820 24 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false
`$form.Controls.Add(`$footer)
`$trayButton = New-WindoButton "Tray" "windo center tray" 836 656 92 ([System.Drawing.Color]::FromArgb(14, 165, 233))
`$form.Controls.Add(`$trayButton)
[void]`$form.ShowDialog()
"@
        return $text.Replace("__WINDO_VERSION__", $WindoVersion)
    }

    function _windo_start_surface_panel {
        if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
            return @{ ok = $false; error = "surface panel requires Windows desktop APIs" }
        }
        if (!(Test-Path $SecureDir)) { New-Item -ItemType Directory -Path $SecureDir -Force | Out-Null }
        $iconPath = _windo_resolve_tray_icon "ready"
        $panelPath = Join-Path $SecureDir "windo_surface_panel.ps1"
        $panelScript = (_windo_surface_panel_script_text).Replace("__WINDO_ICON_PATH__", (($iconPath -replace '\\', '\\') -replace "'", "''"))
        [System.IO.File]::WriteAllText($panelPath, $panelScript, [System.Text.UTF8Encoding]::new($false))
        $exe = "powershell.exe"
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwsh -and $pwsh.Source) { $exe = $pwsh.Source }
        Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList @("-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", $panelPath) | Out-Null
        return @{ ok = $true; path = $panelPath; iconPath = $iconPath }
    }

    function _windo_power_studio_script_text {
        $text = @"
`$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
`$version = "__WINDO_VERSION__"
`$iconPath = "__WINDO_ICON_PATH__"
`$workflows = @(
    @{ Group = "Start"; Title = "Command Center Status"; ActionId = "center-status"; Command = "windo center status"; Detail = "Read the unified command-center state."; Tone = "cyan" },
    @{ Group = "Start"; Title = "Open Surface Panel"; ActionId = "surface-panel"; Command = "windo surface panel"; Detail = "Open the compact native Surface Panel."; Tone = "cyan" },
    @{ Group = "Start"; Title = "Start Tray"; ActionId = "launchpad-tray"; Command = "windo launchpad --tray"; Detail = "Keep WINDO available from the task tray."; Tone = "cyan" },
    @{ Group = "Start"; Title = "Windows Integration"; ActionId = "integrate-status"; Command = "windo integrate status"; Detail = "Inspect Start Menu, startup, shim, and shortcut wiring."; Tone = "cyan" },
    @{ Group = "Trust"; Title = "Trust Console"; ActionId = "trust-online"; Command = "windo trust --online"; Detail = "Validate local trust and published checksum posture."; Tone = "green" },
    @{ Group = "Trust"; Title = "Source of Truth"; ActionId = "source-status"; Command = "windo source"; Detail = "Inspect published installer source and checksum state."; Tone = "green" },
    @{ Group = "Trust"; Title = "Verify Audit Chain"; ActionId = "verify-audit"; Command = "windo verify"; Detail = "Validate encrypted audit log hash chain."; Tone = "green" },
    @{ Group = "Repair"; Title = "Surface Doctor"; ActionId = "surface-doctor"; Command = "windo surface doctor"; Detail = "Check Windows Forms, manifests, prompt, and motion readiness."; Tone = "warn" },
    @{ Group = "Repair"; Title = "Surface Repair"; ActionId = "surface-repair"; Command = "windo surface repair"; Detail = "Refresh manifests and guarded profile prompt init."; Tone = "warn" },
    @{ Group = "Repair"; Title = "Profile Doctor"; ActionId = "profile-doctor"; Command = "windo profile doctor"; Detail = "Inspect profile block and prompt initialization health."; Tone = "warn" },
    @{ Group = "Repair"; Title = "Integration Doctor"; ActionId = "integrate-doctor"; Command = "windo integrate doctor"; Detail = "Check current-user Windows shell integration health."; Tone = "warn" },
    @{ Group = "Repair"; Title = "Repair Integration"; ActionId = "integrate-repair"; Command = "windo integrate repair"; Detail = "Refresh shortcuts, startup tray wiring, and command shim."; Tone = "warn" },
    @{ Group = "Security"; Title = "Scan Home"; ActionId = "scan-home"; Command = "windo scan `$HOME --recurse --max-mb 2"; Detail = "Local-first file posture scan with hashes and script findings."; Tone = "danger" },
    @{ Group = "Security"; Title = "Vault Status"; ActionId = "vault-status"; Command = "windo vault status"; Detail = "Inspect DPAPI vault count without exposing secrets."; Tone = "danger" },
    @{ Group = "Security"; Title = "Crypto Status"; ActionId = "crypto-status"; Command = "windo crypto status"; Detail = "Check OpenSSL and certutil availability."; Tone = "danger" },
    @{ Group = "Developer"; Title = "Python Venv Status"; ActionId = "venv-status"; Command = "windo venv status"; Detail = "Inspect active/local Python virtual environment state."; Tone = "blue" },
    @{ Group = "Developer"; Title = "SSH Tooling"; ActionId = "sshx-status"; Command = "windo sshx status"; Detail = "Check OpenSSH tooling, keys, and config posture."; Tone = "blue" },
    @{ Group = "Developer"; Title = "Recipes"; ActionId = "recipes-list"; Command = "windo recipes"; Detail = "List built-in operator recipes."; Tone = "blue" },
    @{ Group = "Package"; Title = "Package Managers"; ActionId = "pkg-status"; Command = "windo pkg status"; Detail = "Inspect winget, choco, and scoop availability."; Tone = "purple" },
    @{ Group = "Package"; Title = "Install Latest"; ActionId = "install-latest"; Command = "windo install-latest"; Detail = "Run verified update handoff."; Tone = "purple" },
    @{ Group = "Package"; Title = "Preflight"; ActionId = "preflight"; Command = "windo preflight"; Detail = "Run readiness checks with fix commands."; Tone = "purple" }
)
function Start-WindoStudioCommand([string]`$Command) {
    `$exe = "powershell.exe"
    `$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (`$pwsh -and `$pwsh.Source) { `$exe = `$pwsh.Source }
    Start-Process -FilePath `$exe -ArgumentList @("-NoExit", "-Command", `$Command) | Out-Null
}
function Get-WindoStudioTone([string]`$Tone) {
    switch (`$Tone) {
        "green" { return [System.Drawing.Color]::FromArgb(34, 197, 94) }
        "warn" { return [System.Drawing.Color]::FromArgb(245, 158, 11) }
        "danger" { return [System.Drawing.Color]::FromArgb(239, 68, 68) }
        "purple" { return [System.Drawing.Color]::FromArgb(168, 85, 247) }
        "blue" { return [System.Drawing.Color]::FromArgb(37, 99, 235) }
        default { return [System.Drawing.Color]::FromArgb(14, 165, 233) }
    }
}
function New-WindoStudioLabel([string]`$Text, [int]`$X, [int]`$Y, [int]`$W, [int]`$H, [int]`$Size, [System.Drawing.Color]`$Color, [bool]`$Bold = `$false) {
    `$label = New-Object System.Windows.Forms.Label
    `$label.Text = `$Text
    `$label.Location = New-Object System.Drawing.Point(`$X, `$Y)
    `$label.Size = New-Object System.Drawing.Size(`$W, `$H)
    `$label.ForeColor = `$Color
    `$style = if (`$Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    `$label.Font = New-Object System.Drawing.Font("Segoe UI", `$Size, `$style)
    return `$label
}
function New-WindoStudioButton([string]`$Text, [string]`$Command, [int]`$X, [int]`$Y, [int]`$W, [System.Drawing.Color]`$Color) {
    `$btn = New-Object System.Windows.Forms.Button
    `$btn.Text = `$Text
    `$btn.Tag = `$Command
    `$btn.Location = New-Object System.Drawing.Point(`$X, `$Y)
    `$btn.Size = New-Object System.Drawing.Size(`$W, 30)
    `$btn.BackColor = `$Color
    `$btn.ForeColor = [System.Drawing.Color]::White
    `$btn.FlatStyle = "Flat"
    `$btn.Add_Click({ Start-WindoStudioCommand ([string]`$this.Tag) })
    return `$btn
}
function Add-WindoWorkflowRows([System.Windows.Forms.TabPage]`$Tab, [object[]]`$Rows) {
    `$panel = New-Object System.Windows.Forms.FlowLayoutPanel
    `$panel.Location = New-Object System.Drawing.Point(18, 18)
    `$panel.Size = New-Object System.Drawing.Size(1018, 448)
    `$panel.AutoScroll = `$true
    `$panel.FlowDirection = "TopDown"
    `$panel.WrapContents = `$false
    `$panel.BackColor = [System.Drawing.Color]::FromArgb(10, 17, 31)
    `$Tab.Controls.Add(`$panel)
    foreach (`$a in `$Rows) {
        `$tone = Get-WindoStudioTone `$a.Tone
        `$row = New-Object System.Windows.Forms.Panel
        `$row.Width = 972
        `$row.Height = 74
        `$row.Margin = New-Object System.Windows.Forms.Padding(10, 10, 10, 0)
        `$row.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
        `$stripe = New-Object System.Windows.Forms.Panel
        `$stripe.Location = New-Object System.Drawing.Point(0, 0)
        `$stripe.Size = New-Object System.Drawing.Size(5, 74)
        `$stripe.BackColor = `$tone
        `$row.Controls.Add(`$stripe)
        `$row.Controls.Add((New-WindoStudioLabel `$a.Title 18 8 230 22 11 ([System.Drawing.Color]::White) `$true))
        `$row.Controls.Add((New-WindoStudioLabel `$a.Detail 18 32 420 18 8 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
        `$cmd = New-WindoStudioLabel `$a.Command 470 18 290 20 8 ([System.Drawing.Color]::FromArgb(191, 219, 254)) `$false
        `$cmd.Font = New-Object System.Drawing.Font("Consolas", 8)
        `$row.Controls.Add(`$cmd)
        `$row.Controls.Add((New-WindoStudioButton "Preview" ("windo center preview " + [string]`$a.ActionId) 778 10 76 `$tone))
        `$row.Controls.Add((New-WindoStudioButton "Queue" ("windo center queue " + [string]`$a.ActionId) 858 10 62 `$tone))
        `$row.Controls.Add((New-WindoStudioButton "Run" `$a.Command 924 10 44 `$tone))
        `$panel.Controls.Add(`$row)
    }
}
`$form = New-Object System.Windows.Forms.Form
`$form.Text = "WINDO Power Studio"
`$form.Size = New-Object System.Drawing.Size(1120, 760)
`$form.MinimumSize = New-Object System.Drawing.Size(980, 680)
`$form.StartPosition = "CenterScreen"
`$form.BackColor = [System.Drawing.Color]::FromArgb(6, 10, 18)
`$form.ForeColor = [System.Drawing.Color]::White
if (-not [string]::IsNullOrWhiteSpace(`$iconPath) -and (Test-Path -LiteralPath `$iconPath)) { `$form.Icon = New-Object System.Drawing.Icon(`$iconPath) }
`$form.Controls.Add((New-WindoStudioLabel "WINDO Power Studio" 28 18 520 42 25 ([System.Drawing.Color]::White) `$true))
`$form.Controls.Add((New-WindoStudioLabel "WINDO Command Center - modern guided Windows operator workflows - v`$version" 32 62 780 24 10 ([System.Drawing.Color]::FromArgb(56, 189, 248)) `$false))
`$form.Controls.Add((New-WindoStudioLabel "Preview, queue, or run curated actions. No arbitrary hidden execution; PowerShell output remains visible." 32 88 900 24 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$halo = New-Object System.Windows.Forms.ProgressBar
`$halo.Location = New-Object System.Drawing.Point(826, 46)
`$halo.Size = New-Object System.Drawing.Size(242, 10)
`$halo.Style = "Continuous"
`$halo.Minimum = 0
`$halo.Maximum = 100
`$halo.Value = 35
`$form.Controls.Add(`$halo)
`$timer = New-Object System.Windows.Forms.Timer
`$timer.Interval = 90
`$timer.Add_Tick({ `$halo.Value = ((`$halo.Value + 3) % 100) })
`$timer.Start()
`$cards = New-Object System.Windows.Forms.Panel
`$cards.Location = New-Object System.Drawing.Point(28, 124)
`$cards.Size = New-Object System.Drawing.Size(1040, 82)
`$cards.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
`$form.Controls.Add(`$cards)
`$cards.Controls.Add((New-WindoStudioLabel "Mode" 18 12 110 18 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$cards.Controls.Add((New-WindoStudioLabel "GUIDED" 18 34 150 28 18 ([System.Drawing.Color]::FromArgb(56, 189, 248)) `$true))
`$cards.Controls.Add((New-WindoStudioLabel "Boundary" 230 12 120 18 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$cards.Controls.Add((New-WindoStudioLabel "CURATED" 230 34 170 28 18 ([System.Drawing.Color]::FromArgb(245, 158, 11)) `$true))
`$cards.Controls.Add((New-WindoStudioLabel "Output" 470 12 120 18 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$cards.Controls.Add((New-WindoStudioLabel "VISIBLE" 470 34 150 28 18 ([System.Drawing.Color]::FromArgb(34, 197, 94)) `$true))
`$cards.Controls.Add((New-WindoStudioLabel "Surface" 700 12 120 18 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) `$false))
`$cards.Controls.Add((New-WindoStudioLabel "NATIVE" 700 34 150 28 18 ([System.Drawing.Color]::FromArgb(191, 219, 254)) `$true))
`$tabs = New-Object System.Windows.Forms.TabControl
`$tabs.Location = New-Object System.Drawing.Point(28, 228)
`$tabs.Size = New-Object System.Drawing.Size(1040, 512)
`$tabs.Appearance = "Normal"
`$tabs.Font = New-Object System.Drawing.Font("Segoe UI", 9)
`$form.Controls.Add(`$tabs)
foreach (`$group in @("Start", "Trust", "Repair", "Security", "Developer", "Package")) {
    `$tab = New-Object System.Windows.Forms.TabPage
    `$tab.Text = `$group
    `$tab.BackColor = [System.Drawing.Color]::FromArgb(7, 11, 20)
    `$tabs.TabPages.Add(`$tab) | Out-Null
    Add-WindoWorkflowRows `$tab @(`$workflows | Where-Object { `$_.Group -eq `$group })
}
[void]`$form.ShowDialog()
`$timer.Stop()
"@
        return $text.Replace("__WINDO_VERSION__", $WindoVersion)
    }

    function _windo_start_power_studio {
        if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
            return @{ ok = $false; error = "power studio requires Windows desktop APIs" }
        }
        if (!(Test-Path $SecureDir)) { New-Item -ItemType Directory -Path $SecureDir -Force | Out-Null }
        $iconPath = _windo_resolve_tray_icon "elevated"
        $studioPath = Join-Path $SecureDir "windo_power_studio.ps1"
        $studioScript = (_windo_power_studio_script_text).Replace("__WINDO_ICON_PATH__", (($iconPath -replace '\\', '\\') -replace "'", "''"))
        [System.IO.File]::WriteAllText($studioPath, $studioScript, [System.Text.UTF8Encoding]::new($false))
        $exe = "powershell.exe"
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwsh -and $pwsh.Source) { $exe = $pwsh.Source }
        Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList @("-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", $studioPath) | Out-Null
        return @{ ok = $true; path = $studioPath; iconPath = $iconPath }
    }

    function _windo_launchpad_tray_script_text {
        $lines = @(
            '$ErrorActionPreference = "Stop"',
            'Add-Type -AssemblyName System.Windows.Forms',
            'Add-Type -AssemblyName System.Drawing',
            '[System.Windows.Forms.Application]::EnableVisualStyles()',
            '$version = "__WINDO_VERSION__"',
            '$iconPath = "__WINDO_ICON_PATH__"',
            '$actions = @(',
            '    @{ Text = "Preflight"; Command = "windo preflight" },',
            '    @{ Text = "Dashboard"; Command = "windo dashboard" },',
            '    @{ Text = "Dashboard HTML"; Command = "windo dashboard --html" },',
            '    @{ Text = "Launchpad HTML"; Command = "windo launchpad --html" },',
            '    @{ Text = "Native Surface"; Command = "windo surface" },',
            '    @{ Text = "Surface Panel"; Command = "windo surface panel" },',
            '    @{ Text = "Power Studio"; Command = "windo center studio" },',
            '    @{ Text = "Windows Integration"; Command = "windo integrate status" },',
            '    @{ Text = "Repair Integration"; Command = "windo integrate repair" },',
            '    @{ Text = "Control Plane"; Command = "windo control status" },',
            '    @{ Text = "Control Prime"; Command = "windo control prime" },',
            '    @{ Text = "Control History"; Command = "windo control history" },',
            '    @{ Text = "Run Next Queued"; Command = "windo control execute-next" },',
            '    @{ Text = "Command Center Console"; Command = "windo edition open" },',
            '    @{ Text = "Open Control Folder"; Command = "Invoke-Item (Join-Path $HOME ''.pwsh_secure\control'')" },',
            '    @{ Text = "Last Control Result"; Command = "windo signal last" },',
            '    @{ Text = "Signal Deck"; Command = "windo signal timeline" },',
            '    @{ Text = "Motion Pulse"; Command = "windo motion pulse" },',
            '    @{ Text = "Integrity"; Command = "windo integrity" },',
            '    @{ Text = "Verify Audit Chain"; Command = "windo verify" },',
            '    @{ Text = "Repair Keybindings"; Command = "windo repair" },',
            '    @{ Text = "Install Latest"; Command = "windo install-latest" }',
            ')',
            'function Start-WindoTrayCommand([string]$Command) {',
            '    $exe = "powershell.exe"',
            '    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue',
            '    if ($pwsh -and $pwsh.Source) { $exe = $pwsh.Source }',
            '    Start-Process -FilePath $exe -ArgumentList @("-NoExit", "-Command", $Command) | Out-Null',
            '}',
            'function New-WindoLabel([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [int]$Size, [System.Drawing.Color]$Color, [bool]$Bold = $false) {',
            '    $label = New-Object System.Windows.Forms.Label',
            '    $label.Text = $Text',
            '    $label.Location = New-Object System.Drawing.Point($X, $Y)',
            '    $label.Size = New-Object System.Drawing.Size($W, $H)',
            '    $label.ForeColor = $Color',
            '    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }',
            '    $label.Font = New-Object System.Drawing.Font("Segoe UI", $Size, $style)',
            '    return $label',
            '}',
            'function Show-WindoStatusToast {',
            '    $toast = New-Object System.Windows.Forms.Form',
            '    $toast.Text = "WINDO Status"',
            '    $toast.FormBorderStyle = "FixedSingle"',
            '    $toast.MaximizeBox = $false',
            '    $toast.MinimizeBox = $false',
            '    $toast.Size = New-Object System.Drawing.Size(440, 220)',
            '    $toast.StartPosition = "CenterScreen"',
            '    $toast.BackColor = [System.Drawing.Color]::FromArgb(8, 13, 24)',
            '    $toast.Controls.Add($(New-WindoLabel "WINDO Command Center" 22 18 390 28 15 ([System.Drawing.Color]::White) $true))',
            '    $toast.Controls.Add($(New-WindoLabel "WINDO command center is running in the tray." 22 50 390 24 10 ([System.Drawing.Color]::FromArgb(148, 163, 184)) $false))',
            '    $toast.Controls.Add($(New-WindoLabel "Next useful actions" 22 86 180 22 10 ([System.Drawing.Color]::FromArgb(56, 189, 248)) $true))',
            '    $toast.Controls.Add($(New-WindoLabel "windo edition open" 22 112 380 20 9 ([System.Drawing.Color]::FromArgb(191, 219, 254)) $false))',
            '    $toast.Controls.Add($(New-WindoLabel "windo center actions" 22 136 380 20 9 ([System.Drawing.Color]::FromArgb(191, 219, 254)) $false))',
            '    $toast.Controls.Add($(New-WindoLabel "windo signal open" 22 160 380 20 9 ([System.Drawing.Color]::FromArgb(191, 219, 254)) $false))',
            '    $toast.TopMost = $true',
            '    [void]$toast.ShowDialog()',
            '}',
            'function Show-WindoLaunchpadWindow {',
            '    $form = New-Object System.Windows.Forms.Form',
            '    $form.Text = "WINDO Command Center"',
            '    $form.Size = New-Object System.Drawing.Size(860, 720)',
            '    $form.StartPosition = "CenterScreen"',
            '    $form.MinimumSize = New-Object System.Drawing.Size(760, 620)',
            '    $form.BackColor = [System.Drawing.Color]::FromArgb(8, 13, 24)',
            '    $form.ForeColor = [System.Drawing.Color]::White',
            '    $form.Controls.Add($(New-WindoLabel "WINDO Command Center" 24 20 470 36 22 ([System.Drawing.Color]::White) $true))',
            '    $form.Controls.Add($(New-WindoLabel "WINDO Command Center - v$version" 28 62 450 24 10 ([System.Drawing.Color]::FromArgb(56, 189, 248)) $false))',
            '    $form.Controls.Add($(New-WindoLabel "Actions open in visible PowerShell windows so output stays inspectable." 28 88 700 22 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) $false))',
            '    $panel = New-Object System.Windows.Forms.FlowLayoutPanel',
            '    $panel.Location = New-Object System.Drawing.Point(24, 126)',
            '    $panel.Size = New-Object System.Drawing.Size(795, 485)',
            '    $panel.AutoScroll = $true',
            '    $panel.FlowDirection = "TopDown"',
            '    $panel.WrapContents = $false',
            '    $panel.BackColor = [System.Drawing.Color]::FromArgb(11, 18, 32)',
            '    $form.Controls.Add($panel)',
            '    $i = 0',
            '    foreach ($a in $actions) {',
            '        $row = New-Object System.Windows.Forms.Panel',
            '        $row.Width = 748',
            '        $row.Height = 58',
            '        $row.Margin = New-Object System.Windows.Forms.Padding(8, 8, 8, 0)',
            '        $row.BackColor = if (($i % 2) -eq 0) { [System.Drawing.Color]::FromArgb(15, 23, 42) } else { [System.Drawing.Color]::FromArgb(17, 29, 50) }',
            '        $name = New-WindoLabel $a.Text 16 8 210 20 10 ([System.Drawing.Color]::White) $true',
            '        $cmd = New-WindoLabel $a.Command 16 30 490 18 8 ([System.Drawing.Color]::FromArgb(191, 219, 254)) $false',
            '        $cmd.Font = New-Object System.Drawing.Font("Consolas", 8)',
            '        $btn = New-Object System.Windows.Forms.Button',
            '        $btn.Text = "Run"',
            '        $btn.Tag = $a.Command',
            '        $btn.Width = 84',
            '        $btn.Height = 30',
            '        $btn.Location = New-Object System.Drawing.Point(642, 14)',
            '        $btn.BackColor = [System.Drawing.Color]::FromArgb(14, 165, 233)',
            '        $btn.ForeColor = [System.Drawing.Color]::White',
            '        $btn.FlatStyle = "Flat"',
            '        $btn.Add_Click({ Start-WindoTrayCommand ([string]$this.Tag) })',
            '        $row.Controls.Add($name)',
            '        $row.Controls.Add($cmd)',
            '        $row.Controls.Add($btn)',
            '        $panel.Controls.Add($row)',
            '        $i++',
            '    }',
            '    $statusBtn = New-Object System.Windows.Forms.Button',
            '    $statusBtn.Text = "Status"',
            '    $statusBtn.Width = 92',
            '    $statusBtn.Height = 32',
            '    $statusBtn.Location = New-Object System.Drawing.Point(24, 630)',
            '    $statusBtn.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)',
            '    $statusBtn.ForeColor = [System.Drawing.Color]::White',
            '    $statusBtn.FlatStyle = "Flat"',
            '    $statusBtn.Add_Click({ Show-WindoStatusToast })',
            '    $form.Controls.Add($statusBtn)',
            '    $form.Controls.Add($(New-WindoLabel "Right-click the tray icon for the compact menu. Close this window to keep the tray running." 132 636 650 22 9 ([System.Drawing.Color]::FromArgb(148, 163, 184)) $false))',
            '    [void]$form.ShowDialog()',
            '}',
            '$notify = New-Object System.Windows.Forms.NotifyIcon',
            '$notify.Text = "WINDO Command Center v$version"',
            'if (-not [string]::IsNullOrWhiteSpace($iconPath) -and (Test-Path -LiteralPath $iconPath)) {',
            '    $notify.Icon = New-Object System.Drawing.Icon($iconPath)',
            '} else {',
            '    $notify.Icon = [System.Drawing.SystemIcons]::Shield',
            '}',
            '$notify.Visible = $true',
            '$menu = New-Object System.Windows.Forms.ContextMenuStrip',
            '$openItem = $menu.Items.Add("Open Launchpad")',
            '$openItem.Add_Click({ Show-WindoLaunchpadWindow })',
            '$menu.Items.Add("-") | Out-Null',
            'foreach ($a in $actions) {',
            '    $item = $menu.Items.Add($a.Text)',
            '    $item.Tag = $a.Command',
            '    $item.Add_Click({ Start-WindoTrayCommand ([string]$this.Tag) })',
            '}',
            '$menu.Items.Add("-") | Out-Null',
            '$toastItem = $menu.Items.Add("Show Status Notification")',
            '$toastItem.Add_Click({',
            '    $notify.BalloonTipTitle = "WINDO Command Center"',
            '    $notify.BalloonTipText = "WINDO command center is ready. Use the tray menu for center actions, Signal Deck, repair, and update."',
            '    $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info',
            '    $notify.ShowBalloonTip(6000)',
            '    Show-WindoStatusToast',
            '})',
            '$exitItem = $menu.Items.Add("Exit")',
            '$exitItem.Add_Click({',
            '    $notify.Visible = $false',
            '    $notify.Dispose()',
            '    [System.Windows.Forms.Application]::Exit()',
            '})',
            '$notify.ContextMenuStrip = $menu',
            '$notify.Add_DoubleClick({ Show-WindoLaunchpadWindow })',
            '$notify.BalloonTipTitle = "WINDO Command Center"',
            '$notify.BalloonTipText = "WINDO command center is running. Double-click for the command center or right-click for quick actions."',
            '$notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info',
            '$notify.ShowBalloonTip(7000)',
            '[System.Windows.Forms.Application]::Run()'
        )
        return (($lines -join "`r`n") + "`r`n").Replace("__WINDO_VERSION__", $WindoVersion)
    }

    function _windo_start_launchpad_tray {
        if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
            return @{ ok = $false; error = "tray launchpad requires Windows desktop APIs" }
        }
        if (!(Test-Path $SecureDir)) { New-Item -ItemType Directory -Path $SecureDir -Force | Out-Null }
        $trayIconPath = _windo_resolve_tray_icon "ready"
        $trayPath = Join-Path $SecureDir "windo_launchpad_tray.ps1"
        $trayScript = (_windo_launchpad_tray_script_text).Replace("__WINDO_ICON_PATH__", (($trayIconPath -replace '\\', '\\') -replace "'", "''"))
        [System.IO.File]::WriteAllText($trayPath, $trayScript, [System.Text.UTF8Encoding]::new($false))
        $exe = "powershell.exe"
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwsh -and $pwsh.Source) { $exe = $pwsh.Source }
        Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList @("-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", $trayPath) | Out-Null
        return @{ ok = $true; path = $trayPath; iconPath = $trayIconPath }
    }

    function _windo_profile_path_list {
        $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $addOne = {
            param([string]$p)
            if ([string]::IsNullOrWhiteSpace($p)) { return }
            try {
                $full = [System.IO.Path]::GetFullPath($p)
                [void]$set.Add($full)
            } catch { }
        }
        try {
            if ($PROFILE) {
                & $addOne $PROFILE.CurrentUserCurrentHost
                & $addOne $PROFILE.CurrentUserAllHosts
                & $addOne $PROFILE.AllUsersCurrentHost
                & $addOne $PROFILE.AllUsersAllHosts
            }
        } catch {
            & $addOne ([string]$PROFILE)
        }
        foreach ($rel in @(
            (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'),
            (Join-Path $HOME 'Documents\PowerShell\Profile.ps1'),
            (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
            (Join-Path $HOME 'Documents\WindowsPowerShell\Profile.ps1')
        )) { & $addOne $rel }
        return @($set)
    }

    function _windo_read_profile_windo_status([string]$path) {
        if (!(Test-Path -LiteralPath $path)) { return @{ present = $false; hasWindoBlock = $false } }
        try {
            $t = Get-Content -Raw -LiteralPath $path -ErrorAction Stop
            $has = ($t -match [regex]::Escape($ProfileBlockBegin))
            return @{ present = $true; hasWindoBlock = [bool]$has }
        } catch {
            return @{ present = $true; hasWindoBlock = $false }
        }
    }

    function _windo_profile_prompt_issues([string]$Path) {
        $issues = [System.Collections.ArrayList]@()
        if (!(Test-Path -LiteralPath $Path)) { return @($issues) }
        try {
            $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
        } catch {
            [void]$issues.Add([pscustomobject]@{ id = "profile-read"; severity = "warn"; lineNumber = $null; detail = $_.Exception.Message; fixCommand = "" })
            return @($issues)
        }
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = [string]$lines[$i]
            if ($line -match 'oh-my-posh\s+init\s+pwsh' -and $line -match 'Invoke-Expression') {
                $guarded = $false
                for ($j = [Math]::Max(0, $i - 3); $j -lt $i; $j++) {
                    if ([string]$lines[$j] -match 'try\s*\{') { $guarded = $true; break }
                }
                if (-not $guarded) {
                    [void]$issues.Add([pscustomobject]@{
                        id = "oh-my-posh-unguarded-init"
                        severity = "warn"
                        lineNumber = $i + 1
                        detail = "oh-my-posh init is piped to Invoke-Expression without a guard; missing cached init scripts can break profile load."
                        fixCommand = "windo profile repair --prompt-init"
                    })
                }
            }
            $m = [regex]::Match($line, '(?<path>[A-Z]:\\[^''"`|<>]*\\oh-my-posh\\init\.[^''"`|<>\s]+\.ps1)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m.Success) {
                $cachePath = $m.Groups['path'].Value
                if (-not (Test-Path -LiteralPath $cachePath)) {
                    [void]$issues.Add([pscustomobject]@{
                        id = "oh-my-posh-missing-cache"
                        severity = "warn"
                        lineNumber = $i + 1
                        detail = "Profile references missing oh-my-posh cached init script: $cachePath"
                        fixCommand = "windo profile repair --prompt-init"
                    })
                }
            }
        }
        return @($issues)
    }

    function _windo_repair_profile_prompt_init([string]$Path) {
        if (!(Test-Path -LiteralPath $Path)) {
            return [pscustomobject]@{ ok = $false; changed = $false; path = $Path; backupPath = $null; error = "profile not found" }
        }
        try {
            $text = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
            $newText = [regex]::Replace($text, '(?m)^(?<indent>\s*)(?<cmd>.*oh-my-posh\s+init\s+pwsh.*\|\s*Invoke-Expression\s*)$', {
                param($m)
                $cmd = $m.Groups['cmd'].Value.TrimEnd()
                if ($cmd -match '^\s*try\s*\{') { return $m.Value }
                $prefix = $text.Substring(0, $m.Index)
                if ($prefix -match 'try\s*\{\s*$') { return $m.Value }
                $indent = $m.Groups['indent'].Value
                return @(
                    "${indent}try {",
                    "${indent}    $cmd",
                    "${indent}} catch {",
                    "${indent}    Write-Warning (`"oh-my-posh init skipped: `" + `$_.Exception.Message)",
                    "${indent}}"
                ) -join "`r`n"
            })
            $newText = [regex]::Replace($newText, '(?m)^(?<indent>\s*)(?<path>[A-Z]:\\[^''"`|<>]*\\oh-my-posh\\init\.[^''"`|<> \t]+\.ps1)\s*$', {
                param($m)
                $indent = $m.Groups['indent'].Value
                $cachePath = $m.Groups['path'].Value
                return @(
                    "${indent}`$__windoOmpInit = '$($cachePath.Replace("'", "''"))'",
                    "${indent}if (Test-Path -LiteralPath `$__windoOmpInit) { . `$__windoOmpInit }"
                ) -join "`r`n"
            }, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($newText -eq $text) {
                return [pscustomobject]@{ ok = $true; changed = $false; path = $Path; backupPath = $null; error = $null }
            }
            $backup = "$Path.windo-$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
            Copy-Item -LiteralPath $Path -Destination $backup -Force -ErrorAction Stop
            [System.IO.File]::WriteAllText($Path, $newText, [System.Text.UTF8Encoding]::new($false))
            return [pscustomobject]@{ ok = $true; changed = $true; path = $Path; backupPath = $backup; error = $null }
        } catch {
            return [pscustomobject]@{ ok = $false; changed = $false; path = $Path; backupPath = $null; error = $_.Exception.Message }
        }
    }

    function _windo_surface_state {
        $native = _windo_native_surface_state
        $profileIssues = [System.Collections.ArrayList]@()
        foreach ($p in @(_windo_profile_path_list)) {
            foreach ($issue in @(_windo_profile_prompt_issues $p)) {
                [void]$profileIssues.Add([pscustomobject]@{
                    profile = $p
                    id = $issue.id
                    severity = $issue.severity
                    lineNumber = $issue.lineNumber
                    detail = $issue.detail
                    fixCommand = $issue.fixCommand
                })
            }
        }
        $surfaceRoot = Join-Path $SecureDir "surface"
        $manifestPath = Join-Path $surfaceRoot "windo_surface_manifest.json"
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            surfaceRoot = $surfaceRoot
            manifestPath = $manifestPath
            manifestExists = [bool](Test-Path -LiteralPath $manifestPath)
            nativeSurface = $native
            motion = (_windo_resolve_motion_policy)
            profileIssues = @($profileIssues)
            ready = [bool]($native.traySupported -and $profileIssues.Count -eq 0)
            nextCommands = @("windo surface panel", "windo motion status", "windo profile doctor", "windo launchpad --tray", "windo mesh workbench --html")
        }
    }

    function _windo_integration_root { Join-Path $SecureDir "integration" }
    function _windo_integration_bin_dir { Join-Path $SecureDir "bin" }
    function _windo_integration_shim_path { Join-Path (_windo_integration_bin_dir) "windo.cmd" }
    function _windo_integration_startup_script_path { Join-Path $SecureDir "windo_start_tray.ps1" }

    function _windo_shell_folder([string]$Kind, [string]$Fallback) {
        try {
            $value = [Environment]::GetFolderPath($Kind)
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        } catch { }
        return $Fallback
    }

    function _windo_integration_start_menu_dir {
        Join-Path (_windo_shell_folder "StartMenu" (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu")) "Programs\WINDO"
    }

    function _windo_integration_startup_dir {
        _windo_shell_folder "Startup" (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup")
    }

    function _windo_integration_desktop_dir {
        _windo_shell_folder "Desktop" (Join-Path $HOME "Desktop")
    }

    function _windo_integration_shortcut_specs {
        $startMenu = _windo_integration_start_menu_dir
        $desktop = _windo_integration_desktop_dir
        $startup = _windo_integration_startup_dir
        return @(
            [pscustomobject]@{ id = "studio-start"; label = "WINDO Power Studio"; path = (Join-Path $startMenu "WINDO Power Studio.lnk"); command = "windo center studio"; location = "start-menu"; description = "Open the WINDO Power Studio workflow surface." },
            [pscustomobject]@{ id = "tray-start"; label = "WINDO Command Center Tray"; path = (Join-Path $startMenu "WINDO Command Center Tray.lnk"); command = "windo center tray"; location = "start-menu"; description = "Start the WINDO tray command center." },
            [pscustomobject]@{ id = "panel-start"; label = "WINDO Surface Panel"; path = (Join-Path $startMenu "WINDO Surface Panel.lnk"); command = "windo surface panel"; location = "start-menu"; description = "Open the WINDO native surface panel." },
            [pscustomobject]@{ id = "studio-desktop"; label = "WINDO Power Studio"; path = (Join-Path $desktop "WINDO Power Studio.lnk"); command = "windo center studio"; location = "desktop"; description = "Open the WINDO Power Studio workflow surface." },
            [pscustomobject]@{ id = "tray-startup"; label = "WINDO Command Center Tray"; path = (Join-Path $startup "WINDO Command Center Tray.lnk"); command = "windo center tray"; location = "startup"; description = "Start the WINDO tray command center at sign-in." }
        )
    }

    function _windo_integration_state {
        $native = _windo_native_surface_state
        $root = _windo_integration_root
        $shimDir = _windo_integration_bin_dir
        $shimPath = _windo_integration_shim_path
        $startupScript = _windo_integration_startup_script_path
        $pathValue = [Environment]::GetEnvironmentVariable("Path", "User")
        $pathParts = @()
        if (-not [string]::IsNullOrWhiteSpace($pathValue)) { $pathParts = @($pathValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
        $pathContainsShim = @($pathParts | Where-Object {
            try { [System.IO.Path]::GetFullPath($_).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($shimDir).TrimEnd('\') } catch { [string]$_ -ieq $shimDir }
        }).Count -gt 0
        $shortcuts = @(_windo_integration_shortcut_specs | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                label = $_.label
                location = $_.location
                path = $_.path
                command = $_.command
                exists = [bool](Test-Path -LiteralPath $_.path)
            }
        })
        $required = @($shortcuts | Where-Object { $_.location -in @("start-menu", "startup") })
        $missingRequired = @($required | Where-Object { -not $_.exists })
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            root = $root
            rootExists = [bool](Test-Path -LiteralPath $root)
            startMenuDir = (_windo_integration_start_menu_dir)
            startMenuExists = [bool](Test-Path -LiteralPath (_windo_integration_start_menu_dir))
            startupDir = (_windo_integration_startup_dir)
            desktopDir = (_windo_integration_desktop_dir)
            startupScriptPath = $startupScript
            startupScriptExists = [bool](Test-Path -LiteralPath $startupScript)
            shimDir = $shimDir
            shimPath = $shimPath
            shimExists = [bool](Test-Path -LiteralPath $shimPath)
            pathContainsShimDir = [bool]$pathContainsShim
            shellComAvailable = [bool]($native.windowsDesktop)
            nativeSurface = $native
            shortcuts = @($shortcuts)
            ready = [bool]((Test-Path -LiteralPath $shimPath) -and (Test-Path -LiteralPath $startupScript) -and $missingRequired.Count -eq 0)
            nextCommands = @("windo integrate doctor", "windo integrate repair", "windo center studio", "windo control run integrate-repair")
            exitCode = $(if ((Test-Path -LiteralPath $shimPath) -and (Test-Path -LiteralPath $startupScript) -and $missingRequired.Count -eq 0) { 0 } else { 3 })
        }
    }

    function _windo_write_cmd_shim {
        $shimDir = _windo_integration_bin_dir
        $shimPath = _windo_integration_shim_path
        if (!(Test-Path -LiteralPath $shimDir)) { New-Item -ItemType Directory -Path $shimDir -Force | Out-Null }
        $body = (@(
            "@echo off",
            "setlocal",
            'pwsh -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path -LiteralPath $PROFILE) { . $PROFILE }; windo @args" %*',
            "exit /b %ERRORLEVEL%"
        ) -join "`r`n") + "`r`n"
        $changed = $true
        if (Test-Path -LiteralPath $shimPath) {
            try { $changed = ((Get-Content -Raw -LiteralPath $shimPath) -ne $body) } catch { $changed = $true }
        }
        if ($changed) { [System.IO.File]::WriteAllText($shimPath, $body, [System.Text.ASCIIEncoding]::new()) }
        return [pscustomobject]@{ id = "shim"; ok = $true; changed = [bool]$changed; path = $shimPath; error = $null }
    }

    function _windo_ensure_user_path_contains([string]$Directory) {
        $current = [Environment]::GetEnvironmentVariable("Path", "User")
        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace($current)) { $parts = @($current -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
        $exists = @($parts | Where-Object {
            try { [System.IO.Path]::GetFullPath($_).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Directory).TrimEnd('\') } catch { [string]$_ -ieq $Directory }
        }).Count -gt 0
        if ($exists) { return [pscustomobject]@{ id = "user-path"; ok = $true; changed = $false; path = $Directory; error = $null } }
        $newPath = if ([string]::IsNullOrWhiteSpace($current)) { $Directory } else { ($current.TrimEnd(';') + ";" + $Directory) }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        return [pscustomobject]@{ id = "user-path"; ok = $true; changed = $true; path = $Directory; error = $null; note = "New shells will see the updated user PATH." }
    }

    function _windo_write_startup_script {
        $path = _windo_integration_startup_script_path
        $dir = Split-Path -Parent $path
        if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $body = (@(
            '$ErrorActionPreference = "SilentlyContinue"',
            'if (Get-Command windo -ErrorAction SilentlyContinue) {',
            '    windo center tray',
            '} elseif (Test-Path -LiteralPath $PROFILE) {',
            '    . $PROFILE',
            '    windo center tray',
            '}'
        ) -join "`r`n") + "`r`n"
        $changed = $true
        if (Test-Path -LiteralPath $path) {
            try { $changed = ((Get-Content -Raw -LiteralPath $path) -ne $body) } catch { $changed = $true }
        }
        if ($changed) { [System.IO.File]::WriteAllText($path, $body, [System.Text.UTF8Encoding]::new($false)) }
        return [pscustomobject]@{ id = "startup-script"; ok = $true; changed = [bool]$changed; path = $path; error = $null }
    }

    function _windo_new_shortcut([object]$Spec) {
        try {
            $dir = Split-Path -Parent ([string]$Spec.path)
            if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $exe = "powershell.exe"
            $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
            if ($pwsh -and $pwsh.Source) { $exe = [string]$pwsh.Source }
            $icon = _windo_resolve_tray_icon "ready"
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut([string]$Spec.path)
            $shortcut.TargetPath = $exe
            $shortcut.Arguments = ('-NoProfile -STA -ExecutionPolicy Bypass -Command "if (Test-Path -LiteralPath $PROFILE) {{ . $PROFILE }}; {0}"' -f [string]$Spec.command)
            $shortcut.WorkingDirectory = $HOME
            $shortcut.WindowStyle = 1
            $shortcut.Description = [string]$Spec.description
            if (-not [string]::IsNullOrWhiteSpace($icon) -and (Test-Path -LiteralPath $icon)) { $shortcut.IconLocation = $icon }
            $shortcut.Save()
            return [pscustomobject]@{ id = [string]$Spec.id; ok = $true; changed = $true; path = [string]$Spec.path; command = [string]$Spec.command; error = $null }
        } catch {
            return [pscustomobject]@{ id = [string]$Spec.id; ok = $false; changed = $false; path = [string]$Spec.path; command = [string]$Spec.command; error = $_.Exception.Message }
        }
    }

    function _windo_integration_repair([string[]]$Scope = @("all")) {
        $results = [System.Collections.ArrayList]@()
        $wanted = @($Scope | ForEach-Object { ([string]$_).ToLowerInvariant() })
        if ($wanted.Count -eq 0) { $wanted = @("all") }
        $all = $wanted -contains "all"
        if (!(Test-Path -LiteralPath (_windo_integration_root))) { New-Item -ItemType Directory -Path (_windo_integration_root) -Force | Out-Null }
        if ($all -or $wanted -contains "shim") {
            try {
                [void]$results.Add((_windo_write_cmd_shim))
                [void]$results.Add((_windo_ensure_user_path_contains (_windo_integration_bin_dir)))
            } catch { [void]$results.Add([pscustomobject]@{ id = "shim"; ok = $false; changed = $false; path = (_windo_integration_shim_path); error = $_.Exception.Message }) }
        }
        if ($all -or $wanted -contains "startup") {
            try { [void]$results.Add((_windo_write_startup_script)) } catch { [void]$results.Add([pscustomobject]@{ id = "startup-script"; ok = $false; changed = $false; path = (_windo_integration_startup_script_path); error = $_.Exception.Message }) }
        }
        if ($all -or $wanted -contains "shortcuts" -or $wanted -contains "startup") {
            foreach ($spec in @(_windo_integration_shortcut_specs)) {
                if (($wanted -contains "startup") -and $spec.location -ne "startup" -and -not $all -and -not ($wanted -contains "shortcuts")) { continue }
                [void]$results.Add((_windo_new_shortcut $spec))
            }
        }
        $failed = @($results | Where-Object { -not $_.ok })
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            scope = @($wanted)
            results = @($results)
            state = (_windo_integration_state)
            exitCode = $(if ($failed.Count -gt 0) { 2 } else { 0 })
        }
    }

    function _windo_integration_doctor {
        $state = _windo_integration_state
        $checks = [System.Collections.ArrayList]@()
        [void]$checks.Add((_windo_new_check_row "windows-desktop" "Windows desktop runtime" ([bool]$state.nativeSurface.windowsDesktop) "windowsDesktop=$($state.nativeSurface.windowsDesktop)" "" $(if ($state.nativeSurface.windowsDesktop) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "shell-com" "WScript.Shell shortcut COM" ([bool]$state.shellComAvailable) "shellComAvailable=$($state.shellComAvailable)" "windo integrate shortcuts" $(if ($state.shellComAvailable) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "command-shim" "User command shim" ([bool]$state.shimExists) "shim=$($state.shimPath)" "windo integrate shim" $(if ($state.shimExists) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "shim-path" "User PATH includes shim" ([bool]$state.pathContainsShimDir) "shimDir=$($state.shimDir)" "windo integrate shim" $(if ($state.pathContainsShimDir) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "startup-script" "Startup tray script" ([bool]$state.startupScriptExists) "script=$($state.startupScriptPath)" "windo integrate startup" $(if ($state.startupScriptExists) { "info" } else { "warn" })))
        foreach ($s in @($state.shortcuts)) {
            $tone = if ($s.exists) { "info" } else { "warn" }
            [void]$checks.Add((_windo_new_check_row ("shortcut-" + $s.id) ("Shortcut: " + $s.label + " (" + $s.location + ")") ([bool]$s.exists) "path=$($s.path)" "windo integrate shortcuts" $tone))
        }
        $warnings = @($checks | Where-Object { -not $_.ok })
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            readinessLevel = $(if ($warnings.Count -eq 0) { "READY" } else { "ATTENTION" })
            checks = @($checks)
            integration = $state
            exitCode = $(if ($warnings.Count -eq 0) { 0 } else { 3 })
        }
    }

    function _windo_integration_open {
        $dir = _windo_integration_start_menu_dir
        if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Start-Process -FilePath $dir | Out-Null
        return [pscustomobject]@{ ok = $true; path = $dir; exitCode = 0 }
    }

    function _windo_completion_doctor {
        $policy = _windo_resolve_completion_policy
        $tabExpansion = [bool](Get-Command TabExpansion2 -ErrorAction SilentlyContinue)
        $registerFunction = [bool](Get-Command Register-WindoArgumentCompleter -ErrorAction SilentlyContinue)
        $registeredFlag = [bool]$global:__WindoArgCompleterRegistered
        $sample = @()
        $sampleError = $null
        if ($tabExpansion) {
            try {
                $result = TabExpansion2 -inputScript "windo " -cursorColumn 6
                if ($result -and $result.CompletionMatches) {
                    $sample = @($result.CompletionMatches | Select-Object -First 20 | ForEach-Object { [string]$_.CompletionText })
                }
            } catch { $sampleError = $_.Exception.Message }
        }
        $profileText = ""
        try { if (Test-Path -LiteralPath $PROFILE) { $profileText = Get-Content -Raw -LiteralPath $PROFILE } } catch { $profileText = "" }
        $hasWindoBlock = [bool]($profileText -like "*# >>> WINDO-BEGIN >>>*" -and $profileText -like "*# <<< WINDO-END <<<*")
        $hasCompleterBlock = [bool]($profileText -like "*Register-WindoArgumentCompleter*" -and $profileText -like "*Register-ArgumentCompleter -CommandName windo -Native*")
        $hasEarlyReturnRisk = [bool]($profileText -like "*if (-not `$policy.enabled) { return }*" -or $profileText -like "*if (`$null -eq `$selectedPrefixChord) { return }*")
        $hasBuiltinCompletion = @($sample | Where-Object { $_ -in @("doctor", "help", "install-latest", "integrate") }).Count -gt 0
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            policy = $policy
            tabExpansion2Available = $tabExpansion
            registerFunctionAvailable = $registerFunction
            registeredFlag = $registeredFlag
            profilePath = [string]$PROFILE
            profileHasWindoBlock = $hasWindoBlock
            profileHasCompleterBlock = $hasCompleterBlock
            profileHasEarlyReturnRisk = $hasEarlyReturnRisk
            sampleInput = "windo "
            sampleCompletions = @($sample)
            sampleError = $sampleError
            ready = [bool]($tabExpansion -and $registerFunction -and $registeredFlag -and $hasBuiltinCompletion -and -not $hasEarlyReturnRisk)
            nextCommands = @("windo completion repair", ". `$PROFILE", "windo completion native-first", "windo repair")
            exitCode = $(if ($tabExpansion -and $registerFunction -and $registeredFlag -and $hasBuiltinCompletion -and -not $hasEarlyReturnRisk) { 0 } else { 3 })
        }
    }

    function _windo_completion_repair {
        $before = _windo_completion_doctor
        $errorText = $null
        try {
            if (Get-Command Register-WindoArgumentCompleter -ErrorAction SilentlyContinue) {
                $global:__WindoArgCompleterRegistered = $false
                Register-WindoArgumentCompleter
            }
        } catch { $errorText = $_.Exception.Message }
        $after = _windo_completion_doctor
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            before = $before
            after = $after
            error = $errorText
            exitCode = $(if ($null -eq $errorText -and $after.exitCode -eq 0) { 0 } else { 3 })
        }
    }

    function _windo_control_root { Join-Path $SecureDir "control" }
    function _windo_control_manifest_path { Join-Path (_windo_control_root) "windo_control_plane.json" }
    function _windo_control_queue_root { Join-Path (_windo_control_root) "requests" }
    function _windo_control_result_path([string]$Id) { Join-Path (_windo_control_queue_root) ($Id + ".result.json") }
    function _windo_control_executor_path([string]$Id) { Join-Path (_windo_control_root) ($Id + ".executor.ps1") }

    function _windo_control_action_catalog {
        return @(
            [pscustomobject]@{ id = "surface-status"; title = "Surface Status"; command = "windo surface"; group = "native"; execution = "visible-shell"; description = "Inspect native tray, motion, profile, and surface readiness." },
            [pscustomobject]@{ id = "surface-prime"; title = "Prime Surface"; command = "windo surface prime"; group = "native"; execution = "visible-shell"; description = "Write the native surface manifest for tray/control consumers." },
            [pscustomobject]@{ id = "surface-panel"; title = "Surface Panel"; command = "windo surface panel"; group = "native"; execution = "visible-shell"; description = "Open the browser-independent Windows Forms control surface." },
            [pscustomobject]@{ id = "power-studio"; title = "Power Studio"; command = "windo center studio"; group = "native"; execution = "visible-shell"; description = "Open the guided Windows Forms Power Studio workflow surface." },
            [pscustomobject]@{ id = "integrate-status"; title = "Integration Status"; command = "windo integrate status"; group = "native"; execution = "visible-shell"; description = "Inspect current-user Windows shell integration state." },
            [pscustomobject]@{ id = "integrate-doctor"; title = "Integration Doctor"; command = "windo integrate doctor"; group = "repair"; execution = "visible-shell"; description = "Run integration readiness checks for shortcuts, startup, shim, and PATH." },
            [pscustomobject]@{ id = "integrate-repair"; title = "Repair Integration"; command = "windo integrate repair"; group = "repair"; execution = "visible-shell"; description = "Refresh current-user Start Menu, desktop, startup, and command shim integration." },
            [pscustomobject]@{ id = "integrate-open"; title = "Open WINDO Shortcuts"; command = "windo integrate open"; group = "native"; execution = "visible-shell"; description = "Open the current-user WINDO Start Menu shortcut folder." },
            [pscustomobject]@{ id = "integrate-shim"; title = "Repair Command Shim"; command = "windo integrate shim"; group = "repair"; execution = "visible-shell"; description = "Refresh the current-user windo.cmd shim and user PATH entry." },
            [pscustomobject]@{ id = "integrate-startup"; title = "Repair Startup Tray"; command = "windo integrate startup"; group = "repair"; execution = "visible-shell"; description = "Refresh the startup tray script and sign-in shortcut." },
            [pscustomobject]@{ id = "center-status"; title = "Center Status"; command = "windo center status"; group = "native"; execution = "visible-shell"; description = "Inspect unified command-center status." },
            [pscustomobject]@{ id = "launchpad-tray"; title = "Start Tray"; command = "windo launchpad --tray"; group = "native"; execution = "visible-shell"; description = "Start the browser-independent tray command center." },
            [pscustomobject]@{ id = "workbench-html"; title = "Open Workbench"; command = "windo mesh workbench --open"; group = "visual"; execution = "visible-shell"; description = "Render and open the local visual operator workbench." },
            [pscustomobject]@{ id = "edition-open"; title = "Open Command Center"; command = "windo edition open"; group = "visual"; execution = "visible-shell"; description = "Render and open the WINDO command surface." },
            [pscustomobject]@{ id = "motion-pulse"; title = "Motion Pulse"; command = "windo motion pulse"; group = "visual"; execution = "visible-shell"; description = "Render the configured terminal pulse animation when allowed." },
            [pscustomobject]@{ id = "source-status"; title = "Source Status"; command = "windo source"; group = "trust"; execution = "visible-shell"; description = "Inspect published installer source, version, and checksum alignment." },
            [pscustomobject]@{ id = "verify-audit"; title = "Verify Audit"; command = "windo verify"; group = "trust"; execution = "visible-shell"; description = "Validate encrypted audit log format and hash chain." },
            [pscustomobject]@{ id = "surface-doctor"; title = "Surface Doctor"; command = "windo surface doctor"; group = "repair"; execution = "visible-shell"; description = "Check native surface readiness." },
            [pscustomobject]@{ id = "surface-repair"; title = "Surface Repair"; command = "windo surface repair"; group = "repair"; execution = "visible-shell"; description = "Refresh manifests and guarded prompt init." },
            [pscustomobject]@{ id = "profile-doctor"; title = "Profile Doctor"; command = "windo profile doctor"; group = "repair"; execution = "visible-shell"; description = "Check profile block and prompt initialization health." },
            [pscustomobject]@{ id = "trust-online"; title = "Trust Online"; command = "windo trust --online"; group = "trust"; execution = "visible-shell"; description = "Validate local posture and published installer checksum." },
            [pscustomobject]@{ id = "scan-home"; title = "Scan Home"; command = "windo scan `$HOME --recurse --max-mb 2"; group = "security"; execution = "visible-shell"; description = "Run a bounded local file posture scan under the user profile." },
            [pscustomobject]@{ id = "vault-status"; title = "Vault Status"; command = "windo vault status"; group = "security"; execution = "visible-shell"; description = "Inspect DPAPI vault status without exposing secrets." },
            [pscustomobject]@{ id = "crypto-status"; title = "Crypto Status"; command = "windo crypto status"; group = "security"; execution = "visible-shell"; description = "Check certificate and crypto helper tooling." },
            [pscustomobject]@{ id = "venv-status"; title = "Venv Status"; command = "windo venv status"; group = "developer"; execution = "visible-shell"; description = "Inspect Python virtual environment state." },
            [pscustomobject]@{ id = "sshx-status"; title = "SSH Status"; command = "windo sshx status"; group = "developer"; execution = "visible-shell"; description = "Inspect OpenSSH tooling and local SSH posture." },
            [pscustomobject]@{ id = "recipes-list"; title = "Recipes"; command = "windo recipes"; group = "developer"; execution = "visible-shell"; description = "List built-in operator recipes." },
            [pscustomobject]@{ id = "pkg-status"; title = "Package Managers"; command = "windo pkg status"; group = "lifecycle"; execution = "visible-shell"; description = "Inspect winget, choco, and scoop availability." },
            [pscustomobject]@{ id = "preflight"; title = "Preflight"; command = "windo preflight"; group = "trust"; execution = "visible-shell"; description = "Run local readiness checks before privileged work." },
            [pscustomobject]@{ id = "install-latest"; title = "Install Latest"; command = "windo install-latest"; group = "lifecycle"; execution = "visible-shell"; description = "Run the WINDO V6 installer/update handoff." }
        )
    }

    function _windo_control_get_action([string]$Id) {
        if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
        $needle = $Id.Trim()
        foreach ($a in @(_windo_control_action_catalog)) {
            if ($a.id -ieq $needle -or $a.title -ieq $needle) { return $a }
        }
        return $null
    }

    function _windo_control_action_preview([string]$ActionId) {
        $action = _windo_control_get_action $ActionId
        if ($null -eq $action) {
            return [pscustomobject]@{
                ok = $false
                error = "unknown action"
                actionId = $ActionId
                knownActions = @(@(_windo_control_action_catalog) | ForEach-Object { $_.id })
                exitCode = 2
            }
        }
        return [pscustomobject]@{
            ok = $true
            actionId = [string]$action.id
            title = [string]$action.title
            command = [string]$action.command
            group = [string]$action.group
            execution = [string]$action.execution
            route = "curated-visible-shell"
            arbitraryCommandExecution = $false
            canQueue = $true
            canRun = $true
            canExecuteQueuedRequest = $true
            writesLocalFiles = $true
            outputVisible = $true
            nextCommands = @(
                "windo control queue $($action.id)",
                "windo control run $($action.id)",
                "windo center queue $($action.id)"
            )
            exitCode = 0
        }
    }

    function _windo_control_queued_requests {
        $queueRoot = _windo_control_queue_root
        if (!(Test-Path -LiteralPath $queueRoot)) { return @() }
        return @(Get-ChildItem -LiteralPath $queueRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.result.json" } | Sort-Object LastWriteTime -Descending | ForEach-Object {
            try {
                $raw = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction Stop | ConvertFrom-Json
                $resultPath = _windo_control_result_path ([string]$raw.id)
                $result = $null
                if (Test-Path -LiteralPath $resultPath) {
                    try { $result = Get-Content -Raw -LiteralPath $resultPath -ErrorAction Stop | ConvertFrom-Json } catch { $result = $null }
                }
                [pscustomobject]@{
                    id = [string]$raw.id
                    actionId = [string]$raw.actionId
                    command = [string]$raw.command
                    status = [string]$raw.status
                    createdAt = [string]$raw.createdAt
                    updatedAt = $(if ($raw.PSObject.Properties.Name -contains 'updatedAt') { [string]$raw.updatedAt } else { $null })
                    path = [string]$_.FullName
                    resultPath = $(if (Test-Path -LiteralPath $resultPath) { $resultPath } else { $null })
                    result = $result
                }
            } catch {
                [pscustomobject]@{ id = $_.BaseName; actionId = $null; command = $null; status = "unreadable"; createdAt = $null; path = [string]$_.FullName }
            }
        })
    }

    function _windo_control_state {
        $root = _windo_control_root
        $queueRoot = _windo_control_queue_root
        $surface = _windo_surface_state
        $actions = @(_windo_control_action_catalog)
        $queued = @(_windo_control_queued_requests)
        $pending = @($queued | Where-Object { $_.status -eq "queued" })
        $lastResult = @($queued | Where-Object { $null -ne $_.result } | Sort-Object updatedAt, createdAt -Descending | Select-Object -First 1)
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            status = $(if ($surface.ready) { "ready" } elseif ($surface.nativeSurface.traySupported) { "attention" } else { "limited" })
            root = $root
            manifestPath = (_windo_control_manifest_path)
            manifestExists = [bool](Test-Path -LiteralPath (_windo_control_manifest_path))
            queueRoot = $queueRoot
            queuedCount = $pending.Count
            requestCount = $queued.Count
            resultCount = @($queued | Where-Object { $null -ne $_.result }).Count
            lastResult = $(if ($lastResult.Count -gt 0) { $lastResult[0] } else { $null })
            actions = @($actions)
            queued = @($queued)
            surface = $surface
            motion = $surface.motion
            integration = (_windo_integration_state)
            nextCommands = @("windo control prime", "windo control actions", "windo control queue integrate-repair", "windo control execute-next", "windo center open")
            exitCode = 0
        }
    }

    function _windo_control_write_manifest {
        $state = _windo_control_state
        if (!(Test-Path -LiteralPath $state.root)) { New-Item -ItemType Directory -Path $state.root -Force | Out-Null }
        if (!(Test-Path -LiteralPath $state.queueRoot)) { New-Item -ItemType Directory -Path $state.queueRoot -Force | Out-Null }
        $state | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $state.manifestPath -Encoding UTF8
        return (_windo_control_state)
    }

    function _windo_control_queue_action([string]$ActionId, [string]$Note = $null) {
        $action = _windo_control_get_action $ActionId
        if ($null -eq $action) { return [pscustomobject]@{ ok = $false; error = "unknown action"; actionId = $ActionId; path = $null } }
        $queueRoot = _windo_control_queue_root
        if (!(Test-Path -LiteralPath $queueRoot)) { New-Item -ItemType Directory -Path $queueRoot -Force | Out-Null }
        $id = "wcp-" + (Get-Date -Format "yyyyMMddHHmmss") + "-" + ([Guid]::NewGuid().ToString("n").Substring(0,8))
        $path = Join-Path $queueRoot ($id + ".json")
        $payload = [ordered]@{
            schemaVersion = "1.0"
            id = $id
            actionId = [string]$action.id
            title = [string]$action.title
            command = [string]$action.command
            status = "queued"
            createdAt = (Get-Date).ToString("o")
            createdBy = "$env:USERDOMAIN\$env:USERNAME"
            execution = [string]$action.execution
            note = $(if ([string]::IsNullOrWhiteSpace($Note)) { "Queued by WINDO control plane. Execution remains explicit." } else { $Note.Trim() })
        }
        $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        return [pscustomobject]@{ ok = $true; request = ([pscustomobject]$payload); path = $path }
    }

    function _windo_control_find_request([string]$Id) {
        if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
        $queueRoot = _windo_control_queue_root
        if (!(Test-Path -LiteralPath $queueRoot)) { return $null }
        $needle = $Id.Trim()
        $direct = Join-Path $queueRoot ($needle + ".json")
        $path = $null
        if (Test-Path -LiteralPath $direct) { $path = $direct }
        else {
            $matches = @(Get-ChildItem -LiteralPath $queueRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.result.json" -and ($_.BaseName -eq $needle -or $_.BaseName -like "$needle*") } | Sort-Object LastWriteTime -Descending)
            if ($matches.Count -gt 0) { $path = [string]$matches[0].FullName }
        }
        if (-not $path) { return $null }
        try {
            $request = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json
            $resultPath = _windo_control_result_path ([string]$request.id)
            $result = $null
            if (Test-Path -LiteralPath $resultPath) {
                try { $result = Get-Content -Raw -LiteralPath $resultPath -ErrorAction Stop | ConvertFrom-Json } catch { $result = $null }
            }
            return [pscustomobject]@{ ok = $true; path = $path; request = $request; resultPath = $resultPath; result = $result }
        } catch {
            return [pscustomobject]@{ ok = $false; path = $path; request = $null; resultPath = $null; result = $null; error = $_.Exception.Message }
        }
    }

    function _windo_control_write_request([object]$Found, [object]$Request) {
        $Request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath ([string]$Found.path) -Encoding UTF8
    }

    function _windo_control_set_request_status([object]$Found, [string]$Status, [hashtable]$Extra = $null) {
        if ($null -eq $Found -or -not $Found.ok) { return $Found }
        $request = $Found.request
        if ($request.PSObject.Properties.Name -contains 'status') { $request.status = $Status } else { $request | Add-Member -NotePropertyName status -NotePropertyValue $Status -Force }
        $now = (Get-Date).ToString("o")
        if ($request.PSObject.Properties.Name -contains 'updatedAt') { $request.updatedAt = $now } else { $request | Add-Member -NotePropertyName updatedAt -NotePropertyValue $now -Force }
        if ($Extra) {
            foreach ($k in $Extra.Keys) {
                if ($request.PSObject.Properties.Name -contains $k) { $request.$k = $Extra[$k] } else { $request | Add-Member -NotePropertyName $k -NotePropertyValue $Extra[$k] -Force }
            }
        }
        _windo_control_write_request $Found $request
        return (_windo_control_find_request ([string]$request.id))
    }

    function _windo_control_history([int]$Limit = 25) {
        $rows = @(_windo_control_queued_requests)
        if ($Limit -lt 1) { $Limit = 25 }
        return @($rows | Sort-Object updatedAt, createdAt -Descending | Select-Object -First $Limit)
    }

    function _windo_control_cancel_request([string]$Id) {
        $found = _windo_control_find_request $Id
        if ($null -eq $found) { return [pscustomobject]@{ ok = $false; error = "request not found"; id = $Id } }
        if (-not $found.ok) { return $found }
        if ([string]$found.request.status -notin @("queued", "running")) {
            return [pscustomobject]@{ ok = $false; error = "request is already terminal"; id = [string]$found.request.id; status = [string]$found.request.status; path = [string]$found.path }
        }
        $updated = _windo_control_set_request_status $found "cancelled" @{ cancelledAt = (Get-Date).ToString("o") }
        return [pscustomobject]@{ ok = $true; id = [string]$updated.request.id; status = [string]$updated.request.status; path = [string]$updated.path }
    }

    function _windo_control_next_queued {
        $queueRoot = _windo_control_queue_root
        if (!(Test-Path -LiteralPath $queueRoot)) { return $null }
        foreach ($f in @(Get-ChildItem -LiteralPath $queueRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.result.json" } | Sort-Object LastWriteTime)) {
            try {
                $r = Get-Content -Raw -LiteralPath $f.FullName -ErrorAction Stop | ConvertFrom-Json
                if ([string]$r.status -eq "queued") { return (_windo_control_find_request ([string]$r.id)) }
            } catch { }
        }
        return $null
    }

    function _windo_control_executor_script_text([object]$Found) {
        $request = $Found.request
        $id = [string]$request.id
        $command = [string]$request.command
        $requestPath = [string]$Found.path
        $resultPath = _windo_control_result_path $id
        $safeCommand = $command.Replace("'", "''")
        $safeRequest = $requestPath.Replace("'", "''")
        $safeResult = $resultPath.Replace("'", "''")
        return @"
`$ErrorActionPreference = 'Continue'
`$requestPath = '$safeRequest'
`$resultPath = '$safeResult'
`$command = '$safeCommand'
`$startedAt = Get-Date
`$output = @()
`$exitCode = 0
try {
    Write-Host "[windo control] executing $id -> `$command" -ForegroundColor Cyan
    `$output = @(Invoke-Expression `$command 2>&1 | Tee-Object -Variable __windoControlOutput | ForEach-Object { [string]`$_ })
    if (`$global:WINDO_EXIT_CODE -is [int]) { `$exitCode = [int]`$global:WINDO_EXIT_CODE }
    elseif (`$LASTEXITCODE -is [int]) { `$exitCode = [int]`$LASTEXITCODE }
} catch {
    `$exitCode = 2
    `$output += `$_.Exception.Message
}
`$status = if (`$exitCode -eq 0) { 'complete' } else { 'failed' }
try {
    `$req = Get-Content -Raw -LiteralPath `$requestPath | ConvertFrom-Json
    `$req.status = `$status
    `$req.updatedAt = (Get-Date).ToString('o')
    `$req.completedAt = (Get-Date).ToString('o')
    `$req.exitCode = `$exitCode
    `$req.resultPath = `$resultPath
    `$req | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath `$requestPath -Encoding UTF8
} catch { }
`$result = [ordered]@{
    schemaVersion = '1.0'
    id = '$id'
    actionId = '$($request.actionId)'
    command = `$command
    status = `$status
    exitCode = `$exitCode
    startedAt = `$startedAt.ToString('o')
    completedAt = (Get-Date).ToString('o')
    output = @(`$output)
}
`$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath `$resultPath -Encoding UTF8
Write-Host "[windo control] `$status exit=`$exitCode" -ForegroundColor `$(if (`$exitCode -eq 0) { 'Green' } else { 'Red' })
"@
    }

    function _windo_control_execute_found([object]$Found) {
        $found = $Found
        if ($null -eq $found) { return [pscustomobject]@{ ok = $false; error = "control request not found"; exitCode = 2 } }
        if (-not $found.ok) { return [pscustomobject]@{ ok = $false; error = $found.error; request = $found.request; path = $found.path; exitCode = 2 } }
        if ([string]$found.request.status -ne "queued") {
            return [pscustomobject]@{ ok = $false; error = "request is not queued"; request = $found.request; path = $found.path; status = [string]$found.request.status; exitCode = 2 }
        }
        $action = _windo_control_get_action ([string]$found.request.actionId)
        if ($null -eq $action) {
            $updated = _windo_control_set_request_status $found "failed" @{ failure = "unknown action"; completedAt = (Get-Date).ToString("o"); exitCode = 2 }
            return [pscustomobject]@{ ok = $false; error = "unknown action"; request = $updated.request; path = $updated.path; exitCode = 2 }
        }
        $scriptPath = _windo_control_executor_path ([string]$found.request.id)
        if (!(Test-Path -LiteralPath (_windo_control_root))) { New-Item -ItemType Directory -Path (_windo_control_root) -Force | Out-Null }
        $found = _windo_control_set_request_status $found "running" @{ startedAt = (Get-Date).ToString("o"); executorScriptPath = $scriptPath; resultPath = (_windo_control_result_path ([string]$found.request.id)) }
        [System.IO.File]::WriteAllText($scriptPath, (_windo_control_executor_script_text $found), [System.Text.UTF8Encoding]::new($false))
        $exe = "powershell.exe"
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwsh -and $pwsh.Source) { $exe = [string]$pwsh.Source }
        Start-Process -FilePath $exe -ArgumentList @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) | Out-Null
        return [pscustomobject]@{ ok = $true; request = $found.request; path = $found.path; executorScriptPath = $scriptPath; resultPath = (_windo_control_result_path ([string]$found.request.id)); exitCode = 0 }
    }

    function _windo_control_execute_next {
        $found = _windo_control_next_queued
        if ($null -eq $found) { return [pscustomobject]@{ ok = $false; error = "no queued control request"; exitCode = 3 } }
        return (_windo_control_execute_found $found)
    }

    function _windo_control_execute_request([string]$Id) {
        $found = _windo_control_find_request $Id
        return (_windo_control_execute_found $found)
    }

    function _windo_control_start_action([string]$ActionId) {
        $action = _windo_control_get_action $ActionId
        if ($null -eq $action) { return [pscustomobject]@{ ok = $false; error = "unknown action"; actionId = $ActionId; command = $null } }
        $exe = "powershell.exe"
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwsh -and $pwsh.Source) { $exe = [string]$pwsh.Source }
        Start-Process -FilePath $exe -ArgumentList @("-NoExit", "-Command", [string]$action.command) | Out-Null
        return [pscustomobject]@{ ok = $true; actionId = [string]$action.id; command = [string]$action.command; exe = $exe }
    }

    function _windo_surface_doctor {
        $state = _windo_surface_state
        $control = _windo_control_state
        $checks = [System.Collections.ArrayList]@()
        [void]$checks.Add((_windo_new_check_row "windows-desktop" "Windows desktop runtime" ([bool]$state.nativeSurface.windowsDesktop) "windowsDesktop=$($state.nativeSurface.windowsDesktop)" "" $(if ($state.nativeSurface.windowsDesktop) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "windows-forms" "Windows Forms availability" ([bool]$state.nativeSurface.windowsFormsAvailable) "windowsFormsAvailable=$($state.nativeSurface.windowsFormsAvailable)" "" $(if ($state.nativeSurface.windowsFormsAvailable) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "sta-launch" "STA tray launch path" ([bool]$state.nativeSurface.traySupported) "traySupported=$($state.nativeSurface.traySupported)" "windo launchpad --tray" $(if ($state.nativeSurface.traySupported) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "tray-script" "Tray script freshness" ([bool]$state.nativeSurface.trayScriptExists) "trayScript=$($state.nativeSurface.trayScriptPath)" "windo launchpad --tray" $(if ($state.nativeSurface.trayScriptExists) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "surface-panel" "Surface panel script" ([bool]$state.nativeSurface.panelScriptExists) "panelScript=$($state.nativeSurface.panelScriptPath)" "windo surface panel" $(if ($state.nativeSurface.panelScriptExists) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "power-studio" "Power Studio script" ([bool]$state.nativeSurface.studioScriptExists) "studioScript=$($state.nativeSurface.studioScriptPath)" "windo center studio" $(if ($state.nativeSurface.studioScriptExists) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "surface-manifest" "Surface manifest" ([bool]$state.manifestExists) "manifest=$($state.manifestPath)" "windo surface prime" $(if ($state.manifestExists) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "control-manifest" "Control manifest" ([bool]$control.manifestExists) "manifest=$($control.manifestPath)" "windo control prime" $(if ($control.manifestExists) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "profile-prompt" "Profile prompt health" ($state.profileIssues.Count -eq 0) "promptIssues=$($state.profileIssues.Count)" "windo profile repair --prompt-init" $(if ($state.profileIssues.Count -eq 0) { "info" } else { "warn" })))
        [void]$checks.Add((_windo_new_check_row "motion-policy" "Motion policy" ([bool]$state.motion) "mode=$($state.motion.mode), enabled=$($state.motion.enabled)" "windo motion status" "info"))
        $warnings = @($checks | Where-Object { -not $_.ok })
        $level = if ($warnings.Count -eq 0) { "READY" } else { "ATTENTION" }
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            readinessLevel = $level
            checks = @($checks)
            surface = $state
            control = $control
            exitCode = $(if ($warnings.Count -eq 0) { 0 } else { 3 })
        }
    }

    function _windo_surface_repair {
        $results = [System.Collections.ArrayList]@()
        try {
            $state = _windo_surface_state
            if (!(Test-Path -LiteralPath $state.surfaceRoot)) { New-Item -ItemType Directory -Path $state.surfaceRoot -Force | Out-Null }
            $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $state.manifestPath -Encoding UTF8
            [void]$results.Add([pscustomobject]@{ id = "surface-prime"; ok = $true; changed = $true; path = $state.manifestPath; error = $null })
        } catch { [void]$results.Add([pscustomobject]@{ id = "surface-prime"; ok = $false; changed = $false; path = $null; error = $_.Exception.Message }) }
        try {
            $control = _windo_control_write_manifest
            [void]$results.Add([pscustomobject]@{ id = "control-prime"; ok = $true; changed = $true; path = $control.manifestPath; error = $null })
        } catch { [void]$results.Add([pscustomobject]@{ id = "control-prime"; ok = $false; changed = $false; path = $null; error = $_.Exception.Message }) }
        try {
            $profileResult = _windo_repair_profile_prompt_init ([string]$PROFILE)
            [void]$results.Add([pscustomobject]@{ id = "profile-prompt"; ok = [bool]$profileResult.ok; changed = [bool]$profileResult.changed; path = [string]$profileResult.path; backupPath = [string]$profileResult.backupPath; error = $profileResult.error })
        } catch { [void]$results.Add([pscustomobject]@{ id = "profile-prompt"; ok = $false; changed = $false; path = [string]$PROFILE; error = $_.Exception.Message }) }
        $failed = @($results | Where-Object { -not $_.ok })
        [pscustomobject]@{ windoVersion = $WindoVersion; generatedAt = (Get-Date).ToString("o"); results = @($results); exitCode = $(if ($failed.Count -gt 0) { 2 } else { 0 }) }
    }

    function _windo_signal_state([int]$Limit = 25) {
        $control = _windo_control_state
        $history = @(_windo_control_history $Limit)
        $lastMeta = _read_last_meta
        $integrity = _integrity_status
        $audit = _windo_verify_log_state
        $trust = _windo_trust_posture $false
        $surfaceDoctor = _windo_surface_doctor
        $timeline = [System.Collections.ArrayList]@()
        foreach ($h in @($history)) {
            [void]$timeline.Add([pscustomobject]@{ type = "control"; id = $h.id; status = $h.status; actionId = $h.actionId; command = $h.command; at = $(if ($h.updatedAt) { $h.updatedAt } else { $h.createdAt }); exitCode = $(if ($h.result) { $h.result.exitCode } else { $null }) })
        }
        if ($lastMeta) {
            [void]$timeline.Add([pscustomobject]@{ type = "elevation"; id = $(if ($lastMeta.PSObject.Properties.Name -contains 'lastRequestId') { $lastMeta.lastRequestId } else { $null }); status = "last"; actionId = $null; command = $lastMeta.commandLine; at = $lastMeta.storedAt; exitCode = $null })
        }
        $failures = @($timeline | Where-Object { $_.status -in @("failed", "cancelled") -or ($_.exitCode -is [int] -and $_.exitCode -ne 0) })
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            status = $(if ($failures.Count -gt 0 -or $trust.exitCode -ge 3 -or $surfaceDoctor.exitCode -ge 3) { "attention" } else { "ready" })
            timeline = @($timeline | Sort-Object at -Descending)
            control = $control
            last = $(if ($timeline.Count -gt 0) { @($timeline | Sort-Object at -Descending | Select-Object -First 1)[0] } else { $null })
            trust = $trust
            integrity = $integrity
            audit = $audit
            surfaceDoctor = $surfaceDoctor
            recommendations = @("windo signal timeline", "windo control history", "windo surface doctor", "windo export --redact")
            exitCode = $(if ($failures.Count -gt 0 -or $trust.exitCode -ge 3 -or $surfaceDoctor.exitCode -ge 3) { 3 } else { 0 })
        }
    }

    function _windo_write_signal_html([object]$Signal, [string]$OutputPath, [bool]$Open) {
        $sb = [System.Text.StringBuilder]::new()
        $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO Signal Deck</title>')
        $null = $sb.AppendLine('<style>body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#0f172a;color:#e5e7eb}.wrap{max-width:1200px;margin:0 auto;padding:28px}.hero{border-bottom:1px solid #334155;padding-bottom:18px}.title{font-size:36px;font-weight:800}.sub,.muted{color:#94a3b8}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:14px;margin:18px 0}.card{background:#111827;border:1px solid #334155;border-radius:8px;padding:14px}.k{font-size:12px;text-transform:uppercase;color:#94a3b8}.v{font-size:28px;font-weight:800}.ok{color:#22c55e}.warn{color:#f59e0b}.bad{color:#ef4444}.row{display:grid;grid-template-columns:160px 130px 1fr 90px;gap:10px;border-top:1px solid #1f2937;padding:9px 0}code{color:#bfdbfe}</style></head><body><div class="wrap">')
        $cls = if ($Signal.status -eq "ready") { "ok" } else { "warn" }
        $null = $sb.AppendLine(("<div class='hero'><div class='title'>WINDO Signal Deck</div><div class='sub'>v{0} generated {1}. Local evidence view.</div></div>" -f (_html_escape $Signal.windoVersion), (_html_escape (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))))
        $null = $sb.AppendLine("<div class='grid'>")
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Signal</div><div class='v {0}'>{1}</div></div>" -f $cls, (_html_escape $Signal.status)))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Control Queue</div><div class='v'>{0}</div><div class='muted'>{1} total requests</div></div>" -f [int]$Signal.control.queuedCount, [int]$Signal.control.requestCount))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Trust</div><div class='v'>{0}</div><div class='muted'>{1}/100</div></div>" -f (_html_escape $Signal.trust.trustLevel), [int]$Signal.trust.score))
        $null = $sb.AppendLine(("<div class='card'><div class='k'>Surface</div><div class='v'>{0}</div><div class='muted'>{1} checks</div></div>" -f (_html_escape $Signal.surfaceDoctor.readinessLevel), @($Signal.surfaceDoctor.checks).Count))
        $null = $sb.AppendLine("</div><h2>Timeline</h2>")
        foreach ($t in @($Signal.timeline)) {
            $null = $sb.AppendLine(("<div class='row'><div>{0}</div><div>{1}</div><div><code>{2}</code></div><div>{3}</div></div>" -f (_html_escape $t.type), (_html_escape $t.status), (_html_escape $t.command), (_html_escape ([string]$t.exitCode))))
        }
        $null = $sb.AppendLine("</div></body></html>")
        $dir = Split-Path $OutputPath -Parent
        if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
        if ($Open) { Start-Process -FilePath $OutputPath | Out-Null }
        return $OutputPath
    }

    function _windo_center_state {
        $signal = _windo_signal_state 15
        [pscustomobject]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            mode = "command-center"
            status = $signal.status
            centerCommand = "windo center open"
            trayCommand = "windo center tray"
            panelCommand = "windo center panel"
            studioCommand = "windo center studio"
            runCommand = "windo center run <action-id>"
            queueCommand = "windo center queue <action-id>"
            previewCommand = "windo center preview <action-id>"
            executeCommand = "windo center execute <request-id>"
            nextCommand = "windo center execute-next"
            historyCommand = "windo center history"
            surface = $signal.surfaceDoctor.surface
            integration = (_windo_integration_state)
            control = $signal.control
            signal = $signal
            exitCode = $signal.exitCode
        }
    }

    function _windo_help_topics {
        return @(
            [pscustomobject]@{
                Name        = "help"
                Aliases     = @("?","--help","-h")
                Category    = "Core"
                Summary     = "Display WINDO usage and command docs."
                Syntax      = @("windo help [topic]", "windo /? [topic]", "windo --help [topic]", "windo -h [topic]")
                Description = "Use this command to discover WINDO capabilities. Omit topic for a full command index."
                Notes       = "Global options like --json and --dry-run are accepted before any built-in command."
                Examples    = @("windo help", "windo help --json", "windo /? install-latest", "windo --help install")
            },
            [pscustomobject]@{
                Name        = "version"
                Category    = "Core"
                Summary     = "Show WINDO version, file paths, and integrity checks."
                Syntax      = @("windo version [--json]")
                Description = "Use for quick operational checks after profile load or automation."
                Notes       = "Use with `windo doctor` to correlate task/path state."
                Examples    = @("windo version", "windo version --json")
            },
            [pscustomobject]@{
                Name        = "install-latest"
                Aliases     = @("upgrade")
                Category    = "Core"
                Summary     = "Download and run latest installer from v6."
                Syntax      = @("windo install-latest [--force] [--non-interactive] [--timeout <seconds|ms>] [--preserve-env [ALL|name1,name2]]", "windo upgrade [same options]")
                Description = "Upgrade path with non-elevated download, optional verification prompt, and optional non-interactive automation mode."
                Notes       = "Non-interactive requires --force in current shell; WINDO_INSTALL_NONINTERACTIVE / CI auto-skips confirm."
                Examples    = @("windo install-latest", "windo install-latest --force", "windo upgrade --non-interactive")
            },
            [pscustomobject]@{
                Name        = "uninstall"
                Aliases     = @("remove")
                Category    = "Core"
                Summary     = "Run elevated uninstaller (tasks, profile block, WINDO secure files)."
                Syntax      = @("windo uninstall [--keep-snapshots] [--confirm] [--download-fresh]", "windo remove [same options]")
                Description = "Uses the bundled local uninstaller when present, otherwise downloads it from v6, then starts an elevated uninstall."
                Notes       = "Profile helper after load: windo-uninstall [-KeepSnapshots] [-Confirm] (alias: windoremove)."
                Examples    = @("windo uninstall", "windo uninstall --keep-snapshots", "windo remove --download-fresh", "windo-uninstall -KeepSnapshots")
            },
            [pscustomobject]@{
                Name        = "self-update"
                Category    = "Core"
                Summary     = "Run the self-update task (repairs task actions)."
                Syntax      = @("windo self-update [--dry-run]")
                Description = "Triggers the maintenance task that rewrites scheduled-task action arguments if changed."
                Notes       = "Useful after installer profile/version drift."
                Examples    = @("windo self-update", "windo self-update --dry-run")
            },
            [pscustomobject]@{
                Name        = "last"
                Category    = "Core"
                Summary     = "Print last stored elevated command (no execution)."
                Syntax      = @("windo last")
                Description = "Useful when reusing context after session restarts."
                Notes       = "History of built-ins is intentionally not recorded here."
                Examples    = @("windo last")
            },
            [pscustomobject]@{
                Name        = "replay"
                Aliases     = @("!!")
                Category    = "Core"
                Summary     = "Replay last stored elevated command."
                Syntax      = @("windo replay", "windo !!")
                Description = "Re-runs the last non-builtin command captured in windo_last_cmd.txt."
                Notes       = "Any global options set on this call apply to replay invocation."
                Examples    = @("windo replay", "windo !!", "windo replay --non-interactive")
            },
            [pscustomobject]@{
                Name        = "keybindings"
                Category    = "Shell Experience"
                Summary     = "Inspect or set PSReadLine prefix behavior."
                Syntax      = @("windo keybindings [status]", "windo keybindings doctor [--json]", "windo keybindings set --chord <chord>", "windo keybindings disable|enable|reset|safe-reset")
                Description = "Inspect effective chording, recover from broken chords, and switch to safe defaults."
                Notes       = "safe-reset removes legacy handlers and reboots the configured chord in one command. doctor uses advisory heuristics to spot non-WINDO handlers on WINDO chords."
                Examples    = @("windo keybindings status --json", "windo keybindings doctor", "windo keybindings disable", "windo keybindings safe-reset")
            },
            [pscustomobject]@{
                Name        = "completion"
                Category    = "Shell Experience"
                Summary     = "Control WINDO tab completion delegation."
                Syntax      = @("windo completion [status]", "windo completion native-first|hybrid|windo|off|reset [--json]")
                Description = "Controls whether the WINDO argument completer behaves like the native shell after the windo prefix, offers WINDO built-ins, or disables completion registration."
                Notes       = "Default is native-first: non-WINDO input after 'windo ' delegates to PowerShell completion so WINDO feels transparent at command start. WINDO_COMPLETION_MODE overrides prefs for the current process."
                Examples    = @("windo completion", "windo completion native-first", "windo completion hybrid --json", "windo completion reset")
            },
            [pscustomobject]@{
                Name        = "roadmap"
                Category    = "Planning"
                Summary     = "Show the release runway."
                Syntax      = @("windo roadmap [--json]")
                Description = "Displays the current V6 platform train and upcoming feature priorities without exposing future major-package details."
                Notes       = "Roadmap output is local, static, and intentionally non-binding; it is a product/platform planning aid shipped with the installer."
                Examples    = @("windo roadmap", "windo roadmap --json")
            },
            [pscustomobject]@{
                Name        = "trust"
                Category    = "Security"
                Summary     = "Show local trust posture and optional installer checksum validation."
                Syntax      = @("windo trust [--json]", "windo trust --online [--json]")
                Description = "Scores local WINDO trust posture from task presence, runner/updater manifest integrity, audit-chain verification, profile block presence, completion policy, and local installer snapshot hash."
                Notes       = "--online fetches the published installer checksum only from a non-elevated shell; elevated shells are blocked from remote checksum fetches by policy."
                Examples    = @("windo trust", "windo trust --json", "windo trust --online --json")
            },
            [pscustomobject]@{
                Name        = "scan"
                Category    = "Security"
                Summary     = "Local file posture scan for scripts, launchable files, MOTW, and risky patterns."
                Syntax      = @("windo scan [path...] [--recurse] [--max-mb N] [--no-hash] [--json]")
                Description = "Scans files and directories locally without remote signatures. Reports hashes, Mark-of-the-Web, launchable extensions, and common suspicious script patterns."
                Notes       = "This is WINDO posture scanning, not a replacement for Defender or full antivirus engines."
                Examples    = @("windo scan .", "windo scan $HOME\\Downloads --recurse", "windo scan .\\script.ps1 --json")
            },
            [pscustomobject]@{
                Name        = "net-scan"
                Category    = "Security"
                Summary     = "Network posture: adapters, ARP, DNS, ICMP sweep, TCP probe, nmap, RDP/VNC controls, WSL."
                Syntax      = @(
                    "windo net-scan [status] [--json]",
                    "windo net-scan resolve <host...> [--host-tags <path>] [--json]",
                    "windo net-scan arp [--interface <alias>] [--include-stale] [--host-tags <path>] [--json]",
                    "windo net-scan ping <cidr|host...> [--host-tags <path>] [--timeout <secs>] [--host-limit N] [--ports <port,...>] [--json]",
                    "windo net-scan probe <host> <port[,port,port-range,...]> [--timeout <secs>] [--json]",
                    "windo net-scan nmap [nmap args...]",
                    "windo net-scan rdp [status|enable|disable|nla [status|enable|disable]] [--json]",
                    "windo net-scan vnc [status|stop] [--json]",
                    "windo net-scan wsl [--json]"
                )
                Description = "Read-only local network inspection plus optional RDP/VNC apply controls. status shows adapter/gateway/DNS. resolve does forward A/AAAA and reverse PTR for one or more hosts. arp reads the live neighbour table via Get-NetNeighbor with arp.exe fallback. ping sweeps a CIDR or host list with parallel ICMP; add --ports for per-host TCP probes on alive hosts. resolve/arp/ping support --host-tags <json-path> for identity enrichment and tagging. probe is a dedicated non-blocking TCP port prober (netcat-style). nmap delegates to nmap.exe. rdp reads or writes fDenyTSConnections and UserAuthentication registry keys; apply operations need elevation. vnc checks for RealVNC/TightVNC/UltraVNC services and listeners on 5900/5901; stop needs elevation. wsl reports distros, WSL version, and network adapters."
                Notes       = "All read operations are non-elevated. Apply controls (rdp enable/disable, rdp nla enable/disable, vnc stop) check for Administrator role and emit exit-code 3 with a windo run -- re-run hint when elevation is absent. ICMP sweeps use System.Net.NetworkInformation.Ping via a runspace pool (PS5.1 and PS7 compatible). TCP probes use BeginConnect/AsyncWaitHandle for non-blocking checks. Subnet scans are capped at --host-limit (default 254). Port ranges are limited to spans of 100."
                Examples    = @(
                    "windo net-scan",
                    "windo net-scan status --json",
                    "windo net-scan resolve dc01.corp.local --json",
                    "windo net-scan arp --include-stale --json",
                    "windo net-scan arp --host-tags .\\host-tags.json --json",
                    "windo net-scan ping 192.168.1.0/24 --ports 22,80,443 --json",
                    "windo net-scan ping 10.0.0.0/24 --host-limit 50 --timeout 1.5 --json",
                    "windo net-scan probe webserver.local 80,443,8080-8090",
                    "windo net-scan nmap -sV -p 22,80,443 192.168.1.1",
                    "windo net-scan rdp status --json",
                    "windo run -- windo net-scan rdp enable",
                    "windo run -- windo net-scan rdp nla enable",
                    "windo net-scan vnc status --json",
                    "windo net-scan wsl --json"
                )
            },
            [pscustomobject]@{
                Name        = "rdp"
                Category    = "Remote Access"
                Summary     = "Inspect RDP local enablement, firewall rule matching, and optional host diagnostics."
                Syntax      = @(
                    "windo rdp [status] [--json]",
                    "windo rdp firewall [status] [--ports 3389] [--json]",
                    "windo rdp config [--enable|--disable] [--nla on|off] [--security-layer 0|1|2] [--restart] [--json]",
                    "windo rdp troubleshoot [--host localhost] [--ports 3389,3390] [--credential vault-name] [--json]"
                )
                Description = "Reads/writes RDP registry flags and checks service state and firewall posture for remote desktop operations. Status mode is read-only."
                Notes       = "Mutating operations (`config`) should be run elevated (or via `windo run`) and are blocked in non-admin shells."
                Examples    = @(
                    "windo rdp status --json",
                    "windo rdp firewall status --json",
                    "windo rdp config --enable --nla on --json",
                    "windo rdp config --disable --json",
                    "windo rdp troubleshoot --host localhost --ports 3389 --json"
                )
            },
            [pscustomobject]@{
                Name        = "vnc"
                Category    = "Remote Access"
                Summary     = "Inspect VNC service/listener state and validate port reachability."
                Syntax      = @(
                    "windo vnc [status] [--json]",
                    "windo vnc firewall [status] [--ports 5900,5901] [--json]",
                    "windo vnc stop [serviceName...] [--json]",
                    "windo vnc test <host> [--ports 5900,5901] [--timeout 3] [--json]",
                    "windo vnc troubleshoot [--host localhost] [--ports 5900,5901] [--credential vault-name] [--json]"
                )
                Description = "Inspects common VNC services and checks for reachable listener ports locally or against a target host."
                Notes       = "Service stop operations require administrator privileges. Vault preview requires matching DPAPI-protected vault entry in current user context."
                Examples    = @(
                    "windo vnc status --json",
                    "windo vnc firewall status --json",
                    "windo vnc stop winvnc4 --json",
                    "windo vnc test localhost --ports 5900,5901 --json",
                    "windo vnc troubleshoot --host localhost --ports 5900 --json"
                )
            },
            [pscustomobject]@{
                Name        = "vault"
                Category    = "Security"
                Summary     = "DPAPI-backed current-user secret vault."
                Syntax      = @("windo vault status|list [--json]", "windo vault set <name> [value]", "windo vault get <name> [--json]", "windo vault remove <name>")
                Description = "Stores named values under .pwsh_secure using DPAPI CurrentUser protection. Secrets decrypt only for the same Windows user context."
                Notes       = "Avoid printing secrets in shared terminals. JSON get intentionally includes the value only when explicitly requested."
                Examples    = @("windo vault set OPENAI_API_KEY", "windo vault list", "windo vault get OPENAI_API_KEY", "windo vault remove OPENAI_API_KEY")
            },
            [pscustomobject]@{
                Name        = "sshx"
                Category    = "Security"
                Summary     = "SSH operator helpers for status, key generation, config creation, and tests."
                Syntax      = @("windo sshx status [--json]", "windo sshx keygen [--name id_ed25519_windo] [--comment text]", "windo sshx config", "windo sshx test <host>")
                Description = "Wraps local OpenSSH tooling in small task-oriented commands without elevation."
                Notes       = "Key generation uses ed25519 with 100 KDF rounds through ssh-keygen."
                Examples    = @("windo sshx status", "windo sshx keygen --name id_ed25519_ops", "windo sshx config", "windo sshx test git@github.com")
            },
            [pscustomobject]@{
                Name        = "crypto"
                Category    = "Security"
                Summary     = "Certificate, key, and SHA256 helpers using local OpenSSL/certutil."
                Syntax      = @("windo crypto status [--json]", "windo crypto cert <path>", "windo crypto key <path>", "windo crypto hash <path> [--json]")
                Description = "Makes common certificate/key inspection and file hashing commands easier to remember."
                Notes       = "Uses openssl when available for certificate/key inspection, with certutil fallback for certificates."
                Examples    = @("windo crypto status", "windo crypto cert .\\server.crt", "windo crypto key .\\server.key", "windo crypto hash .\\file.zip --json")
            },
            [pscustomobject]@{
                Name        = "source"
                Category    = "Core"
                Summary     = "Show published installer source, version, checksum, and local snapshot alignment."
                Syntax      = @("windo source [--json]")
                Description = "Read-only source-of-truth check for web bootstrap and install-latest. Fetches installer metadata through the GitHub Contents API first, with raw branch fallback."
                Notes       = "Use this when the web one-liner or upgrade path appears stale. Pair with windo trust --online for full local trust posture."
                Examples    = @("windo source", "windo source --json", "windo explain source")
            },
            [pscustomobject]@{
                Name        = "syntax"
                Category    = "Planning"
                Summary     = "Map operator intent to exact WINDO commands without executing them."
                Syntax      = @("windo syntax [query] [--json]", "windo syntax doctor [query] [--json]", "windo syntax --doctor [query] [--json]")
                Description = "Read-only Syntax Forge catalog and doctor for common intents like update, trust, health, repair keys, support bundle, recipes, and launchpad."
                Notes       = "Doctor mode reports exact, fuzzy, ambiguous, or missing intent matches and suggests the safest next command before anything privileged runs."
                Examples    = @("windo syntax", "windo syntax update", "windo syntax doctor proof --json", "windo syntax doctor repair keys")
            },
            [pscustomobject]@{
                Name        = "explain"
                Category    = "Planning"
                Summary     = "Show the execution plan for a WINDO command before running it."
                Syntax      = @("windo explain <command...> [--json]", "windo explain -- <external command...>")
                Description = "Read-only command planner that reports route, privilege boundary, network use, local artifacts, audit behavior, checksum posture, preflight checks, and exact next commands."
                Notes       = "Use -- before target commands with their own flags so WINDO keeps those flags as the explained command instead of treating them as global WINDO options."
                Examples    = @("windo explain install-latest", "windo explain trust --online", "windo explain recipes run firewall-profiles", "windo explain -- Get-Service Spooler")
            },
            [pscustomobject]@{
                Name        = "profile"
                Category    = "Shell Experience"
                Summary     = "Show known profile paths, WINDO block presence, and prompt-init issues."
                Syntax      = @("windo profile [status|doctor] [--json]", "windo profile repair [--prompt-init] [--all] [--json]")
                Description = "Checks current host profile and standard PowerShell profile files. Doctor mode detects prompt initializers that can break profile load, including unguarded oh-my-posh init pipelines."
                Notes       = "Repair wraps oh-my-posh init lines in a try/catch guard and writes a timestamped profile backup before changing anything."
                Examples    = @("windo profile", "windo profile doctor --json", "windo profile repair --prompt-init")
            },
            [pscustomobject]@{
                Name        = "config"
                Category    = "Configuration"
                Summary     = "Show effective WINDO env + runner semantics."
                Syntax      = @("windo config [--json]")
                Description = "Displays effective values and policy-resolution notes for env and keybinding settings."
                Notes       = "Includes SUDO_* and WINDO_INSTALL_NONINTERACTIVE parity controls."
                Examples    = @("windo config", "windo config --json")
            },
            [pscustomobject]@{
                Name        = "output"
                Aliases     = @("verbosity")
                Category    = "Shell Experience"
                Summary     = "Control compact versus legacy command result output."
                Syntax      = @("windo output [status]", "windo output compact|quiet|legacy|reset [--json]")
                Description = "Saves the result-output mode for elevated external commands. Default compact mode prints one small status line plus command output when present."
                Notes       = "WINDO_OUTPUT_MODE overrides the saved preference for the current process. legacy restores the older Status/Duration/Output line layout."
                Examples    = @("windo output", "windo output compact", "windo output legacy", "windo output reset --json")
            },
            [pscustomobject]@{
                Name        = "motion"
                Category    = "Shell Experience"
                Summary     = "Control terminal motion and small WINDO animations."
            Syntax      = @("windo motion [status]", "windo motion auto|on|quiet|off|reset [--json]", "windo motion profile ambient|subtle|steady|standard|rich|burst|cinematic|off [--json]", "windo motion pulse")
            Description = "Controls terminal motion policy and profile. Animation profile can be changed independently from ON/OFF policy."
            Notes       = "Auto mode animates only in interactive terminals and stays quiet for CI, redirected output, WINDO_NO_SPINNER, or WINDO_REDUCED_MOTION."
                Examples    = @("windo motion", "windo motion auto", "windo motion off", "windo motion pulse")
            },
            [pscustomobject]@{
                Name        = "surface"
                Category    = "Shell Experience"
                Summary     = "Inspect and prime the native Windows surface layer."
                Syntax      = @("windo surface [status] [--json]", "windo surface prime|pulse|doctor|repair|open|panel [--json]")
                Description = "Reports tray support, Windows Forms readiness, brand/tray paths, motion policy, prompt-init issues, and native surface readiness. Repair primes manifests and guards prompt init where needed."
                Notes       = "Open starts the browser-independent tray path. Repair writes local manifest/control files and may update the current profile prompt guard with a backup."
                Examples    = @("windo surface", "windo surface panel", "windo surface doctor", "windo surface repair", "windo surface open")
            },
            [pscustomobject]@{
                Name        = "control"
                Category    = "Shell Experience"
                Summary     = "Local Windows control-plane wiring for tray and visual surfaces."
                Syntax      = @("windo control [status] [--json]", "windo control prime|actions|history|pulse|clear", "windo control preview <action-id>", "windo control queue <action-id> [note]", "windo control execute-next|next", "windo control execute|inspect|cancel <request-id>", "windo control run <action-id>")
                Description = "Builds a local action catalog, manifest, request queue, result files, and visible-shell executor under .pwsh_secure so tray/native surfaces can orchestrate known commands without a browser."
                Notes       = "Only curated WINDO action IDs can run. preview is read-only. execute-next consumes the oldest queued request; execute <request-id> runs a specific queued request."
                Examples    = @("windo control", "windo control actions", "windo control preview surface-prime", "windo control queue surface-prime", "windo control execute-next", "windo control execute <id>")
            },
            [pscustomobject]@{
                Name        = "signal"
                Category    = "Inspection"
                Summary     = "Evidence-first Signal Deck for control, audit, trust, and surface state."
                Syntax      = @("windo signal [status] [--json]", "windo signal timeline [--json]", "windo signal last [--json]", "windo signal export [--open] [--output path]", "windo signal open")
                Description = "Correlates control-plane requests/results, last elevation metadata, trust posture, audit-chain health, and native-surface readiness into a local diagnostic view."
                Notes       = "Export writes a local HTML Signal Deck under Documents\\windo unless --output is supplied."
                Examples    = @("windo signal", "windo signal timeline", "windo signal last", "windo signal open")
            },
            [pscustomobject]@{
                Name        = "center"
                Category    = "Shell Experience"
                Summary     = "PowerShell-native WINDO Command Center."
                Syntax      = @("windo center [status] [--json]", "windo center open|tray|panel|studio", "windo center actions|signal|history", "windo center preview|run|queue <action-id>", "windo center execute-next|next", "windo center execute <request-id>")
                Description = "Unifies tray, Power Studio, control plane, Signal Deck, native surface, motion, trust, recipes, modules, extras, audit, and export into a native-feeling Windows command center."
                Notes       = "The first V6 center is PowerShell-native. A compiled companion helper is scaffolded for a later major release but is not required."
                Examples    = @("windo center", "windo center studio", "windo center panel", "windo center actions", "windo center preview power-studio", "windo center queue surface-prime", "windo center execute-next", "windo center signal")
            },
            [pscustomobject]@{
                Name        = "studio"
                Category    = "Shell Experience"
                Summary     = "Open the guided WINDO Power Studio."
                Syntax      = @("windo studio [--json]", "windo center studio [--json]")
                Description = "Starts a modern Windows Forms wizard surface with workflow tabs for Start, Trust, Repair, Security, Developer, and Package operations."
                Notes       = "Power Studio exposes curated WINDO actions only. Preview and queue use the control-plane action catalog; run opens visible PowerShell windows."
                Examples    = @("windo studio", "windo center studio", "windo center preview power-studio")
            },
            [pscustomobject]@{
                Name        = "integrate"
                Aliases     = @("windows", "shortcuts", "startup", "shim")
                Category    = "Shell Experience"
                Summary     = "Install and repair current-user Windows shell integration."
                Syntax      = @("windo integrate [status] [--json]", "windo integrate doctor|prime|repair|shortcuts|startup|shim|open [--json]")
                Description = "Creates and inspects current-user Start Menu, desktop, startup tray, and command-shim integration so WINDO behaves more like a dedicated Windows tool without machine-wide writes."
                Notes       = "Repair is explicit. It may update the current-user PATH for new shells, but does not write Program Files or HKLM."
                Examples    = @("windo integrate doctor", "windo integrate repair", "windo integrate open")
            },
            [pscustomobject]@{
                Name        = "edition"
                Category    = "Shell Experience"
            Summary     = "Open the branded WINDO command surface."
            Syntax      = @("windo edition [status] [--json]", "windo edition open [--output path]", "windo edition html [--output path]", "windo edition pulse")
            Description = "Renders the command surface with official WINDO assets, animated HTML, Command Center status, curated action posture, and release metadata."
                Notes       = "The edition surface is local-only. It writes an HTML artifact under Documents\\windo and does not run elevated commands."
                Examples    = @("windo edition", "windo edition open", "windo edition pulse", "windo center queue edition-open")
            },
            [pscustomobject]@{
                Name        = "backups"
                Category    = "Maintenance"
                Summary     = "List log backup files."
                Syntax      = @("windo backups [--json]", "windo backups --prune --keep N --force")
                Description = "Enumerates and optionally prunes windo_history*.enc.bak files."
                Notes       = "Prune requires --force."
                Examples    = @("windo backups", "windo backups --json", "windo backups --prune --keep 5 --force")
            },
            [pscustomobject]@{
                Name        = "theme"
                Category    = "Configuration"
                Summary     = "Configure JSON envelope style (CLI only)."
                Syntax      = @("windo theme [classic|modern|auto]")
                Description = "Controls whether --json outputs use schema 2.6-style or modern 3.0-style envelopes."
                Notes       = "Does not change runner, elevation, or audit behaviour."
                Examples    = @("windo theme modern", "windo theme auto")
            },
            [pscustomobject]@{
                Name        = "context"
                Category    = "Inspection"
                Summary     = "Show current shell, task, and environment context."
                Syntax      = @("windo context [--json]")
                Description = "Useful for troubleshooting profile load state and last RequestId."
                Notes       = "Pair with windo doctor for a full status check."
                Examples    = @("windo context", "windo context --json")
            },
            [pscustomobject]@{
                Name        = "doctor"
                Category    = "Inspection"
                Summary     = "Quick integrity and task health scan."
                Syntax      = @("windo doctor [--json]")
                Description = "Checks scheduled tasks, manifest presence, and runner/log locations."
                Notes       = "Sets $global:WINDO_EXIT_CODE for machine checks."
                Examples    = @("windo doctor", "windo doctor --json")
            },
            [pscustomobject]@{
                Name        = "integrity"
                Category    = "Inspection"
                Summary     = "Runner/manifest integrity comparison."
                Syntax      = @("windo integrity [--json]")
                Description = "Reports OK, DRIFT, TAMPERED, UNKNOWN for runner and updater manifests."
                Notes       = "Pair with windo verify for chain integrity."
                Examples    = @("windo integrity", "windo integrity --json")
            },
            [pscustomobject]@{
                Name        = "verify"
                Category    = "Inspection"
                Summary     = "Validate DPAPI encrypted audit-chain integrity."
                Syntax      = @("windo verify [--json]")
                Description = "Verifies encrypted log format and hash chaining."
                Notes       = "Useful for forensics and compliance checks."
                Examples    = @("windo verify", "windo verify --json")
            },
            [pscustomobject]@{
                Name        = "log"
                Category    = "Inspection"
                Summary     = "Decrypt and print recent audit log entries."
                Syntax      = @("windo log -n N [--tail] [--json]")
                Description = "Default output is human-readable; with --json returns a structured payload."
                Notes       = "--tail with --json reads only the last N physical lines."
                Examples    = @("windo log -n 20", "windo log -n 10 --tail --json")
            },
            [pscustomobject]@{
                Name        = "stats"
                Category    = "Inspection"
                Summary     = "Summarize decrypted audit entries."
                Syntax      = @("windo stats [--since YYYY-MM-DD] [--last-days N]")
                Description = "Returns aggregate counts and optional averages based on Timestamp filters."
                Notes       = "Filters are mutually exclusive. N must be positive."
                Examples    = @("windo stats --last-days 7", "windo stats --since 2026-04-01")
            },
            [pscustomobject]@{
                Name        = "history"
                Category    = "Inspection"
                Summary     = "Compact recent command history from encrypted audit."
                Syntax      = @("windo history [-n N]")
                Description = "Shows compact summaries for last N entries."
                Notes       = "Defaults to 50 when -n is omitted."
                Examples    = @("windo history", "windo history -n 20")
            },
            [pscustomobject]@{
                Name        = "report"
                Category    = "Reporting"
                Summary     = "Write local HTML audit report."
                Syntax      = @("windo report [-o path]")
                Description = "Builds an HTML summary with counts and categories in Documents\\windo\\."
                Notes       = "Uses most recent logs and integrity context."
                Examples    = @("windo report", "windo report -o .\\windo_report.html")
            },
            [pscustomobject]@{
                Name        = "dashboard"
                Category    = "Reporting"
                Summary     = "Show an operator health dashboard."
                Syntax      = @("windo dashboard [--json]", "windo dashboard --html [-o path]", "windo dashboard --open")
                Description = "Combines task presence, integrity, audit-chain verification, audit categories, and recent entries into terminal, JSON, or local HTML output."
                Notes       = "HTML is local-only and may include sensitive command text."
                Examples    = @("windo dashboard", "windo dashboard --json", "windo dashboard --html", "windo dashboard --open")
            },
            [pscustomobject]@{
                Name        = "preflight"
                Category    = "Inspection"
                Summary     = "Readiness scan with fix commands."
                Syntax      = @("windo preflight [--json]")
                Description = "Checks non-elevated update posture, PowerShell runtime, scheduled tasks, integrity, audit chain, profile block, and keybinding policy."
                Notes       = "Read-only; suggested fix commands are printed but not executed."
                Examples    = @("windo preflight", "windo preflight --json")
            },
            [pscustomobject]@{
                Name        = "launchpad"
                Category    = "Reporting"
                Summary     = "Open the WINDO command center."
            Syntax      = @("windo launchpad [--json]", "windo launchpad --tray", "windo launchpad --html [--output path|--output=path]", "windo launchpad --open")
                Description = "Generates a local command center with health checks, copy-ready recovery/update commands, recipes, modules, and current paths. --tray starts a native Windows task-tray command center."
                Notes       = "Launchpad is read-only and local-only; tray mode uses Windows Forms and runs until you exit it from the tray icon."
                Examples    = @("windo launchpad", "windo launchpad --tray", "windo launchpad --json", "windo launchpad --open")
            },
            [pscustomobject]@{
                Name        = "export"
                Category    = "Reporting"
                Summary     = "Bundle manifest, config payload, and log excerpt."
                Syntax      = @("windo export [-o zip] [-n N] [--redact] [--json]", "windo --json export â€¦")
                Description = "Creates an audit bundle for handoff to support/debug workflows."
                Notes       = "Use --redact to mask path-like strings in JSON payloads. With --json, prints a machine-readable summary after the zip is written (path, size, audit counts)."
                Examples    = @("windo export", "windo export -o .\\bundle.zip --redact", "windo --json export -n 50")
            },
            [pscustomobject]@{
                Name        = "trace"
                Category    = "Reporting"
                Summary     = "Find a decrypted audit entry by RequestId."
                Syntax      = @("windo trace <RequestId>", "windo trace --id <RequestId>")
                Description = "Decrypts and prints a single matching audit entry."
                Notes       = "Useful for postmortem of a specific task execution."
                Examples    = @("windo trace 1234567890abcdef", "windo trace --id 1234567890abcdef")
            },
            [pscustomobject]@{
                Name        = "cleanup"
                Category    = "Maintenance"
                Summary     = "Back up and clear active log; remove pending req/res files."
                Syntax      = @("windo cleanup [-w]")
                Description = "Creates windo_history.<timestamp>.enc.bak and clears log."
                Notes       = "`-w` is accepted for compatibility and ignored."
                Examples    = @("windo cleanup", "windo cleanup -w")
            },
            [pscustomobject]@{
                Name        = "modules"
                Category    = "Shell Experience"
                Summary     = "Optional local modules under Documents\\windo\\modules (module.json + entry script)."
                Syntax      = @("windo modules list [--json]", "windo modules enable|disable <id>", "windo modules doctor [--json]", "windo modules verify [--json]")
                Description = "Lists discovered modules, toggles enabledModules in windo_prefs.json, and validates manifests. Enabled modules load after WINDO core via profile stub (failures are non-fatal)."
                Notes       = "Remote module code is never fetched during elevation; use windo extras fetch from a normal shell if using the curated index."
                Examples    = @("windo modules list --json", "windo modules enable my-mod", "windo modules doctor")
            },
            [pscustomobject]@{
                Name        = "recipes"
                Category    = "Operators"
                Summary     = "Built-in elevated command templates (reviewed, bundled data)."
                Syntax      = @("windo recipes [list] [--json]", "windo recipes show <name> [--json]", "windo recipes preview <name> [--json]", "windo recipes run <name> [--dry-run]", "windo run --recipe <name> [--dry-run]")
                Description = "Shows named templates that expand to fixed cmd.exe-friendly command lines executed via the normal WINDO elevation path."
                Notes       = "preview and --dry-run are read-only and return the exact elevated command without creating request files or appending audit entries."
                Examples    = @("windo recipes", "windo recipes show firewall-profiles", "windo recipes preview firewall-profiles --json", "windo recipes run ollama-list --dry-run", "windo run --recipe os-version")
            },
            [pscustomobject]@{
                Name        = "venv"
                Aliases     = @("python venv", "pyenv")
                Category    = "Developer"
                Summary     = "Create and activate local Python virtual environments."
                Syntax      = @("windo venv status [path] [--json]", "windo venv create [path] [--python <exe>]", "windo venv activate [path]", "windo venv deactivate", "windo venv remove <path> --force")
                Description = "Manages Python virtual environments without elevation. Activation dot-sources the selected Activate.ps1 in the current shell."
                Notes       = "Default path is .\\.venv. remove requires --force. This is intentionally local-user tooling, not scheduled-task elevation."
                Examples    = @("windo venv create", "windo venv activate", "windo venv status --json", "windo venv remove .\\.venv --force")
            },
            [pscustomobject]@{
                Name        = "pkg"
                Aliases     = @("package", "installer")
                Category    = "Packages"
                Summary     = "Route winget, choco, and scoop installs with clearer WINDO intent."
                Syntax      = @("windo pkg status [--json]", "windo pkg winget <args...>", "windo pkg choco <args...>", "windo pkg scoop <args...>")
                Description = "Normalizes package-manager execution into WINDO's elevated runner path where appropriate and prints manager-specific guidance before handoff."
                Notes       = "winget/choco often need elevation for machine installs. scoop is usually user-scoped; WINDO warns because elevated context can differ from your normal user."
                Examples    = @("windo pkg status", "windo pkg winget install Microsoft.PowerShell", "windo pkg choco install git -y", "windo pkg scoop install ripgrep")
            },
            [pscustomobject]@{
                Name        = "container"
                Category    = "Operators"
                Summary     = "Run container actions through docker or podman locally."
                Syntax      = @("windo container [ps|images|status|logs|restart|start|stop|rmi|rm|pull] [--runtime docker|podman|auto] [args...]", "windo container ps --runtime podman", "windo container logs --runtime docker <id> [--tail 100]", "windo container pull --runtime auto <image>")
                Description = "Provides a minimal-risk local wrapper that validates runtime selection, verifies requested subcommand and arguments, and can print structured JSON output."
                Notes       = "Supported subcommands are explicitly validated. In --runtime auto mode, WINDO prefers docker when both are available."
                Examples    = @("windo container ps", "windo container images --runtime podman --json", "windo container status --runtime docker", "windo container --runtime docker logs <id>", "windo container --dry-run pull nginx:latest")
            },
            [pscustomobject]@{
                Name        = "wsl"
                Category    = "Operators"
                Summary     = "WSL distro status, conversion, checks, inspection, command forwarding, path conversions, import/export checks, and safe execution."
                Syntax      = @(
                    "windo wsl status|list|ls [--json]",
                    "windo wsl check install|distro|import|export [--json]",
                    "windo wsl check distro --distro <name> [--json]",
                    "windo wsl check import --name <distro> --tar <file> --path <installPath> [--version 1|2] [--json]",
                    "windo wsl check export --name <distro> --out <tar> [--json]",
                    "windo wsl install --distro <name> [--apply] [--dry-run] [--json]",
                    "windo wsl version",
                    "windo wsl convert --distro <name> --to 1|2 --apply [--dry-run] [--json]",
                    "windo wsl inspect --distro <name> [--json]",
                    "windo wsl exec [--distro <name>] -- <command...>",
                    "windo wsl launch <distro> [--user <name>] [--command <cmd>] [--json]",
                    "windo wsl path to-wsl|to-win --path <value> [--distro <name>] [--json]",
                    "windo wsl import --name <distro> --tar <file> --path <installPath> --apply [--dry-run] [--json]",
                    "windo wsl export --name <distro> --out <tar> --apply [--dry-run] [--json]"
                )
                Description = "Read/write-friendly entry points for WSL operators. Install/convert/import/export require --apply (and pass confirmation in interactive mode)."
                Notes       = "Use --dry-run for command preview without execution. `wsl exec` forwards raw command arguments to WSL after `--`."
                Examples    = @(
                    "windo wsl status --json",
                    "windo wsl check distro --distro Ubuntu-22.04",
                    "windo wsl inspect --distro Ubuntu-22.04 --json",
                    "windo wsl convert --distro Ubuntu-22.04 --to 2 --apply",
                    "windo wsl path to-wsl --path C:\\Users\\You",
                    "windo wsl launch Ubuntu-22.04 --command bash -lc 'ls /'",
                    "windo wsl import --name mydistro --tar .\\backup.tar --path C:\\WSL\\mydistro --apply"
                )
            },
            [pscustomobject]@{
                Name        = "mesh"
                Category    = "Planning"
                Summary     = "Operator Mesh inventory, doctor, cockpit, and workbench."
                Syntax      = @("windo mesh [--json]", "windo mesh doctor [--json]", "windo mesh workbench [--json]", "windo mesh workbench --html [--output path|--output=path]", "windo mesh --html [--output path|--output=path]", "windo mesh --open")
                Description = "Read-only inventory, readiness doctor, local cockpit HTML, and V4 workflow workbench that join modules, recipes, extras, launchpad/tray assets, audit state, and export readiness into one platform view."
                Notes       = "Does not fetch remote extras, start launchpad, write exports, or run elevated commands. HTML/open only write a local artifact under Documents\\windo unless --output is supplied."
                Examples    = @("windo mesh", "windo mesh doctor", "windo mesh workbench", "windo mesh workbench --html", "windo mesh --open")
            },
            [pscustomobject]@{
                Name        = "prompt"
                Category    = "Shell Experience"
                Summary     = "Oh My Posh / terminal theme bridge (env + sample segment)."
                Syntax      = @("windo prompt [--json]", "windo prompt --export <path>")
                Description = "Prints guidance and a sample Oh My Posh segment JSON using WINDO_* environment variables exposed after elevation."
                Notes       = "WINDO does not ship a full theme; integrate with your existing Oh My Posh configuration."
                Examples    = @("windo prompt", "windo prompt --json", "windo prompt --export $HOME\\Documents\\windo\\windo_omp_snippet.json")
            },
            [pscustomobject]@{
                Name        = "extras"
                Category    = "Shell Experience"
                Summary     = "Curated optional extras index (read-only catalog + verified fetch)."
                Syntax      = @("windo extras search [query] [--json]", "windo extras fetch <id> [--force]")
                Description = "Downloads the published extras index from GitHub (v6) and searches entries. Fetch downloads artifacts only from a non-elevated shell and verifies SHA256 when published."
                Notes       = "Override index URL with WINDO_EXTRAS_INDEX_URL for forks or air-gapped mirrors."
                Examples    = @("windo extras search sample", "windo extras fetch sample-hello")
            },
            [pscustomobject]@{
                Name        = "dev"
                Category    = "Developers"
                Summary     = "Scaffold a local WINDO module folder."
                Syntax      = @("windo dev init-module [name]")
                Description = "Creates module.json, Load.ps1, and README.md under Documents\\windo\\modules for contributors."
                Notes       = "Does not enable the module; use windo modules enable."
                Examples    = @("windo dev init-module my-mod")
            },
            [pscustomobject]@{
                Name        = "session"
                Category    = "Inspection"
                Summary     = "Compact session-oriented summary (audit tail + integrity + last command)."
                Syntax      = @("windo session [--json]")
                Description = "Combines task presence, integrity levels, last stored interactive command, and the last decrypted audit entries (compact) for dashboards."
                Notes       = "Read-only; does not execute elevated tasks."
                Examples    = @("windo session --json")
            },
            [pscustomobject]@{
                Name        = "ai"
                Category    = "Shell Experience"
                Summary     = "AI / agent / Ollama env hygiene: names only (never prints secret values)."
                Syntax      = @("windo ai [status] [--json]", "windo ai doctor [--json]")
                Description = "Read-only snapshot of cloud API-key and Ollama-related environment variable names across Process, User, and Machine scopes. Doctor can hint on OLLAMA_HOST exposure. Does not call remote inference APIs or store keys."
                Notes       = "Prefer vault or user-scoped storage; never pass API keys via windo --preserve-env. See docs/ai-bridge.md."
                Examples    = @("windo ai", "windo ai doctor --json")
            },
            [pscustomobject]@{
                Name        = "repair"
                Category    = "Recovery"
                Summary     = "Quick recovery: keybindings safe-reset + hints for profile refresh and install-latest."
                Syntax      = @("windo repair [all|keybindings] [--json]")
                Description = "Runs the same keybindings path as 'windo keybindings safe-reset' (Alt+w, clears legacy WINDO PSReadLine chords in-session). Use when upgrading from older WINDO or when the prefix/w key feels stuck. Does not download the installer."
                Notes       = "For a full profile refresh from v6, run 'windo install-latest' from a non-elevated shell after repair."
                Examples    = @("windo repair", "windo repair keybindings --json")
            }
        )
    }

    function _windo_show_help {
        param([string]$Topic = "")
        $topics = _windo_help_topics
        $topicNorm = ""
        if (-not [string]::IsNullOrWhiteSpace($Topic)) { $topicNorm = [string]$Topic.Trim().ToLowerInvariant() }

        function _windo_render_examples([array]$rows) {
            foreach ($ex in $rows) { Write-Host "  $ex" -ForegroundColor DarkGray }
        }

        if ([string]::IsNullOrWhiteSpace($topicNorm)) {
            if ($JsonOutput) {
                _emit_json "help" @{
                    topic = $null
                    available = @($topics | Select-Object Name,Category,Aliases,Summary,Syntax,Description,Notes)
                    usage = "windo [--json] [--dry-run] [<global sudo flag>] <command>"
                    exitCode = 0
                }
                return
            }
            Write-Host "[windo] WINDO help" -ForegroundColor Cyan
            Write-Host "Usage: windo [--json] [--dry-run] [<global sudo flag>] <command>" -ForegroundColor DarkGray
            Write-Host "Global flags:" -ForegroundColor Yellow
            Write-Host "  --json, -Json     machine-readable payload" -ForegroundColor DarkGray
            Write-Host "  --dry-run         show command and paths only (no task + no log write)" -ForegroundColor DarkGray
            Write-Host "  --non-interactive, -n (before command)   skip install-latest confirmation in automation" -ForegroundColor DarkGray
            Write-Host "  --preserve-env [ALL|name1,name2], -E      pass env variables into elevated child" -ForegroundColor DarkGray
            Write-Host "  --timeout <seconds|ms>, -t              per-command runner timeout override" -ForegroundColor DarkGray
            Write-Host "  --help, -h, -?, /?                    command/topic help" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "Available commands:" -ForegroundColor Cyan
            foreach ($group in ($topics | Group-Object -Property Category | Sort-Object Name)) {
                Write-Host "  $($group.Name)" -ForegroundColor Yellow
                foreach ($entry in ($group.Group | Sort-Object Name)) {
                    $aliasText = ""
                    if ($null -ne $entry.Aliases -and $entry.Aliases.Count -gt 0) {
                        $aliasText = " (" + ($entry.Aliases -join ", ") + ")"
                    }
                    Write-Host ("    {0,-24} {1}" -f ("$($entry.Name)$aliasText"), "$($entry.Summary)") -ForegroundColor Gray
                }
            }
            Write-Host ""
            Write-Host "Run: windo help <command> or windo /? <command> for detailed usage." -ForegroundColor DarkGray
            _windo_set_exit 0
            return
        }

        $match = @($topics | Where-Object {
            $name = ([string]$_.Name).ToLowerInvariant()
            if ($name -eq $topicNorm) { return $true }
            if ($null -ne $_.Aliases) {
                foreach ($a in @($_.Aliases)) {
                    if (($a.ToLowerInvariant()) -eq $topicNorm) { return $true }
                }
            }
            return $false
        }) | Select-Object -First 1

        if ($null -eq $match) {
            $match = @($topics | Where-Object {
                $n = ([string]$_.Name).ToLowerInvariant()
                ($n -like "*$topicNorm*")
            }) | Select-Object -First 3
            if ($JsonOutput) {
                _emit_json "help" @{
                    query = $Topic
                    found = $false
                    suggestions = @($match | Select-Object Name,Category,Summary)
                    exitCode = 2
                }
                _windo_set_exit 2
                return
            }
            Write-Host "[windo] Unknown help topic: '$Topic'" -ForegroundColor Yellow
            if ($match.Count -gt 0) {
                Write-Host "Did you mean:" -ForegroundColor DarkGray
                foreach ($cand in $match) {
                    Write-Host "  windo help $($cand.Name)" -ForegroundColor DarkGray
                }
            }
            Write-Host "Use 'windo help' for full command index." -ForegroundColor DarkGray
            _windo_set_exit 2
            return
        }

        Write-Host "[windo] HELP: $($match.Name)" -ForegroundColor Cyan
        if ($JsonOutput) {
            $matchExport = $match | Select-Object Name,Aliases,Category,Summary,Description,Syntax,Notes,Examples
            _emit_json "help" @{ query = $topicNorm; found = $true; command = $matchExport; exitCode = 0 }
            _windo_set_exit 0
            return
        }
        if ($null -ne $match.Aliases -and $match.Aliases.Count -gt 0) {
            Write-Host "Aliases: $($match.Aliases -join ', ')" -ForegroundColor Yellow
        }
        Write-Host "Summary: $($match.Summary)" -ForegroundColor DarkGray
        Write-Host "Category: $($match.Category)" -ForegroundColor DarkGray
        Write-Host "Description: $($match.Description)" -ForegroundColor DarkGray
        Write-Host "Syntax:" -ForegroundColor Yellow
        foreach ($syntax in $match.Syntax) { Write-Host ("  $syntax") -ForegroundColor DarkGray }
        if ($match.Notes) { Write-Host "Notes: $($match.Notes)" -ForegroundColor DarkGray }
        if ($match.Examples -and $match.Examples.Count -gt 0) {
            Write-Host "Examples:" -ForegroundColor Yellow
            _windo_render_examples $match.Examples
        }
        Write-Host "Related: windo keybindings, windo config, windo doctor, windo version" -ForegroundColor DarkGray
        _windo_set_exit 0
    }

    if ($HelpRequested) {
        if ($Command.Count -gt 0 -and [string]::IsNullOrWhiteSpace($HelpTopic)) { $HelpTopic = [string]$Command[0] }
        _windo_show_help $HelpTopic
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "/?") {
        $topic = $null
        if ($Command.Count -ge 2) { $topic = [string]$Command[1] }
        _windo_show_help $topic
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "help") {
        $topic = $null
        if ($Command.Count -ge 2) { $topic = [string]$Command[1] }
        _windo_show_help $topic
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "-") {
        if ($Command.Count -lt 2 -or [string]::IsNullOrWhiteSpace([string]$Command[1])) {
            if ($JsonOutput) { _emit_json "account" @{ error = "missing username"; syntax = "windo - <username> [command...]"; exitCode = 2 } }
            else { Write-Host "[windo] usage: windo - <username> [command...]" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $targetUser = [string]$Command[1]
        $targetParts = if ($Command.Count -gt 2) { @($Command[2..($Command.Count - 1)]) } else { @() }
        $shellExe = $null
        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwshCmd) { $shellExe = $pwshCmd.Source } else { $shellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
        $argList = @("-NoLogo")
        if ($targetParts.Count -gt 0) {
            $targetLine = ($targetParts | ForEach-Object { _windo_quote_argument ([string]$_) }) -join " "
            $argList += @("-NoExit", "-Command", $targetLine)
        } else {
            $argList += @("-NoExit")
        }
        try {
            $cred = Get-Credential -UserName $targetUser -Message "WINDO account handoff for $targetUser"
            $p = Start-Process -FilePath $shellExe -ArgumentList $argList -Credential $cred -PassThru -ErrorAction Stop
            if ($JsonOutput) {
                _emit_json "account" @{ username = $targetUser; command = $(if ($targetParts.Count -gt 0) { ($targetParts -join " ") } else { $null }); processId = $p.Id; elevated = $false; exitCode = 0 }
            } else {
                Write-Host ("[windo] account handoff started :: user={0} pid={1}" -f $targetUser, $p.Id) -ForegroundColor Green
                Write-Host "  Note: this is a Windows credential handoff, not a Linux-style passwordless su and not automatic UAC elevation." -ForegroundColor DarkGray
            }
            _windo_set_exit 0
        } catch {
            if ($JsonOutput) { _emit_json "account" @{ username = $targetUser; error = $_.Exception.Message; exitCode = 2 } }
            else { Write-Host "[windo] account handoff failed: $($_.Exception.Message)" -ForegroundColor Red }
            _windo_set_exit 2
        }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "motion") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -in @("auto", "on", "off", "quiet")) {
            $map = _windo_read_windo_prefs_map
            $map['schemaVersion'] = "1.0"
            $map['motionMode'] = (_windo_normalize_motion_mode $sub)
            if (-not (_windo_save_windo_prefs $map)) {
                if ($JsonOutput) { _emit_json "motion" @{ error = "could not write prefs"; prefsFile = $PrefsFile; exitCode = 2 } }
                else { Write-Host "[windo] motion: could not write $PrefsFile" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = _windo_resolve_motion_policy
            if ($JsonOutput) { _emit_json "motion" @{ saved = $true; motion = $policy; exitCode = 0 } }
            else {
                Write-Host "[windo] motion mode saved: $($policy.mode)" -ForegroundColor Green
                Write-Host "  Effect: $($policy.description)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "reset") {
            $map = _windo_read_windo_prefs_map
            if ($map.Contains('motionMode')) { $map.Remove('motionMode') }
            if ($map.Contains('motionProfile')) { $map.Remove('motionProfile') }
            $map['schemaVersion'] = "1.0"
            if (-not (_windo_save_windo_prefs $map)) {
                if ($JsonOutput) { _emit_json "motion" @{ error = "could not write prefs"; prefsFile = $PrefsFile; exitCode = 2 } }
                else { Write-Host "[windo] motion reset: could not write $PrefsFile" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = _windo_resolve_motion_policy
            if ($JsonOutput) { _emit_json "motion" @{ reset = $true; motion = $policy; exitCode = 0 } }
            else { Write-Host "[windo] motion reset to default: $($policy.mode)" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "profile") {
            if ($Command.Count -lt 3 -and -not $Command.Contains("--json")) {
                if ($JsonOutput) { _emit_json "motion" @{ error = "missing profile"; expected = "ambient|subtle|steady|standard|rich|burst|cinematic|off"; exitCode = 2 } }
                else { Write-Host "[windo] motion profile: expected ambient|subtle|steady|standard|rich|burst|cinematic|off" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $newProfile = if ($Command.Count -ge 3) { [string]$Command[2] } else { "ambient" }
            $normalized = _windo_normalize_motion_profile $newProfile
            if ($normalized -eq "auto" -or $normalized -eq "off") {
                if ($normalized -eq "auto" -and -not [string]::IsNullOrWhiteSpace($newProfile)) {
                    if ($JsonOutput) { _emit_json "motion" @{ error = "invalid profile"; expected = "ambient|subtle|steady|standard|rich|burst|cinematic|off"; exitCode = 2 } }
                    else { Write-Host "[windo] motion profile: expected ambient|subtle|steady|standard|rich|burst|cinematic|off" -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
                $normalized = "off"
            }
            $map = _windo_read_windo_prefs_map
            $map['schemaVersion'] = "1.0"
            $map['motionProfile'] = $normalized
            if (-not $map.Contains('motionMode')) { $map['motionMode'] = "auto" }
            if (-not (_windo_save_windo_prefs $map)) {
                if ($JsonOutput) { _emit_json "motion" @{ error = "could not write prefs"; prefsFile = $PrefsFile; exitCode = 2 } }
                else { Write-Host "[windo] motion profile: could not write $PrefsFile" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = _windo_resolve_motion_policy
            if ($JsonOutput) { _emit_json "motion" @{ saved = $true; motionProfile = $normalized; motion = $policy; exitCode = 0 } }
            else {
                Write-Host "[windo] motion profile saved: $normalized" -ForegroundColor Green
                Write-Host "  Mode        : $($policy.mode)" -ForegroundColor DarkGray
                Write-Host "  Effect      : $($policy.description)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -in @("pulse", "demo")) {
            $policy = _windo_resolve_motion_policy
            $ran = _windo_motion_pulse "[windo] native surface warming" 1200
            if ($JsonOutput) { _emit_json "motion" @{ motion = $policy; pulseRendered = [bool]$ran; exitCode = 0 } }
            else {
                if ($ran) { Write-Host "[windo] motion pulse complete" -ForegroundColor Green }
                else { Write-Host "[windo] motion pulse skipped ($($policy.description))" -ForegroundColor DarkGray }
            }
            _windo_set_exit 0
            return
        }
            if ($sub -ne "status" -and $sub -ne "") {
                if ($JsonOutput) { _emit_json "motion" @{ error = "expected status | auto | on | quiet | off | reset | profile | pulse | demo"; exitCode = 2 } }
                else { Write-Host "[windo] motion: expected status | auto | on | quiet | off | reset | profile | pulse | demo" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $policy = _windo_resolve_motion_policy
        if ($JsonOutput) { _emit_json "motion" @{ motion = $policy; exitCode = 0 } }
        else {
            Write-Host "[windo] motion" -ForegroundColor Cyan
            Write-Host "  Mode        : $($policy.mode)" -ForegroundColor Yellow
            Write-Host "  Source      : $($policy.source)" -ForegroundColor DarkGray
            Write-Host "  Enabled now : $($policy.enabled)" -ForegroundColor DarkGray
            Write-Host "  Effect      : $($policy.description)" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "surface") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -eq "prime") {
            $state = _windo_surface_state
            try {
                if (!(Test-Path -LiteralPath $state.surfaceRoot)) { New-Item -ItemType Directory -Path $state.surfaceRoot -Force | Out-Null }
                $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $state.manifestPath -Encoding UTF8
                $state = _windo_surface_state
                if ($JsonOutput) { _emit_json "surface" @{ subcommand = "prime"; surface = $state; primed = $true; exitCode = 0 } }
                else {
                    _windo_motion_pulse "[windo] priming native surface" 900 | Out-Null
                    Write-Host "[windo] surface primed" -ForegroundColor Green
                    Write-Host "  Manifest: $($state.manifestPath)" -ForegroundColor DarkGray
                }
                _windo_set_exit 0
                return
            } catch {
                if ($JsonOutput) { _emit_json "surface" @{ subcommand = "prime"; error = $_.Exception.Message; exitCode = 2 } }
                else { Write-Host "[windo] surface prime failed: $($_.Exception.Message)" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
        }
        if ($sub -in @("pulse", "demo")) {
            $state = _windo_surface_state
            $ran = _windo_motion_pulse "[windo] surface signal" 1200
            if ($JsonOutput) { _emit_json "surface" @{ subcommand = "pulse"; surface = $state; pulseRendered = [bool]$ran; exitCode = 0 } }
            else {
                Write-Host "[windo] surface signal" -ForegroundColor Cyan
                Write-Host "  Tray support : $($state.nativeSurface.traySupported)" -ForegroundColor DarkGray
                Write-Host "  Motion       : $($state.motion.mode) enabled=$($state.motion.enabled)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "doctor") {
            $doctor = _windo_surface_doctor
            if ($JsonOutput) { _emit_json "surface" @{ subcommand = "doctor"; doctor = $doctor; exitCode = $doctor.exitCode } }
            else {
                Write-Host "[windo] surface doctor" -ForegroundColor Cyan
                Write-Host "  Readiness : $($doctor.readinessLevel)" -ForegroundColor $(if ($doctor.readinessLevel -eq "READY") { "Green" } else { "Yellow" })
                foreach ($c in @($doctor.checks)) {
                    $mark = if ($c.ok) { "[OK]" } else { "[!]" }
                    Write-Host ("  {0} {1} - {2}" -f $mark, $c.label, $c.detail) -ForegroundColor $(if ($c.ok) { "DarkGray" } else { "Yellow" })
                }
            }
            _windo_set_exit ([int]$doctor.exitCode)
            return
        }
        if ($sub -eq "repair") {
            $repair = _windo_surface_repair
            if ($JsonOutput) { _emit_json "surface" @{ subcommand = "repair"; repair = $repair; exitCode = $repair.exitCode } }
            else {
                _windo_motion_pulse "[windo] success pulse" 800 | Out-Null
                Write-Host "[windo] surface repair" -ForegroundColor Cyan
                foreach ($r in @($repair.results)) {
                    Write-Host ("  {0,-16} ok={1} changed={2} {3}" -f $r.id, $r.ok, $r.changed, $r.path) -ForegroundColor $(if ($r.ok) { "Green" } else { "Red" })
                    if ($r.error) { Write-Host "                  $($r.error)" -ForegroundColor DarkYellow }
                }
            }
            _windo_set_exit ([int]$repair.exitCode)
            return
        }
        if ($sub -in @("panel", "window")) {
            $panelResult = _windo_start_surface_panel
            $exit = if ($panelResult.ok) { 0 } else { 3 }
            if ($JsonOutput) { _emit_json "surface" @{ subcommand = "panel"; panel = $panelResult; exitCode = $exit } }
            else {
                Write-Host "[windo] surface panel" -ForegroundColor Cyan
                if ($panelResult.ok) { Write-Host "  Panel started: $($panelResult.path)" -ForegroundColor Green }
                else { Write-Host "  Panel failed : $($panelResult.error)" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "open") {
            $trayResult = _windo_start_launchpad_tray
            $exit = if ($trayResult.ok) { 0 } else { 3 }
            if ($JsonOutput) { _emit_json "surface" @{ subcommand = "open"; tray = $trayResult; exitCode = $exit } }
            else {
                Write-Host "[windo] surface open" -ForegroundColor Cyan
                if ($trayResult.ok) { Write-Host "  Tray started: $($trayResult.path)" -ForegroundColor Green }
                else { Write-Host "  Tray failed : $($trayResult.error)" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -notin @("status", "")) {
            if ($JsonOutput) { _emit_json "surface" @{ error = "expected status | prime | pulse | doctor | repair | open | panel"; exitCode = 2 } }
            else { Write-Host "[windo] surface: expected status | prime | pulse | doctor | repair | open | panel" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $state = _windo_surface_state
        $exit = if ($state.ready) { 0 } elseif ($state.profileIssues.Count -gt 0) { 3 } else { 0 }
        if ($JsonOutput) { _emit_json "surface" @{ subcommand = "status"; surface = $state; exitCode = $exit } }
        else {
            Write-Host "[windo] native surface" -ForegroundColor Cyan
            Write-Host "  Ready        : $($state.ready)" -ForegroundColor $(if ($state.ready) { "Green" } else { "Yellow" })
            Write-Host "  Tray support : $($state.nativeSurface.traySupported)" -ForegroundColor DarkGray
            Write-Host "  Tray script  : $($state.nativeSurface.trayScriptPath)" -ForegroundColor DarkGray
            Write-Host "  Panel script : $($state.nativeSurface.panelScriptPath)" -ForegroundColor DarkGray
            Write-Host "  Studio script: $($state.nativeSurface.studioScriptPath)" -ForegroundColor DarkGray
            Write-Host "  Motion       : $($state.motion.mode) enabled=$($state.motion.enabled)" -ForegroundColor DarkGray
            if ($state.profileIssues.Count -gt 0) {
                Write-Host "  Profile issues:" -ForegroundColor Yellow
                foreach ($issue in @($state.profileIssues)) {
                    Write-Host "    - $($issue.id) line=$($issue.lineNumber): $($issue.detail)" -ForegroundColor DarkYellow
                    if ($issue.fixCommand) { Write-Host "      fix: $($issue.fixCommand)" -ForegroundColor DarkGray }
                }
            }
            Write-Host "  Open         : windo center studio | windo surface panel | windo launchpad --tray" -ForegroundColor DarkGray
            Write-Host "  Prime        : windo surface prime" -ForegroundColor DarkGray
        }
        _windo_set_exit $exit
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "integrate") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -in @("prime", "repair")) {
            $result = _windo_integration_repair @("all")
            $exit = [int]$result.exitCode
            if ($JsonOutput) { _emit_json "integrate" @{ subcommand = $sub; result = $result; exitCode = $exit } }
            else {
                _windo_motion_pulse "[windo] repairing Windows integration" 950 | Out-Null
                Write-Host "[windo] Windows integration repair" -ForegroundColor Cyan
                foreach ($r in @($result.results)) {
                    $color = if ($r.ok) { if ($r.changed) { "Green" } else { "DarkGray" } } else { "Red" }
                    Write-Host ("  {0,-16} {1} {2}" -f $r.id, $(if ($r.changed) { "changed" } else { "ok" }), $r.path) -ForegroundColor $color
                    if (-not $r.ok -and $r.error) { Write-Host ("    error: {0}" -f $r.error) -ForegroundColor Red }
                }
                Write-Host "  Note         : new shells see PATH changes after restart" -ForegroundColor DarkGray
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -in @("shortcuts", "startup", "shim")) {
            $result = _windo_integration_repair @($sub)
            $exit = [int]$result.exitCode
            if ($JsonOutput) { _emit_json "integrate" @{ subcommand = $sub; result = $result; exitCode = $exit } }
            else {
                Write-Host "[windo] Windows integration $sub" -ForegroundColor Cyan
                foreach ($r in @($result.results)) {
                    Write-Host ("  {0,-16} {1}" -f $r.id, $r.path) -ForegroundColor $(if ($r.ok) { "DarkGray" } else { "Red" })
                }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "doctor") {
            $doctor = _windo_integration_doctor
            if ($JsonOutput) { _emit_json "integrate" @{ subcommand = "doctor"; doctor = $doctor; exitCode = $doctor.exitCode } }
            else {
                Write-Host "[windo] Windows integration doctor" -ForegroundColor Cyan
                Write-Host "  Readiness : $($doctor.readinessLevel)" -ForegroundColor $(if ($doctor.readinessLevel -eq "READY") { "Green" } else { "Yellow" })
                foreach ($c in @($doctor.checks)) {
                    Write-Host ("  {0,-28} {1}" -f $c.label, $(if ($c.ok) { "OK" } else { "ATTENTION" })) -ForegroundColor $(if ($c.ok) { "DarkGray" } else { "Yellow" })
                    if (-not $c.ok -and $c.fixCommand) { Write-Host ("    fix: {0}" -f $c.fixCommand) -ForegroundColor DarkGray }
                }
            }
            _windo_set_exit ([int]$doctor.exitCode)
            return
        }
        if ($sub -eq "open") {
            try {
                $opened = _windo_integration_open
                if ($JsonOutput) { _emit_json "integrate" @{ subcommand = "open"; result = $opened; exitCode = 0 } }
                else { Write-Host "[windo] opened WINDO shortcuts: $($opened.path)" -ForegroundColor Green }
                _windo_set_exit 0
            } catch {
                if ($JsonOutput) { _emit_json "integrate" @{ subcommand = "open"; error = $_.Exception.Message; exitCode = 2 } }
                else { Write-Host "[windo] integrate open failed: $($_.Exception.Message)" -ForegroundColor Red }
                _windo_set_exit 2
            }
            return
        }
        if ($sub -notin @("status", "")) {
            if ($JsonOutput) { _emit_json "integrate" @{ error = "expected status | doctor | prime | repair | shortcuts | startup | shim | open"; exitCode = 2 } }
            else { Write-Host "[windo] integrate: expected status | doctor | prime | repair | shortcuts | startup | shim | open" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $state = _windo_integration_state
        if ($JsonOutput) { _emit_json "integrate" @{ subcommand = "status"; integration = $state; exitCode = $state.exitCode } }
        else {
            Write-Host "[windo] Windows integration" -ForegroundColor Cyan
            Write-Host "  Ready      : $($state.ready)" -ForegroundColor $(if ($state.ready) { "Green" } else { "Yellow" })
            Write-Host "  Shim       : $($state.shimPath)" -ForegroundColor DarkGray
            Write-Host "  Startup    : $($state.startupScriptPath)" -ForegroundColor DarkGray
            Write-Host "  Start Menu : $($state.startMenuDir)" -ForegroundColor DarkGray
            Write-Host "  Repair     : windo integrate repair" -ForegroundColor DarkGray
        }
        _windo_set_exit ([int]$state.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "control") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -eq "prime") {
            try {
                $state = _windo_control_write_manifest
                if ($JsonOutput) { _emit_json "control" @{ subcommand = "prime"; control = $state; primed = $true; exitCode = 0 } }
                else {
                    _windo_motion_pulse "[windo] priming control plane" 950 | Out-Null
                    Write-Host "[windo] control plane primed" -ForegroundColor Green
                    Write-Host "  Manifest : $($state.manifestPath)" -ForegroundColor DarkGray
                    Write-Host "  Queue    : $($state.queueRoot)" -ForegroundColor DarkGray
                }
                _windo_set_exit 0
                return
            } catch {
                if ($JsonOutput) { _emit_json "control" @{ subcommand = "prime"; error = $_.Exception.Message; exitCode = 2 } }
                else { Write-Host "[windo] control prime failed: $($_.Exception.Message)" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
        }
        if ($sub -eq "actions") {
            $state = _windo_control_state
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "actions"; actions = @($state.actions); exitCode = 0 } }
            else {
                Write-Host "[windo] control actions" -ForegroundColor Cyan
                foreach ($a in @($state.actions)) {
                    Write-Host ("  {0,-16} {1}" -f $a.id, $a.command) -ForegroundColor DarkGray
                }
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "preview") {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "control" @{ subcommand = "preview"; error = "missing action id"; exitCode = 2 } }
                else { Write-Host "[windo] control preview: expected action id. Try: windo control actions" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $preview = _windo_control_action_preview ([string]$Command[2])
            $exit = [int]$preview.exitCode
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "preview"; preview = $preview; exitCode = $exit } }
            else {
                if ($preview.ok) {
                    Write-Host "[windo] control preview" -ForegroundColor Cyan
                    Write-Host "  Action : $($preview.actionId)" -ForegroundColor DarkGray
                    Write-Host "  Route  : $($preview.route)" -ForegroundColor DarkGray
                    Write-Host "  Command: $($preview.command)" -ForegroundColor DarkGray
                } else {
                    Write-Host "[windo] control preview failed: $($preview.error)" -ForegroundColor Yellow
                }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "history") {
            $limit = 25
            if ($Command.Count -ge 3) { try { $limit = [Math]::Max(1, [int]$Command[2]) } catch { $limit = 25 } }
            $history = @(_windo_control_history $limit)
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "history"; history = $history; exitCode = 0 } }
            else {
                Write-Host "[windo] control history" -ForegroundColor Cyan
                foreach ($h in @($history)) {
                    Write-Host ("  {0,-26} {1,-10} {2}" -f $h.id, $h.status, $h.command) -ForegroundColor DarkGray
                }
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "inspect") {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "control" @{ subcommand = "inspect"; error = "missing request id"; exitCode = 2 } }
                else { Write-Host "[windo] control inspect: expected request id" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $found = _windo_control_find_request ([string]$Command[2])
            $exit = if ($found) { 0 } else { 2 }
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "inspect"; request = $found; exitCode = $exit } }
            else {
                if ($found) {
                    Write-Host "[windo] control request" -ForegroundColor Cyan
                    Write-Host "  Id     : $($found.request.id)" -ForegroundColor DarkGray
                    Write-Host "  Status : $($found.request.status)" -ForegroundColor DarkGray
                    Write-Host "  Command: $($found.request.command)" -ForegroundColor DarkGray
                    Write-Host "  Path   : $($found.path)" -ForegroundColor DarkGray
                    if ($found.resultPath -and (Test-Path -LiteralPath $found.resultPath)) { Write-Host "  Result : $($found.resultPath)" -ForegroundColor DarkGray }
                } else { Write-Host "[windo] control inspect: request not found" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "cancel") {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "control" @{ subcommand = "cancel"; error = "missing request id"; exitCode = 2 } }
                else { Write-Host "[windo] control cancel: expected request id" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $result = _windo_control_cancel_request ([string]$Command[2])
            $exit = if ($result.ok) { 0 } else { 2 }
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "cancel"; result = $result; exitCode = $exit } }
            else {
                if ($result.ok) { Write-Host "[windo] control request cancelled: $($result.id)" -ForegroundColor Green }
                else { Write-Host "[windo] control cancel failed: $($result.error)" -ForegroundColor Red }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -in @("execute-next", "next")) {
            $result = _windo_control_execute_next
            $exit = [int]$result.exitCode
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "execute-next"; result = $result; exitCode = $exit } }
            else {
                if ($result.ok) {
                    _windo_motion_pulse "[windo] queue/run progress pulse" 900 | Out-Null
                    Write-Host "[windo] control execute-next launched" -ForegroundColor Green
                    Write-Host "  Request: $($result.request.id)" -ForegroundColor DarkGray
                    Write-Host "  Result : $($result.resultPath)" -ForegroundColor DarkGray
                } else {
                    _windo_motion_pulse "[windo] warning pulse" 700 | Out-Null
                    Write-Host "[windo] control execute-next: $($result.error)" -ForegroundColor Yellow
                }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "execute") {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "control" @{ subcommand = "execute"; error = "missing request id"; exitCode = 2 } }
                else { Write-Host "[windo] control execute: expected request id" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $result = _windo_control_execute_request ([string]$Command[2])
            $exit = [int]$result.exitCode
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "execute"; result = $result; exitCode = $exit } }
            else {
                if ($result.ok) {
                    _windo_motion_pulse "[windo] queue/run progress pulse" 900 | Out-Null
                    Write-Host "[windo] control execute launched" -ForegroundColor Green
                    Write-Host "  Request: $($result.request.id)" -ForegroundColor DarkGray
                    Write-Host "  Result : $($result.resultPath)" -ForegroundColor DarkGray
                } else {
                    Write-Host "[windo] control execute failed: $($result.error)" -ForegroundColor Yellow
                }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "queue") {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "control" @{ subcommand = "queue"; error = "missing action id"; exitCode = 2 } }
                else { Write-Host "[windo] control queue: expected action id. Try: windo control actions" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $note = $null
            if ($Command.Count -gt 3) { $note = (@($Command | Select-Object -Skip 3) -join " ") }
            $result = _windo_control_queue_action ([string]$Command[2]) $note
            $exit = if ($result.ok) { 0 } else { 2 }
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "queue"; result = $result; exitCode = $exit } }
            else {
                if ($result.ok) {
                    Write-Host "[windo] control request queued" -ForegroundColor Green
                    Write-Host "  Action : $($result.request.actionId)" -ForegroundColor DarkGray
                    Write-Host "  Path   : $($result.path)" -ForegroundColor DarkGray
                } else {
                    Write-Host "[windo] control queue failed: $($result.error)" -ForegroundColor Red
                }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "run") {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "control" @{ subcommand = "run"; error = "missing action id"; exitCode = 2 } }
                else { Write-Host "[windo] control run: expected action id. Try: windo control actions" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $result = _windo_control_start_action ([string]$Command[2])
            $exit = if ($result.ok) { 0 } else { 2 }
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "run"; result = $result; exitCode = $exit } }
            else {
                if ($result.ok) {
                    Write-Host "[windo] control launched" -ForegroundColor Green
                    Write-Host "  Action : $($result.actionId)" -ForegroundColor DarkGray
                    Write-Host "  Command: $($result.command)" -ForegroundColor DarkGray
                } else {
                    Write-Host "[windo] control run failed: $($result.error)" -ForegroundColor Red
                }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -in @("pulse", "demo")) {
            $state = _windo_control_state
            $ran = _windo_motion_pulse "[windo] control plane signal" 1200
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "pulse"; control = $state; pulseRendered = [bool]$ran; exitCode = 0 } }
            else {
                Write-Host "[windo] control plane signal" -ForegroundColor Cyan
                Write-Host "  Actions : $($state.actions.Count)" -ForegroundColor DarkGray
                Write-Host "  Queued  : $($state.queuedCount)" -ForegroundColor DarkGray
                Write-Host "  Motion  : $($state.motion.mode) enabled=$($state.motion.enabled)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "clear") {
            $queueRoot = _windo_control_queue_root
            $removed = 0
            if (Test-Path -LiteralPath $queueRoot) {
                foreach ($f in @(Get-ChildItem -LiteralPath $queueRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                    $removed++
                }
            }
            if ($JsonOutput) { _emit_json "control" @{ subcommand = "clear"; removed = $removed; exitCode = 0 } }
            else { Write-Host "[windo] control queue cleared: $removed request(s)" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($sub -notin @("status", "")) {
            if ($JsonOutput) { _emit_json "control" @{ error = "expected status | prime | actions | preview | queue | run | execute-next | next | execute | inspect | cancel | history | pulse | clear"; exitCode = 2 } }
            else { Write-Host "[windo] control: expected status | prime | actions | preview | queue | run | execute-next | next | execute | inspect | cancel | history | pulse | clear" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $state = _windo_control_state
        if ($JsonOutput) { _emit_json "control" @{ subcommand = "status"; control = $state; exitCode = 0 } }
        else {
            Write-Host "[windo] control plane" -ForegroundColor Cyan
            Write-Host "  Status   : $($state.status)" -ForegroundColor $(if ($state.status -eq "ready") { "Green" } elseif ($state.status -eq "attention") { "Yellow" } else { "DarkYellow" })
            Write-Host "  Manifest : $($state.manifestPath)" -ForegroundColor DarkGray
            Write-Host "  Actions  : $($state.actions.Count)" -ForegroundColor DarkGray
            Write-Host "  Queued   : $($state.queuedCount)" -ForegroundColor DarkGray
            Write-Host "  Next     : windo control prime | windo control actions | windo control queue surface-prime" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "signal") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        $outPath = Join-Path (Join-Path $HOME "Documents") ("windo\windo_signal_{0}.html" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        $openHtml = $false
        for ($si = 1; $si -lt $Command.Count; $si++) {
            $sa = [string]$Command[$si]
            if ($sa -eq "--open" -or $sa -eq "--html") { $openHtml = ($sa -eq "--open"); continue }
            if (($sa -eq "--output" -or $sa -eq "-o") -and ($si + 1) -lt $Command.Count) { $outPath = [string]$Command[$si + 1]; $si++; continue }
            if ($sa -like "--output=*") { $outPath = $sa.Substring(9); continue }
        }
        if ($sub -eq "last") {
            $signal = _windo_signal_state 25
            if ($JsonOutput) { _emit_json "signal" @{ subcommand = "last"; last = $signal.last; exitCode = 0 } }
            else {
                Write-Host "[windo] signal last" -ForegroundColor Cyan
                if ($signal.last) { Write-Host ("  {0} {1} {2}" -f $signal.last.type, $signal.last.status, $signal.last.command) -ForegroundColor DarkGray }
                else { Write-Host "  No signal timeline entries yet." -ForegroundColor DarkGray }
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "timeline") {
            $signal = _windo_signal_state 40
            if ($JsonOutput) { _emit_json "signal" @{ subcommand = "timeline"; signal = $signal; exitCode = $signal.exitCode } }
            else {
                Write-Host "[windo] signal timeline" -ForegroundColor Cyan
                foreach ($t in @($signal.timeline | Select-Object -First 20)) {
                    Write-Host ("  {0,-10} {1,-10} {2}" -f $t.type, $t.status, $t.command) -ForegroundColor DarkGray
                }
            }
            _windo_set_exit ([int]$signal.exitCode)
            return
        }
        if ($sub -eq "open") { $openHtml = $true }
        if ($sub -in @("export", "open", "html") -or $Command -contains "--html" -or $Command -contains "--open") {
            $signal = _windo_signal_state 80
            $htmlPath = _windo_write_signal_html $signal $outPath $openHtml
            if ($JsonOutput) { _emit_json "signal" @{ subcommand = $(if ($sub -eq "open") { "open" } else { "export" }); signal = $signal; htmlPath = $htmlPath; exitCode = 0 } }
            else { Write-Host "[windo] signal deck: $htmlPath" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($sub -notin @("status", "")) {
            if ($JsonOutput) { _emit_json "signal" @{ error = "expected status | timeline | last | export | open"; exitCode = 2 } }
            else { Write-Host "[windo] signal: expected status | timeline | last | export | open" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $signal = _windo_signal_state 25
        if ($JsonOutput) { _emit_json "signal" @{ subcommand = "status"; signal = $signal; exitCode = $signal.exitCode } }
        else {
            Write-Host "[windo] signal deck" -ForegroundColor Cyan
            Write-Host "  Status  : $($signal.status)" -ForegroundColor $(if ($signal.status -eq "ready") { "Green" } else { "Yellow" })
            Write-Host "  Control : queued=$($signal.control.queuedCount), requests=$($signal.control.requestCount)" -ForegroundColor DarkGray
            Write-Host "  Trust   : $($signal.trust.trustLevel) ($($signal.trust.score)/100)" -ForegroundColor DarkGray
            Write-Host "  Next    : windo signal timeline | windo signal export --open" -ForegroundColor DarkGray
        }
        _windo_set_exit ([int]$signal.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "edition") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        $outPath = Join-Path (Join-Path $HOME "Documents") ("windo\windo_edition_{0}.html" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        $openHtml = $false
        for ($ei = 1; $ei -lt $Command.Count; $ei++) {
            $ea = [string]$Command[$ei]
            if ($ea -eq "--open") { $openHtml = $true; continue }
            if (($ea -eq "--output" -or $ea -eq "-o") -and ($ei + 1) -lt $Command.Count) { $outPath = [string]$Command[$ei + 1]; $ei++; continue }
            if ($ea -like "--output=*") { $outPath = $ea.Substring(9); continue }
        }
        if ($sub -eq "pulse") {
            $edition = _windo_edition_state
            $ran = _windo_motion_edition "[windo] WINDO Command Center" 1500
            if ($JsonOutput) { _emit_json "edition" @{ subcommand = "pulse"; edition = $edition; pulseRendered = [bool]$ran; exitCode = 0 } }
            else {
                Write-Host "[windo] WINDO Command Center pulse" -ForegroundColor Cyan
                Write-Host "  Motion : $($edition.motion.mode) enabled=$($edition.motion.enabled)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -in @("open", "html", "export") -or $Command -contains "--open") {
            if ($sub -eq "open") { $openHtml = $true }
            $edition = _windo_edition_state
            $htmlPath = _windo_write_edition_html $edition $outPath $openHtml
            if ($JsonOutput) { _emit_json "edition" @{ subcommand = $(if ($openHtml) { "open" } else { "html" }); edition = $edition; htmlPath = $htmlPath; exitCode = 0 } }
            else { Write-Host "[windo] command center console: $htmlPath" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($sub -notin @("status", "")) {
            if ($JsonOutput) { _emit_json "edition" @{ error = "expected status | open | html | pulse"; exitCode = 2 } }
            else { Write-Host "[windo] edition: expected status | open | html | pulse" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $edition = _windo_edition_state
        if ($JsonOutput) { _emit_json "edition" @{ subcommand = "status"; edition = $edition; exitCode = $edition.exitCode } }
        else {
            Write-Host "[windo] Command Center" -ForegroundColor Cyan
            Write-Host "  Version : $($edition.windoVersion)" -ForegroundColor DarkGray
            Write-Host "  Center  : $($edition.center.status)" -ForegroundColor $(if ($edition.center.status -eq "ready") { "Green" } else { "Yellow" })
            Write-Host "  Visual  : windo edition open" -ForegroundColor DarkGray
            Write-Host "  Motion  : windo edition pulse" -ForegroundColor DarkGray
        }
        _windo_set_exit ([int]$edition.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "center") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -in @("studio", "wizard", "power")) {
            $studioResult = _windo_start_power_studio
            $center = _windo_center_state
            $exit = if ($studioResult.ok) { 0 } else { 3 }
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "studio"; center = $center; studio = $studioResult; exitCode = $exit } }
            else {
                Write-Host "[windo] power studio" -ForegroundColor Cyan
                if ($studioResult.ok) { Write-Host "  Studio started: $($studioResult.path)" -ForegroundColor Green }
                else { Write-Host "  Studio failed : $($studioResult.error)" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -in @("panel", "surface")) {
            $panelResult = _windo_start_surface_panel
            $center = _windo_center_state
            $exit = if ($panelResult.ok) { 0 } else { 3 }
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "panel"; center = $center; panel = $panelResult; exitCode = $exit } }
            else {
                Write-Host "[windo] command center panel" -ForegroundColor Cyan
                if ($panelResult.ok) { Write-Host "  Panel started: $($panelResult.path)" -ForegroundColor Green }
                else { Write-Host "  Panel failed : $($panelResult.error)" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "open" -or $sub -eq "tray") {
            $trayResult = _windo_start_launchpad_tray
            $center = _windo_center_state
            $exit = if ($trayResult.ok) { 0 } else { 3 }
            if ($JsonOutput) { _emit_json "center" @{ subcommand = $sub; center = $center; tray = $trayResult; exitCode = $exit } }
            else {
                Write-Host "[windo] command center" -ForegroundColor Cyan
                if ($trayResult.ok) { Write-Host "  Tray started: $($trayResult.path)" -ForegroundColor Green }
                else { Write-Host "  Tray failed : $($trayResult.error)" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "actions") {
            $state = _windo_control_state
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "actions"; actions = @($state.actions); exitCode = 0 } }
            else {
                Write-Host "[windo] center actions" -ForegroundColor Cyan
                foreach ($a in @($state.actions)) { Write-Host ("  {0,-16} {1}" -f $a.id, $a.command) -ForegroundColor DarkGray }
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "preview") {
            if ($Command.Count -lt 3) { if ($JsonOutput) { _emit_json "center" @{ error = "missing action id"; exitCode = 2 } } else { Write-Host "[windo] center preview: expected action id" -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $preview = _windo_control_action_preview ([string]$Command[2])
            $exit = [int]$preview.exitCode
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "preview"; preview = $preview; exitCode = $exit } }
            else {
                if ($preview.ok) { Write-Host "[windo] center preview: $($preview.actionId) -> $($preview.command)" -ForegroundColor Cyan }
                else { Write-Host "[windo] center preview failed: $($preview.error)" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "queue") {
            if ($Command.Count -lt 3) { if ($JsonOutput) { _emit_json "center" @{ error = "missing action id"; exitCode = 2 } } else { Write-Host "[windo] center queue: expected action id" -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $note = $null
            if ($Command.Count -gt 3) { $note = (@($Command | Select-Object -Skip 3) -join " ") }
            $result = _windo_control_queue_action ([string]$Command[2]) $note
            $exit = if ($result.ok) { 0 } else { 2 }
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "queue"; result = $result; exitCode = $exit } } else { Write-Host "[windo] center queued: $($result.request.actionId)" -ForegroundColor $(if ($result.ok) { "Green" } else { "Red" }) }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "run") {
            if ($Command.Count -lt 3) { if ($JsonOutput) { _emit_json "center" @{ error = "missing action id"; exitCode = 2 } } else { Write-Host "[windo] center run: expected action id" -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $result = _windo_control_start_action ([string]$Command[2])
            $exit = if ($result.ok) { 0 } else { 2 }
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "run"; result = $result; exitCode = $exit } } else { Write-Host "[windo] center launched: $($result.command)" -ForegroundColor $(if ($result.ok) { "Green" } else { "Red" }) }
            _windo_set_exit $exit
            return
        }
        if ($sub -in @("execute-next", "next")) {
            $result = _windo_control_execute_next
            $exit = [int]$result.exitCode
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "execute-next"; result = $result; exitCode = $exit } }
            else {
                if ($result.ok) { Write-Host "[windo] center execute-next launched: $($result.request.id)" -ForegroundColor Green }
                else { Write-Host "[windo] center execute-next: $($result.error)" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "execute") {
            if ($Command.Count -lt 3) { if ($JsonOutput) { _emit_json "center" @{ error = "missing request id"; exitCode = 2 } } else { Write-Host "[windo] center execute: expected request id" -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $result = _windo_control_execute_request ([string]$Command[2])
            $exit = [int]$result.exitCode
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "execute"; result = $result; exitCode = $exit } }
            else {
                if ($result.ok) { Write-Host "[windo] center execute launched: $($result.request.id)" -ForegroundColor Green }
                else { Write-Host "[windo] center execute failed: $($result.error)" -ForegroundColor Yellow }
            }
            _windo_set_exit $exit
            return
        }
        if ($sub -eq "history") {
            $history = @(_windo_control_history 25)
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "history"; history = $history; exitCode = 0 } } else { Write-Host "[windo] center history" -ForegroundColor Cyan; foreach ($h in $history) { Write-Host ("  {0,-26} {1,-10} {2}" -f $h.id, $h.status, $h.command) -ForegroundColor DarkGray } }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "signal") {
            $signal = _windo_signal_state 25
            if ($JsonOutput) { _emit_json "center" @{ subcommand = "signal"; signal = $signal; exitCode = $signal.exitCode } }
            else {
                Write-Host "[windo] center signal" -ForegroundColor Cyan
                Write-Host "  Status : $($signal.status)" -ForegroundColor $(if ($signal.status -eq "ready") { "Green" } else { "Yellow" })
                Write-Host "  Last   : $($signal.last.command)" -ForegroundColor DarkGray
            }
            _windo_set_exit ([int]$signal.exitCode)
            return
        }
        if ($sub -notin @("status", "")) {
            if ($JsonOutput) { _emit_json "center" @{ error = "expected status | open | tray | panel | studio | actions | preview | run | queue | execute-next | next | execute | history | signal"; exitCode = 2 } } else { Write-Host "[windo] center: expected status | open | tray | panel | studio | actions | preview | run | queue | execute-next | next | execute | history | signal" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $center = _windo_center_state
        if ($JsonOutput) { _emit_json "center" @{ subcommand = "status"; center = $center; exitCode = $center.exitCode } }
        else {
            Write-Host "[windo] command center" -ForegroundColor Cyan
            Write-Host "  Status : $($center.status)" -ForegroundColor $(if ($center.status -eq "ready") { "Green" } else { "Yellow" })
            Write-Host "  Queue  : $($center.control.queuedCount) queued / $($center.control.requestCount) total" -ForegroundColor DarkGray
            Write-Host "  Open   : windo center open" -ForegroundColor DarkGray
            Write-Host "  Panel  : windo center panel" -ForegroundColor DarkGray
            Write-Host "  Studio : windo center studio" -ForegroundColor DarkGray
        }
        _windo_set_exit ([int]$center.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "studio") {
        $studioResult = _windo_start_power_studio
        $center = _windo_center_state
        $exit = if ($studioResult.ok) { 0 } else { 3 }
        if ($JsonOutput) { _emit_json "studio" @{ subcommand = "open"; center = $center; studio = $studioResult; exitCode = $exit } }
        else {
            Write-Host "[windo] power studio" -ForegroundColor Cyan
            if ($studioResult.ok) { Write-Host "  Studio started: $($studioResult.path)" -ForegroundColor Green }
            else { Write-Host "  Studio failed : $($studioResult.error)" -ForegroundColor Yellow }
        }
        _windo_set_exit $exit
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "profile") {
        $profileSub = "status"
        if ($Command.Count -ge 2 -and ([string]$Command[1]).Trim().ToLowerInvariant() -in @("status", "doctor", "repair")) {
            $profileSub = ([string]$Command[1]).Trim().ToLowerInvariant()
        }
        $paths = @(_windo_profile_path_list | Sort-Object)
        $curPf = $null
        try { $curPf = [System.IO.Path]::GetFullPath([string]$PROFILE) } catch { $curPf = $null }
        $rows = [System.Collections.ArrayList]@()
        $allIssues = [System.Collections.ArrayList]@()
        foreach ($p in $paths) {
            $st = _windo_read_profile_windo_status $p
            $isCur = $false
            if ($curPf) {
                try { $isCur = ([System.IO.Path]::GetFullPath($p) -eq $curPf) } catch { $isCur = $false }
            }
            $issues = @(_windo_profile_prompt_issues $p)
            foreach ($issue in $issues) {
                [void]$allIssues.Add([pscustomobject]@{ profile = $p; id = $issue.id; severity = $issue.severity; lineNumber = $issue.lineNumber; detail = $issue.detail; fixCommand = $issue.fixCommand })
            }
            [void]$rows.Add([pscustomobject]@{
                path = $p
                filePresent = $st.present
                hasWindoBlock = $st.hasWindoBlock
                isCurrentProfile = $isCur
                promptIssues = $issues
            })
        }
        if ($profileSub -eq "repair") {
            $repairAll = ($Command -contains "--all")
            $promptInit = ($Command -contains "--prompt-init")
            if (-not $promptInit) { $promptInit = $true }
            $targets = if ($repairAll) { @($paths) } elseif ($curPf) { @($curPf) } else { @([string]$PROFILE) }
            $results = [System.Collections.ArrayList]@()
            foreach ($target in $targets) {
                [void]$results.Add((_windo_repair_profile_prompt_init $target))
            }
            $failed = @($results | Where-Object { -not $_.ok })
            $changed = @($results | Where-Object { $_.changed })
            $exit = if ($failed.Count -gt 0) { 2 } else { 0 }
            if ($JsonOutput) { _emit_json "profile" @{ subcommand = "repair"; promptInit = $promptInit; results = @($results); changedCount = $changed.Count; exitCode = $exit } }
            else {
                Write-Host "[windo] profile repair" -ForegroundColor Cyan
                foreach ($r in $results) {
                    if (-not $r.ok) { Write-Host "  FAILED $($r.path): $($r.error)" -ForegroundColor Red }
                    elseif ($r.changed) { Write-Host "  fixed  $($r.path)" -ForegroundColor Green; Write-Host "         backup: $($r.backupPath)" -ForegroundColor DarkGray }
                    else { Write-Host "  no change $($r.path)" -ForegroundColor DarkGray }
                }
            }
            _windo_set_exit $exit
            return
        }
        if ($JsonOutput) {
            $profileExit = if ($allIssues.Count -gt 0) { 3 } else { 0 }
            _emit_json "profile" @{ subcommand = $profileSub; profiles = @($rows); promptIssues = @($allIssues); exitCode = $profileExit }
            _windo_set_exit $profileExit
            return
        }
        Write-Host "[windo] Profile paths (WINDO block markers)" -ForegroundColor Cyan
        foreach ($r in $rows) {
            $tag = if ($r.isCurrentProfile) { " (current host profile)" } else { "" }
            if (-not $r.filePresent) {
                Write-Host "  (missing) $($r.path)$tag" -ForegroundColor DarkGray
            } elseif ($r.hasWindoBlock) {
                Write-Host "  OK WINDO   $($r.path)$tag" -ForegroundColor Green
            } else {
                Write-Host "  no block   $($r.path)$tag" -ForegroundColor Yellow
            }
            foreach ($issue in @($r.promptIssues)) {
                Write-Host "       prompt: $($issue.id) line=$($issue.lineNumber) - $($issue.detail)" -ForegroundColor DarkYellow
                if ($issue.fixCommand) { Write-Host "       fix   : $($issue.fixCommand)" -ForegroundColor DarkGray }
            }
        }
        _windo_set_exit $(if ($allIssues.Count -gt 0) { 3 } else { 0 })
        return
    }

    if ($Command.Count -ge 1 -and ($Command[0] -eq "uninstall" -or $Command[0] -eq "remove")) {
        $uninstallConfirm = $false
        $uninstallKeepSnapshots = $false
        $uninstallDownloadFresh = $false
        foreach ($ua in @($Command | Select-Object -Skip 1)) {
            switch -Regex ([string]$ua) {
                '^(--confirm|-confirm)$' { $uninstallConfirm = $true; continue }
                '^(--keep-snapshots|-KeepSnapshots)$' { $uninstallKeepSnapshots = $true; continue }
                '^(--download-fresh|--download)$' { $uninstallDownloadFresh = $true; continue }
                default {
                    Write-Host "[windo] uninstall: unknown argument '$ua'" -ForegroundColor Yellow
                    Write-Host "  Supported: --confirm, --keep-snapshots, --download-fresh" -ForegroundColor DarkGray
                    _windo_set_exit 2
                    return
                }
            }
        }
        Invoke-WindoBundledUninstall -Confirm:$uninstallConfirm -KeepSnapshots:$uninstallKeepSnapshots -DownloadFresh:$uninstallDownloadFresh
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "trust") {
        $online = $false
        $badArgs = [System.Collections.ArrayList]@()
        for ($ti = 1; $ti -lt $Command.Count; $ti++) {
            $ta = [string]$Command[$ti]
            if ($ta -eq "--online") { $online = $true; continue }
            if ($ta -eq "--offline") { $online = $false; continue }
            if ($ta -eq "") { continue }
            [void]$badArgs.Add($ta)
        }
        if ($badArgs.Count -gt 0) {
            if ($JsonOutput) { _emit_json "trust" @{ error = "expected --online | --offline"; invalidArgs = @($badArgs.ToArray()); exitCode = 2 } }
            else {
                Write-Host "[windo] trust: expected --online | --offline" -ForegroundColor Yellow
                Write-Host "  Examples: windo trust ; windo trust --online --json" -ForegroundColor DarkGray
            }
            _windo_set_exit 2
            return
        }
        $posture = _windo_trust_posture $online
        if ($JsonOutput) {
            _emit_json "trust" $posture
            _windo_set_exit ([int]$posture.exitCode)
            return
        }
        $levelColor = if ($posture.trustLevel -eq "TRUSTED") { "Green" } elseif ($posture.trustLevel -eq "ATTENTION") { "Yellow" } else { "Red" }
        Write-Host "[windo] Trust Console" -ForegroundColor Cyan
        Write-Host ("  Level    : {0} ({1}/100)" -f $posture.trustLevel, $posture.score) -ForegroundColor $levelColor
        Write-Host "  Online   : $($posture.publishedChecksum.status)" -ForegroundColor DarkGray
        Write-Host "  Integrity: overall=$($posture.integrity.OverallLevel), runner=$($posture.integrity.RunnerLevel), updater=$($posture.integrity.UpdaterLevel)" -ForegroundColor DarkGray
        Write-Host "  Audit    : $(if ($posture.audit.verifyOk) { 'OK' } else { 'CHECK' })" -ForegroundColor DarkGray
        Write-Host "  Tasks    : main=$(if ($posture.tasks.main) { 'present' } else { 'missing' }), update=$(if ($posture.tasks.update) { 'present' } else { 'missing' })" -ForegroundColor DarkGray
        Write-Host "  Snapshot : $($posture.installerSnapshot.path)" -ForegroundColor DarkGray
        if ($posture.installerSnapshot.sha256) {
            Write-Host "             sha256=$($posture.installerSnapshot.sha256)" -ForegroundColor DarkGray
        }
        if ($posture.publishedChecksum.requested) {
            Write-Host "  Published: $($posture.publishedChecksum.url)" -ForegroundColor DarkGray
            Write-Host "             source=$(if ($posture.publishedChecksum.source) { $posture.publishedChecksum.source } else { '(none)' })" -ForegroundColor DarkGray
            Write-Host "             sha256=$(if ($posture.publishedChecksum.sha256) { $posture.publishedChecksum.sha256 } else { '(unavailable)' }), match=$($posture.publishedChecksum.matchesSnapshot)" -ForegroundColor DarkGray
            if ($posture.publishedChecksum.error) { Write-Host "             error=$($posture.publishedChecksum.error)" -ForegroundColor DarkYellow }
        } else {
            Write-Host "  Published: not checked; run windo trust --online from a normal shell" -ForegroundColor DarkGray
        }
        if ($posture.recommendations.Count -gt 0) {
            Write-Host "  Actions  :" -ForegroundColor Yellow
            foreach ($r in $posture.recommendations) { Write-Host "    - $r" -ForegroundColor DarkGray }
        }
        _windo_set_exit ([int]$posture.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "source") {
        $badArgs = [System.Collections.ArrayList]@()
        for ($soi = 1; $soi -lt $Command.Count; $soi++) {
            $soa = [string]$Command[$soi]
            if ([string]::IsNullOrWhiteSpace($soa)) { continue }
            [void]$badArgs.Add($soa)
        }
        if ($badArgs.Count -gt 0) {
            if ($JsonOutput) { _emit_json "source" @{ error = "unexpected argument"; invalidArgs = @($badArgs.ToArray()); exitCode = 2 } }
            else { Write-Host "[windo] source: unexpected argument(s): $($badArgs -join ', ')" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $src = _windo_source_status
        if ($JsonOutput) {
            _emit_json "source" $src
            _windo_set_exit ([int]$src.exitCode)
            return
        }
        Write-Host "[windo] Source of Truth" -ForegroundColor Cyan
        Write-Host "  Installed : $($src.installedVersion)" -ForegroundColor DarkGray
        Write-Host "  Published : status=$($src.publishedInstaller.status), source=$($src.publishedInstaller.source), version=$($src.publishedInstaller.version)" -ForegroundColor DarkGray
        Write-Host "              url=$($src.publishedInstaller.url)" -ForegroundColor DarkGray
        Write-Host "  Checksum  : status=$($src.publishedChecksum.status), source=$($src.publishedChecksum.source)" -ForegroundColor DarkGray
        Write-Host "              sha256=$($src.publishedChecksum.sha256)" -ForegroundColor DarkGray
        Write-Host "  Snapshot  : version=$($src.localSnapshot.version), match=$($src.localSnapshot.matchesPublishedChecksum)" -ForegroundColor DarkGray
        Write-Host "              path=$($src.localSnapshot.path)" -ForegroundColor DarkGray
        Write-Host "  Next      : $($src.recommendation)" -ForegroundColor Yellow
        _windo_set_exit ([int]$src.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "syntax") {
        $doctorMode = $false
        $queryParts = [System.Collections.ArrayList]@()
        $badArgs = [System.Collections.ArrayList]@()
        for ($si = 1; $si -lt $Command.Count; $si++) {
            $sa = [string]$Command[$si]
            if ([string]::IsNullOrWhiteSpace($sa)) { continue }
            if ($sa -eq "doctor" -and $queryParts.Count -eq 0) { $doctorMode = $true; continue }
            if ($sa -eq "--doctor") { $doctorMode = $true; continue }
            if ($sa.StartsWith("--")) { [void]$badArgs.Add($sa); continue }
            [void]$queryParts.Add($sa)
        }
        if ($badArgs.Count -gt 0) {
            if ($JsonOutput) { _emit_json "syntax" @{ error = "unknown option"; invalidArgs = @($badArgs.ToArray()); exitCode = 2 } }
            else { Write-Host "[windo] syntax: unknown option(s): $($badArgs -join ', ')" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $query = ($queryParts.ToArray() -join " ").Trim()
        if ($doctorMode) {
            $doctor = _windo_syntax_doctor $query
            $payload = [ordered]@{
                query = $doctor.query
                doctor = $doctor
                count = $doctor.count
                shortcuts = @($doctor.matches)
                exitCode = $doctor.exitCode
            }
            if ($JsonOutput) {
                _emit_json "syntax" $payload
                _windo_set_exit ([int]$payload.exitCode)
                return
            }
            Write-Host "[windo] Syntax Doctor" -ForegroundColor Cyan
            if ($doctor.query) { Write-Host "  Query   : $($doctor.query)" -ForegroundColor DarkGray }
            $statusColor = if ($doctor.exitCode -eq 0) { "Green" } else { "Yellow" }
            Write-Host "  Status  : $($doctor.status)" -ForegroundColor $statusColor
            Write-Host "  Message : $($doctor.message)" -ForegroundColor DarkGray
            if ($doctor.bestMatch) {
                Write-Host "  Match   : $($doctor.bestMatch.id) - $($doctor.bestMatch.summary)" -ForegroundColor Yellow
                Write-Host "  Command : $($doctor.bestMatch.command)" -ForegroundColor Green
                Write-Host "  Preview : $($doctor.bestMatch.preview)" -ForegroundColor DarkGray
                Write-Host "  Risk    : $($doctor.bestMatch.risk)" -ForegroundColor DarkGray
            }
            if ($doctor.recommendations.Count -gt 0) {
                Write-Host "  Next:" -ForegroundColor Yellow
                foreach ($r in @($doctor.recommendations)) { Write-Host "    - $r" -ForegroundColor DarkGray }
            }
            _windo_set_exit ([int]$doctor.exitCode)
            return
        }
        $matches = @(_windo_syntax_matches $query)
        $payload = [ordered]@{
            query = $(if ([string]::IsNullOrWhiteSpace($query)) { $null } else { $query })
            count = $matches.Count
            shortcuts = @($matches)
            exitCode = $(if ($matches.Count -gt 0) { 0 } else { 3 })
        }
        if ($JsonOutput) {
            _emit_json "syntax" $payload
            _windo_set_exit ([int]$payload.exitCode)
            return
        }
        Write-Host "[windo] Syntax Forge" -ForegroundColor Cyan
        if (-not [string]::IsNullOrWhiteSpace($query)) { Write-Host "  Query: $query" -ForegroundColor DarkGray }
        if ($matches.Count -eq 0) {
            Write-Host "  No shortcut matched. Try: update, proof, health, repair keys, support bundle, recipes, launchpad." -ForegroundColor Yellow
            _windo_set_exit 3
            return
        }
        foreach ($m in $matches) {
            Write-Host ("  {0,-12} {1}" -f $m.id, $m.summary) -ForegroundColor Yellow
            Write-Host "    command : $($m.command)" -ForegroundColor Green
            Write-Host "    preview : $($m.preview)" -ForegroundColor DarkGray
            Write-Host "    risk    : $($m.risk)" -ForegroundColor DarkGray
            Write-Host "    aliases : $((@($m.aliases)) -join ', ')" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "explain") {
        $targetParts = if ($Command.Count -gt 1) { @($Command[1..($Command.Count - 1)]) } else { @() }
        $plan = _windo_new_command_plan $targetParts
        if ($JsonOutput) {
            _emit_json "explain" $plan
            _windo_set_exit ([int]$plan.exitCode)
            return
        }
        Write-Host "[windo] Execution Plan" -ForegroundColor Cyan
        if ($plan.target.Count -gt 0) {
            Write-Host "  Target   : $($plan.commandLine)" -ForegroundColor Yellow
        } else {
            Write-Host "  Target   : (missing)" -ForegroundColor Yellow
        }
        Write-Host "  Route    : $($plan.route)" -ForegroundColor DarkGray
        Write-Host "  Boundary : $($plan.privilegeBoundary)" -ForegroundColor DarkGray
        Write-Host "  Network  : $($plan.network)" -ForegroundColor DarkGray
        Write-Host "  Writes   : $($plan.writesLocalFiles)" -ForegroundColor DarkGray
        Write-Host "  Audit    : $($plan.createsAuditEntry)" -ForegroundColor DarkGray
        Write-Host "  Checksum : $($plan.checksumValidation)" -ForegroundColor DarkGray
        if ($plan.artifacts.Count -gt 0) {
            Write-Host "  Artifacts:" -ForegroundColor Yellow
            foreach ($a in @($plan.artifacts)) { Write-Host "    - $a" -ForegroundColor DarkGray }
        }
        if ($plan.preflight.Count -gt 0) {
            Write-Host "  Check first:" -ForegroundColor Yellow
            foreach ($p in @($plan.preflight)) { Write-Host "    - $p" -ForegroundColor DarkGray }
        }
        if ($plan.nextCommands.Count -gt 0) {
            Write-Host "  Next:" -ForegroundColor Yellow
            foreach ($n in @($plan.nextCommands)) { Write-Host "    - $n" -ForegroundColor Green }
        }
        if ($plan.warnings.Count -gt 0) {
            Write-Host "  Warnings:" -ForegroundColor Yellow
            foreach ($w in @($plan.warnings)) { Write-Host "    - $w" -ForegroundColor DarkYellow }
        }
        _windo_set_exit ([int]$plan.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "context") {
        $mt = $false; $ut = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mt = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $ut = $true } catch {}
        $meta = _read_last_meta
        $lrId = $null; $lrAt = $null
        if ($meta) {
            if ($meta.PSObject.Properties.Name -contains 'lastRequestId') { $lrId = [string]$meta.lastRequestId }
            if ($meta.PSObject.Properties.Name -contains 'storedAt') { $lrAt = [string]$meta.storedAt }
        }
        $pl = @{
            windoVersion = $WindoVersion
            psEdition = $PSVersionTable.PSEdition
            psVersion = $PSVersionTable.PSVersion.ToString()
            profile = $PROFILE
            secureDir = $SecureDir
            logFile = $LogFile
            manifestFile = $ManifestFile
            lastCmdFile = $LastCmdFile
            lastMetaFile = $LastMetaFile
            mainTaskPresent = $mt
            updateTaskPresent = $ut
            lastRequestId = $lrId
            lastStoredAt = $lrAt
        }
        if ($JsonOutput) { _emit_json "context" $pl; return }
        Write-Host "[windo] Context" -ForegroundColor Cyan
        Write-Host "  WINDO        : $WindoVersion"
        Write-Host "  PowerShell   : $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
        Write-Host "  Profile      : $PROFILE"
        Write-Host "  SecureDir    : $SecureDir"
        Write-Host "  Main task    : $(if ($mt) { 'present' } else { 'MISSING' })"
        Write-Host "  Update task  : $(if ($ut) { 'present' } else { 'MISSING' })"
        if ($lrId) { Write-Host "  Last RequestId: $lrId" -ForegroundColor DarkGray }
        if ($lrAt) { Write-Host "  Last meta at : $lrAt" -ForegroundColor DarkGray }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "config") {
        $tmo = _windo_effective_runner_timeout_ms
        $mcs = _windo_effective_runner_max_chars_per_stream
        $mcc = _windo_max_command_chars
        $effJson = _windo_resolve_json_envelope
        $kbPolicy = _windo_resolve_keybinding_policy
        $completionPolicy = _windo_resolve_completion_policy
        $outputPolicy = _windo_resolve_output_policy
        $motionPolicy = _windo_resolve_motion_policy
        $jsonEnvNote = "CLI JSON shape: schemaVersion=$($effJson.schemaLabel), meta=$(if ($effJson.includeMeta) { 'on' } else { 'off' }); env wins over $($PrefsFile); see windo theme"
        $keybindingNote = if ($kbPolicy.enabled) { "enabled: chord=$($kbPolicy.chord) (source=$($kbPolicy.chordSource))" } else { "disabled" + $(if ($kbPolicy.disabledSource) { " by $($kbPolicy.disabledSource)" } else { "" }) }
        $rows = [System.Collections.ArrayList]@(
            [pscustomobject]@{ name = "WINDO_NO_SPINNER"; environmentValue = $(if ($env:WINDO_NO_SPINNER) { [string]$env:WINDO_NO_SPINNER } else { $null }); effectiveNote = $(if ($env:WINDO_NO_SPINNER) { "spinners disabled" } else { "default (interactive spinners when stderr is a console)" }) }
            [pscustomobject]@{ name = "CI"; environmentValue = $(if ($env:CI) { [string]$env:CI } else { $null }); effectiveNote = $(if ($env:CI) { "spinners disabled (CI set)" } else { "unset" }) }
            [pscustomobject]@{ name = "WINDO_RUNNER_TIMEOUT_MS"; environmentValue = $(if ($env:WINDO_RUNNER_TIMEOUT_MS) { [string]$env:WINDO_RUNNER_TIMEOUT_MS } else { $null }); effectiveNote = "${tmo} ms (clamped 1..86400000; default 7200000)" }
            [pscustomobject]@{ name = "WINDO_RUNNER_MAX_OUTPUT_BYTES"; environmentValue = $(if ($env:WINDO_RUNNER_MAX_OUTPUT_BYTES) { [string]$env:WINDO_RUNNER_MAX_OUTPUT_BYTES } else { $null }); effectiveNote = "per-stream capture cap ${mcs} chars (derived from env total bytes; see runner)" }
            [pscustomobject]@{ name = "WINDO_MAX_COMMAND_CHARS"; environmentValue = $(if ($env:WINDO_MAX_COMMAND_CHARS) { [string]$env:WINDO_MAX_COMMAND_CHARS } else { $null }); effectiveNote = "${mcc} chars (max 8191)" }
            [pscustomobject]@{ name = "WINDO_SKIP_INSTALLER_SHA256"; environmentValue = $(if ($env:WINDO_SKIP_INSTALLER_SHA256) { [string]$env:WINDO_SKIP_INSTALLER_SHA256 } else { $null }); effectiveNote = $(if ($env:WINDO_SKIP_INSTALLER_SHA256) { "bootstrap/upgrade checksum check skipped" } else { "checksum enforced when published on v6" }) }
            [pscustomobject]@{ name = "SUDO_TIMEOUT"; environmentValue = $(if ($env:SUDO_TIMEOUT) { [string]$env:SUDO_TIMEOUT } else { $null }); effectiveNote = "defaults runner timeout for --timeout when omitted (seconds or ms; clamped 1..86400000)" }
            [pscustomobject]@{ name = "WINDO_INSTALL_NONINTERACTIVE"; environmentValue = $(if ($env:WINDO_INSTALL_NONINTERACTIVE) { [string]$env:WINDO_INSTALL_NONINTERACTIVE } else { $null }); effectiveNote = "installer confirmation bypass for install-latest" }
            [pscustomobject]@{ name = "SUDO_PROMPT"; environmentValue = $(if ($env:SUDO_PROMPT) { [string]$env:SUDO_PROMPT } else { $null }); effectiveNote = "custom prompt text for install-latest confirmation" }
            [pscustomobject]@{ name = "WINDO_JSON_ENVELOPE"; environmentValue = $(if ($env:WINDO_JSON_ENVELOPE) { [string]$env:WINDO_JSON_ENVELOPE } else { $null }); effectiveNote = $jsonEnvNote }
            [pscustomobject]@{ name = "WINDO_PREFIX_CHORD"; environmentValue = $(if ($env:WINDO_PREFIX_CHORD) { [string]$env:WINDO_PREFIX_CHORD } else { $null }); effectiveNote = "effective chord: $($kbPolicy.chord)" }
            [pscustomobject]@{ name = "WINDO_DISABLE_PSREADLINE_BINDINGS"; environmentValue = $(if ($env:WINDO_DISABLE_PSREADLINE_BINDINGS) { [string]$env:WINDO_DISABLE_PSREADLINE_BINDINGS } else { $null }); effectiveNote = $keybindingNote }
            [pscustomobject]@{ name = "WINDO_AUTO_DETECT_ALT_BINDINGS"; environmentValue = $(if ($env:WINDO_AUTO_DETECT_ALT_BINDINGS) { [string]$env:WINDO_AUTO_DETECT_ALT_BINDINGS } else { $null }); effectiveNote = $(if ($kbPolicy.autoDetectAlt) { "alt-chord auto fallback enabled" } else { "alt-chord auto fallback disabled" }) }
            [pscustomobject]@{ name = "WINDO_KEYBINDING_FALLBACK_CHORD"; environmentValue = $(if ($env:WINDO_KEYBINDING_FALLBACK_CHORD) { [string]$env:WINDO_KEYBINDING_FALLBACK_CHORD } else { $null }); effectiveNote = "fallback chord: $($kbPolicy.fallbackChord)" }
            [pscustomobject]@{ name = "WINDO_KEYBINDING_POLICY"; environmentValue = $null; effectiveNote = "effective source chord=$($kbPolicy.chordSource); enabled=$($kbPolicy.enabled)" }
            [pscustomobject]@{ name = "WINDO_COMPLETION_MODE"; environmentValue = $(if ($env:WINDO_COMPLETION_MODE) { [string]$env:WINDO_COMPLETION_MODE } else { $null }); effectiveNote = "mode=$($completionPolicy.mode) (source=$($completionPolicy.source)); see windo completion" }
            [pscustomobject]@{ name = "WINDO_OUTPUT_MODE"; environmentValue = $(if ($env:WINDO_OUTPUT_MODE) { [string]$env:WINDO_OUTPUT_MODE } else { $null }); effectiveNote = "mode=$($outputPolicy.mode) (source=$($outputPolicy.source)); see windo output" }
            [pscustomobject]@{ name = "WINDO_MOTION"; environmentValue = $(if ($env:WINDO_MOTION) { [string]$env:WINDO_MOTION } else { $null }); effectiveNote = "mode=$($motionPolicy.mode) enabled=$($motionPolicy.enabled) (source=$($motionPolicy.source)); see windo motion" }
            [pscustomobject]@{ name = "WINDO_EXTRAS_INDEX_URL"; environmentValue = $(if ($env:WINDO_EXTRAS_INDEX_URL) { [string]$env:WINDO_EXTRAS_INDEX_URL } else { $null }); effectiveNote = "resolved extras index: $(_windo_extras_index_url)" }
        )
        if ($JsonOutput) {
            _emit_json "config" @{
                settings = @($rows)
                secureDir = $SecureDir
                keybindingPolicy = $kbPolicy
                completionPolicy = $completionPolicy
                outputPolicy = $outputPolicy
                motionPolicy = $motionPolicy
                extrasIndexUrl = (_windo_extras_index_url)
                exitCode = 0
            }
            _windo_set_exit 0
            return
        }
        Write-Host "[windo] Effective configuration (env overrides + runner semantics)" -ForegroundColor Cyan
        Write-Host "  SecureDir: $SecureDir" -ForegroundColor DarkGray
        foreach ($r in $rows) {
            $ev = if ($null -eq $r.environmentValue) { "(unset)" } else { $r.environmentValue }
            Write-Host "  $($r.name)" -ForegroundColor Yellow
            Write-Host "    env      : $ev" -ForegroundColor DarkGray
            Write-Host "    effective: $($r.effectiveNote)" -ForegroundColor DarkGray
        }
        Write-Host "  Read-only: `$global:WINDO_EXIT_CODE (doctor / integrity / verify / stats validation)" -ForegroundColor DarkGray
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "roadmap") {
        $releases = @(_windo_roadmap_releases)
        $payload = [ordered]@{
            currentVersion = $WindoVersion
            targetMajor = "reserved"
            releaseTrain = @($releases)
            principles = @(
                "Keep deliberate elevation and auditability as the core.",
                "Ship hardening and shell ergonomics in small verified sub-versions.",
                "Keep future major-package details brief until the platform is ready."
            )
            docs = "docs/v5-roadmap.md"
            exitCode = 0
        }
        if ($JsonOutput) {
            _emit_json "roadmap" $payload
        } else {
            Write-Host "[windo] Release runway" -ForegroundColor Cyan
            Write-Host "  Current : $WindoVersion" -ForegroundColor DarkGray
            Write-Host "  Target  : V4 Operator Mesh shipped; future major reserved" -ForegroundColor Yellow
            foreach ($r in $releases) {
                $color = if ($r.status -in @("in-progress", "late-stage")) { "Green" } elseif ($r.status -eq "reserved") { "Magenta" } else { "DarkGray" }
                Write-Host ("  {0,-7} {1,-30} {2}" -f $r.version, $r.codename, $r.status) -ForegroundColor $color
                Write-Host ("          {0}" -f $r.theme) -ForegroundColor DarkGray
            }
            Write-Host "  Docs    : docs/v5-roadmap.md" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "mesh") {
        $writeHtml = $false
        $openHtml = $false
        $doctorMode = $false
        $workbenchMode = $false
        $meshOut = Join-Path (Join-Path $HOME "Documents") ("windo\windo_mesh_{0}.html" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        $badArgs = [System.Collections.ArrayList]@()
        for ($mi = 1; $mi -lt $Command.Count; $mi++) {
            $ma = [string]$Command[$mi]
            if ([string]::IsNullOrWhiteSpace($ma)) { continue }
            if ($ma -eq "doctor" -and -not $doctorMode) { $doctorMode = $true; continue }
            if ($ma -eq "workbench" -and -not $workbenchMode) { $workbenchMode = $true; continue }
            if ($ma -eq "--html") { $writeHtml = $true; continue }
            if ($ma -eq "--open") { $writeHtml = $true; $openHtml = $true; continue }
            if ($ma -eq "--output" -and ($mi + 1) -lt $Command.Count) {
                $meshOut = [string]$Command[$mi + 1]
                $writeHtml = $true
                $mi++
                continue
            }
            if ($ma -like "--output=*") {
                $meshOut = $ma.Substring(9)
                $writeHtml = $true
                continue
            }
            if ($ma.StartsWith("--")) { [void]$badArgs.Add($ma); continue }
            [void]$badArgs.Add($ma)
        }
        if ($badArgs.Count -gt 0) {
            if ($JsonOutput) { _emit_json "mesh" @{ error = "unknown argument"; invalidArgs = @($badArgs.ToArray()); exitCode = 2 } }
            else { Write-Host "[windo] mesh: unknown argument(s): $($badArgs -join ', ')" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }

        if ($doctorMode -and $workbenchMode) {
            if ($JsonOutput) { _emit_json "mesh" @{ error = "choose doctor or workbench, not both"; exitCode = 2 } }
            else { Write-Host "[windo] mesh: choose doctor or workbench, not both." -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }

        if ($doctorMode) {
            if ($writeHtml -or $openHtml) {
                if ($JsonOutput) { _emit_json "mesh" @{ error = "doctor does not support html/open output"; exitCode = 2 } }
                else { Write-Host "[windo] mesh doctor: --html/--open are for inventory cockpit output, not doctor output." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $doctor = _windo_mesh_doctor
            if ($JsonOutput) {
                _emit_json "mesh" $doctor
            } else {
                $levelColor = if ($doctor.readinessLevel -eq "READY") { "Green" } elseif ($doctor.readinessLevel -eq "ATTENTION") { "Yellow" } else { "Red" }
                Write-Host "[windo] Operator Mesh doctor" -ForegroundColor Cyan
                Write-Host ("  Readiness : {0} ({1}/100)" -f $doctor.readinessLevel, $doctor.score) -ForegroundColor $levelColor
                Write-Host "  Checks:" -ForegroundColor Yellow
                foreach ($c in @($doctor.checks)) {
                    $mark = if ($c.ok) { "OK" } elseif ($c.severity -eq "critical") { "!!" } else { "!" }
                    $color = if ($c.ok) { "Green" } elseif ($c.severity -eq "critical") { "Red" } else { "Yellow" }
                    Write-Host ("    [{0}] {1} - {2}" -f $mark, $c.label, $c.detail) -ForegroundColor $color
                    if ((-not $c.ok) -and (-not [string]::IsNullOrWhiteSpace([string]$c.fixCommand))) {
                        Write-Host ("         next: {0}" -f $c.fixCommand) -ForegroundColor DarkGray
                    }
                }
                Write-Host "  Recommendations:" -ForegroundColor Yellow
                foreach ($r in @($doctor.recommendations)) { Write-Host "    - $r" -ForegroundColor DarkGray }
            }
            _windo_set_exit ([int]$doctor.exitCode)
            return
        }

        if ($workbenchMode) {
            $workbench = _windo_mesh_workbench
            if ($writeHtml) {
                $workbench | Add-Member -NotePropertyName htmlPath -NotePropertyValue $meshOut -Force
                [void](_windo_write_mesh_workbench_html $workbench $meshOut $openHtml)
            }
            if ($JsonOutput) {
                _emit_json "mesh" $workbench
            } else {
                $levelColor = if ($workbench.readinessLevel -eq "READY") { "Green" } elseif ($workbench.readinessLevel -eq "ATTENTION") { "Yellow" } else { "Red" }
                Write-Host "[windo] Operator Mesh Workbench" -ForegroundColor Cyan
                Write-Host ("  Readiness : {0} ({1}/100)" -f $workbench.readinessLevel, $workbench.score) -ForegroundColor $levelColor
                Write-Host ("  Surface   : {0} recipes, {1} modules, {2} extras" -f $workbench.counts.recipes, $workbench.counts.modules, $workbench.counts.installedExtras) -ForegroundColor Yellow
                Write-Host "  Lanes:" -ForegroundColor Yellow
                foreach ($lane in @($workbench.lanes)) {
                    Write-Host ("    - {0}: {1} cards" -f $lane.title, $lane.cardCount) -ForegroundColor DarkGray
                }
                Write-Host "  Flow:" -ForegroundColor Yellow
                foreach ($f in @($workbench.recommendedFlow)) {
                    Write-Host ("    {0}. {1} -> {2}" -f $f.order, $f.name, $f.command) -ForegroundColor DarkGray
                }
                if ($writeHtml) { Write-Host "  HTML      : $meshOut" -ForegroundColor Green }
            }
            _windo_set_exit 0
            return
        }

        $payload = _windo_mesh_inventory
        if ($writeHtml) {
            $payload | Add-Member -NotePropertyName htmlPath -NotePropertyValue $meshOut -Force
            $sb = [System.Text.StringBuilder]::new()
            $brandImg = ""
            if (-not [string]::IsNullOrWhiteSpace([string]$payload.launchpad.brandLogoPath)) {
                $brandImg = "<img class='brand' alt='WINDO' src='$(_html_escape ([uri]$payload.launchpad.brandLogoPath).AbsoluteUri)'>"
            }
            $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO Operator Mesh</title>')
            $null = $sb.AppendLine('<style>body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#0b1220;color:#e5e7eb}.wrap{max-width:1240px;margin:0 auto;padding:28px}.hero{border-bottom:1px solid #334155;padding-bottom:18px}.brand{max-width:360px;width:100%;height:auto;margin-bottom:8px}.title{font-size:36px;font-weight:800}.sub{color:#94a3b8}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px;margin:18px 0}.card{background:#111827;border:1px solid #334155;border-radius:8px;padding:14px}.k{font-size:12px;text-transform:uppercase;color:#94a3b8}.v{font-size:30px;font-weight:800}.ok{color:#22c55e}.warn{color:#f59e0b}.muted{color:#94a3b8}.row{display:flex;gap:8px;align-items:center;justify-content:space-between;border-top:1px solid #1f2937;padding:10px 0}button{background:#2563eb;color:white;border:0;border-radius:6px;padding:7px 10px;cursor:pointer}code{background:#020617;border:1px solid #334155;border-radius:5px;padding:3px 5px;color:#bfdbfe}table{width:100%;border-collapse:collapse;background:#111827;border:1px solid #334155;margin:12px 0 18px}th,td{padding:8px;border-bottom:1px solid #1f2937;text-align:left;vertical-align:top}th{background:#1f2937}h2{margin-top:24px}</style></head><body><div class="wrap">')
            $null = $sb.AppendLine(("<div class='hero'>{0}<div class='title'>WINDO Operator Mesh</div><div class='sub'>Local preview generated {1}. No remote fetch, no elevation, no workflow execution.</div></div>" -f $brandImg, (_html_escape (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))))
            $null = $sb.AppendLine("<div class='grid'>")
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Modules</div><div class='v'>{0}/{1}</div><div class='muted'>enabled / discovered</div></div>" -f [int]$payload.counts.enabledModules, [int]$payload.counts.modules))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Recipes</div><div class='v'>{0}</div><div class='muted'>built-in previews</div></div>" -f [int]$payload.counts.recipes))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Extras</div><div class='v'>{0}</div><div class='muted'>installed locally</div></div>" -f [int]$payload.counts.installedExtras))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Tray</div><div class='v {0}'>{1}</div><div class='muted'>{2}</div></div>" -f $(if ($payload.launchpad.traySupported) { "ok" } else { "warn" }), $(if ($payload.launchpad.traySupported) { "ready" } else { "n/a" }), (_html_escape ([string]$payload.launchpad.trayIconPath))))
            $null = $sb.AppendLine("</div>")
            $null = $sb.AppendLine("<h2>Next commands</h2>")
            foreach ($cmd in @($payload.nextCommands)) {
                $safeCmd = _html_escape ([string]$cmd)
                $jsCmd = _html_escape (([string]$cmd) -replace "'", "\'")
                $null = $sb.AppendLine(("<div class='row'><div><code>{0}</code></div><button onclick=""copyCmd('{1}')"">Copy</button></div>" -f $safeCmd, $jsCmd))
            }
            $null = $sb.AppendLine("<h2>Recipes</h2><table><tr><th>Id</th><th>Description</th><th>Preview</th></tr>")
            foreach ($r in @($payload.recipes)) {
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td><code>{2}</code></td></tr>" -f (_html_escape $r.id), (_html_escape $r.description), (_html_escape $r.previewCommand)))
            }
            $null = $sb.AppendLine("</table><h2>Modules</h2><table><tr><th>Id</th><th>Status</th><th>Entry</th><th>Path</th></tr>")
            if (@($payload.modules.rows).Count -eq 0) {
                $null = $sb.AppendLine(("<tr><td colspan='4' class='muted'>No modules discovered under <code>{0}</code>.</td></tr>" -f (_html_escape $payload.modules.root)))
            } else {
                foreach ($m in @($payload.modules.rows)) {
                    $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td><code>{3}</code></td></tr>" -f (_html_escape $m.id), $(if ($m.enabled) { "enabled" } else { "available" }), (_html_escape $m.entry), (_html_escape $m.path)))
                }
            }
            $null = $sb.AppendLine("</table><h2>Platform paths</h2><table><tr><th>Name</th><th>Value</th></tr>")
            $null = $sb.AppendLine(("<tr><td>Modules root</td><td><code>{0}</code></td></tr>" -f (_html_escape $payload.modules.root)))
            $null = $sb.AppendLine(("<tr><td>Extras index</td><td><code>{0}</code></td></tr>" -f (_html_escape $payload.extras.indexUrl)))
            $null = $sb.AppendLine(("<tr><td>Extras root</td><td><code>{0}</code></td></tr>" -f (_html_escape $payload.extras.installRoot)))
            $null = $sb.AppendLine(("<tr><td>Export root</td><td><code>{0}</code></td></tr>" -f (_html_escape $payload.export.exportRoot)))
            $null = $sb.AppendLine(("<tr><td>Brand logo</td><td><code>{0}</code></td></tr>" -f (_html_escape ([string]$payload.launchpad.brandLogoPath))))
            $null = $sb.AppendLine("</table><script>function copyCmd(t){ if(navigator.clipboard){navigator.clipboard.writeText(t);} else { prompt('Copy command:', t); } }</script></div></body></html>")
            $dir = Split-Path -Parent $meshOut
            if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllText($meshOut, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
            if ($openHtml) { Start-Process -FilePath $meshOut | Out-Null }
        }
        if ($JsonOutput) {
            _emit_json "mesh" $payload
        } else {
            Write-Host "[windo] Operator Mesh preview" -ForegroundColor Cyan
            Write-Host "  Modules : $($payload.counts.enabledModules)/$($payload.counts.modules) enabled" -ForegroundColor Yellow
            Write-Host "            root: $($payload.modules.root)" -ForegroundColor DarkGray
            Write-Host "  Recipes : $($payload.counts.recipes) built-in previews" -ForegroundColor Yellow
            Write-Host "  Extras  : $($payload.counts.installedExtras) installed" -ForegroundColor Yellow
            Write-Host "            index: $($payload.extras.indexUrl)" -ForegroundColor DarkGray
            Write-Host "  Launch  : traySupported=$($payload.launchpad.traySupported)" -ForegroundColor Yellow
            if ($payload.launchpad.trayIconPath) { Write-Host "            tray icon: $($payload.launchpad.trayIconPath)" -ForegroundColor DarkGray }
            if ($payload.launchpad.brandLogoPath) { Write-Host "            brand: $($payload.launchpad.brandLogoPath)" -ForegroundColor DarkGray }
            Write-Host "  Export  : $($payload.export.command)" -ForegroundColor Yellow
            if ($payload.export.latestZip) { Write-Host "            latest: $($payload.export.latestZip)" -ForegroundColor DarkGray }
            if ($writeHtml) { Write-Host "  HTML    : $meshOut" -ForegroundColor Green }
            Write-Host "  Next:" -ForegroundColor Yellow
            foreach ($n in @($payload.nextCommands)) { Write-Host "    - $n" -ForegroundColor DarkGray }
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "completion") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -eq "doctor") {
            $doctor = _windo_completion_doctor
            if ($JsonOutput) { _emit_json "completion" @{ subcommand = "doctor"; doctor = $doctor; exitCode = $doctor.exitCode } }
            else {
                Write-Host "[windo] completion doctor" -ForegroundColor Cyan
                Write-Host "  Ready        : $($doctor.ready)" -ForegroundColor $(if ($doctor.ready) { "Green" } else { "Yellow" })
                Write-Host "  Mode         : $($doctor.policy.mode)" -ForegroundColor DarkGray
                Write-Host "  Registered   : $($doctor.registeredFlag)" -ForegroundColor DarkGray
                Write-Host "  TabExpansion2: $($doctor.tabExpansion2Available)" -ForegroundColor DarkGray
                Write-Host "  Completer    : $($doctor.profileHasCompleterBlock)" -ForegroundColor DarkGray
                Write-Host "  Early return : $($doctor.profileHasEarlyReturnRisk)" -ForegroundColor $(if ($doctor.profileHasEarlyReturnRisk) { "Yellow" } else { "DarkGray" })
                Write-Host "  Sample       : $(@($doctor.sampleCompletions | Select-Object -First 8) -join ', ')" -ForegroundColor DarkGray
                if (-not $doctor.ready) { Write-Host "  Repair       : windo completion repair ; then reload profile if needed" -ForegroundColor Yellow }
            }
            _windo_set_exit ([int]$doctor.exitCode)
            return
        }
        if ($sub -eq "repair") {
            $repair = _windo_completion_repair
            if ($JsonOutput) { _emit_json "completion" @{ subcommand = "repair"; repair = $repair; exitCode = $repair.exitCode } }
            else {
                Write-Host "[windo] completion repair" -ForegroundColor Cyan
                Write-Host "  Before ready : $($repair.before.ready)" -ForegroundColor DarkGray
                Write-Host "  After ready  : $($repair.after.ready)" -ForegroundColor $(if ($repair.after.ready) { "Green" } else { "Yellow" })
                if ($repair.error) { Write-Host "  Error        : $($repair.error)" -ForegroundColor Red }
            }
            _windo_set_exit ([int]$repair.exitCode)
            return
        }
        $validModes = @("native-first", "native", "stealth", "hybrid", "windo", "builtin", "builtins", "off", "disabled")
        if ($sub -in $validModes) {
            $mode = _windo_normalize_completion_mode $sub
            $map = _windo_read_windo_prefs_map
            $map['schemaVersion'] = "1.0"
            $map['completionMode'] = $mode
            if (-not (_windo_save_windo_prefs $map)) {
                if ($JsonOutput) { _emit_json "completion" @{ error = "could not write prefs"; prefsFile = $PrefsFile; exitCode = 2 } }
                else { Write-Host "[windo] completion: could not write $PrefsFile" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = _windo_resolve_completion_policy
            if ($JsonOutput) { _emit_json "completion" @{ saved = $true; completionPolicy = $policy; exitCode = 0 } }
            else {
                Write-Host "[windo] completion mode saved: $($policy.mode)" -ForegroundColor Green
                Write-Host "  Source now : $($policy.source)" -ForegroundColor DarkGray
                Write-Host "  Effect     : $($policy.description)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "reset") {
            $map = _windo_read_windo_prefs_map
            if ($map.Contains('completionMode')) { $map.Remove('completionMode') }
            $map['schemaVersion'] = "1.0"
            if (-not (_windo_save_windo_prefs $map)) {
                if ($JsonOutput) { _emit_json "completion" @{ error = "could not write prefs"; prefsFile = $PrefsFile; exitCode = 2 } }
                else { Write-Host "[windo] completion reset: could not write $PrefsFile" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = _windo_resolve_completion_policy
            if ($JsonOutput) { _emit_json "completion" @{ reset = $true; completionPolicy = $policy; exitCode = 0 } }
            else {
                Write-Host "[windo] completion mode reset to default: $($policy.mode)" -ForegroundColor Green
                Write-Host "  Override with env WINDO_COMPLETION_MODE or save with windo completion <mode>." -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -ne "status" -and $sub -ne "") {
            if ($JsonOutput) { _emit_json "completion" @{ error = "expected status | doctor | repair | native-first | hybrid | windo | off | reset"; exitCode = 2 } }
            else {
                Write-Host "[windo] completion: expected status | doctor | repair | native-first | hybrid | windo | off | reset" -ForegroundColor Yellow
                Write-Host "  Example: windo completion native-first" -ForegroundColor DarkGray
            }
            _windo_set_exit 2
            return
        }
        $policy = _windo_resolve_completion_policy
        if ($JsonOutput) { _emit_json "completion" @{ completionPolicy = $policy; exitCode = 0 } }
        else {
            Write-Host "[windo] completion" -ForegroundColor Cyan
            Write-Host "  Mode       : $($policy.mode)" -ForegroundColor Yellow
            Write-Host "  Source     : $($policy.source)" -ForegroundColor DarkGray
            Write-Host "  Env        : $(if ($policy.environmentValue) { $policy.environmentValue } else { '(unset)' })" -ForegroundColor DarkGray
            Write-Host "  Pref       : $(if ($policy.preferenceValue) { $policy.preferenceValue } else { '(none)' })" -ForegroundColor DarkGray
            Write-Host "  Effect     : $($policy.description)" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "output") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        $validModes = @("compact", "short", "sudo", "quiet", "minimal", "legacy", "verbose", "classic")
        if ($sub -in $validModes) {
            $mode = _windo_normalize_output_mode $sub
            $map = _windo_read_windo_prefs_map
            $map['schemaVersion'] = "1.0"
            $map['outputMode'] = $mode
            if (-not (_windo_save_windo_prefs $map)) {
                if ($JsonOutput) { _emit_json "output" @{ error = "could not write prefs"; prefsFile = $PrefsFile; exitCode = 2 } }
                else { Write-Host "[windo] output: could not write $PrefsFile" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = _windo_resolve_output_policy
            if ($JsonOutput) { _emit_json "output" @{ saved = $true; outputPolicy = $policy; exitCode = 0 } }
            else {
                Write-Host "[windo] output mode saved: $($policy.mode)" -ForegroundColor Green
                Write-Host "  Effect: $($policy.description)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "reset") {
            $map = _windo_read_windo_prefs_map
            if ($map.Contains('outputMode')) { $map.Remove('outputMode') }
            $map['schemaVersion'] = "1.0"
            if (-not (_windo_save_windo_prefs $map)) {
                if ($JsonOutput) { _emit_json "output" @{ error = "could not write prefs"; prefsFile = $PrefsFile; exitCode = 2 } }
                else { Write-Host "[windo] output reset: could not write $PrefsFile" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = _windo_resolve_output_policy
            if ($JsonOutput) { _emit_json "output" @{ reset = $true; outputPolicy = $policy; exitCode = 0 } }
            else { Write-Host "[windo] output mode reset to default: $($policy.mode)" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($sub -ne "status" -and $sub -ne "") {
            if ($JsonOutput) { _emit_json "output" @{ error = "expected status | compact | quiet | legacy | reset"; exitCode = 2 } }
            else { Write-Host "[windo] output: expected status | compact | quiet | legacy | reset" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $policy = _windo_resolve_output_policy
        if ($JsonOutput) { _emit_json "output" @{ outputPolicy = $policy; exitCode = 0 } }
        else {
            Write-Host "[windo] output" -ForegroundColor Cyan
            Write-Host "  Mode   : $($policy.mode)" -ForegroundColor Yellow
            Write-Host "  Source : $($policy.source)" -ForegroundColor DarkGray
            Write-Host "  Effect : $($policy.description)" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "backups") {
        $doPrune = $false
        $keepN = $null
        $forcePrune = $false
        $bi = 1
        while ($bi -lt $Command.Count) {
            $ba = [string]$Command[$bi]
            if ($ba -eq "--prune") { $doPrune = $true; $bi++; continue }
            if ($ba -eq "--force") { $forcePrune = $true; $bi++; continue }
            if ($ba -eq "--keep" -and $bi + 1 -lt $Command.Count) {
                $kp = 0
                if (-not [int]::TryParse([string]$Command[$bi + 1], [ref]$kp)) {
                    Write-Host "[windo] backups: --keep requires an integer" -ForegroundColor Red
                    _windo_set_exit 2
                    return
                }
                $keepN = $kp
                $bi += 2
                continue
            }
            if ($ba -like "--keep=*") {
                $kp = 0
                if (-not [int]::TryParse(($ba -replace '^--keep=', ''), [ref]$kp)) {
                    Write-Host "[windo] backups: invalid --keep" -ForegroundColor Red
                    _windo_set_exit 2
                    return
                }
                $keepN = $kp
                $bi++
                continue
            }
            Write-Host "[windo] backups: unknown argument: $ba" -ForegroundColor Yellow
            _windo_set_exit 2
            return
        }
        $bakFiles = @(Get-ChildItem -Path $SecureDir -Filter "windo_history*.enc.bak" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $jsonRows = [System.Collections.ArrayList]@()
        foreach ($f in $bakFiles) {
            [void]$jsonRows.Add([ordered]@{
                name = $f.Name
                fullPath = $f.FullName
                lastWriteTime = $f.LastWriteTime.ToString("o")
                sizeBytes = [int64]$f.Length
            })
        }
        if ($doPrune) {
            if ($null -eq $keepN -or [int]$keepN -lt 1) {
                if ($JsonOutput) {
                    _emit_json "backups" @{ error = "--prune requires --keep N with N >= 1"; exitCode = 2; backups = @($jsonRows) }
                } else {
                    Write-Host "[windo] backups: --prune requires --keep N (N >= 1)" -ForegroundColor Red
                }
                _windo_set_exit 2
                return
            }
            if (-not $forcePrune) {
                if ($JsonOutput) {
                    _emit_json "backups" @{ error = "prune requires --force"; exitCode = 2; backups = @($jsonRows); keep = [int]$keepN }
                } else {
                    Write-Host "[windo] backups: prune would delete older backup files; add --force to confirm." -ForegroundColor Yellow
                    Write-Host "  Example: windo backups --prune --keep $keepN --force" -ForegroundColor DarkGray
                }
                _windo_set_exit 2
                return
            }
            $removed = [System.Collections.ArrayList]@()
            $kn = [int]$keepN
            if ($bakFiles.Count -gt $kn) {
                for ($xi = $kn; $xi -lt $bakFiles.Count; $xi++) {
                    $f = $bakFiles[$xi]
                    try {
                        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                        [void]$removed.Add($f.Name)
                    } catch {
                        if ($JsonOutput) {
                            _emit_json "backups" @{ error = "failed to remove $($f.Name): $($_.Exception.Message)"; exitCode = 2; backups = @($jsonRows) }
                        } else {
                            Write-Host "[windo] backups: failed to remove $($f.FullName)" -ForegroundColor Red
                        }
                        _windo_set_exit 2
                        return
                    }
                }
            }
            $rowsAfter = [System.Collections.ArrayList]@()
            foreach ($f in @(Get-ChildItem -Path $SecureDir -Filter "windo_history*.enc.bak" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
                [void]$rowsAfter.Add([ordered]@{
                    name = $f.Name
                    fullPath = $f.FullName
                    lastWriteTime = $f.LastWriteTime.ToString("o")
                    sizeBytes = [int64]$f.Length
                })
            }
            if ($JsonOutput) {
                _emit_json "backups" @{ backups = @($rowsAfter); prunedFiles = @($removed); keep = $kn; exitCode = 0 }
            } else {
                Write-Host "[windo] Log backups (after prune)" -ForegroundColor Cyan
                Write-Host "  Kept newest : $keepN file(s)" -ForegroundColor DarkGray
                Write-Host "  Removed     : $($removed.Count) file(s)" -ForegroundColor $(if ($removed.Count -gt 0) { 'Yellow' } else { 'DarkGray' })
                if ($removed.Count -gt 0) { $removed | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkYellow } }
            }
            _windo_set_exit 0
            return
        }
        if ($JsonOutput) {
            _emit_json "backups" @{ backups = @($jsonRows); backupCount = $jsonRows.Count; exitCode = 0 }
            _windo_set_exit 0
            return
        }
        Write-Host "[windo] Encrypted log backups under SecureDir" -ForegroundColor Cyan
        Write-Host "  Path: $SecureDir" -ForegroundColor DarkGray
        if ($bakFiles.Count -eq 0) {
            Write-Host "  (no windo_history*.enc.bak files; run windo cleanup to create one)" -ForegroundColor DarkGray
        } else {
            foreach ($f in $bakFiles) {
                Write-Host ("  {0,-40} {1,12} bytes  {2}" -f $f.Name, $f.Length, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
            }
            Write-Host "  Prune older: windo backups --prune --keep 5 --force" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "theme") {
        $sub = $null
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -in @('classic', 'modern', 'auto')) {
            try {
                $prefObj = _windo_read_windo_prefs_map
                $prefObj['schemaVersion'] = "1.0"
                $prefObj['jsonEnvelope'] = $sub
                if (-not (_windo_save_windo_prefs $prefObj)) { throw "unable to write prefs file" }
            } catch {
                Write-Host "[windo] theme: could not write $PrefsFile : $($_.Exception.Message)" -ForegroundColor Red
                _windo_set_exit 2
                return
            }
            $eff = _windo_resolve_json_envelope
            if ($JsonOutput) {
                _emit_json "theme" @{
                    saved = $true
                    jsonEnvelope = $sub
                    effective = @{ schemaVersion = $eff.schemaLabel; includeMeta = $eff.includeMeta }
                    prefsFile = $PrefsFile
                    exitCode = 0
                }
            } else {
                Write-Host "[windo] JSON envelope theme saved: $sub  ($PrefsFile)" -ForegroundColor Green
                Write-Host "  Effective --json: schemaVersion=$($eff.schemaLabel), meta=$(if ($eff.includeMeta) { 'on' } else { 'off' })" -ForegroundColor DarkGray
                Write-Host "  (Runner, tasks, and audit security are unchangedâ€”only CLI JSON shape.)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($null -ne $sub -and $sub -ne '') {
            Write-Host "[windo] theme: expected classic | modern | auto  (got: $sub)" -ForegroundColor Red
            _windo_set_exit 2
            return
        }
        $eff = _windo_resolve_json_envelope
        $pf = _read_windo_prefs
        $fileMode = $null
        if ($pf -and $pf.PSObject.Properties.Name -contains 'jsonEnvelope') { $fileMode = [string]$pf.jsonEnvelope }
        if ($JsonOutput) {
            _emit_json "theme" @{
                jsonEnvelopeFile = $fileMode
                environmentOverride = $(if ($env:WINDO_JSON_ENVELOPE) { [string]$env:WINDO_JSON_ENVELOPE } else { $null })
                effective = @{ schemaVersion = $eff.schemaLabel; includeMeta = $eff.includeMeta }
                embeddedProfileSchema = $SchemaVersion
                prefsFile = $PrefsFile
                exitCode = 0
            }
        } else {
            Write-Host "[windo] JSON envelope theme (CLI --json output only)" -ForegroundColor Cyan
            Write-Host "  WINDO $WindoVersion  embedded schema: $SchemaVersion" -ForegroundColor DarkGray
            Write-Host "  Prefs file    : $PrefsFile" -ForegroundColor DarkGray
            Write-Host "  Saved preset  : $(if ($fileMode) { $fileMode } else { '(none â†’ auto)' })"
            Write-Host "  Env override  : $(if ($env:WINDO_JSON_ENVELOPE) { $env:WINDO_JSON_ENVELOPE } else { '(none)' })  (wins over file)"
            Write-Host "  Effective now : schemaVersion=$($eff.schemaLabel), meta=$(if ($eff.includeMeta) { 'on' } else { 'off' })"
            Write-Host "  Set: windo theme classic | modern | auto" -ForegroundColor DarkGray
            Write-Host "    classic = 2.6-style envelope without meta; modern = 3.0 + meta; auto = follow embedded profile" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "modules") {
        $sub = "list"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        $modRoot = _windo_modules_root
        $enabled = @(_windo_get_enabled_module_ids)

        if ($sub -in @('enable', 'disable')) {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "modules" @{ error = "missing module id"; exitCode = 2 } } else { Write-Host "[windo] modules: usage: windo modules $sub <id>" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $mid = [string]$Command[2].Trim()
            if ([string]::IsNullOrWhiteSpace($mid)) {
                _windo_set_exit 2
                return
            }
            $modDir = Join-Path $modRoot $mid
            if ($sub -eq 'enable') {
                if (!(Test-Path -LiteralPath (Join-Path $modDir "module.json"))) {
                    if ($JsonOutput) { _emit_json "modules" @{ error = "module.json not found"; moduleId = $mid; path = $modDir; exitCode = 2 } }
                    else { Write-Host "[windo] modules enable: no module.json under $modDir" -ForegroundColor Red }
                    _windo_set_exit 2
                    return
                }
                $ne = if ($enabled -contains $mid) { @($enabled) } else { @($enabled + $mid) }
                if (-not (_windo_set_enabled_module_ids $ne)) {
                    if ($JsonOutput) { _emit_json "modules" @{ error = "prefs write failed"; exitCode = 2 } } else { Write-Host "[windo] modules enable: could not write $PrefsFile" -ForegroundColor Red }
                    _windo_set_exit 2
                    return
                }
                if ($JsonOutput) { _emit_json "modules" @{ action = "enable"; moduleId = $mid; enabled = @(_windo_get_enabled_module_ids); exitCode = 0 } }
                else { Write-Host "[windo] Module enabled: $mid (reload profile or start a new shell to load)" -ForegroundColor Green }
                _windo_set_exit 0
                return
            }
            $ne2 = @($enabled | Where-Object { $_ -ne $mid })
            if (-not (_windo_set_enabled_module_ids $ne2)) {
                if ($JsonOutput) { _emit_json "modules" @{ error = "prefs write failed"; exitCode = 2 } } else { Write-Host "[windo] modules disable: could not write $PrefsFile" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            if ($JsonOutput) { _emit_json "modules" @{ action = "disable"; moduleId = $mid; enabled = @(_windo_get_enabled_module_ids); exitCode = 0 } }
            else { Write-Host "[windo] Module disabled: $mid" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }

        if ($sub -eq 'verify') {
            $rows = _windo_modules_discover_rows $enabled
            $results = [System.Collections.ArrayList]@()
            $allOk = $true
            foreach ($en in $enabled) {
                $m = @($rows | Where-Object { $_.id -eq $en }) | Select-Object -First 1
                if (-not $m) {
                    [void]$results.Add([ordered]@{ id = $en; ok = $false; detail = "enabled but directory missing" })
                    $allOk = $false
                    continue
                }
                $mf = _windo_read_module_manifest $m.path
                $entry = [string]$m.entry
                $entPath = Join-Path $m.path $entry
                $ok = $true
                $detail = "ok"
                if (!(Test-Path -LiteralPath $entPath)) { $ok = $false; $detail = "entry missing: $entry" }
                if ($ok -and $mf -and $mf.PSObject.Properties.Name -contains 'integrity') {
                    $ih = $mf.integrity
                    if ($null -ne $ih) {
                        $props = @()
                        if ($ih -is [hashtable]) { $props = $ih.Keys }
                        else { foreach ($p in $ih.PSObject.Properties) { $props += $p.Name } }
                        foreach ($rel in @($props)) {
                            $exp = $null
                            if ($ih -is [hashtable]) { $exp = [string]$ih[$rel] }
                            else { $exp = [string]$ih.$rel }
                            $fp = Join-Path $m.path ([string]$rel)
                            if (!(Test-Path -LiteralPath $fp)) { $ok = $false; $detail = "missing $rel"; break }
                            $got = (_file_hash $fp)
                            if ($got.ToUpperInvariant() -cne $exp.Trim().ToUpperInvariant()) { $ok = $false; $detail = "hash mismatch $rel"; break }
                        }
                    }
                }
                if (-not $ok) { $allOk = $false }
                [void]$results.Add([ordered]@{ id = $en; ok = $ok; detail = $detail })
            }
            if ($JsonOutput) { _emit_json "modules" @{ modulesRoot = $modRoot; verify = @($results); allOk = $allOk; exitCode = $(if ($allOk) { 0 } else { 3 }) } }
            else {
                Write-Host "[windo] modules verify" -ForegroundColor Cyan
                foreach ($r in $results) {
                    $c = if ($r.ok) { 'Green' } else { 'Red' }
                    Write-Host "  $($r.id): $($r.detail)" -ForegroundColor $c
                }
            }
            _windo_set_exit $(if ($allOk) { 0 } else { 3 })
            return
        }

        if ($sub -eq 'doctor') {
            if (!(Test-Path -LiteralPath $modRoot)) {
                if ($JsonOutput) { _emit_json "modules" @{ modulesRoot = $modRoot; modulesRootExists = $false; exitCode = 2 } } else { Write-Host "[windo] modules doctor: modules root missing: $modRoot" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $rows = _windo_modules_discover_rows $enabled
            $issues = [System.Collections.ArrayList]@()
            foreach ($en in $enabled) {
                $m = @($rows | Where-Object { $_.id -eq $en }) | Select-Object -First 1
                if (-not $m) { [void]$issues.Add("enabled '$en' has no directory under modules root"); continue }
                $mf = _windo_read_module_manifest $m.path
                if (-not $mf) { [void]$issues.Add("$en : invalid module.json"); continue }
                if (-not (_windo_meets_requires_windo ([string]$m.requiresWindoVersion))) { [void]$issues.Add("$en : requires WINDO $($m.requiresWindoVersion), have $WindoVersion") }
                $entPath = Join-Path $m.path ([string]$m.entry)
                if (!(Test-Path -LiteralPath $entPath)) { [void]$issues.Add("$en : entry script missing ($($m.entry))") }
            }
            $ok = ($issues.Count -eq 0)
            if ($JsonOutput) {
                _emit_json "modules" @{ doctor = $true; modulesRoot = $modRoot; modulesRootExists = $true; discovered = @($rows); enabled = $enabled; issues = @($issues); exitCode = $(if ($ok) { 0 } else { 3 }) }
            } else {
                Write-Host "[windo] modules doctor" -ForegroundColor Cyan
                Write-Host "  Root: $modRoot" -ForegroundColor DarkGray
                Write-Host "  Enabled: $(if ($enabled.Count -gt 0) { $enabled -join ', ' } else { '(none)' })" -ForegroundColor DarkGray
                if ($ok) { Write-Host "  OK" -ForegroundColor Green } else { foreach ($i in $issues) { Write-Host "  - $i" -ForegroundColor Yellow } }
            }
            _windo_set_exit $(if ($ok) { 0 } else { 3 })
            return
        }

        if ($sub -notin @('list', '')) {
            if ($JsonOutput) { _emit_json "modules" @{ error = "unknown subcommand"; sub = $sub; exitCode = 2 } } else { Write-Host "[windo] modules: expected list | enable | disable | doctor | verify" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $rows = _windo_modules_discover_rows $enabled
        if ($JsonOutput) { _emit_json "modules" @{ modulesRoot = $modRoot; modules = @($rows); enabled = $enabled; exitCode = 0 } }
        else {
            Write-Host "[windo] modules (under $modRoot)" -ForegroundColor Cyan
            if ($rows.Count -eq 0) { Write-Host "  (no module directories; windo dev init-module <name>)" -ForegroundColor DarkGray }
            foreach ($r in $rows) {
                $tag = if ($r.enabled) { "[on] " } else { "[off]" }
                Write-Host "  $tag $($r.id)  $($r.manifestName)  entry=$($r.entry)" -ForegroundColor $(if ($r.enabled) { 'Green' } else { 'Gray' })
            }
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "scan") {
        $paths = [System.Collections.ArrayList]@()
        $recurse = $false
        $hash = $true
        $maxMb = 5
        for ($si = 1; $si -lt $Command.Count; $si++) {
            $sa = [string]$Command[$si]
            if ($sa -eq "--recurse" -or $sa -eq "-r") { $recurse = $true; continue }
            if ($sa -eq "--no-hash") { $hash = $false; continue }
            if ($sa -eq "--max-mb" -and ($si + 1) -lt $Command.Count) {
                $tmp = 0
                if ([int]::TryParse([string]$Command[$si + 1], [ref]$tmp) -and $tmp -gt 0) { $maxMb = [Math]::Min($tmp, 100) }
                $si++
                continue
            }
            if ($sa -like "--max-mb=*") {
                $tmp = 0
                if ([int]::TryParse($sa.Substring(9), [ref]$tmp) -and $tmp -gt 0) { $maxMb = [Math]::Min($tmp, 100) }
                continue
            }
            if ($sa.StartsWith("-")) {
                if ($JsonOutput) { _emit_json "scan" @{ error = "unknown option"; option = $sa; exitCode = 2 } }
                else { Write-Host "[windo] scan: unknown option $sa" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            [void]$paths.Add($sa)
        }
        if ($paths.Count -eq 0) { [void]$paths.Add((Get-Location).Path) }
        $pathArray = @($paths.ToArray() | ForEach-Object { [string]$_ })
        $result = _windo_scan_paths ([string[]]$pathArray) $recurse $maxMb $hash
        if ($JsonOutput) {
            _emit_json "scan" $result
        } else {
            $color = if ($result.exitCode -eq 0) { "Green" } elseif ($result.exitCode -eq 3) { "Yellow" } else { "Red" }
            Write-Host ("[windo] scan {0} files :: {1} with findings :: {2} errors" -f $result.fileCount, $result.findingFileCount, $result.errorCount) -ForegroundColor $color
            foreach ($f in @($result.files | Where-Object { [int]$_.findingCount -gt 0 } | Select-Object -First 25)) {
                Write-Host ("  {0}" -f $f.path) -ForegroundColor Yellow
                foreach ($fd in @($f.findings)) { Write-Host ("    [{0}] {1}: {2}" -f $fd.severity, $fd.id, $fd.detail) -ForegroundColor DarkGray }
            }
            if ($result.findingFileCount -gt 25) { Write-Host "  ...more findings omitted; use --json for full detail." -ForegroundColor DarkGray }
            foreach ($e in @($result.errors)) { Write-Host ("  ERROR {0}: {1}" -f $e.path, $e.error) -ForegroundColor Red }
        }
        _windo_set_exit ([int]$result.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "net-scan") {
        $sub = "status"
        $argStart = 1
        if ($Command.Count -ge 2 -and -not ([string]$Command[1]).StartsWith("--")) {
            $sub = [string]$Command[1].Trim().ToLowerInvariant()
            $argStart = 2
        }
        $defaultTimeoutSeconds = 1
        if ($null -ne $CommandTimeoutOverrideMs -and $CommandTimeoutOverrideMs -ge 1) {
            $defaultTimeoutSeconds = [Math]::Max(1, [int][Math]::Ceiling($CommandTimeoutOverrideMs / 1000))
        }
        if ($defaultTimeoutSeconds -lt 1) { $defaultTimeoutSeconds = 1 }
        if ($defaultTimeoutSeconds -gt 900) { $defaultTimeoutSeconds = 900 }

        if ($sub -eq "status" -or $sub -eq "") {
            $status = _windo_net_scan_status
            $statusPayload = [ordered]@{
                subcommand = "status"
                scannedAt = (Get-Date -Format "o")
                status = $status
                discovery = @{
                    methods = @("Get-NetAdapter", "Get-NetIPConfiguration")
                    description = "Local-only network state readers; no network writes are performed."
                }
                exitCode = [int]$status.exitCode
            }
            if ($JsonOutput) { _emit_json "net-scan" $statusPayload }
            else {
                Write-Host "[windo] net-scan status" -ForegroundColor Cyan
                Write-Host "  Discovery methods: Get-NetAdapter, Get-NetIPConfiguration" -ForegroundColor DarkGray
                if ($status.adapters.Count -eq 0) {
                    Write-Host "  No active adapters found." -ForegroundColor Yellow
                } else {
                    foreach ($a in @($status.adapters)) {
                        Write-Host ("  {0}  IPv4: {1}  IPv6: {2}  Gateway: {3}  MAC: {4}" -f $a.alias, ($a.ipv4 -join ", "), ($a.ipv6 -join ", "), $a.gateway, $(if ($a.macAddress) { $a.macAddress } else { "-" })) -ForegroundColor DarkGray
                    }
                }
                if ($status.exitCode -ne 0) {
                    Write-Host "  Warning: status collection reported one or more errors." -ForegroundColor Yellow
                }
            }
            _windo_set_exit $statusPayload.exitCode
            return
        }

        if ($sub -eq "resolve") {
            $hosts = [System.Collections.ArrayList]@()
            $hostTagsFile = $null
            $hostTagRules = @()
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -like "--*") {
                    if ($a -eq "--host-tags") {
                        if ($si + 1 -ge $Command.Count) {
                            if ($JsonOutput) {
                                _emit_json "net-scan" @{ subcommand = "resolve"; scannedAt = (Get-Date -Format "o"); error = "--host-tags requires a value"; exitCode = 2 }
                            } else {
                                Write-Host "[windo] net-scan resolve: --host-tags requires a value." -ForegroundColor Yellow
                            }
                            _windo_set_exit 2
                            return
                        }
                        $hostTagsFile = [string]$Command[$si + 1]
                        $si++
                        continue
                    }
                    if ($JsonOutput) {
                        _emit_json "net-scan" @{ subcommand = "resolve"; scannedAt = (Get-Date -Format "o"); error = "unknown option '$a'"; exitCode = 2 }
                    } else {
                        Write-Host "[windo] net-scan resolve: unknown option $a" -ForegroundColor Yellow
                    }
                    _windo_set_exit 2
                    return
                }
                [void]$hosts.Add($a)
            }
            if ($hosts.Count -eq 0) {
                if ($JsonOutput) {
                    _emit_json "net-scan" @{ subcommand = "resolve"; scannedAt = (Get-Date -Format "o"); error = "resolve requires at least one host"; exitCode = 2 }
                } else {
                    Write-Host "[windo] net-scan resolve requires at least one host." -ForegroundColor Yellow
                }
                _windo_set_exit 2
                return
            }
            if ($hostTagsFile -or $env:WINDO_NET_SCAN_HOST_TAGS) {
                try {
                    $hostTagRules = _windo_net_scan_load_host_tags -TagFilePath $hostTagsFile
                } catch {
                    if ($JsonOutput) {
                        _emit_json "net-scan" @{ subcommand = "resolve"; scannedAt = (Get-Date -Format "o"); error = $_.Exception.Message; exitCode = 2 }
                    } else {
                        Write-Host ("[windo] net-scan resolve: " + $_.Exception.Message) -ForegroundColor Red
                    }
                    _windo_set_exit 2
                    return
                }
            }
            $resolved = _windo_net_scan_resolve -HostList @($hosts) -TagRules @($hostTagRules)
            if ($JsonOutput) {
                _emit_json "net-scan" @{
                    subcommand = "resolve"
                    scannedAt = (Get-Date -Format "o")
                    requested = @($hosts)
                    hosts = $resolved.hosts
                    resolvedCount = $resolved.resolvedCount
                    errorCount = $resolved.errorCount
                    errors = @($resolved.errors)
                    discovery = @{ methods = @("Resolve-DnsName", "System.Net.Dns::GetHostAddresses") }
                    exitCode = [int]$resolved.exitCode
                }
            } else {
                Write-Host "[windo] net-scan resolve" -ForegroundColor Cyan
                Write-Host "  Discovery methods: Resolve-DnsName, System.Net.Dns::GetHostAddresses" -ForegroundColor DarkGray
                if ($hostTagsFile -or $env:WINDO_NET_SCAN_HOST_TAGS) { Write-Host "  Host tags: enabled" -ForegroundColor DarkGray }
                foreach ($r in @($resolved.hosts)) {
                    if ($r.addresses.Count -gt 0) {
                        Write-Host ("  {0}: {1}" -f $r.host, ($r.addresses -join ", ")) -ForegroundColor DarkGray
                        if ($r.reverseHostnames.Count -gt 0) {
                            $flat = [System.Collections.ArrayList]@()
                            foreach ($entry in @($r.reverseHostnames)) { foreach ($n in @($entry)) { [void]$flat.Add([string]$n) } }
                            Write-Host ("    reverse: {0}" -f ($flat -join ", ")) -ForegroundColor DarkGray
                        }
                        if ($r.identityTags.Count -gt 0) {
                            Write-Host ("    tags: {0}" -f (($r.identityTags | ForEach-Object { [string]$_.tags.label }) -join ", ")) -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host ("  {0}: (failed) {1}" -f $r.host, $(if ($r.error) { $r.error } else { "no address found" })) -ForegroundColor Yellow
                    }
                }
            }
            _windo_set_exit $resolved.exitCode
            return
        }

        if ($sub -eq "arp") {
            $ifAlias = $null
            $includeStale = $false
            $hostTagsFile = $null
            $hostTagRules = @()
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -eq "--interface") {
                    if ($si + 1 -ge $Command.Count) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "arp"; scannedAt = (Get-Date -Format "o"); error = "--interface requires a value"; exitCode = 2 } }
                        else { Write-Host "[windo] net-scan arp --interface requires a value." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    $ifAlias = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -eq "--include-stale") { $includeStale = $true; continue }
                if ($a -eq "--host-tags") {
                    if ($si + 1 -ge $Command.Count) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "arp"; scannedAt = (Get-Date -Format "o"); error = "--host-tags requires a value"; exitCode = 2 } }
                        else { Write-Host "[windo] net-scan arp: --host-tags requires a value." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    $hostTagsFile = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--*") {
                    if ($JsonOutput) {
                        _emit_json "net-scan" @{ subcommand = "arp"; scannedAt = (Get-Date -Format "o"); error = "unknown option '$a'"; exitCode = 2 }
                    } else {
                        Write-Host "[windo] net-scan arp: unknown option $a" -ForegroundColor Yellow
                    }
                    _windo_set_exit 2
                    return
                }
            }
            if ($ifAlias) {
                $aliasFound = $false
                try { $aliasFound = ((Get-NetAdapter -Name $ifAlias -ErrorAction Stop) -or (Get-NetAdapter -InterfaceAlias $ifAlias -ErrorAction SilentlyContinue)) } catch { $aliasFound = $false }
                if (-not $aliasFound) {
                    if ($JsonOutput) {
                        _emit_json "net-scan" @{ subcommand = "arp"; scannedAt = (Get-Date -Format "o"); error = "unknown interface '$ifAlias'"; exitCode = 2 }
                    } else {
                        Write-Host "[windo] net-scan arp: unknown interface '$ifAlias'." -ForegroundColor Yellow
                    }
                    _windo_set_exit 2
                    return
                }
            }
            if ($hostTagsFile -or $env:WINDO_NET_SCAN_HOST_TAGS) {
                try { $hostTagRules = _windo_net_scan_load_host_tags -TagFilePath $hostTagsFile } catch {
                    if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "arp"; scannedAt = (Get-Date -Format "o"); error = $_.Exception.Message; exitCode = 2 } }
                    else { Write-Host ("[windo] net-scan arp: " + $_.Exception.Message) -ForegroundColor Red }
                    _windo_set_exit 2
                    return
                }
            }
            $neighbors = _windo_net_scan_arp -Interface $ifAlias -IncludeStale $includeStale
            $neighborsToEmit = @()
            if ($hostTagRules -and $hostTagRules.Count -gt 0) {
                $neighborsToEmit = [System.Collections.ArrayList]@()
                foreach ($n in @($neighbors.neighbors)) {
                    $ip = [string]$n.ip
                    $hostnames = if ($ip) { _windo_net_scan_resolve_reverse_dns -IpAddress $ip } else { @() }
                    $tags = _windo_net_scan_apply_host_tags -Ip $ip -HostNames @($hostnames) -Mac ([string]$n.mac) -InterfaceAlias ([string]$n.interfaceAlias) -Type "arp" -TagRules $hostTagRules
                    [void]$neighborsToEmit.Add([ordered]@{
                        ip = [string]$ip
                        mac = [string]$n.mac
                        state = [string]$n.state
                        interfaceAlias = [string]$n.interfaceAlias
                        hostnames = @($hostnames)
                        identityTags = @($tags)
                    })
                }
            } else {
                $neighborsToEmit = @($neighbors.neighbors)
            }
            if ($JsonOutput) {
                _emit_json "net-scan" @{
                    subcommand = "arp"
                    scannedAt = (Get-Date -Format "o")
                    interface = $ifAlias
                    includeStale = [bool]$includeStale
                    neighbors = @($neighborsToEmit)
                    discovery = @{ methods = @("Get-NetNeighbor", "arp.exe -a"); source = $neighbors.source }
                    errorCount = @($neighbors.errors).Count
                    errors = @($neighbors.errors)
                    exitCode = [int]$neighbors.exitCode
                }
            } else {
                Write-Host "[windo] net-scan arp" -ForegroundColor Cyan
                Write-Host "  Discovery: Get-NetNeighbor (primary), arp.exe -a (fallback)" -ForegroundColor DarkGray
                if ($ifAlias) { Write-Host "  Interface: $ifAlias" -ForegroundColor DarkGray }
                if ($hostTagsFile -or $env:WINDO_NET_SCAN_HOST_TAGS) { Write-Host "  Host tags: enabled" -ForegroundColor DarkGray }
                if ($neighbors.neighbors.Count -eq 0) {
                    Write-Host "  No matching ARP entries." -ForegroundColor Yellow
                } else {
                    foreach ($n in @($neighbors.neighbors)) {
                        Write-Host ("  {0} {1} {2} {3}" -f $n.ip, $n.mac, $n.state, $n.interfaceAlias) -ForegroundColor DarkGray
                        if ($hostTagRules.Count -gt 0) {
                            $detail = $neighborsToEmit | Where-Object { $_.ip -eq $n.ip } | Select-Object -First 1
                            if ($detail.hostnames.Count -gt 0) { Write-Host ("    hostnames: {0}" -f ($detail.hostnames -join ", ")) -ForegroundColor DarkGray }
                            if ($detail.identityTags.Count -gt 0) { Write-Host ("    tags: {0}" -f ($detail.identityTags | ForEach-Object { [string]$_.label } -join ", ")) -ForegroundColor DarkGray }
                        }
                    }
                }
            }
            _windo_set_exit [int]$neighbors.exitCode
            return
        }

        if ($sub -eq "ping") {
            $timeoutSource = "global-default"
            $timeout = $defaultTimeoutSeconds
            $hostLimit = 254
            $portsRaw = $null
            $hostTagsFile = $null
            $hostTagRules = @()
            $targets = [System.Collections.ArrayList]@()
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -eq "--timeout") {
                    if ($si + 1 -ge $Command.Count) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "--timeout requires a value"; exitCode = 2 } } else { Write-Host "[windo] --timeout requires a value." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    $rawTimeout = [string]$Command[$si + 1]
                    $timeoutMs = _windo_parse_timeout_override_ms $rawTimeout
                    if ($null -eq $timeoutMs -or $timeoutMs -lt 1) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "invalid --timeout value"; exitCode = 2 } } else { Write-Host "[windo] --timeout must be 1..900." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    $timeout = [Math]::Min(900, [Math]::Max(1, [int][Math]::Ceiling($timeoutMs / 1000)))
                    $timeoutSource = "--timeout"
                    $si++
                    continue
                }
                if ($a -like "--timeout=*") {
                    $rawTimeout = $a.Substring(10)
                    $timeoutMs = _windo_parse_timeout_override_ms $rawTimeout
                    if ($null -eq $timeoutMs -or $timeoutMs -lt 1) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "invalid --timeout value"; exitCode = 2 } } else { Write-Host "[windo] --timeout must be 1..900." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    $timeout = [Math]::Min(900, [Math]::Max(1, [int][Math]::Ceiling($timeoutMs / 1000)))
                    $timeoutSource = "--timeout"
                    continue
                }
                if ($a -eq "--host-limit") {
                    if ($si + 1 -ge $Command.Count) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "--host-limit requires a value"; exitCode = 2 } } else { Write-Host "[windo] --host-limit requires a value." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    if (-not [int]::TryParse([string]$Command[$si + 1], [ref]$hostLimit) -or $hostLimit -lt 1 -or $hostLimit -gt 10000) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "invalid --host-limit value"; exitCode = 2 } } else { Write-Host "[windo] --host-limit must be 1..10000." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    $si++
                    continue
                }
                if ($a -like "--host-limit=*") {
                    if (-not [int]::TryParse($a.Substring(13), [ref]$hostLimit) -or $hostLimit -lt 1 -or $hostLimit -gt 10000) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "invalid --host-limit value"; exitCode = 2 } } else { Write-Host "[windo] --host-limit must be 1..10000." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    continue
                }
                if ($a -eq "--ports") {
                    if ($si + 1 -ge $Command.Count) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "--ports requires a comma list"; exitCode = 2 } } else { Write-Host "[windo] --ports requires a value." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    $portsRaw = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--ports=*") {
                    $portsRaw = $a.Substring(8)
                    continue
                }
                if ($a -like "--*") {
                    if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "unknown option '$a'"; exitCode = 2 } } else { Write-Host "[windo] net-scan ping: unknown option $a" -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
                [void]$targets.Add($a)
            }

            if ($targets.Count -eq 0) {
                if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "ping requires at least one CIDR or host"; exitCode = 2 } } else { Write-Host "[windo] net-scan ping requires a CIDR or at least one host." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            try {
                $ports = if ([string]::IsNullOrWhiteSpace($portsRaw)) { @() } else { _windo_net_scan_parse_ports -PortsRaw $portsRaw }
            } catch {
                if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = $_.Exception.Message; exitCode = 2 } } else { Write-Host ("[windo] invalid --ports: {0}" -f $_.Exception.Message) -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            if ($ports.Count -eq 0) { $ports = @() }

            $cidr = $null
            $expandedFromCidr = $false
            $pingTargets = [System.Collections.ArrayList]@()
            foreach ($t in @($targets)) {
                $trimmed = [string]$t.Trim()
                if (-not $trimmed) { continue }
                if ($trimmed -match "^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$") {
                    if ($pingTargets.Count -gt 0 -or $expandedFromCidr) {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "only one CIDR target is supported per invocation"; exitCode = 2 } } else { Write-Host "[windo] net-scan ping: only one CIDR target is supported." -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    try {
                        $expanded = _windo_net_scan_expand_subnet -Cidr $trimmed -HostLimit $hostLimit
                        $cidr = $trimmed
                        $expandedFromCidr = $true
                        foreach ($ip in @($expanded)) { [void]$pingTargets.Add($ip) }
                    } catch {
                        if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = $_.Exception.Message; exitCode = 2 } } else { Write-Host "[windo] net-scan ping: $($_.Exception.Message)" -ForegroundColor Yellow }
                        _windo_set_exit 2
                        return
                    }
                    continue
                }
                [void]$pingTargets.Add($trimmed)
            }
            if ($pingTargets.Count -eq 0) {
                if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "ping"; scannedAt = (Get-Date -Format "o"); error = "no valid targets"; exitCode = 2 } } else { Write-Host "[windo] net-scan ping: no valid targets." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $unique = @{}
            $orderedTargets = [System.Collections.ArrayList]@()
            foreach ($p in @($pingTargets)) {
                if (-not $unique.ContainsKey([string]$p)) {
                    $unique[[string]$p] = $true
                    [void]$orderedTargets.Add([string]$p)
                }
            }
            $probeTargets = @($orderedTargets)
            if ($probeTargets.Count -gt $hostLimit) { $probeTargets = $probeTargets[0..($hostLimit - 1)] }

            $nmapMap = $null
            if ($ports.Count -eq 0 -and $probeTargets.Count -gt 64) {
                $allIp = $true
                foreach ($p in @($probeTargets)) { if (-not _windo_net_scan_is_ipv4 $p) { $allIp = $false; break } }
                if ($allIp) { $nmapMap = _windo_net_scan_nmap_reachable -Targets $probeTargets -TimeoutSeconds $timeout }
            }

            $hostRows = [System.Collections.ArrayList]@()
            $errors = [System.Collections.ArrayList]@()
            $reachable = 0
            $unreachable = 0
            $errorCount = 0
            foreach ($host in @($probeTargets)) {
                if ($nmapMap -and $nmapMap.ContainsKey($host)) {
                    $icmp = @{ reachable = $true; rttMs = $null; error = $null }
                } elseif ($nmapMap -isnot $null -and -not $nmapMap.ContainsKey($host)) {
                    $icmp = @{ reachable = $false; rttMs = $null; error = "unreachable" }
                } else {
                    $icmp = _windo_net_scan_probe_icmp -Target $host -TimeoutSeconds $timeout
                }

                $hostError = $null
                if ($icmp.error) {
                    $errorCount++
                    $hostError = $icmp.error
                    [void]$errors.Add([ordered]@{ ip = $host; error = $icmp.error })
                }
                $portMap = [ordered]@{}
                if ($icmp.reachable -and $ports.Count -gt 0) {
                    foreach ($p in @($ports)) {
                        $pProbe = _windo_net_scan_probe_tcp -Host $host -Port $p -TimeoutSeconds $timeout
                        $portMap[[string]$p] = [bool]$pProbe.open
                        if ($pProbe.error) {
                            $errorCount++
                            $hostError = $(if ($hostError) { "$hostError; $($pProbe.error)" } else { $pProbe.error })
                            [void]$errors.Add([ordered]@{ ip = $host; error = $pProbe.error })
                        }
                    }
                }
                if ($icmp.reachable) { $reachable++ } else { $unreachable++ }
                [void]$hostRows.Add([ordered]@{
                    ip = $host
                    reachable = [bool]$icmp.reachable
                    rttMs = if ($icmp.rttMs -eq $null) { $null } else { [int]$icmp.rttMs }
                    ports = if ($ports.Count -eq 0) { @{} } else { [ordered]$portMap }
                })
            }

            $pingPayload = [ordered]@{
                subcommand = "ping"
                scannedAt = (Get-Date -Format "o")
                targets = $(if ($cidr) { @($targets | ForEach-Object { [string]$_ }) } else { @($probeTargets) })
                rawTargets = @($targets | ForEach-Object { [string]$_ })
                cidr = $cidr
                hostLimit = $hostLimit
                hostLimitApplied = $probeTargets.Count
                timeoutSeconds = $timeout
                timeoutSource = $timeoutSource
                ports = @($ports)
                discovery = @{
                    methods = $(if ($nmapMap -ne $null) { @("nmap -sn", "Test-Connection (fallback)") } else { @("Test-Connection") })
                    note = "TCP ports are probed only when ICMP is reachable."
                }
                hostTags = if ($hostTagRules.Count -gt 0) { @("windo") } else { @() }
                hosts = @($hostRows)
                reachableCount = [int]$reachable
                unreachableCount = [int]$unreachable
                errorCount = [int]$errorCount
                probedCount = @($probeTargets).Count
                errors = @($errors | Select-Object -Unique)
                exitCode = $(if ($errorCount -gt 0 -or $unreachable -gt 0) { 3 } else { 0 })
            }
            _windo_net_scan_ping_report -Payload $pingPayload -JsonOutput $JsonOutput
            _windo_set_exit $pingPayload.exitCode
            return
        }

        # probe — dedicated non-blocking TCP port probe (netcat-style, no ICMP required)
        if ($sub -eq "probe") {
            $probeHost = ""; $probePortSpec = ""; $probeTimeoutMs = 800
            $pi = $argStart
            while ($pi -lt $Command.Count) {
                $pa = [string]$Command[$pi]
                if ($pa -eq "--timeout" -and $pi + 1 -lt $Command.Count) {
                    $tv = 0; if ([double]::TryParse([string]$Command[$pi + 1], [ref]$tv)) { $probeTimeoutMs = [int]($tv * 1000) }; $pi += 2; continue
                }
                if ($pa -like "--timeout=*") {
                    $tv = 0; if ([double]::TryParse($pa.Substring(10), [ref]$tv)) { $probeTimeoutMs = [int]($tv * 1000) }; $pi++; continue
                }
                if (-not $pa.StartsWith("-")) {
                    if ([string]::IsNullOrWhiteSpace($probeHost)) { $probeHost = $pa } elseif ([string]::IsNullOrWhiteSpace($probePortSpec)) { $probePortSpec = $pa }
                }
                $pi++
            }
            if ([string]::IsNullOrWhiteSpace($probeHost) -or [string]::IsNullOrWhiteSpace($probePortSpec)) {
                if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "probe"; scannedAt = (Get-Date -Format "o"); error = "usage: windo net-scan probe <host> <port[,port,port-range,...]>"; exitCode = 2 } }
                else { Write-Host "[windo] net-scan probe <host> <port[,port,port-range,...]> [--timeout secs]" -ForegroundColor Yellow }
                _windo_set_exit 2; return
            }
            $probePortNums = @()
            try {
                foreach ($tok in $probePortSpec.Split(",")) {
                    $tok = $tok.Trim()
                    if ($tok -match '^(\d+)-(\d+)$') {
                        $plo = [int]$Matches[1]; $phi2 = [int]$Matches[2]
                        if ($phi2 - $plo -gt 100) { throw "Port range $tok exceeds 100-port limit." }
                        $plo..$phi2 | ForEach-Object { $probePortNums += $_ }
                    } elseif ($tok -match '^\d+$') {
                        $n = [int]$tok; if ($n -lt 1 -or $n -gt 65535) { throw "Port $n is out of range." }
                        $probePortNums += $n
                    } elseif (-not [string]::IsNullOrWhiteSpace($tok)) { throw "Invalid port token: $tok" }
                }
            } catch {
                if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "probe"; scannedAt = (Get-Date -Format "o"); error = $_.Exception.Message; exitCode = 2 } }
                else { Write-Host ("[windo] net-scan probe: {0}" -f $_.Exception.Message) -ForegroundColor Yellow }
                _windo_set_exit 2; return
            }
            if ($probePortNums.Count -eq 0) {
                if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "probe"; scannedAt = (Get-Date -Format "o"); error = "no valid ports in: $probePortSpec"; exitCode = 2 } }
                else { Write-Host ("[windo] net-scan probe: no valid ports in: {0}" -f $probePortSpec) -ForegroundColor Yellow }
                _windo_set_exit 2; return
            }
            $probeResults = @()
            foreach ($p in $probePortNums) {
                $r = _windo_net_scan_probe_tcp -Host $probeHost -Port $p -TimeoutSeconds ([Math]::Max(1, [int][Math]::Ceiling($probeTimeoutMs / 1000)))
                $probeResults += [pscustomobject]@{ port = $p; open = $r.open; error = $r.error }
            }
            $probeOpen   = ($probeResults | Where-Object { $_.open }).Count
            $probeClosed = $probeResults.Count - $probeOpen
            $probeCode   = if ($probeOpen -gt 0) { 0 } else { 3 }
            if ($JsonOutput) {
                _emit_json "net-scan" @{ subcommand = "probe"; scannedAt = (Get-Date -Format "o"); host = $probeHost; open = $probeOpen; closed = $probeClosed; results = $probeResults; exitCode = $probeCode }
            } else {
                Write-Host ("[windo] net-scan probe :: {0} :: {1} open / {2} closed" -f $probeHost, $probeOpen, $probeClosed) -ForegroundColor Cyan
                foreach ($r in $probeResults) {
                    Write-Host ("  :{0,-6} {1}" -f $r.port, $(if ($r.open) { "OPEN  " } else { "closed" })) -ForegroundColor $(if ($r.open) { "Green" } else { "DarkGray" })
                }
            }
            _windo_set_exit $probeCode; return
        }

        # nmap — pass-through to nmap.exe with availability guard
        if ($sub -eq "nmap") {
            $nmapExe = Get-Command nmap -ErrorAction SilentlyContinue
            if (-not $nmapExe) {
                if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "nmap"; scannedAt = (Get-Date -Format "o"); error = "nmap not found in PATH; install with: winget install Insecure.Nmap"; exitCode = 2 } }
                else { Write-Host "[windo] nmap not found.  Install: winget install Insecure.Nmap" -ForegroundColor Yellow }
                _windo_set_exit 2; return
            }
            $nmapPassArgs = @()
            for ($si = $argStart; $si -lt $Command.Count; $si++) { $nmapPassArgs += [string]$Command[$si] }
            if ($nmapPassArgs.Count -eq 0) {
                if ($JsonOutput) { _emit_json "net-scan" @{ subcommand = "nmap"; scannedAt = (Get-Date -Format "o"); error = "no nmap arguments supplied"; exitCode = 2 } }
                else { Write-Host "[windo] net-scan nmap [nmap args...]" -ForegroundColor Yellow }
                _windo_set_exit 2; return
            }
            & nmap @nmapPassArgs
            _windo_set_exit $(if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 })
            return
        }

        # rdp — delegate to the windo rdp verb (read posture; apply requires elevation)
        if ($sub -eq "rdp") {
            $rdpFwdArgs = @("rdp")
            for ($si = $argStart; $si -lt $Command.Count; $si++) { $rdpFwdArgs += [string]$Command[$si] }
            $Command = [object[]]$rdpFwdArgs
            # fall through to the rdp verb below
        }

        # vnc — delegate to the windo vnc verb (read posture; stop requires elevation)
        if ($sub -eq "vnc") {
            $vncFwdArgs = @("vnc")
            for ($si = $argStart; $si -lt $Command.Count; $si++) { $vncFwdArgs += [string]$Command[$si] }
            $Command = [object[]]$vncFwdArgs
            # fall through to the vnc verb below
        }

        # wsl — delegate to the windo wsl verb
        if ($sub -eq "wsl") {
            $wslFwdArgs = @("wsl")
            for ($si = $argStart; $si -lt $Command.Count; $si++) { $wslFwdArgs += [string]$Command[$si] }
            $Command = [object[]]$wslFwdArgs
            # fall through to the wsl verb below
        }

        if ($sub -notin @("rdp", "vnc", "wsl")) {
            if ($JsonOutput) {
                _emit_json "net-scan" @{ subcommand = $sub; scannedAt = (Get-Date -Format "o"); error = "unknown subcommand"; exitCode = 2 }
            } else {
                Write-Host "[windo] net-scan: expected status | resolve | arp | ping | probe | nmap | rdp | vnc | wsl (got: $sub)" -ForegroundColor Yellow
            }
            _windo_set_exit 2
            return
        }
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "rdp") {
        $sub = "status"
        $argStart = 1
        if ($Command.Count -ge 2 -and -not ([string]$Command[1]).StartsWith("--")) {
            $sub = [string]$Command[1].Trim().ToLowerInvariant()
            $argStart = 2
        }
        if ($sub -eq "" -or $sub -eq "status") {
            $config = _windo_remote_rdp_config_snapshot
            $rules = _windo_firewall_rules_for_patterns @("RDP", "Remote Desktop", "Terminal Services", "Remote Assistance") @()
            $payload = [ordered]@{
                subcommand = "status"
                scannedAt = (Get-Date -Format "o")
                service = $config.service
                config = $config.registry
                firewall = @{
                    count = @($rules).Count
                    rules = @($rules)
                }
                exitCode = 0
            }
            if ($JsonOutput) {
                _emit_json "rdp" $payload
            } else {
                Write-Host "[windo] rdp status" -ForegroundColor Cyan
                $enabledText = if (($config.registry.terminalServerFq -eq 0)) { "enabled" } else { "disabled" }
                $nlaText = if ($config.registry.userAuthentication -eq 1) { "on" } else { "off" }
                Write-Host "  service=$($config.service.status)  enabled=$enabledText  nla=$nlaText  securityLayer=$($config.registry.securityLayer)" -ForegroundColor DarkGray
                Write-Host "  firewallRules=$(@($rules).Count)  serviceExists=$($config.service.exists)" -ForegroundColor DarkGray
                if (-not $config.service.exists) { Write-Host "  TermService was not found; check permissions and OS edition." -ForegroundColor Yellow }
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "firewall") {
            $action = "status"
            $portsRaw = $null
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -notlike "--*" -and $action -eq "status") {
                    if ($a -in @("status", "enable", "disable")) { $action = $a.ToLowerInvariant(); continue }
                }
                if ($a -eq "--ports") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); error = "--ports requires a value"; exitCode = 2 } } else { Write-Host "[windo] rdp firewall --ports requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $portsRaw = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--ports=*") { $portsRaw = $a.Substring(8); continue }
                if ($a -like "--*") {
                    if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); error = "unknown option '$a'"; exitCode = 2 } } else { Write-Host "[windo] rdp firewall: unknown option $a" -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
            }
            if (-not $action) { $action = "status" }
            $ports = @()
            if (-not [string]::IsNullOrWhiteSpace($portsRaw)) {
                try { $ports = _windo_parse_ports_raw $portsRaw } catch { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); error = $_.Exception.Message; exitCode = 2 } } else { Write-Host ("[windo] invalid --ports: {0}" -f $_.Exception.Message) -ForegroundColor Yellow }; _windo_set_exit 2; return }
            }
            $rules = _windo_firewall_rules_for_patterns @("RDP", "Remote Desktop", "Terminal Services", "Remote Assistance") @($ports)
            if ($action -eq "status") {
                if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); action = "status"; requestedPorts = @($ports); rules = @($rules); exitCode = 0 } }
                else {
                    Write-Host "[windo] rdp firewall status" -ForegroundColor Cyan
                    Write-Host "  matchedRules=$($rules.Count)" -ForegroundColor DarkGray
                    foreach ($r in @($rules)) {
                        Write-Host ("  {0} [{1}] enabled={2} profile={3}" -f $r.displayName, $r.name, $r.enabled, $r.profile) -ForegroundColor DarkGray
                    }
                }
                _windo_set_exit 0
                return
            }
            if ($action -in @("enable", "disable")) {
                if ($DryRun) {
                    if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); action = $action; dryRun = $true; requestedPorts = @($ports); exitCode = 0; estimatedEffect = "read-only preview" } }
                    else { Write-Host "[windo] rdp firewall $action (dry-run)" -ForegroundColor Yellow }
                    _windo_set_exit 0
                    return
                }
                if (-not (_windo_is_process_elevated)) {
                    if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); action = $action; error = "elevation required"; exitCode = 3; next = "windo run -- windo rdp firewall $action" } }
                    else { Write-Host "[windo] rdp firewall $action requires elevation. Use windo run -- windo rdp firewall $action." -ForegroundColor Yellow }
                    _windo_set_exit 3
                    return
                }
                $names = @(@($rules) | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
                if ($names.Count -eq 0) {
                    if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); error = "no matching firewall rule found"; exitCode = 2 } } else { Write-Host "[windo] rdp firewall: no matching rule was found." -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
                $result = _windo_firewall_apply_rules $names ($action -eq "enable")
                if ($JsonOutput) {
                    _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); action = $action; requestedPorts = @($ports); updates = @($result); exitCode = $(if (@(@($result) | Where-Object { -not $_.success }).Count -gt 0) { 2 } else { 0 }) }
                } else {
                    Write-Host "[windo] rdp firewall $action" -ForegroundColor Cyan
                    foreach ($u in @($result)) {
                        if ($u.success) { Write-Host ("  [ok] {0}" -f $u.name) -ForegroundColor Green } else { Write-Host ("  [fail] {0} ({1})" -f $u.name, $u.error) -ForegroundColor Red }
                    }
                }
                _windo_set_exit $(if (@($result | Where-Object { -not $_.success }).Count -gt 0) { 2 } else { 0 })
                return
            }
            if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); error = "expected status|enable|disable"; exitCode = 2 } } else { Write-Host "[windo] rdp firewall: expected status|enable|disable" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }

        if ($sub -eq "config") {
            $rdpEnable = $null
            $rdpNla = $null
            $rdpSecurityLayer = $null
            $restart = $false
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -eq "--enable") { $rdpEnable = $true; continue }
                if ($a -eq "--disable") { $rdpEnable = $false; continue }
                if ($a -eq "--restart") { $restart = $true; continue }
                if ($a -eq "--nla") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; error = "--nla requires a value"; exitCode = 2 } } else { Write-Host "[windo] --nla requires a value (on|off)." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $rdpNlaText = [string]$Command[$si + 1]
                    switch ($rdpNlaText.Trim().ToLowerInvariant()) {
                        '1' { $rdpNla = $true }
                        'true' { $rdpNla = $true }
                        'yes' { $rdpNla = $true }
                        'on' { $rdpNla = $true }
                        'enabled' { $rdpNla = $true }
                        '0' { $rdpNla = $false }
                        'false' { $rdpNla = $false }
                        'no' { $rdpNla = $false }
                        'off' { $rdpNla = $false }
                        'disabled' { $rdpNla = $false }
                        default {
                            if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; error = "--nla must be on|off|true|false|yes|no|1|0"; exitCode = 2 } else { Write-Host "[windo] --nla must be one of: on, off, true, false, yes, no, 1, 0." -ForegroundColor Yellow }
                            _windo_set_exit 2
                            return
                        }
                    }
                    $si++
                    continue
                }
                if ($a -like "--nla=*") {
                    $rdpNlaText = $a.Substring(6)
                    switch ($rdpNlaText.Trim().ToLowerInvariant()) {
                        '1' { $rdpNla = $true }
                        'true' { $rdpNla = $true }
                        'yes' { $rdpNla = $true }
                        'on' { $rdpNla = $true }
                        'enabled' { $rdpNla = $true }
                        '0' { $rdpNla = $false }
                        'false' { $rdpNla = $false }
                        'no' { $rdpNla = $false }
                        'off' { $rdpNla = $false }
                        'disabled' { $rdpNla = $false }
                        default {
                            if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; error = "--nla must be on|off|true|false|yes|no|1|0"; exitCode = 2 } else { Write-Host "[windo] --nla must be one of: on, off, true, false, yes, no, 1, 0." -ForegroundColor Yellow }
                            _windo_set_exit 2
                            return
                        }
                    }
                    continue
                }
                if ($a -eq "--security-layer") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; error = "--security-layer requires a value"; exitCode = 2 } } else { Write-Host "[windo] --security-layer requires a value (0|1|2)." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $rawLayer = [string]$Command[$si + 1]
                    $tmp = 0
                    if (-not [int]::TryParse($rawLayer, [ref]$tmp) -or $tmp -lt 0 -or $tmp -gt 2) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; error = "--security-layer must be 0|1|2"; exitCode = 2 } } else { Write-Host "[windo] --security-layer must be 0, 1, or 2." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $rdpSecurityLayer = $tmp
                    $si++
                    continue
                }
                if ($a -like "--security-layer=*") {
                    $rawLayer = $a.Substring(16)
                    $tmp = 0
                    if (-not [int]::TryParse($rawLayer, [ref]$tmp) -or $tmp -lt 0 -or $tmp -gt 2) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; error = "--security-layer must be 0|1|2"; exitCode = 2 } } else { Write-Host "[windo] --security-layer must be 0, 1, or 2." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $rdpSecurityLayer = $tmp
                    continue
                }
                if ($a -like "--*") { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; error = "unknown option '$a'"; exitCode = 2 } } else { Write-Host "[windo] rdp config: unknown option $a" -ForegroundColor Yellow }; _windo_set_exit 2; return }
                if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; error = "unexpected argument '$a'"; exitCode = 2 } } else { Write-Host "[windo] rdp config: unexpected argument '$a'" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            if ($rdpEnable -eq $null -and $rdpNla -eq $null -and $rdpSecurityLayer -eq $null) {
                if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; scannedAt = (Get-Date -Format "o"); error = "provide --enable|--disable and/or --nla/--security-layer"; exitCode = 2 } } else { Write-Host "[windo] rdp config requires at least one mutation flag." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            if ($DryRun) {
                $payload = [ordered]@{
                    subcommand = "config"
                    scannedAt = (Get-Date -Format "o")
                    dryRun = $true
                    requested = @{
                        enable = $rdpEnable
                        nla = $rdpNla
                        securityLayer = $rdpSecurityLayer
                        restart = $restart
                    }
                    exitCode = 0
                }
                if ($JsonOutput) { _emit_json "rdp" $payload } else { Write-Host "[windo] rdp config (dry-run) -- no changes written." -ForegroundColor Yellow }
                _windo_set_exit 0
                return
            }
            if (-not (_windo_is_process_elevated)) {
                $runArgs = [System.Collections.ArrayList]@()
                if ($rdpEnable -eq $true) { [void]$runArgs.Add("--enable") }
                if ($rdpEnable -eq $false) { [void]$runArgs.Add("--disable") }
                if ($rdpNla -ne $null) { [void]$runArgs.Add("--nla"); [void]$runArgs.Add($(if ($rdpNla) { "on" } else { "off" })) }
                if ($rdpSecurityLayer -ne $null) { [void]$runArgs.Add("--security-layer"); [void]$runArgs.Add([string]$rdpSecurityLayer) }
                if ($restart) { [void]$runArgs.Add("--restart") }
                $runCommand = "windo run -- windo rdp config $($runArgs -join ' ')"
                if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "config"; scannedAt = (Get-Date -Format "o"); error = "elevation required"; exitCode = 3; next = $runCommand } } else { Write-Host "[windo] rdp config requires elevation. Use: $runCommand" -ForegroundColor Yellow }
                _windo_set_exit 3
                return
            }
            $result = _windo_remote_set_rdp_config -Enable $rdpEnable -Nla $rdpNla -SecurityLayer $rdpSecurityLayer -RestartService:$restart
            if ($JsonOutput) {
                _emit_json "rdp" @{ subcommand = "config"; scannedAt = (Get-Date -Format "o"); requested = @{ enable = $rdpEnable; nla = $rdpNla; securityLayer = $rdpSecurityLayer; restart = $restart }; result = $result; exitCode = $(if ($result.success) { 0 } else { 2 }) }
            } else {
                if ($result.success) { Write-Host "[windo] rdp config updated." -ForegroundColor Green } else { Write-Host "[windo] rdp config failed: $($result.error)" -ForegroundColor Red }
                if ($result.changes.Count -gt 0) { foreach ($c in @($result.changes)) { Write-Host "  $($c.key) -> $($c.value)" -ForegroundColor DarkGray } }
            }
            _windo_set_exit $(if ($result.success) { 0 } else { 2 })
            return
        }

        if ($sub -eq "troubleshoot") {
            $host = "localhost"
            $portsRaw = "3389"
            $timeoutSeconds = 3
            $credName = $null
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -eq "--host") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "troubleshoot"; error = "--host requires a value"; exitCode = 2 } } else { Write-Host "[windo] --host requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $host = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--host=*") { $host = $a.Substring(7); continue }
                if ($a -eq "--ports") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "troubleshoot"; error = "--ports requires a value"; exitCode = 2 } } else { Write-Host "[windo] --ports requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $portsRaw = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--ports=*") { $portsRaw = $a.Substring(8); continue }
                if ($a -eq "--timeout") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "troubleshoot"; error = "--timeout requires a value"; exitCode = 2 } } else { Write-Host "[windo] --timeout requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $rawTimeout = [string]$Command[$si + 1]
                    $timeoutSec = 0
                    if (-not [int]::TryParse($rawTimeout, [ref]$timeoutSec) -or $timeoutSec -lt 1 -or $timeoutSec -gt 900) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "troubleshoot"; error = "invalid --timeout value"; exitCode = 2 } } else { Write-Host "[windo] --timeout must be 1..900." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $timeoutSeconds = $timeoutSec
                    $si++
                    continue
                }
                if ($a -like "--timeout=*") {
                    $rawTimeout = $a.Substring(10)
                    $timeoutSec = 0
                    if (-not [int]::TryParse($rawTimeout, [ref]$timeoutSec) -or $timeoutSec -lt 1 -or $timeoutSec -gt 900) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "troubleshoot"; error = "invalid --timeout value"; exitCode = 2 } } else { Write-Host "[windo] --timeout must be 1..900." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $timeoutSeconds = $timeoutSec
                    continue
                }
                if ($a -eq "--credential") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "troubleshoot"; error = "--credential requires a value"; exitCode = 2 } } else { Write-Host "[windo] --credential requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $credName = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--credential=*") { $credName = $a.Substring(13); continue }
                if ($a -like "--*") { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "troubleshoot"; error = "unknown option '$a'"; exitCode = 2 } } else { Write-Host "[windo] rdp troubleshoot: unknown option $a" -ForegroundColor Yellow }; _windo_set_exit 2; return }
            }
            try { $ports = _windo_parse_ports_raw $portsRaw } catch { if ($JsonOutput) { _emit_json "rdp" @{ subcommand = "troubleshoot"; scannedAt = (Get-Date -Format "o"); error = $_.Exception.Message; exitCode = 2 } } else { Write-Host ("[windo] invalid --ports: " + $_.Exception.Message) -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $status = _windo_remote_rdp_config_snapshot
            $probeRows = [System.Collections.ArrayList]@()
            foreach ($p in @($ports)) { $probe = _windo_net_scan_probe_tcp -Host $host -Port $p -TimeoutSeconds $timeoutSeconds; [void]$probeRows.Add([ordered]@{ port = [int]$p; reachable = [bool]$probe.open; error = $probe.error }) }
            $rules = _windo_firewall_rules_for_patterns @("RDP", "Remote Desktop", "Terminal Services", "Remote Assistance") @($ports)
            $cred = if ($credName) { _windo_remote_credential_preview $credName } else { $null }
            $payload = [ordered]@{
                subcommand = "troubleshoot"
                scannedAt = (Get-Date -Format "o")
                host = $host
                timeoutSeconds = $timeoutSeconds
                config = $status
                firewall = @{
                    rules = @($rules)
                    matchedCount = @($rules).Count
                }
                portChecks = @($probeRows)
                credential = $cred
                exitCode = 0
            }
            if ($JsonOutput) { _emit_json "rdp" $payload }
            else {
                Write-Host "[windo] rdp troubleshoot" -ForegroundColor Cyan
                Write-Host "  Host: $host Timeout: $timeoutSeconds sec" -ForegroundColor DarkGray
                Write-Host "  Service: $($status.service.status)" -ForegroundColor DarkGray
                foreach ($p in @($probeRows)) { Write-Host ("  Port {0}: {1}" -f $p.port, $(if ($p.reachable) { "open" } else { "closed/filtered" })) -ForegroundColor $(if ($p.reachable) { "Green" } else { "Yellow" }) }
                if ($credName) { if ($cred -and $cred.exists) { Write-Host ("  Credential preview: {0} / {1}" -f $cred.username, $cred.passwordPreview) -ForegroundColor DarkGray } else { Write-Host "  Credential entry not found." -ForegroundColor Yellow } }
            }
            _windo_set_exit 0
            return
        }

        if ($JsonOutput) { _emit_json "rdp" @{ subcommand = $sub; scannedAt = (Get-Date -Format "o"); error = "unknown subcommand"; exitCode = 2 } } else { Write-Host "[windo] rdp: expected status|firewall|config|troubleshoot (got: $sub)" -ForegroundColor Yellow }
        _windo_set_exit 2
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "vnc") {
        $sub = "status"
        $argStart = 1
        if ($Command.Count -ge 2 -and -not ([string]$Command[1]).StartsWith("--")) {
            $sub = [string]$Command[1].Trim().ToLowerInvariant()
            $argStart = 2
        }
        if ($sub -eq "" -or $sub -eq "status") {
            $vncServices = _windo_remote_vnc_services
            $firewallRules = _windo_firewall_rules_for_patterns @("vnc", "ultravnc", "tightvnc", "realvnc", "winvnc", "x11", "vncserver") @()
            $probeRows = [System.Collections.ArrayList]@()
            foreach ($p in @(5900,5901)) { $probe = _windo_net_scan_probe_tcp -Host "localhost" -Port $p -TimeoutSeconds 2; [void]$probeRows.Add([ordered]@{ port = $p; reachable = [bool]$probe.open; error = $probe.error }) }
            if ($JsonOutput) {
                _emit_json "vnc" @{
                    subcommand = "status"
                    scannedAt = (Get-Date -Format "o")
                    services = @($vncServices)
                    firewall = @{ count = @($firewallRules).Count; rules = @($firewallRules) }
                    localProbes = @($probeRows)
                    exitCode = 0
                }
            } else {
                Write-Host "[windo] vnc status" -ForegroundColor Cyan
                Write-Host ("  services={0} firewallRules={1}" -f @($vncServices).Count, @($firewallRules).Count) -ForegroundColor DarkGray
                foreach ($s in @($vncServices)) { Write-Host ("  service {0} ({1}) status={2}" -f $s.name, $s.displayName, $s.status) -ForegroundColor DarkGray }
                foreach ($p in @($probeRows)) { Write-Host ("  localhost:{0} {1}" -f $p.port, $(if ($p.reachable) { "open" } else { "closed" })) -ForegroundColor DarkGray }
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "firewall") {
            $fwSub = "status"
            $portsRaw = $null
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -notlike "--*" -and $fwSub -eq "status") {
                    if ($a -in @("status", "enable", "disable")) { $fwSub = $a.ToLowerInvariant(); continue }
                }
                if ($a -eq "--ports") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "firewall"; error = "--ports requires a value"; exitCode = 2 } } else { Write-Host "[windo] --ports requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $portsRaw = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--ports=*") { $portsRaw = $a.Substring(8); continue }
                if ($a -like "--*") { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "firewall"; error = "unknown option '$a'"; exitCode = 2 } } else { Write-Host "[windo] vnc firewall: unknown option $a" -ForegroundColor Yellow }; _windo_set_exit 2; return }
            }
            $ports = @()
            if (-not [string]::IsNullOrWhiteSpace($portsRaw)) { try { $ports = _windo_parse_ports_raw $portsRaw } catch { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "firewall"; error = $_.Exception.Message; exitCode = 2 } } else { Write-Host ("[windo] invalid --ports: " + $_.Exception.Message) -ForegroundColor Yellow }; _windo_set_exit 2; return }
            }
            $rules = _windo_firewall_rules_for_patterns @("vnc", "ultravnc", "tightvnc", "realvnc", "winvnc", "x11", "vncserver") @($ports)
            if ($fwSub -eq "status") {
                if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); rules = @($rules); action = "status"; exitCode = 0 } } else { Write-Host "[windo] vnc firewall status" -ForegroundColor Cyan; foreach ($r in @($rules)) { Write-Host ("  {0}" -f $r.displayName) -ForegroundColor DarkGray } }
                _windo_set_exit 0
                return
            }
            if ($DryRun) {
                if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); action = $fwSub; dryRun = $true; exitCode = 0 } } else { Write-Host "[windo] vnc firewall $fwSub (dry-run)" -ForegroundColor Yellow }
                _windo_set_exit 0
                return
            }
            if (-not (_windo_is_process_elevated)) {
                if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "firewall"; error = "elevation required"; exitCode = 3; next = "windo run -- windo vnc firewall $fwSub" } } else { Write-Host "[windo] vnc firewall requires elevation. Use windo run -- windo vnc firewall $fwSub." -ForegroundColor Yellow }
                _windo_set_exit 3
                return
            }
            $names = @(@($rules) | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
            if ($names.Count -eq 0) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "firewall"; error = "no matching firewall rules"; exitCode = 2 } } else { Write-Host "[windo] vnc firewall: no matching rules." -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $result = _windo_firewall_apply_rules $names ($fwSub -eq "enable")
            if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "firewall"; scannedAt = (Get-Date -Format "o"); action = $fwSub; updates = @($result); exitCode = $(if (@(@($result) | Where-Object { -not $_.success }).Count -gt 0) { 2 } else { 0 }) } } else { Write-Host "[windo] vnc firewall $fwSub" -ForegroundColor Cyan; foreach ($u in @($result)) { Write-Host ("  {0}: {1}" -f $u.name, $(if ($u.success) { "ok" } else { "failed" })) -ForegroundColor $(if ($u.success) { "Green" } else { "Red" }) } }
            _windo_set_exit $(if (@($result | Where-Object { -not $_.success }).Count -gt 0) { 2 } else { 0 })
            return
        }

        if ($sub -eq "test") {
            $host = $null
            if ($Command.Count -ge ($argStart + 1)) { $host = [string]$Command[$argStart] } else { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "test"; error = "missing host"; exitCode = 2 } } else { Write-Host "[windo] vnc test requires a host argument." -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $portsRaw = "5900,5901"
            $timeoutSeconds = 2
            for ($si = $argStart + 1; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -eq "--ports") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "test"; error = "--ports requires a value"; exitCode = 2 } } else { Write-Host "[windo] --ports requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $portsRaw = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--ports=*") { $portsRaw = $a.Substring(8); continue }
                if ($a -eq "--timeout") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "test"; error = "--timeout requires a value"; exitCode = 2 } } else { Write-Host "[windo] --timeout requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    if (-not [int]::TryParse([string]$Command[$si + 1], [ref]$timeoutSeconds) -or $timeoutSeconds -lt 1 -or $timeoutSeconds -gt 900) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "test"; error = "invalid --timeout value"; exitCode = 2 } } else { Write-Host "[windo] --timeout must be 1..900." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $si++
                    continue
                }
                if ($a -like "--timeout=*") {
                    $tmp = 0
                    if (-not [int]::TryParse($a.Substring(10), [ref]$timeoutSeconds) -or $timeoutSeconds -lt 1 -or $timeoutSeconds -gt 900) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "test"; error = "invalid --timeout value"; exitCode = 2 } } else { Write-Host "[windo] --timeout must be 1..900." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    continue
                }
                if ($a -like "--*") { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "test"; error = "unknown option '$a'"; exitCode = 2 } } else { Write-Host "[windo] vnc test: unknown option $a" -ForegroundColor Yellow }; _windo_set_exit 2; return }
            }
            try { $ports = _windo_parse_ports_raw $portsRaw } catch { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "test"; error = $_.Exception.Message; exitCode = 2 } } else { Write-Host ("[windo] invalid --ports: {0}" -f $_.Exception.Message) -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $rows = [System.Collections.ArrayList]@()
            foreach ($p in @($ports)) { $probe = _windo_net_scan_probe_tcp -Host $host -Port $p -TimeoutSeconds $timeoutSeconds; [void]$rows.Add([ordered]@{ port = [int]$p; open = [bool]$probe.open; error = $probe.error }) }
            if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "test"; host = $host; scannedAt = (Get-Date -Format "o"); timeoutSeconds = $timeoutSeconds; rows = @($rows); exitCode = $(if (@(@($rows) | Where-Object { -not $_.open }).Count -eq @($ports).Count) { 3 } else { 0 }) } } else { Write-Host "[windo] vnc test $host" -ForegroundColor Cyan; foreach ($r in @($rows)) { Write-Host ("  $host : {0} -> {1}" -f $r.port, $(if ($r.open) { "open" } else { "closed" })) -ForegroundColor $(if ($r.open) { "Green" } else { "Yellow" }) } }
            _windo_set_exit $(if (@(@($rows) | Where-Object { -not $_.open }).Count -eq @($ports).Count) { 3 } else { 0 })
            return
        }

        if ($sub -eq "stop") {
            $serviceNames = [System.Collections.ArrayList]@()
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -eq "--") { continue }
                if ($a -like "--*") { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "stop"; error = "unknown option '$a'"; exitCode = 2 } } else { Write-Host "[windo] vnc stop: unknown option $a" -ForegroundColor Yellow }; _windo_set_exit 2; return }
                [void]$serviceNames.Add($a)
            }
            if ($serviceNames.Count -eq 0) {
                $serviceNames = @(@($(_windo_remote_vnc_services) | ForEach-Object { [string]$_.name }))
            }
            if ($serviceNames.Count -eq 0) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "stop"; error = "no VNC services found"; exitCode = 2 } } else { Write-Host "[windo] vnc stop: no VNC service found." -ForegroundColor Yellow }; _windo_set_exit 2; return }
            if ($DryRun) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "stop"; dryRun = $true; services = @($serviceNames); exitCode = 0 } } else { Write-Host "[windo] vnc stop (dry-run) no action" -ForegroundColor Yellow }; _windo_set_exit 0; return }
            if (-not (_windo_is_process_elevated)) {
                if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "stop"; error = "elevation required"; exitCode = 3; next = "windo run -- windo vnc stop $(($serviceNames -join ' '))" } } else { Write-Host "[windo] vnc stop requires elevation. Use windo run -- windo vnc stop <services>." -ForegroundColor Yellow }
                _windo_set_exit 3
                return
            }
            $rows = [System.Collections.ArrayList]@()
            foreach ($svc in @($serviceNames)) {
                try { Stop-Service -Name $svc -ErrorAction Stop; [void]$rows.Add([ordered]@{ name = [string]$svc; status = "stopped"; success = $true }) } catch { [void]$rows.Add([ordered]@{ name = [string]$svc; success = $false; error = $_.Exception.Message }) }
            }
            if ($JsonOutput) {
                _emit_json "vnc" @{ subcommand = "stop"; scannedAt = (Get-Date -Format "o"); services = @($rows); exitCode = $(if (@(@($rows) | Where-Object { -not $_.success }).Count -gt 0) { 2 } else { 0 }) }
            } else {
                Write-Host "[windo] vnc stop" -ForegroundColor Cyan
                foreach ($r in @($rows)) { if ($r.success) { Write-Host ("  [ok] {0}" -f $r.name) -ForegroundColor Green } else { Write-Host ("  [fail] {0}: {1}" -f $r.name, $r.error) -ForegroundColor Red } }
            }
            _windo_set_exit $(if (@(@($rows) | Where-Object { -not $_.success }).Count -gt 0) { 2 } else { 0 })
            return
        }

        if ($sub -eq "troubleshoot") {
            $host = "localhost"
            $portsRaw = "5900,5901"
            $timeoutSeconds = 2
            $credName = $null
            for ($si = $argStart; $si -lt $Command.Count; $si++) {
                $a = [string]$Command[$si]
                if ($a -eq "--host") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "troubleshoot"; error = "--host requires a value"; exitCode = 2 } } else { Write-Host "[windo] --host requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $host = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--host=*") { $host = $a.Substring(7); continue }
                if ($a -eq "--ports") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "troubleshoot"; error = "--ports requires a value"; exitCode = 2 } } else { Write-Host "[windo] --ports requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $portsRaw = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--ports=*") { $portsRaw = $a.Substring(8); continue }
                if ($a -eq "--timeout") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "troubleshoot"; error = "--timeout requires a value"; exitCode = 2 } } else { Write-Host "[windo] --timeout requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    if (-not [int]::TryParse([string]$Command[$si + 1], [ref]$timeoutSeconds) -or $timeoutSeconds -lt 1 -or $timeoutSeconds -gt 900) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "troubleshoot"; error = "invalid --timeout value"; exitCode = 2 } } else { Write-Host "[windo] --timeout must be 1..900." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $si++
                    continue
                }
                if ($a -like "--timeout=*") { if (-not [int]::TryParse($a.Substring(10), [ref]$timeoutSeconds) -or $timeoutSeconds -lt 1 -or $timeoutSeconds -gt 900) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "troubleshoot"; error = "invalid --timeout value"; exitCode = 2 } } else { Write-Host "[windo] --timeout must be 1..900." -ForegroundColor Yellow }; _windo_set_exit 2; return }; continue }
                if ($a -eq "--credential") {
                    if ($si + 1 -ge $Command.Count) { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "troubleshoot"; error = "--credential requires a value"; exitCode = 2 } } else { Write-Host "[windo] --credential requires a value." -ForegroundColor Yellow }; _windo_set_exit 2; return }
                    $credName = [string]$Command[$si + 1]
                    $si++
                    continue
                }
                if ($a -like "--credential=*") { $credName = $a.Substring(13); continue }
                if ($a -like "--*") { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "troubleshoot"; error = "unknown option '$a'"; exitCode = 2 } } else { Write-Host "[windo] vnc troubleshoot: unknown option $a" -ForegroundColor Yellow }; _windo_set_exit 2; return }
            }
            try { $ports = _windo_parse_ports_raw $portsRaw } catch { if ($JsonOutput) { _emit_json "vnc" @{ subcommand = "troubleshoot"; error = $_.Exception.Message; exitCode = 2 } } else { Write-Host ("[windo] invalid --ports: " + $_.Exception.Message) -ForegroundColor Yellow }; _windo_set_exit 2; return }
            $services = _windo_remote_vnc_services
            $firewall = _windo_firewall_rules_for_patterns @("vnc", "ultravnc", "tightvnc", "realvnc", "winvnc", "x11", "vncserver") @($ports)
            $rows = [System.Collections.ArrayList]@()
            foreach ($p in @($ports)) { $probe = _windo_net_scan_probe_tcp -Host $host -Port $p -TimeoutSeconds $timeoutSeconds; [void]$rows.Add([ordered]@{ port = [int]$p; open = [bool]$probe.open; error = $probe.error }) }
            $cred = if ($credName) { _windo_remote_credential_preview $credName } else { $null }
            if ($JsonOutput) {
                _emit_json "vnc" @{ subcommand = "troubleshoot"; scannedAt = (Get-Date -Format "o"); host = $host; services = @($services); firewall = @{ count = @($firewall).Count; rules = @($firewall) }; timeoutSeconds = $timeoutSeconds; ports = @($rows); credential = $cred; exitCode = 0 }
            } else {
                Write-Host "[windo] vnc troubleshoot" -ForegroundColor Cyan
                Write-Host "  services=$(@($services).Count) firewallRules=$(@($firewall).Count)" -ForegroundColor DarkGray
                foreach ($r in @($rows)) { Write-Host ("  {0}:{1} {2}" -f $host, $r.port, $(if ($r.open) { "open" } else { "closed/filtered" })) -ForegroundColor $(if ($r.open) { "Green" } else { "Yellow" }) }
                if ($credName) { if ($cred -and $cred.exists) { Write-Host ("  credential={0} ({1})" -f $cred.username, $cred.passwordPreview) -ForegroundColor DarkGray } else { Write-Host "  credential not found." -ForegroundColor Yellow } }
            }
            _windo_set_exit 0
            return
        }

        if ($JsonOutput) { _emit_json "vnc" @{ subcommand = $sub; error = "unknown subcommand"; exitCode = 2 } } else { Write-Host "[windo] vnc: expected status|firewall|test|stop|troubleshoot (got: $sub)" -ForegroundColor Yellow }
        _windo_set_exit 2
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "vault") {
        $sub = if ($Command.Count -ge 2) { [string]$Command[1].Trim().ToLowerInvariant() } else { "status" }
        $vaultPath = _windo_vault_path
        $map = _windo_vault_read_map
        if ($sub -eq "status" -or $sub -eq "list" -or $sub -eq "") {
            $names = @($map.Keys | Sort-Object)
            if ($JsonOutput) { _emit_json "vault" @{ vaultPath = $vaultPath; protectedBy = "DPAPI CurrentUser"; count = $names.Count; names = $names; exitCode = 0 } }
            else {
                Write-Host "[windo] vault" -ForegroundColor Cyan
                Write-Host "  Path      : $vaultPath" -ForegroundColor DarkGray
                Write-Host "  Protected : DPAPI CurrentUser" -ForegroundColor DarkGray
                Write-Host "  Entries   : $($names.Count)" -ForegroundColor Yellow
                foreach ($n in $names) { Write-Host "    - $n" -ForegroundColor DarkGray }
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "set") {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "vault" @{ error = "missing secret name"; exitCode = 2 } } else { Write-Host "[windo] vault set <name> [value]" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $name = [string]$Command[2]
            if ($Command.Count -ge 4) {
                $value = ($Command[3..($Command.Count - 1)] -join " ")
            } else {
                $secureValue = Read-Host -Prompt "Secret value for $name" -AsSecureString
                $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
                try { $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            }
            $map[$name] = [ordered]@{ protected = (_dpapi_protect $value); updatedAt = (Get-Date -Format "o") }
            if (-not (_windo_vault_save_map $map)) {
                if ($JsonOutput) { _emit_json "vault" @{ error = "vault write failed"; path = $vaultPath; exitCode = 2 } } else { Write-Host "[windo] vault write failed: $vaultPath" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            if ($JsonOutput) { _emit_json "vault" @{ action = "set"; name = $name; vaultPath = $vaultPath; exitCode = 0 } }
            else { Write-Host "[windo] vault set :: $name" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "get") {
            if ($Command.Count -lt 3 -or -not $map.Contains([string]$Command[2])) {
                if ($JsonOutput) { _emit_json "vault" @{ error = "secret not found"; exitCode = 2 } } else { Write-Host "[windo] vault get: secret not found" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $name = [string]$Command[2]
            $plain = _dpapi_unprotect ([string]$map[$name].protected)
            if ($JsonOutput) { _emit_json "vault" @{ name = $name; value = $plain; warning = "secret value included because get was requested"; exitCode = 0 } }
            else { Write-Host $plain }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "remove") {
            if ($Command.Count -lt 3) { _windo_set_exit 2; return }
            $name = [string]$Command[2]
            $removed = $map.Contains($name)
            if ($removed) { $map.Remove($name) }
            [void](_windo_vault_save_map $map)
            if ($JsonOutput) { _emit_json "vault" @{ action = "remove"; name = $name; removed = $removed; exitCode = 0 } }
            else { Write-Host "[windo] vault remove :: $name removed=$removed" -ForegroundColor $(if ($removed) { "Green" } else { "Yellow" }) }
            _windo_set_exit 0
            return
        }
        if ($JsonOutput) { _emit_json "vault" @{ error = "expected status | list | set | get | remove"; exitCode = 2 } }
        else { Write-Host "[windo] vault: expected status | list | set | get | remove" -ForegroundColor Yellow }
        _windo_set_exit 2
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "sshx") {
        $sub = if ($Command.Count -ge 2) { [string]$Command[1].Trim().ToLowerInvariant() } else { "status" }
        $sshDir = Join-Path $HOME ".ssh"
        if ($sub -eq "status" -or $sub -eq "") {
            $keys = @()
            if (Test-Path -LiteralPath $sshDir) { $keys = @(Get-ChildItem -LiteralPath $sshDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(id_|.+\.pub$)' } | Select-Object Name,FullName,Length) }
            $tools = @((_windo_tool_state "ssh"), (_windo_tool_state "ssh-keygen"), (_windo_tool_state "scp"), (_windo_tool_state "sftp"))
            if ($JsonOutput) { _emit_json "sshx" @{ sshDir = $sshDir; tools = $tools; keys = $keys; configPath = (Join-Path $sshDir "config"); exitCode = 0 } }
            else {
                Write-Host "[windo] sshx" -ForegroundColor Cyan
                foreach ($t in $tools) { Write-Host ("  {0,-10} {1} {2}" -f $t.name, $(if ($t.available) { "OK" } else { "missing" }), $t.path) -ForegroundColor $(if ($t.available) { "Green" } else { "Yellow" }) }
                Write-Host "  Config    : $(Join-Path $sshDir "config")" -ForegroundColor DarkGray
                Write-Host "  Keys      : $($keys.Count)" -ForegroundColor Yellow
            }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "keygen") {
            $name = "id_ed25519_windo"
            $comment = "$env:USERNAME@$env:COMPUTERNAME"
            for ($ki = 2; $ki -lt $Command.Count; $ki++) {
                $ka = [string]$Command[$ki]
                if ($ka -eq "--name" -and ($ki + 1) -lt $Command.Count) { $name = [string]$Command[$ki + 1]; $ki++; continue }
                if ($ka -eq "--comment" -and ($ki + 1) -lt $Command.Count) { $comment = [string]$Command[$ki + 1]; $ki++; continue }
            }
            if (!(Get-Command ssh-keygen -ErrorAction SilentlyContinue)) { Write-Host "[windo] ssh-keygen not found" -ForegroundColor Red; _windo_set_exit 2; return }
            if (!(Test-Path -LiteralPath $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
            $keyPath = Join-Path $sshDir $name
            & ssh-keygen -t ed25519 -a 100 -f $keyPath -C $comment
            $code = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            if ($JsonOutput) { _emit_json "sshx" @{ action = "keygen"; keyPath = $keyPath; publicKeyPath = "$keyPath.pub"; exitCode = $code } }
            else { Write-Host "[windo] ssh keygen exit=$code :: $keyPath" -ForegroundColor $(if ($code -eq 0) { "Green" } else { "Red" }) }
            _windo_set_exit $code
            return
        }
        if ($sub -eq "config") {
            if (!(Test-Path -LiteralPath $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
            $cfg = Join-Path $sshDir "config"
            if (!(Test-Path -LiteralPath $cfg)) { New-Item -ItemType File -Path $cfg -Force | Out-Null }
            if ($JsonOutput) { _emit_json "sshx" @{ action = "config"; path = $cfg; exists = $true; exitCode = 0 } }
            else { Write-Host "[windo] ssh config :: $cfg" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "test") {
            if ($Command.Count -lt 3) { Write-Host "[windo] sshx test <host>" -ForegroundColor Yellow; _windo_set_exit 2; return }
            $target = [string]$Command[2]
            & ssh -T $target
            $code = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            _windo_set_exit $code
            return
        }
        if ($JsonOutput) { _emit_json "sshx" @{ error = "expected status | keygen | config | test"; exitCode = 2 } } else { Write-Host "[windo] sshx: expected status | keygen | config | test" -ForegroundColor Yellow }
        _windo_set_exit 2
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "crypto") {
        $sub = if ($Command.Count -ge 2) { [string]$Command[1].Trim().ToLowerInvariant() } else { "status" }
        if ($sub -eq "status" -or $sub -eq "") {
            $tools = @((_windo_tool_state "openssl"), (_windo_tool_state "certutil"))
            if ($JsonOutput) { _emit_json "crypto" @{ tools = $tools; exitCode = 0 } }
            else { Write-Host "[windo] crypto" -ForegroundColor Cyan; foreach ($t in $tools) { Write-Host ("  {0,-8} {1} {2}" -f $t.name, $(if ($t.available) { "OK" } else { "missing" }), $t.path) -ForegroundColor $(if ($t.available) { "Green" } else { "Yellow" }) } }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "cert") {
            if ($Command.Count -lt 3) { Write-Host "[windo] crypto cert <path>" -ForegroundColor Yellow; _windo_set_exit 2; return }
            $p = [string]$Command[2]
            if (!(Test-Path -LiteralPath $p)) { Write-Host "[windo] crypto cert: missing $p" -ForegroundColor Red; _windo_set_exit 2; return }
            if (Get-Command openssl -ErrorAction SilentlyContinue) { & openssl x509 -in $p -noout -text }
            else { & certutil -dump $p }
            _windo_set_exit $(if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 })
            return
        }
        if ($sub -eq "hash") {
            if ($Command.Count -lt 3) { Write-Host "[windo] crypto hash <path>" -ForegroundColor Yellow; _windo_set_exit 2; return }
            $p = [string]$Command[2]
            if (!(Test-Path -LiteralPath $p)) { Write-Host "[windo] crypto hash: missing $p" -ForegroundColor Red; _windo_set_exit 2; return }
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
            if ($JsonOutput) { _emit_json "crypto" @{ action = "hash"; path = (Resolve-Path -LiteralPath $p).Path; sha256 = $h; exitCode = 0 } } else { Write-Host $h }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "key") {
            if ($Command.Count -lt 3) { Write-Host "[windo] crypto key <path>" -ForegroundColor Yellow; _windo_set_exit 2; return }
            if (!(Get-Command openssl -ErrorAction SilentlyContinue)) { Write-Host "[windo] openssl not found" -ForegroundColor Red; _windo_set_exit 2; return }
            & openssl pkey -in ([string]$Command[2]) -noout -text
            _windo_set_exit $(if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 })
            return
        }
        if ($JsonOutput) { _emit_json "crypto" @{ error = "expected status | cert | key | hash"; exitCode = 2 } } else { Write-Host "[windo] crypto: expected status | cert | key | hash" -ForegroundColor Yellow }
        _windo_set_exit 2
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "venv") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        $venvPath = ".\.venv"
        $pythonExe = "python"
        $force = $false
        $vi = 2
        while ($vi -lt $Command.Count) {
            $va = [string]$Command[$vi]
            if ($va -eq "--force") { $force = $true; $vi++; continue }
            if ($va -eq "--python" -and ($vi + 1) -lt $Command.Count) { $pythonExe = [string]$Command[$vi + 1]; $vi += 2; continue }
            if ($va -like "--python=*") { $pythonExe = $va.Substring(9); $vi++; continue }
            if (-not $va.StartsWith("-")) { $venvPath = $va; $vi++; continue }
            if ($JsonOutput) { _emit_json "venv" @{ error = "unknown option"; option = $va; exitCode = 2 } }
            else { Write-Host "[windo] venv: unknown option $va" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $venvFull = try { [System.IO.Path]::GetFullPath($venvPath) } catch { $venvPath }
        $activate = Join-Path $venvFull "Scripts\Activate.ps1"
        $pythonInVenv = Join-Path $venvFull "Scripts\python.exe"
        $exists = Test-Path -LiteralPath $activate
        if ($sub -eq "status" -or $sub -eq "") {
            $active = (-not [string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV))
            $payload = @{ path = $venvFull; exists = $exists; active = $active; activePath = $(if ($active) { [string]$env:VIRTUAL_ENV } else { $null }); activateScript = $activate; python = $(if (Test-Path -LiteralPath $pythonInVenv) { $pythonInVenv } else { $null }); exitCode = $(if ($exists -or $active) { 0 } else { 3 }) }
            if ($JsonOutput) { _emit_json "venv" $payload }
            else {
                Write-Host "[windo] venv" -ForegroundColor Cyan
                Write-Host "  Path   : $venvFull" -ForegroundColor DarkGray
                Write-Host "  Exists : $exists" -ForegroundColor $(if ($exists) { "Green" } else { "Yellow" })
                Write-Host "  Active : $(if ($active) { $env:VIRTUAL_ENV } else { 'no' })" -ForegroundColor DarkGray
                if (-not $exists) { Write-Host "  Create : windo venv create $venvPath" -ForegroundColor Yellow }
            }
            _windo_set_exit ([int]$payload.exitCode)
            return
        }
        if ($sub -eq "create") {
            if (Test-Path -LiteralPath $venvFull) {
                if ($JsonOutput) { _emit_json "venv" @{ path = $venvFull; exists = $true; error = "path already exists"; exitCode = 2 } }
                else { Write-Host "[windo] venv create: path already exists: $venvFull" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            & $pythonExe -m venv $venvFull
            $code = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            $ok = ($code -eq 0 -and (Test-Path -LiteralPath $activate))
            if ($JsonOutput) { _emit_json "venv" @{ action = "create"; path = $venvFull; python = $pythonExe; ok = $ok; exitCode = $(if ($ok) { 0 } else { $code }) } }
            else {
                if ($ok) { Write-Host "[windo] venv created :: $venvFull" -ForegroundColor Green; Write-Host "  Activate: windo venv activate $venvPath" -ForegroundColor DarkGray }
                else { Write-Host "[windo] venv create failed (exit $code)" -ForegroundColor Red }
            }
            _windo_set_exit $(if ($ok) { 0 } else { $code })
            return
        }
        if ($sub -eq "activate") {
            if (!(Test-Path -LiteralPath $activate)) {
                if ($JsonOutput) { _emit_json "venv" @{ action = "activate"; path = $venvFull; error = "Activate.ps1 not found"; exitCode = 2 } }
                else { Write-Host "[windo] venv activate: missing $activate" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            . $activate
            if ($JsonOutput) { _emit_json "venv" @{ action = "activate"; path = $venvFull; activePath = [string]$env:VIRTUAL_ENV; exitCode = 0 } }
            else { Write-Host "[windo] venv active :: $env:VIRTUAL_ENV" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($sub -eq "deactivate") {
            if (Get-Command deactivate -ErrorAction SilentlyContinue) {
                deactivate
                if ($JsonOutput) { _emit_json "venv" @{ action = "deactivate"; exitCode = 0 } }
                else { Write-Host "[windo] venv deactivated" -ForegroundColor Green }
                _windo_set_exit 0
                return
            }
            if ($JsonOutput) { _emit_json "venv" @{ action = "deactivate"; error = "no active deactivate function"; exitCode = 3 } }
            else { Write-Host "[windo] no active Python venv found in this shell" -ForegroundColor Yellow }
            _windo_set_exit 3
            return
        }
        if ($sub -eq "remove") {
            if (-not $force) {
                if ($JsonOutput) { _emit_json "venv" @{ action = "remove"; path = $venvFull; error = "requires --force"; exitCode = 2 } }
                else { Write-Host "[windo] venv remove requires --force: $venvFull" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            if (Test-Path -LiteralPath $venvFull) { Remove-Item -LiteralPath $venvFull -Recurse -Force }
            if ($JsonOutput) { _emit_json "venv" @{ action = "remove"; path = $venvFull; removed = $true; exitCode = 0 } }
            else { Write-Host "[windo] venv removed :: $venvFull" -ForegroundColor Green }
            _windo_set_exit 0
            return
        }
        if ($JsonOutput) { _emit_json "venv" @{ error = "expected status | create | activate | deactivate | remove"; exitCode = 2 } }
        else { Write-Host "[windo] venv: expected status | create | activate | deactivate | remove" -ForegroundColor Yellow }
        _windo_set_exit 2
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "pkg") {
        $manager = if ($Command.Count -ge 2) { [string]$Command[1].Trim().ToLowerInvariant() } else { "status" }
        if ($manager -eq "status" -or $manager -eq "") {
            $rows = @("winget", "choco", "scoop") | ForEach-Object {
                $c = Get-Command $_ -ErrorAction SilentlyContinue
                [pscustomobject]@{ id = $_; available = [bool]$c; path = $(if ($c) { [string]$c.Source } else { $null }) }
            }
            if ($JsonOutput) { _emit_json "pkg" @{ managers = @($rows); exitCode = 0 } }
            else {
                Write-Host "[windo] package managers" -ForegroundColor Cyan
                foreach ($r in $rows) { Write-Host ("  {0,-6} {1} {2}" -f $r.id, $(if ($r.available) { "OK" } else { "missing" }), $r.path) -ForegroundColor $(if ($r.available) { "Green" } else { "Yellow" }) }
            }
            _windo_set_exit 0
            return
        }
        if ($manager -notin @("winget", "choco", "scoop")) {
            if ($JsonOutput) { _emit_json "pkg" @{ error = "expected winget | choco | scoop | status"; manager = $manager; exitCode = 2 } }
            else { Write-Host "[windo] pkg: expected winget | choco | scoop | status" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $pkgArgs = if ($Command.Count -gt 2) { @($Command[2..($Command.Count - 1)]) } else { @() }
        if ($pkgArgs.Count -eq 0) {
            if ($JsonOutput) { _emit_json "pkg" @{ error = "missing package-manager arguments"; manager = $manager; exitCode = 2 } }
            else { Write-Host "[windo] pkg ${manager}: missing arguments" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $cmd = Get-Command $manager -ErrorAction SilentlyContinue
        if (-not $cmd) {
            if ($JsonOutput) { _emit_json "pkg" @{ error = "package manager not found"; manager = $manager; exitCode = 2 } }
            else { Write-Host "[windo] pkg: $manager was not found in PATH" -ForegroundColor Red }
            _windo_set_exit 2
            return
        }
        if ($manager -eq "scoop") {
            Write-Host "[windo] pkg scoop: scoop is normally user-scoped; elevated context may differ from your normal shell." -ForegroundColor Yellow
        } elseif ($manager -eq "winget") {
            Write-Host "[windo] pkg winget: routing through elevated runner for clearer machine-install behavior." -ForegroundColor DarkGray
        } else {
            Write-Host "[windo] pkg choco: routing through elevated runner; use package-manager flags like -y when you want unattended installs." -ForegroundColor DarkGray
        }
        $managerPath = if ($cmd.CommandType -eq "Application") { [string]$cmd.Source } else { $manager }
        $Command = @($managerPath) + @($pkgArgs)
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "container") {
        $sub = $null
        $runtimePreference = "auto"
        $runtimeArgs = [System.Collections.ArrayList]@()
        $i = 1
        while ($i -lt $Command.Count) {
            $current = [string]$Command[$i]
            if ($current -eq '--runtime') {
                if (($i + 1) -ge $Command.Count) {
                    if ($JsonOutput) { _emit_json "container" @{ error = "--runtime requires a value (docker|podman|auto)"; exitCode = 2 } }
                    else { Write-Host "[windo] container: --runtime requires a value (docker|podman|auto)" -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
                $runtimePreference = [string]$Command[$i + 1]
                $i += 2
                continue
            }
            if ($current -like '--runtime=*') {
                $runtimePreference = $current.Substring(10)
                $i++
                continue
            }
            if (($current -eq '--') -or ($i -eq 1 -and [string]::IsNullOrWhiteSpace($current))) {
                $i++
                break
            }
            if (($current -like '--*') -and ($null -eq $sub)) {
                if ($JsonOutput) { _emit_json "container" @{ error = "unknown container option: $current"; exitCode = 2 } }
                else { Write-Host "[windo] container: unknown option before subcommand: $current" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            if ($null -eq $sub) {
                $sub = [string]$current.ToLowerInvariant()
            } else {
                [void]$runtimeArgs.Add($current)
            }
            $i++
        }
        while ($i -lt $Command.Count) {
            [void]$runtimeArgs.Add([string]$Command[$i])
            $i++
        }
        if ($null -eq $sub) { $sub = "ps" }

        $known = @("ps", "images", "status", "logs", "restart", "start", "stop", "rmi", "rm", "pull")
        if ($known -notcontains $sub) {
            if ($JsonOutput) { _emit_json "container" @{ error = "unknown container subcommand"; subcommand = $sub; exitCode = 2 } }
            else { Write-Host "[windo] container: expected ps, images, status, logs, restart, start, stop, rmi, rm, pull" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }

        $runtimeId = [string]$runtimePreference.ToLowerInvariant().Trim()
        if ($runtimeId -notin @("auto", "docker", "podman")) {
            if ($JsonOutput) { _emit_json "container" @{ error = "invalid --runtime value"; runtime = $runtimePreference; exitCode = 2 } }
            else { Write-Host "[windo] container: --runtime supports docker, podman, or auto" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }

        $runtimeCmd = $null
        if ($runtimeId -eq "docker") {
            $runtimeFound = Get-Command docker -ErrorAction SilentlyContinue
            if ($runtimeFound) { $runtimeCmd = [string]$runtimeFound.Source; $runtimeUsed = "docker" } else {
                if ($JsonOutput) { _emit_json "container" @{ error = "runtime not found: docker"; exitCode = 2 } }
                else { Write-Host "[windo] container: docker binary was not found in PATH" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
        } elseif ($runtimeId -eq "podman") {
            $runtimeFound = Get-Command podman -ErrorAction SilentlyContinue
            if ($runtimeFound) { $runtimeCmd = [string]$runtimeFound.Source; $runtimeUsed = "podman" } else {
                if ($JsonOutput) { _emit_json "container" @{ error = "runtime not found: podman"; exitCode = 2 } }
                else { Write-Host "[windo] container: podman binary was not found in PATH" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
        } else {
            $podmanFound = Get-Command podman -ErrorAction SilentlyContinue
            $dockerFound = Get-Command docker -ErrorAction SilentlyContinue
            if ($dockerFound) { $runtimeUsed = "docker"; $runtimeCmd = [string]$dockerFound.Source }
            elseif ($podmanFound) { $runtimeUsed = "podman"; $runtimeCmd = [string]$podmanFound.Source }
            else {
                if ($JsonOutput) { _emit_json "container" @{ error = "runtime not found: docker or podman"; exitCode = 2 } }
                else { Write-Host "[windo] container: no docker or podman found in PATH" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
        }

        if ($sub -eq "status") { $runtimeSub = "info" } else { $runtimeSub = $sub }
        if (($sub -in @("logs", "restart", "start", "stop", "rmi", "rm", "pull")) -and $runtimeArgs.Count -eq 0) {
            $hint = "container id or image name argument required"
            if ($JsonOutput) { _emit_json "container" @{ subcommand = $sub; runtime = $runtimeUsed; command = @($runtimeSub); error = $hint; exitCode = 2 } } else { Write-Host "[windo] container $sub requires an identifier argument." -ForegroundColor Yellow; Write-Host "  Example: windo container $sub <id-or-name>" -ForegroundColor DarkGray }
            _windo_set_exit 2
            return
        }

        $runtimeArgList = @($runtimeSub) + @($runtimeArgs)
        $renderCommand = @($runtimeUsed, @($runtimeArgList) -join ' ') -join ' '
        if ($DryRun) {
            if ($JsonOutput) {
                _emit_json "container" @{
                    runtime = $runtimeUsed
                    subcommand = $sub
                    runtimeCommand = $runtimeArgList
                    dryRun = $true
                    commandLine = $renderCommand
                    exitCode = 0
                }
            } else {
                Write-Host "[windo] DRY-RUN container command (no execution)" -ForegroundColor Yellow
                Write-Host "  Runtime : $runtimeUsed"
                Write-Host "  Command : $renderCommand"
                Write-Host "  Full cmd: $runtimeCmd " + [string]::Join(" ", @($runtimeArgList | ForEach-Object { _windo_quote_argument $_ }))
            }
            _windo_set_exit 0
            return
        }

        try {
            $output = @(& $runtimeCmd @runtimeArgList 2>&1 | ForEach-Object { if ($null -ne $_) { [string]$_ } })
            $exitCode = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
            if ($exitCode -eq 0) {
                if ($JsonOutput) { _emit_json "container" @{ runtime = $runtimeUsed; subcommand = $sub; command = $runtimeArgList; exitCode = $exitCode; output = $output } }
                else { if ($output.Count -gt 0) { Write-Host ($output -join "`r`n") } }
            } else {
                if ($JsonOutput) { _emit_json "container" @{ runtime = $runtimeUsed; subcommand = $sub; command = $runtimeArgList; error = "command failed"; exitCode = $exitCode; output = $output } }
                else { Write-Host "[windo] container $sub failed with exit code $exitCode" -ForegroundColor Red; if ($output.Count -gt 0) { Write-Host ($output -join "`r`n") -ForegroundColor Yellow } }
            }
            _windo_set_exit $exitCode
            return
        } catch {
            if ($JsonOutput) { _emit_json "container" @{ runtime = $runtimeUsed; subcommand = $sub; command = $runtimeArgList; error = $_.Exception.Message; exitCode = 1 } }
            else { Write-Host "[windo] container: failed to execute $runtimeUsed" -ForegroundColor Red; Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray }
            _windo_set_exit 1
            return
        }
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "wsl") {
        function _windo_wsl_exec {
            param([string[]]$Args)
            $r = [ordered]@{
                args     = @("wsl") + @($Args)
                exitCode = 0
                output   = @()
            }
            try {
                $raw = @(& wsl.exe @Args 2>&1 | ForEach-Object { [string]$_ })
                $r.output = @($raw)
                if ($LASTEXITCODE -is [int]) { $r.exitCode = [int]$LASTEXITCODE }
                return [pscustomobject]$r
            } catch {
                return [pscustomobject]@{
                    args     = @("wsl") + @($Args)
                    exitCode = 1
                    output   = @([string]$_.Exception.Message)
                }
            }
        }

        function _windo_wsl_distros {
            $status = _windo_wsl_exec @("--list","--verbose")
            if ($status.exitCode -ne 0) {
                return @{
                    found       = $false
                    exitCode    = [int]$status.exitCode
                    error       = if ($status.output.Count -gt 0) { [string]($status.output -join " ") } else { "wsl list failed" }
                    distros     = @()
                    defaultName = $null
                }
            }
            $distros = [System.Collections.ArrayList]@()
            $header = $false
            $defaultName = $null
            foreach ($line in @($status.output)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -match '^\s*NAME\s+STATE\s+VERSION') { $header = $true; continue }
                if (-not $header) {
                    if ($line -match '(?i)^Windows Subsystem for Linux has no installed distributions') {
                        break
                    }
                    continue
                }
                $trim = [string]$line.Trim()
                if ($trim -notmatch '^(?<name>.+?)\s+(?<state>[A-Za-z]+)\s+(?<version>\d+)\s*$') { continue }
                $rawName  = $Matches['name']
                $state    = [string]$Matches['state']
                $version  = [int][string]$Matches['version']
                $isDefault = $rawName.TrimStart().StartsWith("*")
                $name = $rawName.Trim().TrimStart("*").Trim()
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if ($isDefault) { $defaultName = $name }
                [void]$distros.Add([pscustomobject]@{ name = $name; state = $state; version = $version; default = [bool]$isDefault })
            }
            return @{ found = $true; exitCode = 0; error = $null; distros = @($distros); defaultName = $defaultName }
        }

        function _windo_wsl_find_distro {
            param([string]$Name)
            $rows = _windo_wsl_distros
            if (-not $rows.found) { return $rows }
            $row = @($rows.distros | Where-Object { $_.name -ieq $Name })[0]
            if ($null -eq $row) {
                return @{ found = $false; error = "distro '$Name' was not found"; exitCode = 2; distros = @($rows.distros); defaultName = $rows.defaultName }
            }
            return @{ found = $true; distro = $row; exitCode = 0; distros = @($rows.distros); defaultName = $rows.defaultName }
        }

        function _windo_parse_kv {
            param([string[]]$Tokens, [int]$Start = 0)
            $result = @{}
            $i = $Start
            while ($i -lt $Tokens.Count) {
                $current = [string]$Tokens[$i]
                if ($current -eq '--') { break }
                if ($current -like '--*=*') {
                    $idx = $current.IndexOf('=')
                    $k = $current.Substring(2, $idx - 2).ToLowerInvariant()
                    $v = $current.Substring($idx + 1)
                    $result[$k] = $v
                    $i++
                    continue
                }
                if ($current -like '--*') {
                    $key = $current.ToLowerInvariant()
                    if ($key -eq '--distro' -or $key -eq '--distribution' -or $key -eq '--name' -or $key -eq '--tar' -or $key -eq '--path' -or $key -eq '--out' -or $key -eq '--output' -or $key -eq '--user' -or $key -eq '--version' -or $key -eq '--to' -or $key -eq '--command') {
                        if (($i + 1) -ge $Tokens.Count) { return @{ error = "$key requires a value"; exitCode = 2 } }
                        $result[$key.TrimStart('-')] = [string]$Tokens[$i + 1]
                        $i += 2
                        continue
                    }
                    if ($key -eq '--apply' -or $key -eq '--dry-run' -or $key -eq '--overwrite' -or $key -eq '--json') {
                        $result[$key.TrimStart('-')] = $true
                        $i++
                        continue
                    }
                    if (-not $result.ContainsKey('_args')) { $result._args = @() }
                    [void]$result._args.Add($key)
                    $i++
                    continue
                }
                if (-not $result.ContainsKey('_args')) { $result._args = @() }
                [void]$result._args.Add($current)
                $i++
            }
            return $result
        }

        function _windo_wsl_confirm {
            param([string]$Message, [string]$CommandLine, [switch]$AutoApprove)
            if ($AutoApprove -or $NonInteractive -or -not [Environment]::UserInteractive) {
                return $true
            }
            Write-Host "[windo] $Message" -ForegroundColor Yellow
            $prompt = "Proceed with: $CommandLine [y/N]"
            if (-not $prompt.Contains('[y/N]')) { $prompt += " [y/N]" }
            $ans = Read-Host $prompt
            return ($ans -eq 'y' -or $ans -eq 'Y' -or $ans -eq 'yes')
        }

        $wslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wslExe) {
            if ($JsonOutput) { _emit_json "wsl" @{ error = "wsl.exe is not available"; exitCode = 2 } }
            else { Write-Host "[windo] wsl.exe was not found in PATH." -ForegroundColor Red }
            _windo_set_exit 2
            return
        }

        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].ToLowerInvariant() }
        $argMap = @{ }
        if ($Command.Count -gt 2) { $argMap = _windo_parse_kv -Tokens $Command -Start 2 }
        if ($argMap.ContainsKey('error')) {
            if ($JsonOutput) { _emit_json "wsl" @{ error = $argMap.error; exitCode = [int]$argMap.exitCode } }
            else { Write-Host "[windo] wsl: $($argMap.error)" -ForegroundColor Yellow }
            _windo_set_exit [int]$argMap.exitCode
            return
        }

        if ($sub -eq "status" -or $sub -eq "list" -or $sub -eq "ls") {
            $status = _windo_wsl_exec @("--status")
            $distros = _windo_wsl_distros
            if ($JsonOutput) {
                _emit_json "wsl" @{
                    command      = "status"
                    wslAvailable = [bool]$wslExe
                    wslStatus    = @($status.output)
                    wslExitCode  = [int]$status.exitCode
                    distros      = @($distros.distros)
                    default      = $distros.defaultName
                    exitCode     = [int]$(if ($status.exitCode -ne 0 -or -not $distros.found) { 2 } else { 0 })
                }
                _windo_set_exit $(if ($status.exitCode -ne 0 -or -not $distros.found) { 2 } else { 0 })
                return
            }
            Write-Host "[windo] WSL availability" -ForegroundColor Cyan
            if ($status.exitCode -ne 0) {
                Write-Host "  wsl --status failed. Exit=$($status.exitCode)" -ForegroundColor Red
                foreach ($l in @($status.output)) { Write-Host "  $l" -ForegroundColor DarkGray }
                _windo_set_exit 2
                return
            }
            foreach ($l in @($status.output)) { Write-Host "  $l" -ForegroundColor DarkGray }
            if ($distros.found) {
                Write-Host "  Distros:" -ForegroundColor Cyan
                if ($distros.distros.Count -eq 0) { Write-Host "    none" -ForegroundColor Yellow }
                foreach ($d in @($distros.distros)) {
                    Write-Host ("  {0,-22} {1,-8} v{2}{3}" -f $d.name, $d.state, $d.version, $(if ($d.default) { " *" } else { "" })) -ForegroundColor $(if ($d.state -eq "Running") { "Green" } else { "DarkGray" })
                }
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "check") {
            $check = "install"
            if ($argMap.ContainsKey('_args') -and $argMap._args.Count -gt 0) { $check = [string]$argMap._args[0].ToLowerInvariant() }
            $ok = $true
            $notes = [System.Collections.ArrayList]@()
            if ($check -in @("install", "inst", "")) {
                $status = _windo_wsl_exec @("--status")
                if ($status.exitCode -ne 0) {
                    $ok = $false
                    [void]$notes.Add("wsl --status returned $($status.exitCode)")
                } else {
                    [void]$notes.Add("wsl command is executable")
                }
                $d = _windo_wsl_distros
                $payload = @{
                    command   = "check install"
                    ok        = [bool]$ok
                    wslStatus = @($status.output)
                    distros   = @($d.distros)
                    default   = $d.defaultName
                    exitCode  = $(if ($ok) { 0 } else { 2 })
                    notes     = @($notes)
                }
                if ($JsonOutput) { _emit_json "wsl" $payload; _windo_set_exit $payload.exitCode; return }
                if (-not $ok) { Write-Host "[windo] WSL install check failed: $($notes[0])" -ForegroundColor Red; _windo_set_exit 2; return }
                Write-Host "[windo] WSL install check passed." -ForegroundColor Green
                _windo_set_exit 0
                return
            }
            if ($check -eq "distro") {
                $name = if ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } elseif ($argMap.ContainsKey('name')) { [string]$argMap['name'] } elseif ($argMap.ContainsKey('_args') -and $argMap._args.Count -gt 1) { [string]$argMap._args[1] } else { $null }
                if ([string]::IsNullOrWhiteSpace($name)) {
                    if ($JsonOutput) { _emit_json "wsl" @{ command = "check distro"; error = "missing distro name"; exitCode = 2 } } else { Write-Host "[windo] wsl check distro requires --distro <name>" -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
                $found = _windo_wsl_find_distro $name
                if (-not $found.found -or -not $found.distro) { if ($JsonOutput) { _emit_json "wsl" @{ command = "check distro"; distro = $name; exists = $false; exitCode = 2 } } else { Write-Host "[windo] Distro not found: $name" -ForegroundColor Yellow }; _windo_set_exit 2; return }
                if ($JsonOutput) { _emit_json "wsl" @{ command = "check distro"; distro = $found.distro; exists = $true; exitCode = 0 } }
                else { Write-Host "[windo] Distro '$name' is present. State=$($found.distro.state), Version=$($found.distro.version), Default=$($found.distro.default)" -ForegroundColor Green }
                _windo_set_exit 0
                return
            }
            if ($check -eq "import") {
                $name = if ($argMap.ContainsKey('name')) { [string]$argMap['name'] } elseif ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } else { $null }
                $tar  = if ($argMap.ContainsKey('tar')) { [string]$argMap['tar'] } else { $null }
                $path = if ($argMap.ContainsKey('path')) { [string]$argMap['path'] } else { $null }
                $ver  = if ($argMap.ContainsKey('version')) { [string]$argMap['version'] } else { "2" }
                $errors = [System.Collections.ArrayList]@()
                if ([string]::IsNullOrWhiteSpace($name))  { [void]$errors.Add("missing --name") }
                if ([string]::IsNullOrWhiteSpace($tar))   { [void]$errors.Add("missing --tar") }
                if ([string]::IsNullOrWhiteSpace($path))  { [void]$errors.Add("missing --path") }
                if (-not ($ver -in @("1","2")))           { [void]$errors.Add("version must be 1 or 2") }
                if ($tar -and !(Test-Path -LiteralPath $tar)) { [void]$errors.Add("tar file not found: $tar") }
                if ($path -and !(Test-Path -LiteralPath $path)) { [void]$errors.Add("install location not found: $path") }
                $importWillCreate = $false
                if ($name -and ($null -eq $errors)) {
                    $d = _windo_wsl_find_distro $name
                    if ($d.found -and $d.distro) { [void]$errors.Add("distribution '$name' already exists; choose --distro-new or remove first") }
                    else { $importWillCreate = $true }
                }
                if ($errors.Count -gt 0) {
                    if ($JsonOutput) { _emit_json "wsl" @{ command = "check import"; errors = @($errors); exitCode = 2 } }
                    else { Write-Host "[windo] import check failed: $($errors -join '; ')" -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
                if ($JsonOutput) { _emit_json "wsl" @{ command = "check import"; distribution = $name; tar = $tar; path = $path; version = $ver; safeToApply = [bool]$importWillCreate; applyRequired = $true; exitCode = 0 } }
                else { Write-Host "[windo] import check passed: would import '$name' from '$tar' into '$path' as WSL $ver." -ForegroundColor Green; Write-Host "  This is a dry-preflight check. Add --apply to run." -ForegroundColor DarkGray }
                _windo_set_exit 0
                return
            }
            if ($check -eq "export") {
                $name = if ($argMap.ContainsKey('name')) { [string]$argMap['name'] } elseif ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } else { $null }
                $out  = if ($argMap.ContainsKey('out')) { [string]$argMap['out'] } elseif ($argMap.ContainsKey('output')) { [string]$argMap['output'] } else { $null }
                if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($out)) {
                    if ($JsonOutput) { _emit_json "wsl" @{ command = "check export"; error = "missing --name or --out"; exitCode = 2 } }
                    else { Write-Host "[windo] wsl check export requires --name <distro> and --out <path>" -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
                $d = _windo_wsl_find_distro $name
                if (-not $d.found -or -not $d.distro) {
                    if ($JsonOutput) { _emit_json "wsl" @{ command = "check export"; distribution = $name; exists = $false; exitCode = 2 } } else { Write-Host "[windo] Distro not found: $name" -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
                $parent = Split-Path $out -Parent
                if ([string]::IsNullOrWhiteSpace($parent)) { $parent = "." }
                if (-not (Test-Path -LiteralPath $parent)) { if ($JsonOutput) { _emit_json "wsl" @{ command = "check export"; error = "output directory not found: $parent"; exitCode = 2 } } else { Write-Host "[windo] Output directory not found: $parent" -ForegroundColor Yellow }; _windo_set_exit 2; return }
                if ((Test-Path -LiteralPath $out) -and -not $argMap.ContainsKey('overwrite')) {
                    if ($JsonOutput) { _emit_json "wsl" @{ command = "check export"; distribution = $name; out = $out; exists = $true; error = "output file exists; use --overwrite"; exitCode = 2 } } else { Write-Host "[windo] Output already exists: $out. Add --overwrite" -ForegroundColor Yellow }; _windo_set_exit 2; return
                }
                if ($JsonOutput) { _emit_json "wsl" @{ command = "check export"; distribution = $name; out = $out; exists = $true; safeToApply = $true; applyRequired = $true; exitCode = 0 } } else { Write-Host "[windo] export check passed: would export '$name' -> '$out'." -ForegroundColor Green; Write-Host "  This is a dry-preflight check. Add --apply to run." -ForegroundColor DarkGray }
                _windo_set_exit 0
                return
            }
            if ($JsonOutput) { _emit_json "wsl" @{ command = "check"; error = "unknown check target"; exitCode = 2 } } else { Write-Host "[windo] Unknown check target '$check'. Expected install|distro|import|export." -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }

        if ($sub -eq "version") {
            $res = _windo_wsl_exec @("--version")
            $lines = @($res.output)
            if ($JsonOutput) {
                _emit_json "wsl" @{
                    command = "version"
                    output = $lines
                    exitCode = [int]$res.exitCode
                }
            } else {
                Write-Host "[windo] wsl --version" -ForegroundColor Cyan
                foreach ($l in $lines) { Write-Host "  $l" -ForegroundColor DarkGray }
            }
            _windo_set_exit [int]$res.exitCode
            return
        }

        if ($sub -eq "install") {
            $distro = if ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } elseif ($argMap.ContainsKey('distribution')) { [string]$argMap['distribution'] } elseif ($argMap.ContainsKey('_args') -and $argMap._args.Count -gt 0) { [string]$argMap._args[0] } else { $null }
            if ([string]::IsNullOrWhiteSpace($distro)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "install"; error = "missing --distro"; exitCode = 2 } } else { Write-Host "[windo] wsl install requires --distro <name>" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $apply = $argMap.ContainsKey('apply')
            if (-not $apply -and -not $DryRun) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "install"; error = "install requires --apply to execute"; exitCode = 2 } } else { Write-Host "[windo] install is dry-preview by default. Add --apply to execute." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $args = @('--install', '--distribution', $distro)
            $commandLine = "wsl " + ($args -join " ")
            if ($DryRun -and -not $argMap.ContainsKey('dry-run')) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "install"; distribution = $distro; dryRun = $true; commandLine = $commandLine; exitCode = 0 } } else { Write-Host "[windo] DRY-RUN install: $commandLine" -ForegroundColor Yellow }
                _windo_set_exit 0
                return
            }
            if (-not (_windo_wsl_confirm -Message "Run wsl install" -CommandLine $commandLine -AutoApprove:$apply)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "install"; distribution = $distro; cancelled = $true; exitCode = 0 } } else { Write-Host "[windo] install cancelled." -ForegroundColor DarkGray }
                _windo_set_exit 0
                return
            }
            $res = _windo_wsl_exec @($args)
            if ($JsonOutput) { _emit_json "wsl" @{ command = "install"; distribution = $distro; apply = $true; commandLine = $commandLine; output = @($res.output); exitCode = [int]$res.exitCode } } else { if ($res.exitCode -eq 0) { Write-Host "[windo] Install requested for '$distro'." -ForegroundColor Green } else { Write-Host "[windo] install failed: $($res.output -join ""`r`n"")" -ForegroundColor Red } }
            _windo_set_exit [int]$res.exitCode
            return
        }

        if ($sub -eq "convert") {
            $distro = if ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } elseif ($argMap.ContainsKey('distribution')) { [string]$argMap['distribution'] } else { $null }
            $to = if ($argMap.ContainsKey('to')) { [string]$argMap['to'] } elseif ($argMap.ContainsKey('version')) { [string]$argMap['version'] } else { $null }
            if ([string]::IsNullOrWhiteSpace($distro) -or [string]::IsNullOrWhiteSpace($to)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "convert"; error = "missing --distro and --to"; exitCode = 2 } } else { Write-Host "[windo] wsl convert requires --distro <name> --to 1|2" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            if ($to -notin @("1","2")) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "convert"; error = "to must be 1 or 2"; exitCode = 2 } } else { Write-Host "[windo] --to must be 1 or 2" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $apply = $argMap.ContainsKey('apply')
            if (-not $apply -and -not $DryRun) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "convert"; error = "convert requires --apply to execute"; exitCode = 2 } } else { Write-Host "[windo] convert is dry-preview by default. Add --apply to execute." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $args = @('--set-version', $distro, $to)
            $commandLine = "wsl " + ($args -join " ")
            if ($DryRun -and -not $argMap.ContainsKey('dry-run')) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "convert"; distribution = $distro; to = $to; dryRun = $true; commandLine = $commandLine; exitCode = 0 } } else { Write-Host "[windo] DRY-RUN convert: $commandLine" -ForegroundColor Yellow }
                _windo_set_exit 0
                return
            }
            if (-not (_windo_wsl_confirm -Message "Run wsl convert" -CommandLine $commandLine -AutoApprove:$apply)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "convert"; distribution = $distro; to = $to; cancelled = $true; exitCode = 0 } } else { Write-Host "[windo] convert cancelled." -ForegroundColor DarkGray }
                _windo_set_exit 0
                return
            }
            $res = _windo_wsl_exec @($args)
            if ($JsonOutput) { _emit_json "wsl" @{ command = "convert"; distribution = $distro; to = $to; apply = $true; commandLine = $commandLine; output = @($res.output); exitCode = [int]$res.exitCode } } else { if ($res.exitCode -eq 0) { Write-Host "[windo] Converted '$distro' to version $to." -ForegroundColor Green } else { Write-Host "[windo] convert failed: $($res.output -join ""`r`n"")" -ForegroundColor Red } }
            _windo_set_exit [int]$res.exitCode
            return
        }

        if ($sub -eq "inspect") {
            $distro = if ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } elseif ($argMap.ContainsKey('_args') -and $argMap._args.Count -gt 0) { [string]$argMap._args[0] } else { $null }
            if ([string]::IsNullOrWhiteSpace($distro)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "inspect"; error = "missing --distro"; exitCode = 2 } } else { Write-Host "[windo] wsl inspect requires --distro <name>" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $d = _windo_wsl_find_distro $distro
            if (-not $d.found -or -not $d.distro) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "inspect"; distro = $distro; exists = $false; exitCode = 2 } } else { Write-Host "[windo] Unknown distro: $distro" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $uname = _windo_wsl_exec @('-d', $distro, '--exec', 'uname', '-a')
            $os   = _windo_wsl_exec @('-d', $distro, '--exec', 'cat', '/etc/os-release')
            $ip   = _windo_wsl_exec @('-d', $distro, '--exec', 'hostname', '-I')
            $payload = @{
                command = "inspect"
                distribution = [ordered]@{
                    name = $distro
                    state = [string]$d.distro.state
                    default = [bool]$d.distro.default
                    version = [string]$d.distro.version
                    kernel = if ($uname.exitCode -eq 0) { [string]($uname.output -join " ") } else { "" }
                    ip = if ($ip.exitCode -eq 0) { [string]($ip.output -join " ").Trim() } else { "" }
                }
                osRelease = if ($os.exitCode -eq 0) { @($os.output) } else { @() }
                exitCode = 0
            }
            if ($uname.exitCode -ne 0 -or $os.exitCode -ne 0 -or $ip.exitCode -ne 0) { $payload.exitCode = 2 }
            if ($uname.exitCode -ne 0) { $payload['unameExitCode'] = [int]$uname.exitCode }
            if ($os.exitCode -ne 0) { $payload['osReleaseExitCode'] = [int]$os.exitCode }
            if ($ip.exitCode -ne 0) { $payload['ipExitCode'] = [int]$ip.exitCode }
            if ($JsonOutput) { _emit_json "wsl" $payload; _windo_set_exit [int]$payload.exitCode; return }
            Write-Host "[windo] Inspect '$distro':" -ForegroundColor Cyan
            Write-Host ("  state: {0}" -f $payload.distribution.state) -ForegroundColor DarkGray
            if ($payload.distribution.kernel) { Write-Host ("  kernel: {0}" -f $payload.distribution.kernel) -ForegroundColor DarkGray }
            if ($payload.distribution.ip) { Write-Host ("  ip: {0}" -f $payload.distribution.ip) -ForegroundColor DarkGray }
            if ($payload.osRelease.Count -gt 0) {
                Write-Host "  os-release:" -ForegroundColor DarkGray
                foreach ($line in @($payload.osRelease)) { Write-Host ("    {0}" -f $line) -ForegroundColor DarkGray }
            }
            _windo_set_exit [int]$payload.exitCode
            return
        }

        if ($sub -eq "exec") {
            $distro = if ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } elseif ($argMap.ContainsKey('distribution')) { [string]$argMap['distribution'] } else { $null }
            if (-not $distro) {
                if ($argMap.ContainsKey('_args') -and $argMap._args.Count -gt 0 -and $argMap._args[0] -notlike '--') {
                    $distro = [string]$argMap._args[0]
                }
            }
            $runIdx = $Command.IndexOf('--')
            if ($runIdx -lt 0 -or $runIdx -ge ($Command.Count - 1)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "exec"; error = "wsl exec requires -- and command args"; exitCode = 2 } } else { Write-Host "[windo] wsl exec requires: -- d command..." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $payload = if ($distro) { @('-d', $distro) } else { @() }
            $cmdArgs = $Command[($runIdx + 1)..($Command.Count - 1)]
            $payload += @('--exec') + $cmdArgs
            $res = _windo_wsl_exec @($payload)
            if ($JsonOutput) { _emit_json "wsl" @{ command = "exec"; distro = $distro; command = @($cmdArgs); output = @($res.output); exitCode = [int]$res.exitCode } } else { if ($res.output.Count -gt 0) { Write-Host ($res.output -join "`r`n") } }
            if ($res.exitCode -ne 0 -and -not $JsonOutput) { Write-Host "[windo] exec failed." -ForegroundColor Red }
            _windo_set_exit [int]$res.exitCode
            return
        }

        if ($sub -eq "launch") {
            $distro = if ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } elseif ($argMap.ContainsKey('_args') -and $argMap._args.Count -gt 0) { [string]$argMap._args[0] } else { $null }
            if ([string]::IsNullOrWhiteSpace($distro)) {
                $d = _windo_wsl_distros
                if (-not $d.found -and $d.defaultName) { $distro = $d.defaultName }
            }
            if ([string]::IsNullOrWhiteSpace($distro)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "launch"; error = "missing distro name"; exitCode = 2 } } else { Write-Host "[windo] wsl launch requires <distro> or --distro" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $present = _windo_wsl_find_distro $distro
            if (-not $present.found -or -not $present.distro) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "launch"; distro = $distro; error = "distro not found"; exitCode = 2 } } else { Write-Host "[windo] Unknown distro: $distro" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $user = if ($argMap.ContainsKey('user')) { [string]$argMap['user'] } else { $null }
            $commandText = if ($argMap.ContainsKey('command')) { [string]$argMap['command'] } else { $null }
            if (-not $commandText -and $argMap.ContainsKey('_args') -and $argMap._args.Count -gt 1) {
                $commandText = [string]($argMap._args[1..($argMap._args.Count - 1)] -join " ")
            }
            $runArgs = @('-d', $distro)
            if ($user) { [void]$runArgs.Add("--user"); [void]$runArgs.Add($user) }
            if ($commandText) { [void]$runArgs.Add("--exec"); $runArgs += @($commandText) }
            if ($DryRun -and -not $argMap.ContainsKey('dry-run')) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "launch"; distro = $distro; args = @($runArgs); dryRun = $true; commandLine = "wsl " + ($runArgs -join " "); exitCode = 0 } } else { Write-Host "[windo] DRY-RUN launch command: wsl " + ($runArgs -join " "); Write-Host "  Add --apply to execute launch." -ForegroundColor DarkGray }
                _windo_set_exit 0
                return
            }
            $full = @("wsl") + @($runArgs)
            try {
                if ($JsonOutput) {
                    if ($commandText) {
                        $res = _windo_wsl_exec @($runArgs)
                        _emit_json "wsl" @{ command = "launch"; distro = $distro; command = @($runArgs); output = @($res.output); exitCode = [int]$res.exitCode }
                        _windo_set_exit [int]$res.exitCode
                        return
                    }
                    $p = Start-Process -FilePath $wslExe.Source -ArgumentList $runArgs -PassThru -ErrorAction Stop
                    _emit_json "wsl" @{ command = "launch"; distro = $distro; processId = [int]$p.Id; commandLine = ($full -join " "); dryRun = $false; exitCode = 0 }
                    _windo_set_exit 0
                    return
                }
                if ($commandText) {
                    $res = _windo_wsl_exec @($runArgs)
                    if ($res.exitCode -eq 0 -and $res.output.Count -gt 0) { Write-Host ($res.output -join "`r`n") } else { if ($res.output.Count -gt 0) { Write-Host ($res.output -join "`r`n") } }
                    _windo_set_exit [int]$res.exitCode
                } else {
                    $p = Start-Process -FilePath $wslExe.Source -ArgumentList $runArgs -PassThru -ErrorAction Stop
                    Write-Host "[windo] wsl launch started: pid=$($p.Id), distro=$distro" -ForegroundColor Green
                    _windo_set_exit 0
                }
            } catch {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "launch"; distro = $distro; error = $_.Exception.Message; exitCode = 1 } } else { Write-Host "[windo] launch failed: $($_.Exception.Message)" -ForegroundColor Red }
                _windo_set_exit 1
            }
            return
        }

        if ($sub -eq "path") {
            $direction = if ($argMap.ContainsKey('_args') -and $argMap._args.Count -gt 0) { [string]$argMap._args[0].ToLowerInvariant() } else { $null }
            $targetPath = if ($argMap.ContainsKey('path')) { [string]$argMap['path'] } elseif ($argMap.ContainsKey('_args') -and $argMap._args.Count -gt 1) { [string]$argMap._args[1] } else { $null }
            $distro = if ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } else { $null }
            if ($direction -notin @("to-wsl","to-win")) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "path"; error = "expected to-wsl or to-win"; exitCode = 2 } } else { Write-Host "[windo] wsl path requires 'to-wsl' or 'to-win'." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            if ([string]::IsNullOrWhiteSpace($targetPath)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "path"; direction = $direction; error = "missing path"; exitCode = 2 } } else { Write-Host "[windo] wsl path $direction requires --path <value>" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $convert = if ($direction -eq "to-wsl") { "-u" } else { "-w" }
            $toolArgs = @()
            if ($distro) { $toolArgs += @('-d', $distro) }
            $toolArgs += @('--exec','wslpath',$convert,$targetPath)
            if ($DryRun -and -not $argMap.ContainsKey('dry-run')) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "path"; direction = $direction; path = $targetPath; distro = $distro; converted = $null; dryRun = $true; command = "wsl " + ($toolArgs -join " "); exitCode = 0 } } else { Write-Host "[windo] DRY-RUN path convert command: wsl " + ($toolArgs -join " ") }
                _windo_set_exit 0
                return
            }
            $res = _windo_wsl_exec @($toolArgs)
            if ($res.exitCode -ne 0) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "path"; direction = $direction; path = $targetPath; distro = $distro; error = "path conversion failed"; output = @($res.output); exitCode = [int]$res.exitCode } } else { Write-Host "[windo] wslpath failed: $($res.output -join "`r`n")" -ForegroundColor Red }
                _windo_set_exit [int]$res.exitCode
                return
            }
            $converted = if ($res.output.Count -gt 0) { [string]$res.output[0] } else { "" }
            if ($JsonOutput) { _emit_json "wsl" @{ command = "path"; direction = $direction; path = $targetPath; distro = $distro; converted = $converted; exitCode = 0 } }
            else { Write-Host ("[windo] {0} -> {1}" -f $targetPath, $converted) -ForegroundColor Cyan }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "import") {
            $name = if ($argMap.ContainsKey('name')) { [string]$argMap['name'] } elseif ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } else { $null }
            $tar  = if ($argMap.ContainsKey('tar')) { [string]$argMap['tar'] } else { $null }
            $path = if ($argMap.ContainsKey('path')) { [string]$argMap['path'] } else { $null }
            $ver  = if ($argMap.ContainsKey('version')) { [string]$argMap['version'] } else { "2" }
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($tar) -or [string]::IsNullOrWhiteSpace($path)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "import"; error = "missing --name, --tar, or --path"; exitCode = 2 } } else { Write-Host "[windo] wsl import requires --name <distro> --tar <source> --path <target>" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $check = _windo_parse_kv -Tokens $Command -Start 2
            $apply = $check.ContainsKey('apply')
            if (-not $apply -and -not $DryRun) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "import"; error = "--apply is required for execution"; exitCode = 2 } } else { Write-Host "[windo] import is preview-only by default. Add --apply to run." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $pre = @{}
            $pre.command = "import"
            $pre.distribution = $name
            $pre.tar = $tar
            $pre.path = $path
            $pre.version = $ver
            if ($argMap.ContainsKey('_args')) { $pre.notes = @($argMap._args) }
            $args = @('--import', $name, $path, $tar, '--version', $ver)
            if ($DryRun -and -not $argMap.ContainsKey('dry-run')) { if ($JsonOutput) { $pre.dryRun = $true; $pre.commandLine = "wsl " + ($args -join " "); _emit_json "wsl" $pre } else { Write-Host "[windo] DRY-RUN import: wsl " + ($args -join " "); Write-Host "  Add --apply to execute." -ForegroundColor DarkGray }; _windo_set_exit 0; return }
            $commandLine = "wsl " + ($args -join " ")
            $apply = $argMap.ContainsKey('apply')
            if (-not (_windo_wsl_confirm -Message "Run wsl import" -CommandLine $commandLine -AutoApprove:$apply)) {
                if ($JsonOutput) { $pre.cancelled = $true; $pre.exitCode = 0; _emit_json "wsl" $pre } else { Write-Host "[windo] import cancelled." -ForegroundColor DarkGray }
                _windo_set_exit 0
                return
            }
            $res = _windo_wsl_exec @($args)
            if ($JsonOutput) { _emit_json "wsl" @{ command = "import"; distribution = $name; version = $ver; apply = $true; exitCode = [int]$res.exitCode; output = @($res.output) } } else { if ($res.exitCode -eq 0) { Write-Host "[windo] Import command completed for '$name'." -ForegroundColor Green } else { Write-Host "[windo] Import failed: $($res.output -join "`r`n")" -ForegroundColor Red } }
            _windo_set_exit [int]$res.exitCode
            return
        }

        if ($sub -eq "export") {
            $name = if ($argMap.ContainsKey('name')) { [string]$argMap['name'] } elseif ($argMap.ContainsKey('distro')) { [string]$argMap['distro'] } else { $null }
            $out  = if ($argMap.ContainsKey('out')) { [string]$argMap['out'] } elseif ($argMap.ContainsKey('output')) { [string]$argMap['output'] } else { $null }
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($out)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "export"; error = "missing --name or --out"; exitCode = 2 } } else { Write-Host "[windo] wsl export requires --name <distro> --out <tar>" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $existing = _windo_wsl_find_distro $name
            if (-not $existing.found -or -not $existing.distro) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "export"; distribution = $name; exists = $false; exitCode = 2 } } else { Write-Host "[windo] Unknown distro: $name" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $overwrite = $argMap.ContainsKey('overwrite')
            if ((Test-Path -LiteralPath $out) -and -not $overwrite) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "export"; distribution = $name; out = $out; error = "output exists; add --overwrite"; exitCode = 2 } } else { Write-Host "[windo] Output exists and --overwrite was not used: $out" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $apply = $argMap.ContainsKey('apply')
            if (-not $apply -and -not $DryRun) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "export"; error = "--apply is required for execution"; exitCode = 2 } } else { Write-Host "[windo] export is preview-only by default. Add --apply to run." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $args = @('--export', $name, $out)
            if ($DryRun -and -not $argMap.ContainsKey('dry-run')) { if ($JsonOutput) { _emit_json "wsl" @{ command = "export"; distribution = $name; out = $out; dryRun = $true; commandLine = "wsl " + ($args -join " "); exitCode = 0 } } else { Write-Host "[windo] DRY-RUN export: wsl " + ($args -join " "); Write-Host "  Add --apply to execute." -ForegroundColor DarkGray }; _windo_set_exit 0; return }
            $commandLine = "wsl " + ($args -join " ")
            $apply = $argMap.ContainsKey('apply')
            if (-not (_windo_wsl_confirm -Message "Run wsl export" -CommandLine $commandLine -AutoApprove:$apply)) {
                if ($JsonOutput) { _emit_json "wsl" @{ command = "export"; distribution = $name; out = $out; cancelled = $true; exitCode = 0 } } else { Write-Host "[windo] export cancelled." -ForegroundColor DarkGray }
                _windo_set_exit 0
                return
            }
            $res = _windo_wsl_exec @($args)
            if ($JsonOutput) { _emit_json "wsl" @{ command = "export"; distribution = $name; out = $out; apply = $true; exitCode = [int]$res.exitCode; output = @($res.output) } } else { if ($res.exitCode -eq 0) { Write-Host "[windo] Export completed: $out" -ForegroundColor Green } else { Write-Host "[windo] Export failed: $($res.output -join "`r`n")" -ForegroundColor Red } }
            _windo_set_exit [int]$res.exitCode
            return
        }

            if ($JsonOutput) { _emit_json "wsl" @{ command = "wsl"; error = "unknown subcommand '$sub'"; exitCode = 2 } }
        else { Write-Host "[windo] wsl: expected status|list|check|version|install|convert|inspect|exec|launch|path|import|export" -ForegroundColor Yellow }
        _windo_set_exit 2
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "recipes" -and -not ($Command.Count -ge 2 -and $Command[1] -ieq "run")) {
        $sub = "list"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        $book = _windo_builtin_recipes
        if ($sub -eq 'show' -or $sub -eq 'preview') {
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "recipes" @{ error = "missing recipe name"; subcommand = $sub; exitCode = 2 } } else { Write-Host "[windo] recipes $sub <name>" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $rn = [string]$Command[2].Trim()
            $preview = _windo_get_recipe_preview $rn
            if ($null -eq $preview) {
                if ($JsonOutput) { _emit_json "recipes" @{ error = "unknown recipe"; name = $rn; exitCode = 2 } } else { Write-Host "[windo] Unknown recipe: $rn" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            if ($JsonOutput) { _emit_json "recipes" @{ subcommand = $sub; preview = $preview; exitCode = 0 } }
            else {
                Write-Host "[windo] Recipe: $($preview.name)" -ForegroundColor Cyan
                Write-Host "  $($preview.description)" -ForegroundColor DarkGray
                Write-Host "  Command : $($preview.command)" -ForegroundColor Yellow
                Write-Host "  Preview : $($preview.previewCommand)" -ForegroundColor DarkGray
                Write-Host "  Dry-run : $($preview.dryRunCommand)" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        if ($sub -notin @('list', '')) {
            if ($JsonOutput) { _emit_json "recipes" @{ error = "unknown subcommand"; sub = $sub; exitCode = 2 } } else { Write-Host "[windo] recipes: expected list | show <name> | preview <name>" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $list = [System.Collections.ArrayList]@()
        foreach ($k in @($book.Keys | Sort-Object)) {
            [void]$list.Add([ordered]@{ name = $k; description = [string]$book[$k].description; command = [string]$book[$k].command })
        }
        if ($JsonOutput) { _emit_json "recipes" @{ recipes = @($list); windoVersion = $WindoVersion; exitCode = 0 } }
        else {
            Write-Host "[windo] Built-in recipes ($WindoVersion)" -ForegroundColor Cyan
            foreach ($item in $list) {
                Write-Host ("  {0,-22} {1}" -f $item.name, $item.description) -ForegroundColor Gray
            }
            Write-Host "  Run: windo recipes run <name>   or   windo run --recipe <name>" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "prompt") {
        $exportPath = $null
        $pi = 1
        while ($pi -lt $Command.Count) {
            $a = [string]$Command[$pi]
            if ($a -eq '--export' -and ($pi + 1) -lt $Command.Count) { $exportPath = [string]$Command[$pi + 1]; $pi += 2; continue }
            if ($a -like '--export=*') { $exportPath = $a.Substring(9); $pi++; continue }
            $pi++
        }
        $text = _windo_prompt_bridge_text
        $jsonPayload = @{
            windoVersion     = $WindoVersion
            environmentHints = @('WINDO_LAST_REQUEST_ID', 'WINDO_VERSION')
            ohMyPoshSegmentExample = @{
                type = "text"
                style = "diamond"
                foreground = "#569cd6"
                background = "#1e1e1e"
                leading_diamond = " "
                trailing_diamond = ""
                template = " WINDO {{ if .Env.WINDO_VERSION }}v{{ .Env.WINDO_VERSION }}{{ end }}{{ if .Env.WINDO_LAST_REQUEST_ID }} Â· {{ .Env.WINDO_LAST_REQUEST_ID }}{{ end }} "
            }
            exitCode = 0
        }
        if (-not [string]::IsNullOrWhiteSpace($exportPath)) {
            try {
                $dir = Split-Path -Parent $exportPath
                if (-not [string]::IsNullOrWhiteSpace($dir) -and !(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Set-Content -LiteralPath $exportPath -Value $text -Encoding UTF8
                if ($JsonOutput) { _emit_json "prompt" ($jsonPayload + @{ exportedTo = (Resolve-Path -LiteralPath $exportPath).Path }) }
                else { Write-Host "[windo] Wrote prompt bridge snippet to: $exportPath" -ForegroundColor Green }
            } catch {
                if ($JsonOutput) { _emit_json "prompt" @{ error = $_.Exception.Message; exitCode = 2 } } else { Write-Host "[windo] prompt: could not write $exportPath : $($_.Exception.Message)" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            _windo_set_exit 0
            return
        }
        if ($JsonOutput) { _emit_json "prompt" $jsonPayload } else { Write-Host $text }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "extras") {
        $sub = "search"
        $q = ""
        if ($Command.Count -ge 2) {
            $t1 = [string]$Command[1].Trim().ToLowerInvariant()
            if ($t1 -in @('search', 'fetch')) {
                $sub = $t1
                if ($sub -eq 'search' -and $Command.Count -ge 3) {
                    $q = ($Command[2..($Command.Count - 1)] -join " ").Trim()
                }
            } else {
                $sub = 'search'
                $q = ($Command[1..($Command.Count - 1)] -join " ").Trim()
            }
        }
        if ($sub -eq 'fetch') {
            if (_windo_is_process_elevated) {
                if ($JsonOutput) { _emit_json "extras" @{ error = "fetch refused while elevated"; exitCode = 2 } } else {
                    Write-Host "[windo] extras fetch: downloads are not performed while running as Administrator." -ForegroundColor Yellow
                    Write-Host "  Open a normal PowerShell window and run the same command." -ForegroundColor DarkGray
                }
                _windo_set_exit 2
                return
            }
            if ($Command.Count -lt 3) {
                if ($JsonOutput) { _emit_json "extras" @{ error = "missing id"; exitCode = 2 } } else { Write-Host "[windo] extras fetch <id>" -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $xid = [string]$Command[2].Trim()
            $force = $false
            foreach ($a in $Command) { if ([string]$a -eq '--force') { $force = $true } }
            $url = _windo_extras_index_url
            $raw = _windo_fetch_text_url $url
            $idx = $raw | ConvertFrom-Json
            $item = $null
            foreach ($it in @($idx.items)) {
                if ([string]$it.id -eq $xid) { $item = $it; break }
            }
            if (-not $item) {
                if ($JsonOutput) { _emit_json "extras" @{ error = "id not in index"; id = $xid; exitCode = 2 } } else { Write-Host "[windo] extras: id not found in index: $xid" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $src = [string]$item.sourceUrl
            if ([string]::IsNullOrWhiteSpace($src)) {
                if ($JsonOutput) { _emit_json "extras" @{ error = "item has no sourceUrl"; id = $xid; exitCode = 2 } } else { Write-Host "[windo] extras: this catalog entry has no download URL." -ForegroundColor Yellow }
                _windo_set_exit 2
                return
            }
            $expectHash = [string]$item.sha256
            if ([string]::IsNullOrWhiteSpace($expectHash)) {
                if (-not $force) {
                    if ($JsonOutput) { _emit_json "extras" @{ error = "sha256 missing; use --force to accept"; id = $xid; exitCode = 2 } }
                    else { Write-Host "[windo] extras: index entry has no sha256. Re-run with --force to download anyway." -ForegroundColor Yellow }
                    _windo_set_exit 2
                    return
                }
            }
            $destRoot = Join-Path (_windo_extras_install_root) $xid
            if (!(Test-Path -LiteralPath $destRoot)) { New-Item -ItemType Directory -Path $destRoot -Force | Out-Null }
            $uriObj = [uri]$src
            $leaf = [System.IO.Path]::GetFileName($uriObj.LocalPath)
            if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "download.bin" }
            $destFile = Join-Path $destRoot $leaf
            try {
                $prev = $ProgressPreference
                $ProgressPreference = 'SilentlyContinue'
                Invoke-RestMethod -Uri $src -OutFile $destFile -TimeoutSec 120 -ErrorAction Stop
                $ProgressPreference = $prev
            } catch {
                if ($JsonOutput) { _emit_json "extras" @{ error = $_.Exception.Message; exitCode = 2 } } else { Write-Host "[windo] extras fetch: download failed: $($_.Exception.Message)" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $got = (Get-FileHash -LiteralPath $destFile -Algorithm SHA256).Hash
            if (-not [string]::IsNullOrWhiteSpace($expectHash)) {
                if ($got.ToUpperInvariant() -cne $expectHash.Trim().ToUpperInvariant()) {
                    Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue
                    if ($JsonOutput) { _emit_json "extras" @{ error = "sha256 mismatch"; expected = $expectHash; actual = $got; exitCode = 2 } }
                    else { Write-Host "[windo] extras: SHA256 mismatch. File removed." -ForegroundColor Red }
                    _windo_set_exit 2
                    return
                }
            }
            if ($JsonOutput) { _emit_json "extras" @{ id = $xid; path = $destFile; sha256 = $got; exitCode = 0 } }
            else { Write-Host "[windo] Downloaded extra to: $destFile" -ForegroundColor Green; Write-Host "  SHA256: $got" -ForegroundColor DarkGray }
            _windo_set_exit 0
            return
        }
        try {
            $raw = _windo_fetch_text_url (_windo_extras_index_url)
            $idx = $raw | ConvertFrom-Json
        } catch {
            if ($JsonOutput) { _emit_json "extras" @{ error = $_.Exception.Message; exitCode = 2 } } else { Write-Host "[windo] extras: could not read index: $($_.Exception.Message)" -ForegroundColor Red }
            _windo_set_exit 2
            return
        }
        $all = @($idx.items)
        $match = $all
        if (-not [string]::IsNullOrWhiteSpace($q)) {
            $qn = $q.ToLowerInvariant()
            $match = @($all | Where-Object {
                ([string]$_.id).ToLowerInvariant() -like "*$qn*" -or
                ([string]$_.description).ToLowerInvariant() -like "*$qn*"
            })
        }
        if ($JsonOutput) { _emit_json "extras" @{ query = $q; items = @($match); indexSchema = [string]$idx.schemaVersion; exitCode = 0 } }
        else {
            Write-Host "[windo] extras catalog ($($match.Count) match(es))" -ForegroundColor Cyan
            foreach ($it in $match) {
                Write-Host ("  {0,-20} {1}" -f [string]$it.id, [string]$it.description) -ForegroundColor Gray
            }
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "dev") {
        $sub = ""
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -ne 'init-module') {
            if ($JsonOutput) { _emit_json "dev" @{ error = "expected: dev init-module [name]"; exitCode = 2 } } else { Write-Host "[windo] dev init-module [name]" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $mid = "new-module"
        if ($Command.Count -ge 3) { $mid = [string]$Command[2].Trim() }
        if ([string]::IsNullOrWhiteSpace($mid) -or $mid -match '[\\/<>:*?"|]') {
            if ($JsonOutput) { _emit_json "dev" @{ error = "invalid module name"; exitCode = 2 } } else { Write-Host "[windo] dev: invalid module name" -ForegroundColor Red }
            _windo_set_exit 2
            return
        }
        $modRoot = _windo_modules_root
        if (!(Test-Path -LiteralPath $modRoot)) { New-Item -ItemType Directory -Path $modRoot -Force | Out-Null }
        $modDir = Join-Path $modRoot $mid
        if (Test-Path -LiteralPath $modDir) {
            if ($JsonOutput) { _emit_json "dev" @{ error = "directory exists"; path = $modDir; exitCode = 2 } } else { Write-Host "[windo] dev: already exists: $modDir" -ForegroundColor Red }
            _windo_set_exit 2
            return
        }
        New-Item -ItemType Directory -Path $modDir -Force | Out-Null
        $mj = @"
{
  "name": "$mid",
  "version": "0.1.0",
  "entry": "Load.ps1",
  "requiresWindoVersion": "4.0.0"
}
"@
        $lp = @"
# WINDO module $mid â€” loaded after WINDO core (non-fatal on error)
`$WindoModuleId = '$mid'
Write-Host "[WINDO module $mid] loaded." -ForegroundColor DarkGray
"@
        $readme = @"
# WINDO module: $mid

Local-only module loaded after the WINDO profile block.

Enable: windo modules enable $mid

Trust: review Load.ps1 (and any other files) before enabling. Modules run in your interactive shell context.

See the WINDO repository docs/modules-and-extras.md for the modules and extras trust model.
"@
        Set-Content -LiteralPath (Join-Path $modDir "module.json") -Value $mj.Trim() -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $modDir "Load.ps1") -Value $lp.Trim() -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $modDir "README.md") -Value $readme.Trim() -Encoding UTF8
        if ($JsonOutput) { _emit_json "dev" @{ action = "init-module"; moduleId = $mid; path = $modDir; readme = (Join-Path $modDir "README.md"); exitCode = 0 } }
        else { Write-Host "[windo] Scaffolded module at $modDir" -ForegroundColor Green; Write-Host "  Enable: windo modules enable $mid" -ForegroundColor DarkGray }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "session") {
        $mt = $false; $ut = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mt = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $ut = $true } catch {}
        $ix = _integrity_status
        $meta = _read_last_meta
        $lc = $null
        if (Test-Path $LastCmdFile) { $lc = (Get-Content -Raw -Path $LastCmdFile -ErrorAction SilentlyContinue).Trim() }
        $auditAll = @(_parse_log_entries)
        $lastAudit = $null
        $recentAudit = [System.Collections.ArrayList]@()
        if ($auditAll.Count -gt 0) {
            $lastAudit = $auditAll[$auditAll.Count - 1]
            $take = [Math]::Min(5, $auditAll.Count)
            foreach ($a in @($auditAll | Select-Object -Last $take)) {
                $elev = $null
                if ($a.PSObject.Properties.Name -contains 'Elevation') { $elev = [string]$a.Elevation }
                $rid = $null
                if ($a.PSObject.Properties.Name -contains 'RequestId') { $rid = [string]$a.RequestId }
                [void]$recentAudit.Add([ordered]@{
                    timestamp = [string]$a.Timestamp
                    command = [string]$a.Command
                    exitCode = [int]$a.ExitCode
                    elevation = $elev
                    requestId = $rid
                })
            }
        }
        $lastAuditPayload = $null
        if ($null -ne $lastAudit) {
            $le = $null
            if ($lastAudit.PSObject.Properties.Name -contains 'Elevation') { $le = [string]$lastAudit.Elevation }
            $lrid = $null
            if ($lastAudit.PSObject.Properties.Name -contains 'RequestId') { $lrid = [string]$lastAudit.RequestId }
            $lastAuditPayload = @{
                timestamp = [string]$lastAudit.Timestamp
                command = [string]$lastAudit.Command
                exitCode = [int]$lastAudit.ExitCode
                elevation = $le
                requestId = $lrid
            }
        }
        $pl = @{
            windoVersion = $WindoVersion
            secureDir = $SecureDir
            mainTaskPresent = $mt
            updateTaskPresent = $ut
            integrityOverall = $ix.OverallLevel
            integrityRunner = $ix.RunnerLevel
            integrityUpdater = $ix.UpdaterLevel
            lastCommand = $lc
            lastRequestId = $(if ($meta -and $meta.PSObject.Properties.Name -contains 'lastRequestId') { [string]$meta.lastRequestId } else { $null })
            lastStoredAt = $(if ($meta -and $meta.PSObject.Properties.Name -contains 'storedAt') { [string]$meta.storedAt } else { $null })
            lastAudit = $lastAuditPayload
            recentAudit = @($recentAudit)
            exitCode = 0
        }
        if ($JsonOutput) { _emit_json "session" $pl }
        else {
            Write-Host "[windo] session" -ForegroundColor Cyan
            Write-Host "  Version    : $WindoVersion"
            Write-Host "  Tasks      : main=$(if ($mt) { 'ok' } else { 'MISSING' })  update=$(if ($ut) { 'ok' } else { 'MISSING' })"
            Write-Host "  Integrity  : $($ix.OverallLevel) (runner $($ix.RunnerLevel), updater $($ix.UpdaterLevel))"
            if ($lc) { Write-Host "  Last cmd   : $lc" -ForegroundColor DarkGray }
            if ($pl.lastRequestId) { Write-Host "  Last reqId : $($pl.lastRequestId)" -ForegroundColor DarkGray }
            if ($null -ne $lastAuditPayload) {
                Write-Host "  Last audit : $($lastAuditPayload.timestamp)  exit=$($lastAuditPayload.exitCode)  $($lastAuditPayload.elevation)" -ForegroundColor DarkGray
                Write-Host "             $($lastAuditPayload.command)" -ForegroundColor DarkGray
            } else {
                Write-Host "  Last audit : (no log entries yet)" -ForegroundColor DarkGray
            }
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "dashboard") {
        $dashOut = $null
        $writeHtml = $false
        $openHtml = $false
        $di = 1
        while ($di -lt $Command.Count) {
            $a = [string]$Command[$di]
            if ($a -eq '--html') { $writeHtml = $true; $di++; continue }
            if ($a -eq '--open') { $writeHtml = $true; $openHtml = $true; $di++; continue }
            if (($a -eq '-o' -or $a -eq '--output') -and ($di + 1) -lt $Command.Count) {
                $dashOut = [string]$Command[$di + 1]
                $writeHtml = $true
                $di += 2
                continue
            }
            if ($a -like '--output=*') {
                $dashOut = $a.Substring(9)
                $writeHtml = $true
                $di++
                continue
            }
            $di++
        }
        if ([string]::IsNullOrWhiteSpace($dashOut)) {
            $dashOut = Join-Path (Join-Path $HOME "Documents") ("windo\windo_dashboard_{0}.html" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        }

        $mainTask = $false; $updateTask = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mainTask = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $updateTask = $true } catch {}
        $ix = _integrity_status
        $vf = _windo_verify_log_state
        if (Test-Path $LogFile) {
            $lcD = _windo_log_line_count $LogFile
            if ($lcD -gt 100000) {
                Write-Host "[windo] Warning: large audit log (~$lcD lines); dashboard decrypts all entries. See docs/performance.md." -ForegroundColor DarkYellow
            }
        }
        $entries = @(_parse_log_entries)
        $cat = @{ SUCCESS = 0; NONZERO = 0; ELEVATION_FAILED = 0; OTHER = 0 }
        $durationTotal = 0; $durationCount = 0
        foreach ($e in $entries) {
            $c = _windo_audit_category $e
            $cat[$c] = [int]$cat[$c] + 1
            if ($e.PSObject.Properties.Name -contains 'DurationMs') { try { $durationTotal += [int]$e.DurationMs; $durationCount++ } catch {} }
        }
        $avgMs = if ($durationCount -gt 0) { [Math]::Round($durationTotal / $durationCount) } else { $null }
        $score = 100
        $issues = [System.Collections.ArrayList]@()
        if (-not $mainTask) { $score -= 25; [void]$issues.Add("main scheduled task missing") }
        if (-not $updateTask) { $score -= 10; [void]$issues.Add("self-update task missing") }
        if ($ix.OverallLevel -ne 'OK') { $score -= 30; [void]$issues.Add("integrity is $($ix.OverallLevel)") }
        if (-not $vf.verifyOk) { $score -= 20; [void]$issues.Add("audit verify: $($vf.error)") }
        if ([int]$cat['ELEVATION_FAILED'] -gt 0) { $score -= 10; [void]$issues.Add("recent elevation failures present") }
        if ($score -lt 0) { $score = 0 }
        $status = if ($score -ge 90) { 'OK' } elseif ($score -ge 70) { 'WARN' } else { 'CRITICAL' }
        $recent = [System.Collections.ArrayList]@()
        foreach ($e in @($entries | Select-Object -Last 8)) {
            $rid = $null
            if ($e.PSObject.Properties.Name -contains 'RequestId') { $rid = [string]$e.RequestId }
            $elev = $null
            if ($e.PSObject.Properties.Name -contains 'Elevation') { $elev = [string]$e.Elevation }
            [void]$recent.Add([ordered]@{
                timestamp = [string]$e.Timestamp
                command = [string]$e.Command
                exitCode = [int]$e.ExitCode
                elevation = $elev
                requestId = $rid
            })
        }
        $payload = [ordered]@{
            generatedAt = (Get-Date).ToString("o")
            windoVersion = $WindoVersion
            host = [System.Net.Dns]::GetHostName()
            status = $status
            healthScore = [int]$score
            issues = @($issues)
            tasks = @{ main = $mainTask; selfUpdate = $updateTask }
            integrity = @{ overallLevel = $ix.OverallLevel; runnerLevel = $ix.RunnerLevel; updaterLevel = $ix.UpdaterLevel }
            verify = @{ verifyOk = [bool]$vf.verifyOk; physicalLines = [int]$vf.physicalLines; error = $(if ($vf.error) { [string]$vf.error } else { $null }); failureLine = $vf.failureLine }
            audit = @{ totalEntries = $entries.Count; categories = $cat; avgDurationMs = $avgMs; recent = @($recent) }
            paths = @{ secureDir = $SecureDir; logFile = $LogFile; manifestFile = $ManifestFile }
            htmlPath = $(if ($writeHtml) { $dashOut } else { $null })
            exitCode = $(if ($status -eq 'OK') { 0 } elseif ($status -eq 'WARN') { 3 } else { 4 })
        }

        if ($writeHtml) {
            $maxCat = [Math]::Max(1, ($cat.Values | Measure-Object -Maximum).Maximum)
            $sb = [System.Text.StringBuilder]::new()
            $statusClass = if ($status -eq 'OK') { 'ok' } elseif ($status -eq 'WARN') { 'warn' } else { 'bad' }
            $assets = _windo_brand_assets
            $brandImg = _windo_html_img ([string]$assets.banner) "brand" "WINDO banner"
            $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO dashboard</title>')
            $null = $sb.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#08111f;color:#e5e7eb}.wrap{max-width:1240px;margin:0 auto;padding:28px}.hero{position:relative;border-bottom:1px solid #24324e;padding:0 0 22px;margin-bottom:18px}.hero:after{content:"";position:absolute;left:0;right:0;bottom:-1px;height:2px;background:linear-gradient(90deg,#38bdf8,#22c55e,transparent)}.brand{max-width:720px;width:100%;height:auto;margin-bottom:16px}.title{font-size:36px;font-weight:800;margin:0}.meta{color:#a7b4c8}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px;margin:18px 0}.card{background:#0f172a;border:1px solid #24324e;border-radius:8px;padding:16px;box-shadow:0 12px 34px rgba(0,0,0,.18)}.k{font-size:11px;text-transform:uppercase;color:#94a3b8}.v{font-size:30px;font-weight:800;margin-top:4px}.ok{color:#22c55e}.warn{color:#f59e0b}.bad{color:#ef4444}.bar{height:12px;background:#1f2937;border-radius:4px;overflow:hidden}.fill{height:100%;background:linear-gradient(90deg,#2563eb,#22c55e)}table{border-collapse:collapse;width:100%;background:#0f172a;border:1px solid #24324e;margin:12px 0 24px}th,td{padding:10px;border-bottom:1px solid #1f2937;text-align:left;vertical-align:top}th{background:#111d33;color:#cbd5e1}code{background:#020617;border:1px solid #24324e;color:#bfdbfe;padding:3px 5px;border-radius:5px}.section{margin-top:24px}.issue{border-left:3px solid #f59e0b}.pathline{line-height:1.8}@media(max-width:760px){.title{font-size:30px}.wrap{padding:18px}table{font-size:13px}}</style></head><body><div class="wrap">')
            $null = $sb.AppendLine(("<div class='hero'>{0}<div class='title'>WINDO Dashboard</div><div class='meta'>Generated {1} on {2}. Local-only HTML; command text may be sensitive.</div></div>" -f $brandImg, (_html_escape (Get-Date -Format "yyyy-MM-dd HH:mm:ss")), (_html_escape $payload.host)))
            $null = $sb.AppendLine("<div class='grid'>")
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Health</div><div class='v {0}'>{1}</div><div class='bar'><div class='fill' style='width:{2}%'></div></div></div>" -f $statusClass, (_html_escape $status), [int]$score))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Audit entries</div><div class='v'>{0}</div><div class='meta'>verify: {1}</div></div>" -f $entries.Count, $(if ($vf.verifyOk) { 'OK' } else { _html_escape ([string]$vf.error) })))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Integrity</div><div class='v {0}'>{1}</div><div class='meta'>runner {2}, updater {3}</div></div>" -f $(if ($ix.OverallLevel -eq 'OK') { 'ok' } else { 'bad' }), (_html_escape $ix.OverallLevel), (_html_escape $ix.RunnerLevel), (_html_escape $ix.UpdaterLevel)))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Tasks</div><div class='v'>{0}/{1}</div><div class='meta'>main / self-update</div></div>" -f $(if ($mainTask) { 'ok' } else { 'missing' }), $(if ($updateTask) { 'ok' } else { 'missing' })))
            $null = $sb.AppendLine("</div>")
            if ($issues.Count -gt 0) { $null = $sb.AppendLine(("<div class='card issue'><div class='k'>Issues</div><p>{0}</p></div>" -f (_html_escape (@($issues) -join '; ')))) }
            $null = $sb.AppendLine("<div class='section'><h2>Audit categories</h2><table><tr><th>Category</th><th>Count</th><th>Visual</th></tr>")
            foreach ($name in @('SUCCESS','NONZERO','ELEVATION_FAILED','OTHER')) {
                $pct = [Math]::Round(([int]$cat[$name] / [double]$maxCat) * 100)
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td><div class='bar'><div class='fill' style='width:{2}%'></div></div></td></tr>" -f $name, [int]$cat[$name], $pct))
            }
            $null = $sb.AppendLine("</table></div><div class='section'><h2>Recent audit</h2><table><tr><th>Time</th><th>Exit</th><th>Elevation</th><th>Command</th></tr>")
            foreach ($e in $recent) {
                $cmd = [string]$e.command
                if ($cmd.Length -gt 220) { $cmd = $cmd.Substring(0, 220) + "..." }
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>" -f (_html_escape $e.timestamp), (_html_escape ([string]$e.exitCode)), (_html_escape ([string]$e.elevation)), (_html_escape $cmd)))
            }
            $null = $sb.AppendLine(("</table></div><div class='section'><h2>Paths</h2><p class='pathline'><code>{0}</code><br><code>{1}</code></p></div></div></body></html>" -f (_html_escape $SecureDir), (_html_escape $LogFile)))
            $dir = Split-Path $dashOut -Parent
            if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllText($dashOut, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
            if ($openHtml) { Start-Process -FilePath $dashOut | Out-Null }
        }

        if ($JsonOutput) {
            _emit_json "dashboard" $payload
        } else {
            Write-Host "[windo] dashboard" -ForegroundColor Cyan
            Write-Host "  Health     : $status ($score/100)" -ForegroundColor $(if ($status -eq 'OK') { 'Green' } elseif ($status -eq 'WARN') { 'Yellow' } else { 'Red' })
            Write-Host "  Tasks      : main=$(if ($mainTask) { 'ok' } else { 'MISSING' })  update=$(if ($updateTask) { 'ok' } else { 'MISSING' })"
            Write-Host "  Integrity  : $($ix.OverallLevel) (runner $($ix.RunnerLevel), updater $($ix.UpdaterLevel))"
            Write-Host "  Verify     : $(if ($vf.verifyOk) { 'OK' } else { "$($vf.error) line=$($vf.failureLine)" })"
            Write-Host "  Audit      : total=$($entries.Count) avgMs=$(if ($null -ne $avgMs) { $avgMs } else { 'n/a' })"
            foreach ($name in @('SUCCESS','NONZERO','ELEVATION_FAILED','OTHER')) {
                Write-Host ("    {0,-16} {1,5}  {2}" -f $name, [int]$cat[$name], (_windo_text_bar ([int]$cat[$name]) ([Math]::Max(1, $entries.Count)) 24)) -ForegroundColor DarkGray
            }
            if ($issues.Count -gt 0) { Write-Host "  Issues     : $(@($issues) -join '; ')" -ForegroundColor Yellow }
            if ($writeHtml) { Write-Host "  HTML       : $dashOut" -ForegroundColor Green }
        }
        _windo_set_exit ([int]$payload.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "preflight") {
        $rows = @(_windo_preflight_rows)
        $fail = @($rows | Where-Object { -not $_.ok })
        $critical = @($fail | Where-Object { $_.severity -eq 'critical' })
        $exit = if ($critical.Count -gt 0) { 4 } elseif ($fail.Count -gt 0) { 3 } else { 0 }
        $payload = @{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            ok = ($fail.Count -eq 0)
            failedCount = $fail.Count
            criticalCount = $critical.Count
            checks = $rows
            exitCode = $exit
        }
        if ($JsonOutput) {
            _emit_json "preflight" $payload
        } else {
            Write-Host "[windo] preflight" -ForegroundColor Cyan
            foreach ($r in $rows) {
                $mark = if ($r.ok) { "[OK]" } elseif ($r.severity -eq 'critical') { "[!!]" } else { "[!]" }
                $color = if ($r.ok) { "Green" } elseif ($r.severity -eq 'critical') { "Red" } else { "Yellow" }
                Write-Host ("  {0} {1}" -f $mark, $r.label) -ForegroundColor $color
                Write-Host ("       {0}" -f $r.detail) -ForegroundColor DarkGray
                if (-not $r.ok -and -not [string]::IsNullOrWhiteSpace($r.fixCommand)) {
                    Write-Host ("       fix: {0}" -f $r.fixCommand) -ForegroundColor DarkYellow
                }
            }
            Write-Host "  Exit code: $exit  (0=ready, 3=warnings, 4=critical)" -ForegroundColor DarkGray
        }
        _windo_set_exit $exit
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "launchpad") {
        $outPath = Join-Path (Join-Path $HOME "Documents") ("windo\windo_launchpad_{0}.html" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        $writeHtml = $false
        $openHtml = $false
        $startTray = $false
        $li = 1
        while ($li -lt $Command.Count) {
            $a = [string]$Command[$li]
            if ($a -eq '--html') { $writeHtml = $true; $li++; continue }
            if ($a -eq '--open') { $writeHtml = $true; $openHtml = $true; $li++; continue }
            if ($a -eq '--tray') { $startTray = $true; $li++; continue }
            if ($a -eq '--output' -and ($li + 1) -lt $Command.Count) {
                $outPath = [string]$Command[$li + 1]
                $writeHtml = $true
                $li += 2
                continue
            }
            if ($a -like '--output=*') {
                $outPath = $a.Substring(9)
                $writeHtml = $true
                $li++
                continue
            }
            $li++
        }

        $checks = @(_windo_preflight_rows)
        $failed = @($checks | Where-Object { -not $_.ok })
        $critical = @($failed | Where-Object { $_.severity -eq 'critical' })
        $recipeMap = _windo_builtin_recipes
        $recipes = @($recipeMap.GetEnumerator() | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{ id = $_.Name; description = [string]$_.Value.description; command = [string]$_.Value.command }
        })
        $modules = @(_windo_modules_discover_rows)
        $actions = @(_windo_operator_actions)
        $score = 100 - ($critical.Count * 25) - (($failed.Count - $critical.Count) * 10)
        if ($score -lt 0) { $score = 0 }
        $status = if ($score -ge 90) { "READY" } elseif ($score -ge 70) { "ATTENTION" } else { "REPAIR" }
        $brandLogoPath = $null
        foreach ($candidateLogoPath in @(
            [string]$env:WINDO_LOGO_PATH,
            (Join-Path $HOME "Documents\GitHub\windo\brand\Enterprise\assets\logo\windo-logo-full-dark-512.png"),
            (Join-Path $HOME "Documents\windo\brand\Enterprise\assets\logo\windo-logo-full-dark-512.png")
        )) {
            if (-not [string]::IsNullOrWhiteSpace($candidateLogoPath) -and (Test-Path -LiteralPath $candidateLogoPath)) {
                $brandLogoPath = $candidateLogoPath
                break
            }
        }
        $payload = [ordered]@{
            windoVersion = $WindoVersion
            generatedAt = (Get-Date).ToString("o")
            status = $status
            score = [int]$score
            checks = $checks
            actions = $actions
            recipes = $recipes
            modules = $modules
            paths = @{ secureDir = $SecureDir; snapshotDir = (Join-Path (Join-Path $HOME "Documents") "windo"); profile = [string]$PROFILE; brandLogo = $brandLogoPath }
            htmlPath = $(if ($writeHtml) { $outPath } else { $null })
            tray = @{ requested = $startTray; started = $false; scriptPath = $null; iconPath = $null; error = $null }
            exitCode = $(if ($status -eq "READY") { 0 } elseif ($status -eq "ATTENTION") { 3 } else { 4 })
        }

        if ($startTray) {
            $trayResult = _windo_start_launchpad_tray
            $payload.tray.started = [bool]$trayResult.ok
            if ($trayResult.ok) {
                $payload.tray.scriptPath = [string]$trayResult.path
                $payload.tray.iconPath = [string]$trayResult.iconPath
            } else {
                $payload.tray.error = [string]$trayResult.error
                if ([int]$payload.exitCode -eq 0) { $payload.exitCode = 3 }
            }
        }

        if ($writeHtml) {
            $json = ($payload | ConvertTo-Json -Depth 14)
            $sb = [System.Text.StringBuilder]::new()
            $assets = _windo_brand_assets
            $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO Launchpad</title>')
            $null = $sb.AppendLine('<style>body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#070b14;color:#e5e7eb}.wrap{max-width:1260px;margin:0 auto;padding:28px}.hero{position:relative;display:grid;grid-template-columns:minmax(280px,1fr) 230px;gap:22px;align-items:center;border-bottom:1px solid #24324e;padding-bottom:22px}.hero:after{content:"";position:absolute;left:0;right:0;bottom:-1px;height:2px;background:linear-gradient(90deg,#38bdf8,#22c55e,transparent)}.brand{max-width:690px;width:100%;height:auto;margin-bottom:10px}.mark{max-width:210px;width:100%;height:auto}.title{font-size:40px;font-weight:800}.sub{color:#a7b4c8;max-width:760px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px;margin:20px 0}.card{background:#0f172a;border:1px solid #24324e;border-radius:8px;padding:16px}.k{font-size:11px;text-transform:uppercase;color:#94a3b8}.v{font-size:30px;font-weight:800}.ready{color:#22c55e}.attention{color:#f59e0b}.repair{color:#ef4444}button{background:#0ea5e9;color:white;border:0;border-radius:6px;padding:7px 10px;cursor:pointer;min-width:64px}code{background:#020617;border:1px solid #24324e;border-radius:5px;padding:3px 5px;color:#bfdbfe}.row{display:grid;grid-template-columns:1fr auto;gap:12px;align-items:center;border-top:1px solid #1f2937;padding:12px 0}.muted{color:#94a3b8}table{width:100%;border-collapse:collapse;background:#0f172a;border:1px solid #24324e;margin:12px 0 24px}th,td{padding:10px;border-bottom:1px solid #1f2937;text-align:left;vertical-align:top}th{background:#111d33;color:#cbd5e1}.section{margin-top:24px}@media(max-width:820px){.hero{grid-template-columns:1fr}.title{font-size:32px}.mark{max-width:130px}.row{grid-template-columns:1fr}}</style></head><body><div class="wrap">')
            $brandImg = _windo_html_img ([string]$assets.banner) "brand" "WINDO banner"
            if ([string]::IsNullOrWhiteSpace($brandImg) -and -not [string]::IsNullOrWhiteSpace($brandLogoPath)) {
                $brandImg = "<img class='brand' alt='WINDO' src='$(_html_escape ([uri]$brandLogoPath).AbsoluteUri)'>"
            }
            $markImg = _windo_html_img ([string]$assets.avatar) "mark" "WINDO"
            $null = $sb.AppendLine(("<div class='hero'><div>{0}<div class='title'>WINDO Launchpad</div><div class='sub'>WINDO Command Center launchpad generated {1}. Local-only; command text may be sensitive.</div></div><div>{2}</div></div>" -f $brandImg, (_html_escape (Get-Date -Format "yyyy-MM-dd HH:mm:ss")), $markImg))
            $cls = $status.ToLowerInvariant()
            $null = $sb.AppendLine(("<div class='grid'><div class='card'><div class='k'>Status</div><div class='v {0}'>{1}</div></div><div class='card'><div class='k'>Score</div><div class='v'>{2}/100</div></div><div class='card'><div class='k'>Checks</div><div class='v'>{3}</div><div class='muted'>{4} need attention</div></div></div>" -f $cls, $status, [int]$score, $checks.Count, $failed.Count))
            $null = $sb.AppendLine("<div class='section'><h2>Quick actions</h2><div class='card'>")
            foreach ($a in $actions) {
                $null = $sb.AppendLine(("<div class='row'><div><strong>{0}</strong><div class='muted'>{1}</div><code>{2}</code></div><button onclick=""copyCmd('{3}')"">Copy</button></div>" -f (_html_escape $a.title), (_html_escape $a.note), (_html_escape $a.command), (_html_escape ($a.command -replace "'", "\'"))))
            }
            $null = $sb.AppendLine("</div></div><div class='section'><h2>Preflight</h2><table><tr><th>Check</th><th>Status</th><th>Detail</th><th>Fix</th></tr>")
            foreach ($c in $checks) {
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td><code>{3}</code></td></tr>" -f (_html_escape $c.label), $(if ($c.ok) { 'OK' } else { _html_escape $c.severity }), (_html_escape $c.detail), (_html_escape $c.fixCommand)))
            }
            $null = $sb.AppendLine("</table></div><div class='section'><h2>Recipes</h2><table><tr><th>ID</th><th>Description</th><th>Command</th></tr>")
            foreach ($r in $recipes) {
                $cmd = "windo recipes run $($r.id)"
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td><code>{2}</code></td></tr>" -f (_html_escape $r.id), (_html_escape $r.description), (_html_escape $cmd)))
            }
            $null = $sb.AppendLine("</table></div><div class='section'><h2>Modules</h2><table><tr><th>ID</th><th>Status</th><th>Entry</th></tr>")
            foreach ($m in $modules) {
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>" -f (_html_escape $m.id), $(if ($m.enabled) { 'enabled' } else { 'available' }), (_html_escape $m.entry)))
            }
            $null = $sb.AppendLine("</table></div><script>")
            $null = $sb.AppendLine("const WINDO_LAUNCHPAD_DATA = ")
            $null = $sb.AppendLine($json)
            $null = $sb.AppendLine("; function copyCmd(t){ if(navigator.clipboard){navigator.clipboard.writeText(t);} else { prompt('Copy command:', t); } }</script></div></body></html>")
            $dir = Split-Path $outPath -Parent
            if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllText($outPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
            if ($openHtml) { Start-Process -FilePath $outPath | Out-Null }
        }

        if ($JsonOutput) {
            _emit_json "launchpad" $payload
        } else {
            Write-Host "[windo] launchpad" -ForegroundColor Cyan
            Write-Host "  Status : $status ($score/100)" -ForegroundColor $(if ($status -eq 'READY') { 'Green' } elseif ($status -eq 'ATTENTION') { 'Yellow' } else { 'Red' })
            Write-Host "  Checks : $($checks.Count) total, $($failed.Count) need attention"
            Write-Host "  Actions:" -ForegroundColor DarkGray
            foreach ($a in $actions | Select-Object -First 6) {
                Write-Host ("    {0,-20} {1}" -f $a.title, $a.command) -ForegroundColor DarkGray
            }
            Write-Host "  Recipes: $($recipes.Count) built-in; Modules: $($modules.Count) discovered" -ForegroundColor DarkGray
            if ($startTray) {
                if ($payload.tray.started) { Write-Host "  Tray   : started ($($payload.tray.scriptPath))" -ForegroundColor Green }
                else { Write-Host "  Tray   : $($payload.tray.error)" -ForegroundColor Yellow }
            }
            if ($writeHtml) { Write-Host "  HTML   : $outPath" -ForegroundColor Green }
        }
        _windo_set_exit ([int]$payload.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "ai") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -notin @('status', 'doctor')) {
            if ($JsonOutput) { _emit_json "ai" @{ error = "expected status or doctor"; sub = $sub; exitCode = 2 } } else { Write-Host "[windo] ai: expected status | doctor  (got: $sub)" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $snap = _windo_ai_credential_env_snapshot
        $ollamaAdv = _windo_ai_ollama_host_advisory
        $issues = [System.Collections.ArrayList]@()
        if ($snap.elevated -and $snap.processHasSecret) {
            [void]$issues.Add("API-related environment variables are set in this elevated process; high-privilege sessions should not load API keys.")
        }
        if ($snap.machineScopeHasSecret) {
            [void]$issues.Add("At least one cloud API key-related variable is set at Machine (system-wide) scope; prefer per-user or vault-backed storage.")
        }
        if ($null -ne $ollamaAdv -and $ollamaAdv -match 'may point|binds all interfaces') {
            [void]$issues.Add($ollamaAdv)
        }
        $rec = [System.Collections.ArrayList]@()
        if ($sub -eq "doctor") {
            if ($null -ne $ollamaAdv -and $ollamaAdv.Length -gt 0 -and $ollamaAdv -match 'defaults to 127') {
                [void]$rec.Add($ollamaAdv)
            }
            [void]$rec.Add("Use SecretManagement, Windows Credential Manager, or a user-scoped profile snippet that runs only in non-elevated shells.")
            [void]$rec.Add("Do not include API keys in windo --preserve-env lists; they can be copied into the elevated child environment.")
            [void]$rec.Add("See docs/ai-bridge.md for OpenAI CLI, Ollama, agents, and IDE integration patterns.")
        }
        $exitPayload = 0
        if ($issues.Count -gt 0) { $exitPayload = 3 }
        $pl = @{
            subcommand = $sub
            elevated = [bool]$snap.elevated
            processSetNames = $snap.processSetNames
            userSetNames = $snap.userSetNames
            machineSetNames = $snap.machineSetNames
            ollamaSetNames = $snap.ollamaSetNames
            ollamaAdvisory = $ollamaAdv
            processEnvFlags = $snap.process
            userEnvFlags = $snap.user
            machineEnvFlags = $snap.machine
            issues = @($issues)
            recommendations = $(if ($sub -eq "doctor") { @($rec) } else { @() })
            docHint = "docs/ai-bridge.md"
            exitCode = $(if ($sub -eq "status") { 0 } else { $exitPayload })
        }
        if ($JsonOutput) { _emit_json "ai" $pl } else {
            Write-Host "[windo] ai $sub â€” AI / local env names only (values never shown)" -ForegroundColor Cyan
            Write-Host "  Elevated         : $($snap.elevated)" -ForegroundColor DarkGray
            Write-Host "  Ollama (set)     : $(if ($snap.ollamaSetNames.Count) { $snap.ollamaSetNames -join ', ' } else { '(none)' })" -ForegroundColor DarkGray
            Write-Host "  Process (set)    : $(if ($snap.processSetNames.Count) { $snap.processSetNames -join ', ' } else { '(none)' })"
            Write-Host "  User scope (set) : $(if ($snap.userSetNames.Count) { $snap.userSetNames -join ', ' } else { '(none)' })"
            Write-Host "  Machine (set)    : $(if ($snap.machineSetNames.Count) { $snap.machineSetNames -join ', ' } else { '(none)' })"
            foreach ($iss in $issues) { Write-Host "  ! $iss" -ForegroundColor Yellow }
            if ($sub -eq "doctor") { foreach ($r in $rec) { Write-Host "  â†’ $r" -ForegroundColor DarkGray } }
        }
        _windo_set_exit $(if ($sub -eq "status") { 0 } else { $exitPayload })
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "repair") {
        $sub = "all"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
        if ($sub -notin @('all', 'keybindings')) {
            if ($JsonOutput) { _emit_json "repair" @{ error = "expected all or keybindings"; sub = $sub; exitCode = 2 } } else { Write-Host "[windo] repair: expected all | keybindings  (got: $sub)" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
        $res = _windo_keybindings_safe_reset_apply
        if (-not $res.ok) {
            if ($JsonOutput) { _emit_json "repair" @{ error = $res.error; exitCode = 2 } } else { Write-Host "[windo] repair: $($res.error)" -ForegroundColor Red }
            _windo_set_exit 2
            return
        }
        $pol = $res.policy
        $hints = @(
            "Open a new terminal or run:  . `$PROFILE  â€” so your profile block matches prefs.",
            "From a normal (non-elevated) window:  windo install-latest  â€” refreshes the embedded profile from v6 when you are behind."
        )
        if ($JsonOutput) {
            _emit_json "repair" @{
                actions = @('keybindings-safe-reset')
                scope = $sub
                keybindingsPolicy = $pol
                profilePath = $PROFILE
                prefsFile = $PrefsFile
                hints = $hints
                exitCode = 0
            }
        } else {
            Write-Host "[windo] repair ($sub): keybindings safe-reset â€” legacy WINDO chords cleared this session; prefix preference Alt+w." -ForegroundColor Green
            Write-Host "  Effective: $(if ($pol.enabled) { $pol.chord } else { '(disabled)' }) (source=$($pol.chordSource))" -ForegroundColor DarkGray
            foreach ($h in $hints) { Write-Host "  â†’ $h" -ForegroundColor DarkGray }
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "keybindings") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }

        if ($sub -eq "doctor") {
            try {
                Import-Module PSReadLine -ErrorAction Stop | Out-Null
                $null = [Microsoft.PowerShell.PSConsoleReadLine]
            } catch {
                if ($JsonOutput) { _emit_json "keybindings" @{ error = "PSReadLine not available: $($_.Exception.Message)"; exitCode = 2 } } else { Write-Host "[windo] keybindings doctor: PSReadLine not available." -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = _windo_resolve_keybinding_policy
            $checks = [System.Collections.ArrayList]@()
            if ($policy.enabled -and -not [string]::IsNullOrWhiteSpace($policy.chord)) {
                [void]$checks.Add((_windo_keybinding_inspect_chord_for_doctor -Chord $policy.chord -Role 'prefix'))
            } else {
                [void]$checks.Add([pscustomobject]@{ chord = $policy.chord; role = 'prefix'; handlerPresent = $false; looksLikeWindoBinding = $false; scriptPreview = $null; advisory = "WINDO keybindings disabled or no chord configured in policy." })
            }
            [void]$checks.Add((_windo_keybinding_inspect_chord_for_doctor -Chord 'Shift+Enter' -Role 'run'))
            [void]$checks.Add((_windo_keybinding_inspect_chord_for_doctor -Chord 'Alt+Enter' -Role 'run'))
            $anyAdv = @($checks | Where-Object { $null -ne $_.advisory -and -not [string]::IsNullOrWhiteSpace([string]$_.advisory) })
            if ($JsonOutput) {
                _emit_json "keybindings" @{
                    subcommand = 'doctor'
                    policy = $policy
                    chordChecks = @($checks)
                    anyAdvisory = [bool]($anyAdv.Count -gt 0)
                    exitCode = 0
                }
            } else {
                Write-Host "[windo] keybindings doctor (advisory â€” heuristic only)" -ForegroundColor Cyan
                foreach ($c in $checks) {
                    $st = if ($c.looksLikeWindoBinding) { 'ok' } else { 'review' }
                    Write-Host "  [$st] $($c.role) $($c.chord)" -ForegroundColor $(if ($c.looksLikeWindoBinding) { 'Green' } else { 'Yellow' })
                    if ($c.advisory) { Write-Host "       $($c.advisory)" -ForegroundColor DarkYellow }
                }
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "status") {
            $policy = _windo_resolve_keybinding_policy
            $chords = @('w', 'w,w', 'Alt+w', 'Shift+Enter', 'Alt+Enter')
            if ($policy.enabled -and ($null -ne $policy.chord) -and ($chords -notcontains $policy.chord)) {
                $chords = @($policy.chord) + $chords
            }
            if ($policy.enabled -and $policy.autoDetectAlt -and $policy.fallbackChord) {
                $fallbackChord = $policy.fallbackChord
                if ($chords -notcontains $fallbackChord) { $chords = @($fallbackChord) + $chords }
            }
            $registered = [System.Collections.ArrayList]@()
            $hasRh = Get-Command Get-PSReadLineKeyHandler -ErrorAction SilentlyContinue
            $effectiveChord = $null
            foreach ($c in ($chords | Select-Object -Unique)) {
                $isReg = $false
                if ($hasRh) {
                    try {
                        $handler = Get-PSReadLineKeyHandler -Chord $c -ErrorAction Stop
                        if ($null -ne $handler) { $isReg = $true }
                    } catch { }
                }
                if ($isReg -and $null -eq $effectiveChord) { $effectiveChord = $c }
                [void]$registered.Add([ordered]@{
                    chord = $c
                    registered = $isReg
                    matchesPolicy = $(if ($policy.enabled -and $policy.chord -eq $c) { $true } else { $false })
                })
            }
            if ($JsonOutput) {
                _emit_json "keybindings" @{
                    profilePath = $PROFILE
                    prefsFile = $PrefsFile
                    policy = $policy
                    bindings = @($registered)
                    effectiveChord = $effectiveChord
                    psReadLineAvailable = [bool]$hasRh
                    exitCode = 0
                }
            } else {
                Write-Host "[windo] PSReadLine keybindings policy" -ForegroundColor Cyan
                Write-Host "  Policy enabled : $($policy.enabled)" -ForegroundColor DarkGray
                Write-Host "  Effective      : $(if ($policy.enabled) { if ($effectiveChord) { $effectiveChord } else { '(none)' } } else { '(disabled)' })" -ForegroundColor DarkGray
                if ($policy.enabled) {
                    Write-Host "  Source         : chord=$($policy.chordSource), prefs=$($PrefsFile)" -ForegroundColor DarkGray
                    if ($policy.autoDetected) { Write-Host "  Auto-detect    : $($policy.autoDetectedReason)" -ForegroundColor DarkGray }
                } else {
                    Write-Host "  Disabled by   : $(if ($policy.disabledSource) { $policy.disabledSource } else { 'runtime default' })" -ForegroundColor DarkGray
                }
                Write-Host "  Registered handlers:"
                foreach ($row in $registered) {
                    Write-Host ("  {0,-12} registered={1,-5} policy={2}" -f $row.chord, $row.registered, $row.matchesPolicy) -ForegroundColor DarkGray
                }
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "set") {
            $setChord = $null
            $si = 2
            while ($si -lt $Command.Count) {
                $arg = [string]$Command[$si]
                if ($arg -eq '--chord') {
                    if ($si + 1 -ge $Command.Count) {
                        Write-Host "[windo] keybindings set: --chord requires a value" -ForegroundColor Red
                        _windo_set_exit 2
                        return
                    }
                    $setChord = [string]$Command[$si + 1]
                    $si += 2
                    continue
                }
                if ($arg -like '--chord=*') {
                    $setChord = $arg.Substring(8)
                    $si++
                    continue
                }
                Write-Host "[windo] keybindings set: unknown argument '$arg'" -ForegroundColor Yellow
                Write-Host "  Usage: windo keybindings set --chord <windo prefix chord>" -ForegroundColor DarkGray
                _windo_set_exit 2
                return
            }
            if ([string]::IsNullOrWhiteSpace($setChord)) {
                Write-Host "[windo] keybindings set: --chord is required" -ForegroundColor Yellow
                Write-Host "  Example: windo keybindings set --chord Alt+w" -ForegroundColor DarkGray
                _windo_set_exit 2
                return
            }
            $setChord = $setChord.Trim()
            if ($setChord -eq 'w,w') {
                Write-Host "[windo] Warning: 'w,w' can interfere with commands that start with 'w' (for example 'where', 'winget', 'wsl')." -ForegroundColor Yellow
                Write-Host "  For safer behavior, consider 'Alt+w' or a non-typing fallback chord." -ForegroundColor DarkGray
            }
            $map = _windo_read_windo_prefs_map
            $map['keybindingPrefixChord'] = $setChord
            $map['keybindingDisabled'] = $false
            if (-not (_windo_save_windo_prefs $map)) {
                Write-Host "[windo] keybindings set: could not update $PrefsFile" -ForegroundColor Red
                _windo_set_exit 2
                return
            }
            _windo_apply_runtime_keybindings | Out-Null
            $policy = _windo_resolve_keybinding_policy
            if ($JsonOutput) {
                _emit_json "keybindings" @{ action = "set"; chord = $setChord; profilePath = $PROFILE; prefsFile = $PrefsFile; policy = $policy; exitCode = 0 }
            } else {
                Write-Host "[windo] keybinding chord set and saved" -ForegroundColor Green
                Write-Host "  chord: $($policy.chord) (source=$($policy.chordSource))" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "disable") {
            $map = _windo_read_windo_prefs_map
            $map['keybindingDisabled'] = $true
            if (-not (_windo_save_windo_prefs $map)) {
                Write-Host "[windo] keybindings disable: could not update $PrefsFile" -ForegroundColor Red
                _windo_set_exit 2
                return
            }
            _windo_apply_runtime_keybindings | Out-Null
            $policy = _windo_resolve_keybinding_policy
            if ($JsonOutput) {
                _emit_json "keybindings" @{ action = "disable"; policy = $policy; profilePath = $PROFILE; prefsFile = $PrefsFile; exitCode = 0 }
            } else {
                Write-Host "[windo] keybindings disabled and saved." -ForegroundColor Green
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "enable") {
            $map = _windo_read_windo_prefs_map
            $map['keybindingDisabled'] = $false
            if (-not (_windo_save_windo_prefs $map)) {
                Write-Host "[windo] keybindings enable: could not update $PrefsFile" -ForegroundColor Red
                _windo_set_exit 2
                return
            }
            _windo_apply_runtime_keybindings | Out-Null
            $policy = _windo_resolve_keybinding_policy
            if ($JsonOutput) {
                _emit_json "keybindings" @{ action = "enable"; policy = $policy; profilePath = $PROFILE; prefsFile = $PrefsFile; exitCode = 0 }
            } else {
                Write-Host "[windo] keybindings enabled and restored." -ForegroundColor Green
                Write-Host "  chord: $($policy.chord) (source=$($policy.chordSource))" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "reset") {
            $map = _windo_read_windo_prefs_map
            if ($map.Contains("keybindingPrefixChord")) { $map.Remove("keybindingPrefixChord") }
            if ($map.Contains("keybindingDisabled")) { $map.Remove("keybindingDisabled") }
            if (-not (_windo_save_windo_prefs $map)) {
                Write-Host "[windo] keybindings reset: could not update $PrefsFile" -ForegroundColor Red
                _windo_set_exit 2
                return
            }
            _windo_apply_runtime_keybindings | Out-Null
            $policy = _windo_resolve_keybinding_policy
            if ($JsonOutput) {
                _emit_json "keybindings" @{ action = "reset"; policy = $policy; profilePath = $PROFILE; prefsFile = $PrefsFile; exitCode = 0 }
            } else {
                Write-Host "[windo] keybindings reset to host defaults (including vscode fallback)." -ForegroundColor Green
                Write-Host "  chord: $($policy.chord) (source=$($policy.chordSource))" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }

        if ($sub -eq "safe-reset") {
            $sr = _windo_keybindings_safe_reset_apply
            if (-not $sr.ok) {
                if ($JsonOutput) { _emit_json "keybindings" @{ action = "safe-reset"; error = $sr.error; exitCode = 2 } } else { Write-Host "[windo] keybindings safe-reset: $($sr.error)" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            $policy = $sr.policy
            if ($JsonOutput) {
                _emit_json "keybindings" @{ action = "safe-reset"; policy = $policy; profilePath = $PROFILE; prefsFile = $PrefsFile; exitCode = 0 }
            } else {
                Write-Host "[windo] keybindings safe-reset completed (legacy handlers removed, Alt+w preference reapplied)." -ForegroundColor Green
                Write-Host "  Effective: $(if ($policy.enabled) { $policy.chord } else { '(disabled)' }) (source=$($policy.chordSource))" -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }

        Write-Host "[windo] keybindings: expected status | doctor | set --chord <chord> | disable | enable | reset | safe-reset  (got: $sub)" -ForegroundColor Yellow
        _windo_set_exit 2
        return
    }

    if ($Command.Count -ge 1 -and ($Command[0] -eq "upgrade" -or $Command[0] -eq "install-latest")) {
        $forceInst = $false
        if ($Command.Count -gt 1) {
            foreach ($a in $Command[1..($Command.Count - 1)]) {
                $aa = [string]$a
                if ($aa -eq '--force' -or $aa -eq '-Force') { $forceInst = $true }
                else {
                    Write-Host "[windo] install-latest: unknown argument '$aa' (use --force to skip confirmation)" -ForegroundColor Yellow
                    _windo_set_exit 2
                    return
                }
            }
        }
        _windo_run_genisis_installer -ForceContinue:$forceInst -NonInteractive:$NonInteractive
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "trace") {
        if ($Command.Count -lt 2) { Write-Host "[windo] Usage: windo trace <RequestId> | windo trace --id <RequestId>" -ForegroundColor Yellow; return }
        $tid = $null
        if ($Command.Count -ge 3 -and $Command[1] -eq '--id') { $tid = [string]$Command[2].Trim() }
        else { $tid = [string]$Command[1].Trim() }
        if ([string]::IsNullOrWhiteSpace($tid)) { Write-Host "[windo] Usage: windo trace <RequestId> | windo trace --id <RequestId>" -ForegroundColor Yellow; return }
        $allE = @(_parse_log_entries)
        $found = $null
        for ($ti = $allE.Count - 1; $ti -ge 0; $ti--) {
            if ([string]$allE[$ti].RequestId -eq $tid) { $found = $allE[$ti]; break }
        }
        $runnerHint = ""
        if (Test-Path $RunnerLast) {
            $rcontent = Get-Content -Raw -Path $RunnerLast -ErrorAction SilentlyContinue
            if ($rcontent -and $rcontent -match [regex]::Escape($tid)) { $runnerHint = "(RequestId appears in runner log tail)" }
        }
        $pl = @{ requestId = $tid; logEntry = $found; runnerLogNote = $runnerHint }
        if ($JsonOutput) { _emit_json "trace" $pl; return }
        if (-not $found) {
            Write-Host "[windo] No audit log entry for RequestId: $tid" -ForegroundColor Yellow
            if ($runnerHint) { Write-Host "  $runnerHint" -ForegroundColor DarkGray }
            Write-Host "  Try: windo log -n 50" -ForegroundColor DarkGray
            return
        }
        Write-Host "[windo] Trace for RequestId=$tid" -ForegroundColor Cyan
        Write-Host "  Time     : $($found.Timestamp)"
        Write-Host "  Command  : $($found.Command)"
        Write-Host "  ExitCode : $($found.ExitCode)"
        Write-Host "  Elevation: $($found.Elevation)"
        if ($found.PSObject.Properties.Name -contains 'DurationMs') { Write-Host "  Duration : $($found.DurationMs)ms" }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "last") {
        if (!(Test-Path $LastCmdFile)) {
            if ($JsonOutput) { _emit_json "last" @{ lastCommand = $null; meta = $null } } else { Write-Host "[windo] No previous command stored." -ForegroundColor Yellow }
            return
        }
        $lc = (Get-Content -Raw -Path $LastCmdFile).Trim()
        $mm = _read_last_meta
        if ($JsonOutput) { _emit_json "last" @{ lastCommand = $lc; meta = $mm }; return }
        Write-Host "[windo] Last stored command (for windo !! / replay):" -ForegroundColor Cyan
        Write-Host $lc
        if ($mm) {
            if ($mm.PSObject.Properties.Name -contains 'lastRequestId') { Write-Host "  RequestId : $($mm.lastRequestId)" -ForegroundColor DarkGray }
            if ($mm.PSObject.Properties.Name -contains 'storedAt') { Write-Host "  Stored at : $($mm.storedAt)" -ForegroundColor DarkGray }
        }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "stats") {
        $sinceStr = $null
        $lastDaysN = $null
        $lastDaysSeen = $false
        $sxi = 1
        while ($sxi -lt $Command.Count) {
            $a = [string]$Command[$sxi]
            if ($a -eq "--since") {
                if ($sxi + 1 -ge $Command.Count) {
                    Write-Host "[windo] stats: --since requires YYYY-MM-DD" -ForegroundColor Red
                    _windo_set_exit 2
                    return
                }
                $sinceStr = [string]$Command[$sxi + 1]
                $sxi += 2
                continue
            }
            if ($a -like "--since=*") {
                $sinceStr = $a.Substring(8).Trim()
                $sxi++
                continue
            }
            if ($a -eq "--last-days") {
                $lastDaysSeen = $true
                if ($sxi + 1 -ge $Command.Count) {
                    Write-Host "[windo] stats: --last-days requires a positive integer" -ForegroundColor Red
                    _windo_set_exit 2
                    return
                }
                $rawLd = [string]$Command[$sxi + 1]
                $ldParsed = 0
                if (-not [int]::TryParse($rawLd, [ref]$ldParsed)) {
                    Write-Host "[windo] stats: invalid --last-days (use a positive integer, e.g. 7)" -ForegroundColor Red
                    _windo_set_exit 2
                    return
                }
                $lastDaysN = $ldParsed
                $sxi += 2
                continue
            }
            if ($a -like "--last-days=*") {
                $lastDaysSeen = $true
                $vv = $a -replace '^--last-days=', ''
                $ldParsed = 0
                if (-not [int]::TryParse($vv, [ref]$ldParsed)) {
                    Write-Host "[windo] stats: invalid --last-days (use a positive integer, e.g. 7)" -ForegroundColor Red
                    _windo_set_exit 2
                    return
                }
                $lastDaysN = $ldParsed
                $sxi++
                continue
            }
            $sxi++
        }
        $sinceDt = $null
        if ($sinceStr) {
            try {
                $sinceDt = [DateTime]::Parse($sinceStr.Trim(), [System.Globalization.CultureInfo]::InvariantCulture).Date
            } catch {
                Write-Host "[windo] stats: invalid --since (use YYYY-MM-DD)" -ForegroundColor Red
                _windo_set_exit 2
                return
            }
        }
        if ($lastDaysSeen -and $null -ne $lastDaysN -and [int]$lastDaysN -le 0) {
            Write-Host "[windo] stats: --last-days must be a positive integer" -ForegroundColor Red
            _windo_set_exit 2
            return
        }
        if ($null -ne $sinceDt -and $lastDaysSeen) {
            Write-Host "[windo] stats: use only one of --since or --last-days" -ForegroundColor Yellow
            _windo_set_exit 2
            return
        }
        if (Test-Path $LogFile) {
            $lcWarn = _windo_log_line_count $LogFile
            if ($lcWarn -gt 100000 -and $null -eq $sinceDt -and $null -eq $lastDaysN) {
                Write-Host "[windo] Warning: large audit log (~$lcWarn lines); stats may use significant memory. Consider rotation (windo cleanup), --since/--last-days, or archiving." -ForegroundColor DarkYellow
            }
        }
        $entries = @(_parse_log_entries)
        $entries = @(_windo_filter_entries_by_time $entries $sinceDt $lastDaysN)
        $okc = 0; $fail = 0; $totalMs = 0; $withDur = 0
        foreach ($e in $entries) {
            try { $ec = [int]$e.ExitCode } catch { $ec = -1 }
            if ($ec -eq 0) { $okc++ } else { $fail++ }
            if ($e.PSObject.Properties.Name -contains 'DurationMs') { $totalMs += [int]$e.DurationMs; $withDur++ }
        }
        $avg = if ($withDur -gt 0) { [math]::Round($totalMs / $withDur) } else { $null }
        if ($JsonOutput) {
            $cat = @{ SUCCESS = 0; NONZERO = 0; ELEVATION_FAILED = 0; OTHER = 0 }
            foreach ($e in $entries) {
                try { $ec = [int]$e.ExitCode } catch { $ec = -999 }
                $el = "OTHER"
                if ($e.PSObject.Properties.Name -contains 'Elevation' -and [string]$e.Elevation -eq 'FAILED') { $el = 'ELEVATION_FAILED' }
                elseif ($ec -eq 0) { $el = 'SUCCESS' }
                elseif ($ec -ne -999) { $el = 'NONZERO' }
                $cat[$el] = [int]$cat[$el] + 1
            }
            _emit_json "stats" @{
                entryCount = $entries.Count; successCount = $okc; nonZeroExitCount = $fail; avgDurationMs = $avg; logFile = $LogFile; categories = $cat
                filterSince = $(if ($sinceStr) { $sinceStr } else { $null })
                filterLastDays = $(if ($lastDaysSeen) { $lastDaysN } else { $null })
                exitCode = 0
            }
            _windo_set_exit 0
            return
        }
        Write-Host "[windo] Audit log stats" -ForegroundColor Cyan
        if ($sinceStr) { Write-Host "  Filter --since : $sinceStr" -ForegroundColor DarkGray }
        if ($null -ne $lastDaysN) { Write-Host "  Filter --last-days : $lastDaysN" -ForegroundColor DarkGray }
        Write-Host "  Entries        : $($entries.Count)"
        Write-Host "  Exit code 0    : $okc"
        Write-Host "  Non-zero exit  : $fail"
        $catT = @{ SUCCESS = 0; NONZERO = 0; ELEVATION_FAILED = 0; OTHER = 0 }
        foreach ($e in $entries) {
            try { $ec = [int]$e.ExitCode } catch { $ec = -999 }
            $el = "OTHER"
            if ($e.PSObject.Properties.Name -contains 'Elevation' -and [string]$e.Elevation -eq 'FAILED') { $el = 'ELEVATION_FAILED' }
            elseif ($ec -eq 0) { $el = 'SUCCESS' }
            elseif ($ec -ne -999) { $el = 'NONZERO' }
            $catT[$el] = [int]$catT[$el] + 1
        }
        Write-Host "  Categories     : SUCCESS=$($catT['SUCCESS']) NONZERO=$($catT['NONZERO']) ELEVATION_FAILED=$($catT['ELEVATION_FAILED']) OTHER=$($catT['OTHER'])" -ForegroundColor DarkGray
        if ($null -ne $avg) { Write-Host "  Avg duration   : ${avg}ms (entries with DurationMs)" -ForegroundColor DarkGray }
        Write-Host "  Log file       : $LogFile"
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "history") {
        $hn = 50
        if ($Command.Count -ge 3 -and $Command[1] -eq "-n") { [int]$hn = $Command[2] }
        if (Test-Path $LogFile) {
            $lcH = _windo_log_line_count $LogFile
            if ($lcH -gt 100000) {
                Write-Host "[windo] Warning: large audit log (~$lcH lines); history decrypts the full log. See docs/performance.md." -ForegroundColor DarkYellow
            }
        }
        $all = @(_parse_log_entries)
        $slice = @($all | Select-Object -Last $hn)
        if ($JsonOutput) { _emit_json "history" @{ entries = $slice; count = $slice.Count }; return }
        Write-Host "[windo] History (last $hn entries)" -ForegroundColor Cyan
        foreach ($e in $slice) {
            Write-Host "  $($e.Timestamp)  ex=$($e.ExitCode)  $($e.Command)" -ForegroundColor Gray
        }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "report") {
        $repOut = Join-Path (Join-Path $HOME "Documents") ("windo\windo_report_{0}.html" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        $rix = 0
        while ($rix -lt $Command.Count) {
            if (($Command[$rix] -eq '-o' -or $Command[$rix] -eq '--output') -and ($rix + 1) -lt $Command.Count) {
                $repOut = $Command[$rix + 1]
                break
            }
            $rix++
        }
        $idr = _integrity_status
        if (Test-Path $LogFile) {
            $lcR = _windo_log_line_count $LogFile
            if ($lcR -gt 100000) {
                Write-Host "[windo] Warning: large audit log (~$lcR lines); report generation decrypts all entries. See docs/performance.md." -ForegroundColor DarkYellow
            }
        }
        $allRep = @(_parse_log_entries)
        $ents = @($allRep | Select-Object -Last 30)
        $okc = 0; $nz = 0
        $cat = @{ SUCCESS = 0; NONZERO = 0; ELEVATION_FAILED = 0; OTHER = 0 }
        foreach ($e in $allRep) {
            try { $ec = [int]$e.ExitCode } catch { $ec = -999 }
            if ($ec -eq 0) { $okc++ } else { $nz++ }
            $el = "OTHER"
            if ($e.PSObject.Properties.Name -contains 'Elevation' -and [string]$e.Elevation -eq 'FAILED') { $el = 'ELEVATION_FAILED' }
            elseif ($ec -eq 0) { $el = 'SUCCESS' }
            elseif ($ec -ne -999) { $el = 'NONZERO' }
            $cat[$el] = [int]$cat[$el] + 1
        }
        $levClass = @{ OK = 'ok'; DRIFT = 'bad'; TAMPERED = 'bad'; UNKNOWN = 'bad' }
        $maxCat = [Math]::Max(1, ($cat.Values | Measure-Object -Maximum).Maximum)
        $sb = [System.Text.StringBuilder]::new()
        $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO audit report</title>')
        $null = $sb.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;background:#f5f7fa;color:#172033;}h1{border-bottom:1px solid #d6dce5;padding-bottom:8px}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px;max-width:1200px}.card{background:white;border:1px solid #dde3ea;border-radius:8px;padding:12px}.k{font-size:12px;text-transform:uppercase;color:#667085}.v{font-size:26px;font-weight:700;margin-top:4px}table{border-collapse:collapse;width:100%;max-width:1200px;background:white;} th,td{border-bottom:1px solid #e6eaf0;padding:8px;text-align:left;} th{background:#eef2f6;} .ok{color:#067647;} .bad{color:#b42318;} .bar{height:12px;background:#e6eaf0;border-radius:3px;overflow:hidden}.fill{height:100%;background:#2563eb} code{background:#eef2f6;padding:2px 4px;border-radius:4px;}</style></head><body>')
        $null = $sb.AppendLine(("<h1>WINDO audit report</h1><p>Generated {0} on {1}</p><p>Local-only HTML; may include sensitive command text. Choose elevation before execution.</p>" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), [System.Net.Dns]::GetHostName()))
        $null = $sb.AppendLine(("<h2>Summary</h2><div class='cards'><div class='card'><div class='k'>Total entries</div><div class='v'>{0}</div></div><div class='card'><div class='k'>Exit code 0</div><div class='v ok'>{1}</div></div><div class='card'><div class='k'>Non-zero exit</div><div class='v bad'>{2}</div></div></div>" -f $allRep.Count, $okc, $nz))
        $null = $sb.AppendLine("<h2>Categories</h2><table><tr><th>Category</th><th>Count</th><th>Visual</th></tr>")
        foreach ($name in @('SUCCESS','NONZERO','ELEVATION_FAILED','OTHER')) {
            $pct = [Math]::Round(([int]$cat[$name] / [double]$maxCat) * 100)
            $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td><div class='bar'><div class='fill' style='width:{2}%'></div></div></td></tr>" -f $name, [int]$cat[$name], $pct))
        }
        $null = $sb.AppendLine("</table>")
        $null = $sb.AppendLine(("<h2>Version</h2><p>{0}</p>" -f (_html_escape $WindoVersion)))
        $null = $sb.AppendLine(("<h2>Paths</h2><table><tr><td>SecureDir</td><td><code>{0}</code></td></tr><tr><td>Log</td><td><code>{1}</code></td></tr><tr><td>Manifest</td><td><code>{2}</code></td></tr></table>" -f (_html_escape $SecureDir), (_html_escape $LogFile), (_html_escape $ManifestFile)))
        $ovCls = if ($idr.OverallLevel -eq 'OK') { 'ok' } else { 'bad' }
        $null = $sb.AppendLine(("<h2>Integrity</h2><p>Overall: <strong class='{0}'>{1}</strong></p><table><tr><th>Component</th><th>Level</th><th>Match</th></tr><tr><td>Runner</td><td class='{2}'>{3}</td><td>{4}</td></tr><tr><td>Self-update</td><td class='{5}'>{6}</td><td>{7}</td></tr></table>" -f $ovCls, (_html_escape $idr.OverallLevel), $levClass[$idr.RunnerLevel], (_html_escape $idr.RunnerLevel), $(if ($idr.RunnerMatch) { 'yes' } else { 'no' }), $levClass[$idr.UpdaterLevel], (_html_escape $idr.UpdaterLevel), $(if ($idr.UpdaterMatch) { 'yes' } else { 'no' })))
        $null = $sb.AppendLine("<h2>Recent audit entries</h2><table><tr><th>Time</th><th>Exit</th><th>Elevation</th><th>Command</th></tr>")
        foreach ($e in $ents) {
            $cmdStr = [string]$e.Command
            if ($cmdStr.Length -gt 200) { $cmdStr = $cmdStr.Substring(0, 200) + "..." }
            $elev = ""
            if ($e.PSObject.Properties.Name -contains 'Elevation') { $elev = [string]$e.Elevation }
            $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>" -f (_html_escape [string]$e.Timestamp), (_html_escape [string]$e.ExitCode), (_html_escape $elev), (_html_escape $cmdStr)))
        }
        $null = $sb.AppendLine("</table><p>Run <code>windo verify</code> for full chain validation.</p></body></html>")
        $dir = Split-Path $repOut -Parent
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($repOut, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
        Write-Host "[windo] Report written: $repOut" -ForegroundColor Green
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "export") {
        $expZip = Join-Path (Join-Path $HOME "Documents\windo\exports") ("windo_export_{0}.zip" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        $expN = 30
        $expRedact = $false
        $ei = 1
        while ($ei -lt $Command.Count) {
            $tok = [string]$Command[$ei]
            if (($tok -eq '-o' -or $tok -eq '--output') -and ($ei + 1) -lt $Command.Count) {
                $expZip = $Command[$ei + 1]
                $ei += 2
                continue
            }
            if ($tok -eq '-n' -and ($ei + 1) -lt $Command.Count) {
                try { $expN = [int]$Command[$ei + 1] } catch { $expN = 30 }
                $ei += 2
                continue
            }
            if ($tok -eq '-Redact' -or $tok -eq '--redact') {
                $expRedact = $true
                $ei += 1
                continue
            }
            $ei++
        }
        $expDir = Split-Path $expZip -Parent
        if (!(Test-Path $expDir)) { New-Item -ItemType Directory -Path $expDir -Force | Out-Null }
        if (Test-Path $LogFile) {
            $lcE = _windo_log_line_count $LogFile
            if ($lcE -gt 100000) {
                Write-Host "[windo] Warning: large audit log (~$lcE lines); export decrypts all entries for counts. See docs/performance.md." -ForegroundColor DarkYellow
            }
        }
        $ix = _integrity_status
        $lm = _read_last_meta
        $pwshwPath = (Get-Command pwshw.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
        $mt = $false; $ut = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mt = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $ut = $true } catch {}
        $doctorPayload = @{
            secureDir = $SecureDir
            logFile = $LogFile
            taskMain = $TaskName
            taskUpdate = $TaskUpdate
            pwshwExe = $pwshwPath
            mainTaskOk = $mt
            updateTaskOk = $ut
            runnerPresent = (Test-Path $RunnerPath)
            runnerLogPresent = (Test-Path $RunnerLast)
            updateLogPresent = (Test-Path $UpdateLast)
            lastMeta = $lm
            integrity = @{ overallLevel = $ix.OverallLevel; runnerLevel = $ix.RunnerLevel; updaterLevel = $ix.UpdaterLevel }
        }
        $integrityPayload = @{
            manifestPath = $ManifestFile
            overallLevel = $ix.OverallLevel
            runner = @{ expected = $ix.RunnerExpected; actual = $ix.RunnerActual; match = $ix.RunnerMatch; level = $ix.RunnerLevel }
            selfUpdate = @{ expected = $ix.UpdaterExpected; actual = $ix.UpdaterActual; match = $ix.UpdaterMatch; level = $ix.UpdaterLevel }
        }
        $allEx = @(_parse_log_entries)
        $sliceEx = @($allEx | Select-Object -Last $expN)
        $auditPayload = @{ entryCount = $allEx.Count; included = $sliceEx.Count; entries = $sliceEx }
        if ($expRedact) {
            $doctorPayload = _redact_export_deep $doctorPayload
            $integrityPayload = _redact_export_deep $integrityPayload
            $auditPayload = _redact_export_deep $auditPayload
        }
        $tmpRoot = Join-Path $env:TEMP ("windo_export_" + [Guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
        try {
            if (Test-Path $ManifestFile) { Copy-Item -LiteralPath $ManifestFile -Destination (Join-Path $tmpRoot "windo_manifest.json") -Force }
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText((Join-Path $tmpRoot "doctor.json"), ((_json_envelope "doctor" $doctorPayload) | ConvertTo-Json -Depth 14), $utf8)
            [System.IO.File]::WriteAllText((Join-Path $tmpRoot "integrity.json"), ((_json_envelope "integrity" $integrityPayload) | ConvertTo-Json -Depth 14), $utf8)
            [System.IO.File]::WriteAllText((Join-Path $tmpRoot "audit_excerpt.json"), ((_json_envelope "export" $auditPayload) | ConvertTo-Json -Depth 14), $utf8)
            if (Test-Path $expZip) { Remove-Item -LiteralPath $expZip -Force }
            try {
                Compress-Archive -Path (Join-Path $tmpRoot '*') -DestinationPath $expZip -Force
            } catch {
                if ($JsonOutput) {
                    _emit_json "export" @{ error = [string]$_.Exception.Message; exitCode = 2 }
                    _windo_set_exit 2
                } else {
                    Write-Host "[windo] Export failed: $($_.Exception.Message)" -ForegroundColor Red
                }
                return
            }
        } finally {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (!(Test-Path -LiteralPath $expZip)) {
            if ($JsonOutput) {
                _emit_json "export" @{ error = "zip file was not created"; exitCode = 2 }
                _windo_set_exit 2
            } else {
                Write-Host "[windo] Export did not produce a zip file." -ForegroundColor Red
            }
            return
        }
        $len = (Get-Item -LiteralPath $expZip).Length
        if ($JsonOutput) {
            _emit_json "export" @{
                zipPath = $expZip
                sizeBytes = [int64]$len
                redacted = [bool]$expRedact
                auditExcerptLimit = [int]$expN
                auditTotalEntries = [int]$allEx.Count
                auditIncludedInExcerpt = [int]$sliceEx.Count
                exitCode = 0
            }
            _windo_set_exit 0
            return
        }
        $redactNote = if ($expRedact) { " (--redact: paths in JSON strings masked)" } else { "" }
        Write-Host "[windo] Export bundle written (may contain sensitive command text):$redactNote" -ForegroundColor Yellow
        Write-Host "  $expZip  ($len bytes)" -ForegroundColor Green
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "integrity") {
        $i = _integrity_status
        $ixExit = 0
        if ($i.OverallLevel -eq "OK") { $ixExit = 0 }
        elseif ($i.OverallLevel -eq "UNKNOWN") { $ixExit = 6 }
        else { $ixExit = 3 }
        if ($JsonOutput) {
            _emit_json "integrity" @{
                manifestPath = $ManifestFile
                overallLevel = $i.OverallLevel
                exitCode = $ixExit
                runner = @{ expected = $i.RunnerExpected; actual = $i.RunnerActual; match = $i.RunnerMatch; level = $i.RunnerLevel }
                selfUpdate = @{ expected = $i.UpdaterExpected; actual = $i.UpdaterActual; match = $i.UpdaterMatch; level = $i.UpdaterLevel }
            }
            _windo_set_exit $ixExit
            return
        }
        Write-Host "[windo] Integrity (levels: OK | DRIFT | TAMPERED | UNKNOWN)" -ForegroundColor Cyan
        Write-Host "  Manifest : $ManifestFile" -ForegroundColor DarkGray
        Write-Host "  Overall  : $($i.OverallLevel)"
        Write-Host "  Runner   : $($i.RunnerLevel)  (expected $($i.RunnerExpected))"
        Write-Host "  Actual   : $($i.RunnerActual)"
        Write-Host "  Self-upd : $($i.UpdaterLevel)  (expected $($i.UpdaterExpected))"
        Write-Host "  Actual   : $($i.UpdaterActual)"
        if ($i.OverallLevel -ne "OK") { Write-Host "  Next: reinstall windo_install.ps1 elevated or 'windo self-update' after fixing tasks." -ForegroundColor Yellow }
        _windo_set_exit $ixExit
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "self-update") {
        if ($DryRun) {
            Write-Host "[windo] DRY-RUN: would start scheduled task '$TaskUpdate' (no elevation, no task run)" -ForegroundColor Yellow
            return
        }
        try {
            $before = $null
            if (Test-Path $UpdateLast) { $before = (Get-Item $UpdateLast).LastWriteTime }
            Start-ScheduledTask -TaskName $TaskUpdate | Out-Null
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $selfUpdateMotionProfile = _windo_resolve_motion_profile_name -Context "self-update" -RequestedProfile "standard"
            $selfUpdateFrameDelay = _windo_motion_interval_ms $selfUpdateMotionProfile
            $suFrame = 0
            $suLabel = "[windo] Self-update running..."
            while ($sw.Elapsed.TotalSeconds -lt 10) {
                if (Test-Path $UpdateLast) {
                    $current = (Get-Item $UpdateLast).LastWriteTime
                    $content = Get-Content -Raw -Path $UpdateLast -ErrorAction SilentlyContinue
                    if (($before -eq $null -or $current -gt $before) -and $content -match 'SELF-UPDATE END') { break }
                }
                _windo_spinner_line $suLabel $suFrame $selfUpdateMotionProfile
                $suFrame = ($suFrame + 1) % 4
                Start-Sleep -Milliseconds $selfUpdateFrameDelay
            }
            if (_windo_spinner_enabled) { _windo_clear_spinner_line ($suLabel.Length + 4) }
            Write-Host "[windo] Self-update triggered." -ForegroundColor Green
            if (Test-Path $UpdateLast) { Write-Host "[windo] Trace:" -ForegroundColor Yellow; Write-Host (Get-Content -Raw -Path $UpdateLast).TrimEnd() }
            else { Write-Host "[windo] Trace file not present after wait period." -ForegroundColor Yellow }
        } catch {
            Write-Host "[windo] Self-update failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "version") {
        $i = _integrity_status
        $mt = $false; $ut = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mt = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $ut = $true } catch {}
        if ($JsonOutput) {
            $lcJson = $null
            if (Test-Path $LastCmdFile) { $lcJson = (Get-Content -Raw $LastCmdFile).Trim() }
            $mm = _read_last_meta
            _emit_json "version" @{
                profile = $PROFILE
                runnerHash = (_file_hash $RunnerPath)
                updaterHash = (_file_hash $UpdatePath)
                logFile = $LogFile
                lastCommand = $lcJson
                lastMeta = $mm
                integrity = @{ overallLevel = $i.OverallLevel; runnerLevel = $i.RunnerLevel; updaterLevel = $i.UpdaterLevel }
                mainTaskPresent = $mt
                updateTaskPresent = $ut
            }
            return
        }
        Write-Host "[windo] Version report" -ForegroundColor Cyan
        Write-Host "  Version      : $WindoVersion"
        Write-Host "  Profile      : $PROFILE"
        Write-Host "  Runner hash  : $(_file_hash $RunnerPath)"
        Write-Host "  Updater hash : $(_file_hash $UpdatePath)"
        Write-Host "  Log file     : $LogFile"
        Write-Host "  Last cmd     : $(if (Test-Path $LastCmdFile) { (Get-Content -Raw $LastCmdFile).Trim() } else { '(none)' })"
        Write-Host "  Integrity    : $($i.OverallLevel)  (runner $($i.RunnerLevel), self-update $($i.UpdaterLevel))" -ForegroundColor $(if ($i.OverallLevel -eq 'OK') { 'Green' } elseif ($i.OverallLevel -eq 'UNKNOWN') { 'DarkYellow' } else { 'Yellow' })
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; Write-Host "  Main task    : OK" -ForegroundColor Green } catch { Write-Host "  Main task    : MISSING" -ForegroundColor Red }
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; Write-Host "  Update task  : OK" -ForegroundColor Green } catch { Write-Host "  Update task  : MISSING" -ForegroundColor Red }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "doctor") {
        $pwshwPath = (Get-Command pwshw.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
        $mt = $false; $ut = $false
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; $mt = $true } catch {}
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; $ut = $true } catch {}
        if ($JsonOutput) {
            $ix = _integrity_status
            $lm = _read_last_meta
            $docExit = 0
            if (-not $mt -or -not (Test-Path $RunnerPath)) { $docExit = 2 }
            elseif ($ix.OverallLevel -eq "UNKNOWN") { $docExit = 6 }
            elseif ($ix.OverallLevel -ne "OK") { $docExit = 3 }
            _emit_json "doctor" @{
                secureDir = $SecureDir
                logFile = $LogFile
                taskMain = $TaskName
                taskUpdate = $TaskUpdate
                pwshwExe = $pwshwPath
                mainTaskOk = $mt
                updateTaskOk = $ut
                runnerPresent = (Test-Path $RunnerPath)
                runnerLogPresent = (Test-Path $RunnerLast)
                updateLogPresent = (Test-Path $UpdateLast)
                lastMeta = $lm
                exitCode = $docExit
                integrity = @{ overallLevel = $ix.OverallLevel; runnerLevel = $ix.RunnerLevel; updaterLevel = $ix.UpdaterLevel }
                envHints = @{
                    WINDO_NO_SPINNER = $(if ($env:WINDO_NO_SPINNER) { $env:WINDO_NO_SPINNER } else { $null })
                    WINDO_MOTION = $(if ($env:WINDO_MOTION) { $env:WINDO_MOTION } else { $null })
                    WINDO_RUNNER_TIMEOUT_MS = $(if ($env:WINDO_RUNNER_TIMEOUT_MS) { $env:WINDO_RUNNER_TIMEOUT_MS } else { $null })
                    WINDO_RUNNER_MAX_OUTPUT_BYTES = $(if ($env:WINDO_RUNNER_MAX_OUTPUT_BYTES) { $env:WINDO_RUNNER_MAX_OUTPUT_BYTES } else { $null })
                    WINDO_MAX_COMMAND_CHARS = $(if ($env:WINDO_MAX_COMMAND_CHARS) { $env:WINDO_MAX_COMMAND_CHARS } else { $null })
                    WINDO_SKIP_INSTALLER_SHA256 = $(if ($env:WINDO_SKIP_INSTALLER_SHA256) { $env:WINDO_SKIP_INSTALLER_SHA256 } else { $null })
                    WINDO_JSON_ENVELOPE = $(if ($env:WINDO_JSON_ENVELOPE) { $env:WINDO_JSON_ENVELOPE } else { $null })
                    WINDO_PREFIX_CHORD = $(if ($env:WINDO_PREFIX_CHORD) { $env:WINDO_PREFIX_CHORD } else { $null })
                    WINDO_DISABLE_PSREADLINE_BINDINGS = $(if ($env:WINDO_DISABLE_PSREADLINE_BINDINGS) { $env:WINDO_DISABLE_PSREADLINE_BINDINGS } else { $null })
                    WINDO_AUTO_DETECT_ALT_BINDINGS = $(if ($env:WINDO_AUTO_DETECT_ALT_BINDINGS) { $env:WINDO_AUTO_DETECT_ALT_BINDINGS } else { $null })
                    WINDO_KEYBINDING_FALLBACK_CHORD = $(if ($env:WINDO_KEYBINDING_FALLBACK_CHORD) { $env:WINDO_KEYBINDING_FALLBACK_CHORD } else { $null })
                }
            }
            _windo_set_exit $docExit
            return
        }
        $ixd = _integrity_status
        $mdoc = _read_last_meta
        $docExitT = 0
        if (-not $mt -or -not (Test-Path $RunnerPath)) { $docExitT = 2 }
        elseif ($ixd.OverallLevel -eq "UNKNOWN") { $docExitT = 6 }
        elseif ($ixd.OverallLevel -ne "OK") { $docExitT = 3 }
        Write-Host "[windo] Doctor (paths, tasks, integrity levels)" -ForegroundColor Cyan
        Write-Host "  SecureDir : $SecureDir"
        Write-Host "  LogFile   : $LogFile"
        Write-Host "  TaskMain  : $TaskName"
        Write-Host "  TaskUpd   : $TaskUpdate"
        Write-Host "  Integrity : $($ixd.OverallLevel)  (runner $($ixd.RunnerLevel), self-update $($ixd.UpdaterLevel))"
        if ($mdoc -and $mdoc.PSObject.Properties.Name -contains 'lastRequestId') { Write-Host "  Last ReqId: $($mdoc.lastRequestId)" -ForegroundColor DarkGray }
        if ($pwshwPath) { Write-Host "  pwshw.exe : $pwshwPath" } else { Write-Host "  pwshw.exe : (not found)" }
        try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null; Write-Host "  MainTask  : OK" -ForegroundColor Green } catch { Write-Host "  MainTask  : MISSING (run installer elevated once)" -ForegroundColor Red }
        try { Get-ScheduledTask -TaskName $TaskUpdate -ErrorAction Stop | Out-Null; Write-Host "  UpdTask   : OK" -ForegroundColor Green } catch { Write-Host "  UpdTask   : MISSING (run installer elevated once)" -ForegroundColor Red }
        if (Test-Path $RunnerPath) { Write-Host "  Runner    : OK" -ForegroundColor Green } else { Write-Host "  Runner    : MISSING" -ForegroundColor Red }
        if (Test-Path $RunnerLast) { Write-Host "  RunnerLog : OK" -ForegroundColor Green } else { Write-Host "  RunnerLog : (none yet)" -ForegroundColor Yellow }
        if (Test-Path $UpdateLast) { Write-Host "  UpdLog    : OK" -ForegroundColor Green } else { Write-Host "  UpdLog    : (none yet)" -ForegroundColor Yellow }
        _warn_if_tampered
        Write-Host "  Env (optional overrides; unset = defaults)" -ForegroundColor DarkGray
        Write-Host "    WINDO_NO_SPINNER, WINDO_MOTION, WINDO_RUNNER_TIMEOUT_MS, WINDO_RUNNER_MAX_OUTPUT_BYTES" -ForegroundColor DarkGray
        Write-Host "    WINDO_MAX_COMMAND_CHARS, WINDO_SKIP_INSTALLER_SHA256, WINDO_JSON_ENVELOPE, WINDO_PREFIX_CHORD, WINDO_DISABLE_PSREADLINE_BINDINGS, WINDO_AUTO_DETECT_ALT_BINDINGS, WINDO_KEYBINDING_FALLBACK_CHORD  (see README / SECURITY)" -ForegroundColor DarkGray
        Write-Host "  Tip: 'windo config' for effective env; 'windo integrity' for hashes; 'windo verify' for audit chain." -ForegroundColor DarkGray
        Write-Host "  Exit code    : $docExitT  (`$global:WINDO_EXIT_CODE; 0=ok, 2=task/runner, 3=integrity, 6=unknown integrity)" -ForegroundColor DarkGray
        _windo_set_exit $docExitT
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "verify") {
        $vf = _windo_verify_log_state
        if ($JsonOutput) {
            _emit_json "verify" @{
                verifyOk = [bool]$vf.verifyOk
                physicalLines = [int]$vf.physicalLines
                error = $(if ($vf.error) { [string]$vf.error } else { $null })
                failureLine = $vf.failureLine
                exitCode = [int]$vf.exitCode
            }
            _windo_set_exit ([int]$vf.exitCode)
            return
        }
        if ($vf.verifyOk) {
            Write-Host "[windo] VERIFY: OK (hashes + chain intact)" -ForegroundColor Green
        } elseif ($vf.error -eq "no log file") {
            Write-Host "[windo] No log file found." -ForegroundColor Yellow
        } elseif ($vf.error -eq "log empty") {
            Write-Host "[windo] Log file is empty." -ForegroundColor Yellow
        } else {
            Write-Host "[windo] VERIFY FAILED at line $($vf.failureLine): $($vf.error)" -ForegroundColor Red
        }
        _windo_set_exit ([int]$vf.exitCode)
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "log") {
        $n = 20
        $tailFast = $false
        $li = 1
        while ($li -lt $Command.Count) {
            if ($Command[$li] -eq "-n" -and $li + 1 -lt $Command.Count) {
                try { [int]$n = [int]$Command[$li + 1] } catch { $n = 20 }
                $li += 2
                continue
            }
            if ($Command[$li] -eq "--tail") { $tailFast = $true }
            $li++
        }
        if (!(Test-Path $LogFile)) { Write-Host "[windo] No log file found." -ForegroundColor Yellow; return }
        if ($JsonOutput) {
            if ($tailFast) {
                $phys = @(Get-Content -Path $LogFile | Select-Object -Last $n)
                $sliceL = [System.Collections.ArrayList]@()
                foreach ($line in $phys) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $parts = $line.Split(":", 2)
                    if ($parts.Count -lt 2) { continue }
                    try {
                        $json = _dpapi_unprotect $parts[1]
                        $sliceL.Add(($json | ConvertFrom-Json)) | Out-Null
                    } catch { }
                }
                _emit_json "log" @{ entries = @($sliceL); count = $sliceL.Count; tail = $true }
                return
            }
            $allL = @(_parse_log_entries)
            $sliceL = @($allL | Select-Object -Last $n)
            _emit_json "log" @{ entries = $sliceL; count = $sliceL.Count }
            return
        }
        $lines = @(Get-Content -Path $LogFile | Select-Object -Last $n)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Split(":", 2)
            if ($parts.Count -lt 2) { continue }
            try {
                $json = _dpapi_unprotect $parts[1]
                $obj  = $json | ConvertFrom-Json
                Write-Host "-----" -ForegroundColor DarkGray
                Write-Host "Time     : $($obj.Timestamp)"
                Write-Host "User     : $($obj.User)"
                Write-Host "Host     : $($obj.Host)"
                Write-Host "Command  : $($obj.Command)"
                Write-Host "ExitCode : $($obj.ExitCode)"
                if ($obj.PSObject.Properties.Name -contains "DurationMs") { Write-Host "Duration : $($obj.DurationMs)ms" }
                if ([string]::IsNullOrWhiteSpace([string]$obj.Output)) { Write-Host "Output   : <no output>" -ForegroundColor DarkGray }
                else { Write-Host "Output   :`n$($obj.Output)" }
            } catch {
                Write-Host "[windo] Failed to decrypt one entry." -ForegroundColor Red
            }
        }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "cleanup") {
        $cleanupRest = @()
        if ($Command.Count -gt 1) { $cleanupRest = @($Command[1..($Command.Count - 1)]) }
        $unknown = $cleanupRest | Where-Object { $_ -and $_ -ne '-w' }
        if ($unknown.Count -gt 0) {
            Write-Host "[windo] cleanup: ignoring unknown argument(s): $($unknown -join ' ')" -ForegroundColor Yellow
        }
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backup = Join-Path $SecureDir ("windo_history.$stamp.enc.bak")
        if (Test-Path $LogFile) {
            Copy-Item $LogFile $backup -Force
            Clear-Content $LogFile
            Write-Host "[windo] Backed up to $backup" -ForegroundColor Green
            Write-Host "[windo] Cleared active log." -ForegroundColor Yellow
        } else {
            Write-Host "[windo] No log file found to clean." -ForegroundColor Yellow
        }
        Get-ChildItem -Path $SecureDir -Filter "windo_req.*.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $SecureDir -Filter "windo_res.*.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        return
    }

    if ($Command.Count -ge 2 -and $Command[0] -ieq "recipes" -and $Command[1] -ieq "run") {
        if ($Command.Count -lt 3) {
            Write-Host "[windo] recipes run <name>" -ForegroundColor Yellow
            _windo_set_exit 2
            return
        }
        $recipeName = [string]$Command[2].Trim()
        $preview = _windo_get_recipe_preview $recipeName
        if ($null -eq $preview) {
            if ($JsonOutput) { _emit_json "recipes" @{ error = "unknown recipe"; name = $recipeName; exitCode = 2 } } else { Write-Host "[windo] Unknown recipe: $recipeName" -ForegroundColor Red }
            _windo_set_exit 2
            return
        }
        if ($DryRun) {
            if ($JsonOutput) { _emit_json "recipes" @{ subcommand = "run"; preview = $preview; dryRun = $true; exitCode = 0 } }
            else {
                Write-Host "[windo] Recipe dry-run: $($preview.name)" -ForegroundColor Cyan
                Write-Host "  Elevated command : $($preview.elevatedCommand)" -ForegroundColor Yellow
                Write-Host "  No task, request file, result file, or audit entry will be created." -ForegroundColor DarkGray
            }
            _windo_set_exit 0
            return
        }
        Write-Host "[windo] Recipe '$($preview.name)' -> elevated: $($preview.elevatedCommand)" -ForegroundColor Cyan
        $Command = @($preview.elevatedCommand)
    }

    if ($Command.Count -eq 1 -and $Command[0] -ieq "run") {
        if ($JsonOutput) { _emit_json "recipes" @{ error = "windo run requires --recipe <name>"; exitCode = 2 } } else { Write-Host "[windo] Usage: windo run --recipe <name>  (see: windo recipes)" -ForegroundColor Yellow }
        _windo_set_exit 2
        return
    }

    if ($Command.Count -ge 2 -and $Command[0] -ieq "run") {
        $recipeName = $null
        if ($Command.Count -ge 3 -and $Command[1] -ieq "--recipe") {
            $recipeName = [string]$Command[2].Trim()
        } elseif ($Command.Count -ge 2 -and $Command[1] -like "--recipe=*") {
            $recipeName = $Command[1].Substring(9).Trim()
        }
        if ($null -ne $recipeName -and -not [string]::IsNullOrWhiteSpace($recipeName)) {
            $preview = _windo_get_recipe_preview $recipeName
            if ($null -eq $preview) {
                if ($JsonOutput) { _emit_json "recipes" @{ error = "unknown recipe"; name = $recipeName; exitCode = 2 } } else { Write-Host "[windo] Unknown recipe: $recipeName" -ForegroundColor Red }
                _windo_set_exit 2
                return
            }
            if ($DryRun) {
                if ($JsonOutput) { _emit_json "recipes" @{ subcommand = "run"; preview = $preview; dryRun = $true; exitCode = 0 } }
                else {
                    Write-Host "[windo] Recipe dry-run: $($preview.name)" -ForegroundColor Cyan
                    Write-Host "  Elevated command : $($preview.elevatedCommand)" -ForegroundColor Yellow
                    Write-Host "  No task, request file, result file, or audit entry will be created." -ForegroundColor DarkGray
                }
                _windo_set_exit 0
                return
            }
            Write-Host "[windo] Recipe '$($preview.name)' -> elevated: $($preview.elevatedCommand)" -ForegroundColor Cyan
            $Command = @($preview.elevatedCommand)
        } else {
            if ($JsonOutput) { _emit_json "recipes" @{ error = "windo run requires --recipe <name>"; exitCode = 2 } } else { Write-Host "[windo] Usage: windo run --recipe <name>  (see: windo recipes)" -ForegroundColor Yellow }
            _windo_set_exit 2
            return
        }
    }

    if ($Command.Count -ge 1 -and ($Command[0] -eq "!!" -or $Command[0] -eq "replay")) {
        if (!(Test-Path $LastCmdFile)) { Write-Host "[windo] No previous command stored." -ForegroundColor Yellow; return }
        $lastCmd = (Get-Content -Raw -Path $LastCmdFile).Trim()
        if ([string]::IsNullOrWhiteSpace($lastCmd)) { Write-Host "[windo] Previous command file is empty." -ForegroundColor Yellow; return }
        Write-Host "[windo] Re-running last command: $lastCmd" -ForegroundColor Cyan
        $Command = @($lastCmd)
    }

    if (-not $Command -or $Command.Count -eq 0) {
        Write-Host "Usage: windo help | windo <command...> | windo install-latest | windo uninstall | windo !! | windo replay | ...  (see windo help)" -ForegroundColor Yellow
        return
    }

    try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null } catch { Write-Host "[windo] Task missing: $TaskName (run installer elevated once)" -ForegroundColor Red; return }

    _warn_if_tampered

    $cmdLine = ($Command -join " ").Trim()
    $cmdErr = _windo_validate_elevated_command $cmdLine
    $motionPlan = _windo_new_command_plan $Command
    if ($cmdErr) {
        Write-Host "[windo] $cmdErr" -ForegroundColor Red
        return
    }
    if ($DryRun) {
        Write-Host "[windo] DRY-RUN (no scheduled task, no request files, no audit log write)" -ForegroundColor Yellow
        Write-Host "  Command line : $cmdLine"
        Write-Host "  SecureDir    : $SecureDir"
        Write-Host "  Task         : $TaskName"
        Write-Host "  Runner       : $RunnerPath"
        Write-Host "  Would create : windo_req.<guid>.json and windo_res.<guid>.json under SecureDir"
        return
    }
    if ($cmdLine) {
        $firstTok = ($cmdLine -split '\s+', 2)[0]
        if ($firstTok -notin @(_windo_builtin_subcommands)) {
            Set-Content -Path $LastCmdFile -Value $cmdLine -Encoding UTF8
        }
    }

    $reqId   = [Guid]::NewGuid().ToString("n")
    $reqPath = Join-Path $SecureDir ("windo_req.$reqId.json")
    $outPath = Join-Path $SecureDir ("windo_res.$reqId.json")
    $preservedEnvSnapshot = $null
    $preservedEnvPayload = $null
    if ($PreserveEnvAll -or ($PreserveEnvNames -and $PreserveEnvNames.Count -gt 0)) {
        if ($PreserveEnvAll) { $preservedEnvSnapshot = _windo_collect_env_snapshot $null }
        else { $preservedEnvSnapshot = _windo_collect_env_snapshot ([string[]]$PreserveEnvNames) }
        $preservedEnvPayload = _windo_build_preserve_environment_payload $preservedEnvSnapshot
    }

    $pending = @{
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        RequestId = $reqId
        Command   = $cmdLine
        OutPath   = $outPath
        Host      = $env:COMPUTERNAME
        User      = "$env:USERDOMAIN\$env:USERNAME"
        TimeoutOverrideMs = $(if ($null -eq $CommandTimeoutOverrideMs) { $null } else { [int]$CommandTimeoutOverrideMs })
        PreserveEnvironment = $preservedEnvPayload
        PreserveEnvironmentMode = $(if ($PreserveEnvAll) { "all" } elseif ($preservedEnvSnapshot) { "names" } elseif ($PreserveEnvNames -and $PreserveEnvNames.Count -gt 0) { "names" } else { $null })
    } | ConvertTo-Json -Compress

    Set-Content -Path $reqPath -Value $pending -Encoding UTF8

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-ScheduledTask -TaskName $TaskName | Out-Null
    $dispatchProfile = _windo_resolve_motion_profile_name -Plan $motionPlan -Context "dispatch" -RequestedProfile $motionPlan.motionProfileHint
    $dispatchDelay = _windo_motion_interval_ms $dispatchProfile

    $waitFrame = 0
    $waitLabel = "[windo] Waiting for elevated result..."
    while (!(Test-Path $outPath) -and $sw.Elapsed.TotalSeconds -lt 20) {
        _windo_spinner_line $waitLabel $waitFrame $dispatchProfile
        $waitFrame = ($waitFrame + 1) % 4
        Start-Sleep -Milliseconds $dispatchDelay
    }
    if (_windo_spinner_enabled) { _windo_clear_spinner_line ($waitLabel.Length + 4) }

    if (!(Test-Path $outPath)) {
        $hint = ""
        if (Test-Path $RunnerLast) { $hint = (Get-Content -Raw -Path $RunnerLast).TrimEnd() }
        _append_log @{
            Timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            User       = "$env:USERDOMAIN\$env:USERNAME"
            Host       = $env:COMPUTERNAME
            Command    = $cmdLine
            ExitCode   = -2
            Output     = "<TIMEOUT WAITING FOR RESULT>`n$hint"
            Elevation  = "FAILED"
            DurationMs = [int]$sw.Elapsed.TotalMilliseconds
            Version    = $WindoVersion
            RequestId  = $reqId
        }
        _write_last_meta $cmdLine $reqId
        Write-Host "[windo] Timed out waiting for elevated result." -ForegroundColor Red
        if ($hint) { Write-Host "[windo] Runner trace:" -ForegroundColor Yellow; Write-Host $hint }
        _suggest_if_denied -2 $hint
        return
    }

    try { $res = Get-Content -Raw $outPath | ConvertFrom-Json } catch {
        $res = [pscustomobject]@{
            Timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Command    = $cmdLine
            Output     = "<FAILED TO PARSE RESULT>"
            ExitCode   = 1
            DurationMs = [int]$sw.Elapsed.TotalMilliseconds
            RequestId  = $reqId
        }
    }

    try {
        $env:WINDO_LAST_REQUEST_ID = [string]$res.RequestId
        $env:WINDO_VERSION = $WindoVersion
    } catch { }

    try { Remove-Item $outPath -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item $reqPath -Force -ErrorAction SilentlyContinue } catch {}

    _append_log @{
        Timestamp  = [string]$res.Timestamp
        User       = "$env:USERDOMAIN\$env:USERNAME"
        Host       = $env:COMPUTERNAME
        Command    = [string]$res.Command
        ExitCode   = [int]$res.ExitCode
        Output     = [string]$res.Output
        Elevation  = "TASK"
        DurationMs = [int]$res.DurationMs
        Version    = $WindoVersion
        RequestId  = [string]$res.RequestId
    }
    _write_last_meta $cmdLine ([string]$res.RequestId)

    _pretty_print $cmdLine ([int]$res.ExitCode) ([string]$res.Output) ([int]$res.DurationMs)
    if ($res.PSObject.Properties.Name -contains 'RunnerTimedOut' -and [bool]$res.RunnerTimedOut) {
        Write-Host "[windo] Elevated child hit WINDO_RUNNER_TIMEOUT_MS (see SECURITY)." -ForegroundColor Yellow
    }
    if ($res.PSObject.Properties.Name -contains 'OutputTruncated' -and [bool]$res.OutputTruncated) {
        Write-Host "[windo] Output was truncated (WINDO_RUNNER_MAX_OUTPUT_BYTES)." -ForegroundColor Yellow
    }
}

'@
$WindoFunctionBody = $WindoFunctionBody.Replace("__WINDO_BUILTIN_ARRAY__", $WindoBuiltinVerbsArrayLiteral)
$WindoFunctionBody = $WindoFunctionBody.Replace("__VERSION__", $WindoVersion)

$WindoPsReadLineBlock = @'
try {
    Import-Module PSReadLine -ErrorAction Stop
    $null = [Microsoft.PowerShell.PSConsoleReadLine]

    function __windo_parse_bool_value {
        param([object]$Raw, [bool]$Default = $false)
        if ($null -eq $Raw) { return $Default }
        $value = [string]$Raw
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        switch ($value.Trim().ToLowerInvariant()) {
            '1' { return $true }
            'true' { return $true }
            'yes' { return $true }
            'on' { return $true }
            'enabled' { return $true }
            '0' { return $false }
            'false' { return $false }
            'no' { return $false }
            'off' { return $false }
            'disabled' { return $false }
            default { return $Default }
        }
    }

    function __windo_read_windo_prefs {
        $windoSecureDir = Join-Path $HOME ".pwsh_secure"
        $windoPrefsFile = Join-Path $windoSecureDir "windo_prefs.json"
        if (!(Test-Path -LiteralPath $windoPrefsFile)) { return $null }
        try { Get-Content -Raw -Path $windoPrefsFile | ConvertFrom-Json } catch { $null }
    }

    function __windo_resolve_keybinding_policy {
        $pref = __windo_read_windo_prefs
        $prefChord = $null
        $prefDisabled = $null
        if ($pref -and $pref.PSObject.Properties.Name -contains 'keybindingPrefixChord') { $prefChord = [string]$pref.keybindingPrefixChord }
        if ($pref -and $pref.PSObject.Properties.Name -contains 'keybindingDisabled') { $prefDisabled = $pref.keybindingDisabled }

        $envDisable = [string]$env:WINDO_DISABLE_PSREADLINE_BINDINGS
        $envChord = [string]$env:WINDO_PREFIX_CHORD
        $disabled = $false
        if (-not [string]::IsNullOrWhiteSpace($envDisable)) {
            $disabled = __windo_parse_bool_value -Raw $envDisable -Default $false
        } elseif ($null -ne $prefDisabled) {
            $disabled = __windo_parse_bool_value -Raw $prefDisabled -Default $false
        }

        $chord = $null
        if (-not [string]::IsNullOrWhiteSpace($envChord)) {
            $chord = $envChord.Trim()
        } elseif (-not [string]::IsNullOrWhiteSpace($prefChord)) {
            $chord = $prefChord.Trim()
        } else {
            $chord = "Alt+w"
        }

        if ($disabled) { $chord = $null }
        $autoDetectAlt = [string]$env:WINDO_AUTO_DETECT_ALT_BINDINGS
        $autoDetectAltEnabled = $true
        if (-not [string]::IsNullOrWhiteSpace($autoDetectAlt)) {
            $autoDetectAltEnabled = __windo_parse_bool_value -Raw $autoDetectAlt -Default $true
        }
        $fallbackChord = [string]$env:WINDO_KEYBINDING_FALLBACK_CHORD
        if ([string]::IsNullOrWhiteSpace($fallbackChord)) { $fallbackChord = "Alt+;" } else { $fallbackChord = $fallbackChord.Trim() }
        [pscustomobject]@{
            enabled = [bool](-not $disabled)
            autoDetectAlt = [bool]$autoDetectAltEnabled
            fallbackChord = $fallbackChord
            chord = $chord
            source = $(if ([string]::IsNullOrWhiteSpace($envChord)) { if (-not [string]::IsNullOrWhiteSpace($prefChord)) { "prefs" } else { "auto" } } else { "env" })
            chordSource = $(if ([string]::IsNullOrWhiteSpace($envChord)) { if (-not [string]::IsNullOrWhiteSpace($prefChord)) { "prefs" } else { "auto" } } else { "env" })
            requestedChord = $chord
            requestedSource = $(if ([string]::IsNullOrWhiteSpace($envChord)) { if (-not [string]::IsNullOrWhiteSpace($prefChord)) { "prefs" } else { "auto" } } else { "env" })
            autoDetected = $false
            autoDetectedReason = $null
            appliedChord = $null
        }
    }

    $legacyChords = @('w', 'w,w', 'Alt+w', 'Shift+Enter', 'Alt+Enter')
    foreach ($legacyChord in $legacyChords) {
        try { Remove-PSReadLineKeyHandler -Chord $legacyChord -ErrorAction SilentlyContinue } catch { }
    }

    $policy = __windo_resolve_keybinding_policy
    if ($policy.enabled -and -not [string]::IsNullOrWhiteSpace($policy.chord)) {
    $windoPrefixOnly = {
        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        $m = [regex]::Match($line, '^(\s*)(.*)$')
        $rest = $m.Groups[2].Value
        if ($rest -match '^(?i)windo(\s|$)') { return }
        $indent = $m.Groups[1].Value
        $newLine = $indent + 'windo ' + $rest
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $newLine)
    }

    $windoPrefixRun = {
        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        $m = [regex]::Match($line, '^(\\s*)(.*)$')
        $rest = $m.Groups[2].Value
        if ($rest -notmatch '^(?i)windo(\\s|$)') {
            $indent = $m.Groups[1].Value
            $newLine = $indent + 'windo ' + $rest
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $newLine)
        }
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }

        $requestedChord = $policy.chord
        $prefixCandidates = [System.Collections.ArrayList]@()
        [void]$prefixCandidates.Add($requestedChord)

        if ($policy.autoDetectAlt -and ($requestedChord -like 'Alt+*') -and ([string]::IsNullOrWhiteSpace($policy.fallbackChord) -eq $false) -and ($policy.fallbackChord -ne $requestedChord)) {
            [void]$prefixCandidates.Add($policy.fallbackChord)
        }

        $selectedPrefixChord = $null
        foreach ($candidate in ($prefixCandidates | Select-Object -Unique)) {
            try {
                Set-PSReadLineKeyHandler -Chord $candidate -ScriptBlock $windoPrefixOnly -ErrorAction Stop
                $handler = Get-PSReadLineKeyHandler -Chord $candidate -ErrorAction Stop
                if ($null -ne $handler) {
                    $selectedPrefixChord = $candidate
                    break
                }
            } catch {
                try { Remove-PSReadLineKeyHandler -Chord $candidate -ErrorAction SilentlyContinue } catch { }
            }
        }

        if ($null -ne $selectedPrefixChord) {
        if ($selectedPrefixChord -ne $requestedChord) {
            $policy.chord = $selectedPrefixChord
            $policy.chordSource = "auto-fallback"
            $policy.autoDetected = $true
            $policy.autoDetectedReason = "alt binding did not bind, fallback to '$selectedPrefixChord'"
        } else {
            $policy.appliedChord = $selectedPrefixChord
        }

    try {
        Set-PSReadLineKeyHandler -Chord 'Shift+Enter' -ScriptBlock $windoPrefixRun
    } catch { }
    try {
        Set-PSReadLineKeyHandler -Chord 'Alt+Enter' -ScriptBlock $windoPrefixRun
    } catch { }
        }
    }
} catch {
    Write-Warning ("WINDO: PSReadLine keybindings skipped: " + $_.Exception.Message)
}
'@

$WindoCompleterBlock = @'
function __windo_normalize_completion_mode([string]$Mode) {
    if ([string]::IsNullOrWhiteSpace($Mode)) { return "native-first" }
    switch ($Mode.Trim().ToLowerInvariant()) {
        "native" { return "native-first" }
        "stealth" { return "native-first" }
        "native-first" { return "native-first" }
        "hybrid" { return "hybrid" }
        "windo" { return "windo" }
        "builtin" { return "windo" }
        "builtins" { return "windo" }
        "off" { return "off" }
        "disabled" { return "off" }
        default { return "native-first" }
    }
}

function __windo_resolve_completion_mode {
    $pref = $null
    try { $pref = __windo_read_windo_prefs } catch { $pref = $null }
    $prefMode = $null
    if ($pref -and $pref.PSObject.Properties.Name -contains 'completionMode') { $prefMode = [string]$pref.completionMode }
    $envMode = [string]$env:WINDO_COMPLETION_MODE
    if (-not [string]::IsNullOrWhiteSpace($envMode)) { return (__windo_normalize_completion_mode $envMode) }
    if (-not [string]::IsNullOrWhiteSpace($prefMode)) { return (__windo_normalize_completion_mode $prefMode) }
    return "native-first"
}

function __windo_completion_specs {
    @{
        help = @('version','install-latest','source','trust','scan','net-scan','rdp','vnc','vault','sshx','crypto','explain','syntax','mesh','completion','output','motion','surface','integrate','control','signal','center','studio','edition','keybindings','recipes','venv','pkg','container','wsl','launchpad','preflight','dashboard','integrity','verify','config','profile','modules','extras','ai','repair')
        completion = @('status','doctor','repair','native-first','hybrid','windo','off','reset','--json')
        output = @('status','compact','quiet','legacy','reset','--json')
        motion = @('status','auto','on','quiet','off','reset','pulse','demo','--json')
        surface = @('status','prime','pulse','demo','doctor','repair','open','panel','window','--json')
        integrate = @('status','doctor','prime','repair','shortcuts','startup','shim','open','--json')
        control = @('status','prime','actions','preview','queue','run','execute-next','next','execute','inspect','cancel','history','pulse','demo','clear','surface-status','surface-prime','surface-panel','power-studio','integrate-status','integrate-doctor','integrate-repair','integrate-open','integrate-shim','integrate-startup','center-status','source-status','verify-audit','surface-doctor','surface-repair','scan-home','vault-status','crypto-status','venv-status','sshx-status','recipes-list','pkg-status','launchpad-tray','workbench-html','edition-open','motion-pulse','profile-doctor','trust-online','preflight','install-latest','--json')
        signal = @('status','timeline','last','export','open','html','--html','--open','--output','--json')
        center = @('status','open','tray','panel','surface','studio','wizard','power','actions','preview','run','queue','execute-next','next','execute','history','signal','surface-status','surface-prime','surface-panel','power-studio','integrate-status','integrate-doctor','integrate-repair','integrate-open','integrate-shim','integrate-startup','center-status','source-status','verify-audit','surface-doctor','surface-repair','scan-home','vault-status','crypto-status','venv-status','sshx-status','recipes-list','pkg-status','launchpad-tray','workbench-html','edition-open','motion-pulse','profile-doctor','trust-online','preflight','install-latest','--json')
        studio = @('--json')
        edition = @('status','open','html','export','pulse','--open','--output','--json')
        trust = @('--online','--offline','--json')
        scan = @('--recurse','--max-mb','--no-hash','--json')
        'net-scan' = @('status','resolve','arp','ping','probe','nmap','rdp','vnc','wsl','--interface','--include-stale','--timeout','--host-limit','--ports','--json')
        rdp = @('status','firewall','config','troubleshoot','--enable','--disable','--nla','--security-layer','--restart','--host','--ports','--timeout','--credential','--json')
        vnc = @('status','firewall','stop','test','troubleshoot','--ports','--host','--timeout','--credential','--json')
        vault = @('status','list','set','get','remove','--json')
        sshx = @('status','keygen','config','test','--name','--comment','--json')
        crypto = @('status','cert','key','hash','--json')
        source = @('--json')
        explain = @('install-latest','source','trust --online','recipes preview','recipes run','launchpad --tray','--json','--')
        syntax = @('doctor','--doctor','update','proof','health','repair keys','support bundle','recipes','launchpad','--json')
        mesh = @('doctor','workbench','--json','--html','--open','--output')
        keybindings = @('status','doctor','set','disable','enable','reset','safe-reset','--json','--chord')
        recipes = @('list','show','preview','run','--json','--dry-run','arp-cache','audit-policy','bitlocker-status','boot-config','cert-my-store','cert-root-store','defender-preferences','defender-status','disk-free','dns-client-cache','driverquery','driverquery-signed','environment-os','firewall-current-profile','firewall-profiles','fsutil-drives','fsutil-trim','gpresult-summary','hostname','ipconfig-all','ipconfig-brief','local-admins','local-groups','local-users','net-accounts','net-sessions','net-shares','net-use','netstat-ports','network-adapters','network-dns-servers','network-ip-config','network-ipv6-interfaces','network-routes','network-wifi','ollama-list','ollama-ps','ollama-version','os-build','os-version','physical-disks','pnputil-drivers','power-availability','power-device-wake','power-lastwake','power-requests','processes-services','processes-verbose','recovery-info','scheduled-tasks','scheduled-tasks-verbose','service-bits-config','service-bits-query','service-spooler-query','service-winrm-query','services-all','services-drivers','shares-open-files','systeminfo','time-configuration','time-peers','time-status','tool-docker-version','tool-git-version','tool-node-version','tool-powershell-path','tool-python-version','tool-winget-version','uptime','volumes','whoami-all','whoami-groups','whoami-privileges','winhttp-proxy','winrm-config','windows-update-services')
        venv = @('status','create','activate','deactivate','remove','--python','--force','--json')
        pkg = @('status','winget','choco','scoop','install','upgrade','list','search','--json')
        container = @('ps','images','status','logs','restart','start','stop','rmi','rm','pull','--runtime','auto','docker','podman','--json','--dry-run')
        wsl = @('status','list','ls','check','install','version','convert','inspect','exec','launch','path','import','export','--distro','--distribution','--name','--path','--tar','--out','--output','--version','--to','--user','--command','--to-wsl','--to-win','--json','--dry-run','--apply','--overwrite')
        launchpad = @('--json','--html','--open','--tray','--output')
        dashboard = @('--json','--html','--open','--output','-o')
        preflight = @('--json')
        profile = @('status','doctor','repair','--prompt-init','--all','--json')
        config = @('--json')
        roadmap = @('--json')
        version = @('--json')
        doctor = @('--json')
        integrity = @('--json')
        verify = @('--json')
        context = @('--json')
        session = @('--json')
        modules = @('list','enable','disable','doctor','verify','--json')
        extras = @('search','fetch','--json','--force')
        ai = @('status','doctor','--json')
        repair = @('all','keybindings','--json')
        theme = @('classic','modern','auto')
        backups = @('--json','--prune','--keep','--force')
        log = @('-n','--tail','--json')
        history = @('-n')
        stats = @('--since','--last-days')
        export = @('-o','-n','--redact','--json')
        uninstall = @('--keep-snapshots','--confirm','--download-fresh')
        remove = @('--keep-snapshots','--confirm','--download-fresh')
        'install-latest' = @('--force','--non-interactive','--timeout','--preserve-env')
        upgrade = @('--force','--non-interactive','--timeout','--preserve-env')
    }
}

function __windo_complete_values([string[]]$Values, [string]$Word) {
    foreach ($v in @($Values | Where-Object { [string]$_ -like "$Word*" } | Sort-Object -Unique)) {
        [System.Management.Automation.CompletionResult]::new($v, $v, [System.Management.Automation.CompletionResultType]::ParameterValue, "WINDO syntax: $v")
    }
}

function Register-WindoArgumentCompleter {
    if ($global:__WindoArgCompleterRegistered) { return }
    if (-not (Get-Command TabExpansion2 -ErrorAction SilentlyContinue)) {
        Write-Warning "WINDO: TabExpansion2 not available; delegated tab completion skipped."
        return
    }
    Register-ArgumentCompleter -CommandName windo -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $builtin = [string[]]@(__WINDO_BUILTIN_ARRAY__, '!!')
        try {
            $mode = __windo_resolve_completion_mode
            if ($mode -eq "off") { return }
            if ($null -eq $commandAst) { return }
            $line = $commandAst.Extent.Text
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            $m = [regex]::Match($line, '^\s*windo(?:\s+|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if (-not $m.Success) { return }
            $delegate = $line.Substring($m.Length)
            $trimmedDelegate = $delegate.TrimStart()
            if ($trimmedDelegate -match '^(--json|--dry-run|--non-interactive|-n|-Json|-DryRun)\s+') {
                $delegate = $trimmedDelegate -replace '^(--json|--dry-run|--non-interactive|-n|-Json|-DryRun)\s+', ''
                $trimmedDelegate = $delegate.TrimStart()
            }
            if ($trimmedDelegate -match '^--\s+') {
                $delegate = $trimmedDelegate -replace '^--\s+', ''
                $trimmedDelegate = $delegate.TrimStart()
            }
            if ([string]::IsNullOrWhiteSpace($trimmedDelegate)) {
                foreach ($b in $builtin) {
                    [System.Management.Automation.CompletionResult]::new($b, $b, [System.Management.Automation.CompletionResultType]::ParameterValue, "WINDO command: $b")
                }
                return
            }
            $firstTok = ($trimmedDelegate -split '\s+', 2)[0]
            $builtinMatches = @($builtin | Where-Object { $_ -like "$firstTok*" } | Sort-Object -Unique)
            $isExactBuiltin = $false
            foreach ($b in $builtin) {
                if ($firstTok -ceq $b -or $firstTok -ieq $b) { $isExactBuiltin = $true; break }
            }
            if ($isExactBuiltin) {
                $specs = __windo_completion_specs
                $key = $firstTok.ToLowerInvariant()
                if ($specs.ContainsKey($key)) {
                    $afterBuiltin = $trimmedDelegate.Substring($firstTok.Length)
                    $syntaxWord = ""
                    if (-not [string]::IsNullOrWhiteSpace($afterBuiltin)) {
                        $syntaxWord = ($afterBuiltin.TrimStart() -split '\s+')[-1]
                    }
                    __windo_complete_values ([string[]]$specs[$key]) $syntaxWord
                }
                return
            }
            if ($mode -eq "native-first" -and $builtinMatches.Count -gt 0) {
                foreach ($b in $builtinMatches) {
                    [System.Management.Automation.CompletionResult]::new($b, $b, [System.Management.Automation.CompletionResultType]::ParameterValue, "WINDO command: $b")
                }
                return
            }
            if ($mode -ne "native-first") {
                foreach ($b in $builtinMatches) {
                    [System.Management.Automation.CompletionResult]::new($b, $b, [System.Management.Automation.CompletionResultType]::ParameterValue, "WINDO command: $b")
                }
                if ($mode -eq "windo") { return }
            }
            $cursor = $delegate.Length
            if (-not [string]::IsNullOrEmpty($wordToComplete)) {
                $ix = $delegate.LastIndexOf($wordToComplete, [StringComparison]::Ordinal)
                if ($ix -ge 0) { $cursor = $ix + $wordToComplete.Length }
            }
            $completion = TabExpansion2 -inputScript $delegate -cursorColumn $cursor 2>$null
            if ($null -eq $completion) { return }
            $matches = $completion.CompletionMatches
            if ($null -eq $matches -or $matches.Count -eq 0) { return }
            foreach ($cm in @($matches)) {
                [System.Management.Automation.CompletionResult]::new(
                    $cm.CompletionText,
                    $cm.ListItemText,
                    $cm.ResultType,
                    $cm.ToolTip
                )
            }
        } catch {
        }
    }
    $global:__WindoArgCompleterRegistered = $true
}
Register-WindoArgumentCompleter
'@
$WindoCompleterBlock = $WindoCompleterBlock.Replace("__WINDO_BUILTIN_ARRAY__", $WindoBuiltinVerbsArrayLiteral)

$WindoModulesLoaderBlock = @'
# WINDO optional modules loader (enabled in %USERPROFILE%\.pwsh_secure\windo_prefs.json â†’ enabledModules)
$__wmRoot = Join-Path $HOME 'Documents\windo\modules'
$__wmPrefs = Join-Path $HOME '.pwsh_secure\windo_prefs.json'
$__wmEnabled = [string[]]@()
if (Test-Path -LiteralPath $__wmPrefs) {
    try {
        $__p = Get-Content -Raw -LiteralPath $__wmPrefs | ConvertFrom-Json
        if ($__p.PSObject.Properties.Name -contains 'enabledModules' -and $null -ne $__p.enabledModules) {
            $__wmEnabled = @($__p.enabledModules | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    } catch { }
}
foreach ($__mid in $__wmEnabled) {
    $__modDir = Join-Path $__wmRoot $__mid
    $__mj = Join-Path $__modDir 'module.json'
    if (!(Test-Path -LiteralPath $__mj)) { continue }
    try {
        $__mf = Get-Content -Raw -LiteralPath $__mj | ConvertFrom-Json
        $__entry = 'Load.ps1'
        if ($__mf.PSObject.Properties.Name -contains 'entry' -and -not [string]::IsNullOrWhiteSpace([string]$__mf.entry)) { $__entry = [string]$__mf.entry }
        $__req = $null
        if ($__mf.PSObject.Properties.Name -contains 'requiresWindoVersion') { $__req = [string]$__mf.requiresWindoVersion }
        if (-not [string]::IsNullOrWhiteSpace($__req)) {
            try {
                $__have = [version]::Parse('__WINDO_PROFILE_VERSION__'.Split('-')[0].Split('+')[0])
                $__need = [version]::Parse($__req.Split('-')[0].Split('+')[0])
                if ($__have -lt $__need) { continue }
            } catch { }
        }
        $__ent = Join-Path $__modDir $__entry
        if (Test-Path -LiteralPath $__ent) { . $__ent }
    } catch {
        Write-Warning ("WINDO module '" + $__mid + "' failed to load: " + $_.Exception.Message)
    }
}
'@
$WindoModulesLoaderBlock = $WindoModulesLoaderBlock.Replace("__WINDO_PROFILE_VERSION__", $WindoVersion)

$profileText = ''
if (Test-Path -LiteralPath $PROFILE) {
    try {
        $profileText = Get-Content -Raw -LiteralPath $PROFILE
        $profileText = Repair-WindoProfileText -Text $profileText
    } catch {
        $profileText = ''
    }
}
$block = $BeginMarker + "`r`n" + $WindoFunctionBody + "`r`n" + $WindoPsReadLineBlock + "`r`n" + $WindoCompleterBlock + "`r`n" + $WindoModulesLoaderBlock + "`r`n" + $EndMarker + "`r`n"
Write-Utf8NoBomFile -Path $PROFILE -Content ($profileText.TrimEnd() + "`r`n`r`n" + $block)
Write-WindoInstallStep -Status ok -Label "PowerShell profile refreshed" -Color Green

Write-WindoInstallStep -Status run -Label "Writing local snapshot" -Detail $SnapshotDir
if (!(Test-Path $SnapshotDir)) { New-Item -ItemType Directory -Path $SnapshotDir | Out-Null }
Copy-Item $RunnerPath (Join-Path $SnapshotDir "windo_runner.ps1") -Force
Copy-Item $UpdateScript (Join-Path $SnapshotDir "windo_self_update.ps1") -Force
Copy-Item $UninstallPath (Join-Path $SnapshotDir "windo_uninstall.ps1") -Force
Copy-Item $ManifestFile (Join-Path $SnapshotDir "windo_manifest.json") -Force

$SnapshotInstaller = Join-Path $SnapshotDir "windo_install.ps1"
$installerSource = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($installerSource)) {
    try { $installerSource = $MyInvocation.MyCommand.Path } catch { $installerSource = $null }
}
if (-not [string]::IsNullOrWhiteSpace($installerSource) -and (Test-Path -LiteralPath $installerSource)) {
    Copy-Item -LiteralPath $installerSource -Destination $SnapshotInstaller -Force
} else {
    Write-Warning "WINDO: Could not snapshot windo_install.ps1 (pathless or in-memory execution). Other snapshot files were written to: $SnapshotDir"
}
Write-WindoInstallStep -Status ok -Label "Snapshot refreshed" -Color Green

Write-Host ""
Write-WindoInstallStep -Status ok -Label "WINDO v$WindoVersion installed" -Detail "snapshot: $SnapshotDir" -Color Green
Write-Host ""
Write-Host "  Next in a normal shell:" -ForegroundColor Yellow
Write-Host "    . `$PROFILE" -ForegroundColor Yellow
Write-Host "    windo preflight" -ForegroundColor Yellow
Write-Host "    windo dashboard --html" -ForegroundColor Yellow
Write-Host "    windo version" -ForegroundColor Yellow
Write-Host ""

