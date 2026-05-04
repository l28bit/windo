<# =====================================================================
WINDO v3.6.2 Special Edition Installer
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

$WindoVersion = "3.6.2"

# Single source of truth for embedded profile: completer skip-list (plus '!!') and windo last-command first-token exclusions.
$WindoBuiltinVerbs = @(
    'help', 'last', 'stats', 'history', 'report', 'dashboard', 'preflight', 'launchpad', 'export', 'self-update', 'version',
    'doctor', 'integrity', 'verify', 'trust', 'explain', 'log', 'cleanup', 'config', 'backups', 'context', 'trace', 'replay',
    'theme', 'upgrade', 'install-latest', 'uninstall', 'remove', 'profile', 'keybindings', 'completion', 'roadmap', 'syntax',
    'modules', 'recipes', 'prompt', 'extras', 'dev', 'session', 'ai', 'repair', 'run'
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
    Write-Host ("  WINDO {0}  Special Edition  ::  {1}" -f $WindoVersion, $Phase.ToUpperInvariant()) -ForegroundColor White
    Write-Host "  deliberate elevation | audit chain | operator visuals" -ForegroundColor DarkGray
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
WINDO uninstall — removes scheduled tasks, profile block, and WINDO data.

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
        -Principal $Principal -Settings $Settings -Force | Out-Null

    Register-ScheduledTask -TaskName $TaskUpdate `
        -Action (New-ScheduledTaskAction -Execute $UpdateActionArgs.Execute -Argument $UpdateActionArgs.Argument) `
        -Principal $Principal -Settings $Settings -Force | Out-Null
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
    $UnUrl = "https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_uninstall.ps1"
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
        if ($HelpRequested) {
            if ($Command.Count -gt 0 -and [string]::IsNullOrWhiteSpace($HelpTopic)) { $HelpTopic = [string]$Command[0] }
            _windo_show_help $HelpTopic
            _windo_set_exit 0
            return
        }
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

                if ($tx -eq '--help' -or $tx -eq '-h' -or $tx -eq '-?' -or $tx -eq '/?') {
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
        if ($HelpRequested) {
            if ($Command.Count -gt 0 -and [string]::IsNullOrWhiteSpace($HelpTopic)) { $HelpTopic = [string]$Command[0] }
            _windo_show_help $HelpTopic
            _windo_set_exit 0
            return
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
            return "Ollama: OLLAMA_HOST is unset — server defaults to 127.0.0.1:11434 (local only)."
        }
        $t = $h.Trim()
        $tl = $t.ToLowerInvariant()
        if ($tl -match '^(https?://)?(127\.0\.0\.1|localhost)(:|/|$)' -or $tl -match '^127\.0\.0\.1:\d+$' -or $tl -match '^localhost:\d+$') {
            return $null
        }
        if ($tl -match '^(https?://)?0\.0\.0\.0(:|/|$)' -or $tl -match '^0\.0\.0\.0:\d+$') {
            return "Ollama: OLLAMA_HOST binds all interfaces — confirm firewall rules and intentional LAN exposure."
        }
        return "Ollama: OLLAMA_HOST may point off loopback — confirm intentional network exposure and firewall rules."
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
            'service-bits-query' = @{ description = 'Query the Background Intelligent Transfer Service (sc.exe).'; command = 'sc.exe query bits' }
            'firewall-profiles'  = @{ description = 'Show Windows Firewall profile states (netsh).'; command = 'netsh advfirewall show allprofiles state' }
            'os-version'         = @{ description = 'Print Windows version string (ver).'; command = 'cmd.exe /c ver' }
            'ipconfig-brief'     = @{ description = 'Basic IP configuration (ipconfig, no switches).'; command = 'ipconfig.exe' }
            'ollama-version'     = @{ description = 'Ollama CLI version (read-only; requires ollama on PATH).'; command = 'ollama.exe --version' }
            'ollama-ps'          = @{ description = 'Ollama running models snapshot (ollama ps).'; command = 'ollama.exe ps' }
            'ollama-list'        = @{ description = 'List local Ollama models (ollama list).'; command = 'ollama.exe list' }
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

    function _windo_extras_index_url {
        $raw = [string]$env:WINDO_EXTRAS_INDEX_URL
        if (-not [string]::IsNullOrWhiteSpace($raw)) { return $raw.Trim() }
        return "https://raw.githubusercontent.com/l28bit/windo/Genisis/extras/index.json"
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

Example segment (JSON) — map fields to your theme's env segment or a custom script block:
{
  "type": "text",
  "style": "diamond",
  "foreground": "#569cd6",
  "background": "#1e1e1e",
  "leading_diamond": " ",
  "trailing_diamond": "",
  "template": " WINDO {{ if .Env.WINDO_VERSION }}v{{ .Env.WINDO_VERSION }}{{ end }}{{ if .Env.WINDO_LAST_REQUEST_ID }} · {{ .Env.WINDO_LAST_REQUEST_ID }}{{ end }} "
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
                status = "in-progress"
                operatorValue = "The shell keeps normal PowerShell muscle memory while WINDO remains available as an escalation wrapper."
            },
            [pscustomobject]@{
                version = "3.5.0"
                codename = "Trust Console"
                theme = "Make trust state explicit before elevation."
                focus = @("windo trust", "policy summary", "installer provenance", "profile and task drift repair", "clear remediation commands")
                status = "in-progress"
                operatorValue = "Operators can see whether the local install is trusted, current, and repairable before running privileged work."
            },
            [pscustomobject]@{
                version = "3.6.0"
                codename = "Syntax Forge"
                theme = "Make common elevation workflows shorter and safer."
                focus = @("windo syntax", "command aliases", "recipe parameters", "dry-run previews", "syntax doctor")
                status = "in-progress"
                operatorValue = "High-frequency commands become easier to express without loosening validation or audit trails."
            },
            [pscustomobject]@{
                version = "4.0.0"
                codename = "Operator Mesh"
                theme = "Turn modules, recipes, extras, prompt, and launchpad into one coherent platform layer."
                focus = @("module lifecycle", "verified extras", "launchpad workflows", "structured handoff bundles")
                status = "planned"
                operatorValue = "WINDO becomes a composable local operations platform, not just an elevation helper."
            },
            [pscustomobject]@{
                version = "4.5.0"
                codename = "Signal Deck"
                theme = "Make diagnosis and audit evidence faster to consume."
                focus = @("timeline views", "request correlation", "health scoring", "support-ready export profiles")
                status = "planned"
                operatorValue = "Troubleshooting shifts from raw logs to explainable, shareable operational evidence."
            },
            [pscustomobject]@{
                version = "5.0.0"
                codename = "Special Edition Extravaganza"
                theme = "Package the runway into the next major reveal."
                focus = @("special edition visuals", "command center polish", "trust posture", "workflow packs", "operator-grade release notes")
                status = "target"
                operatorValue = "A major release that feels new because the underlying platform foundations have been hardened across the 3.x and 4.x train."
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
                summary = "Open the Special Edition launchpad or native tray command center."
                command = "windo launchpad --tray"
                preview = "windo launchpad"
                risk = "starts local tray helper"
                notes = "Use windo launchpad --html for a browser artifact instead."
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

    function _windo_quote_plan_part([string]$Part) {
        if ($null -eq $Part) { return "''" }
        if ($Part -match '^[A-Za-z0-9_./:\\=-]+$') { return $Part }
        return "'" + ($Part -replace "'", "''") + "'"
    }

    function _windo_join_plan_command([object[]]$Parts) {
        if ($null -eq $Parts -or $Parts.Count -eq 0) { return "" }
        return ((@($Parts) | ForEach-Object { _windo_quote_plan_part ([string]$_) }) -join " ")
    }

    function _windo_new_command_plan([object[]]$Parts) {
        $target = @($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($target.Count -gt 0 -and ([string]$target[0]).ToLowerInvariant() -eq "windo") {
            $target = if ($target.Count -gt 1) { @($target[1..($target.Count - 1)]) } else { @() }
        }

        $commandLine = _windo_join_plan_command $target
        $verb = if ($target.Count -gt 0) { ([string]$target[0]).ToLowerInvariant() } else { "" }
        $sub = if ($target.Count -gt 1) { ([string]$target[1]).ToLowerInvariant() } else { "" }
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
            { $_ -in @("version", "config", "context", "profile", "roadmap", "preflight", "dashboard", "integrity", "verify", "session", "log", "history", "stats", "backups", "modules", "extras", "prompt", "ai", "help") } {
                $plan.route = "local built-in command"
                $plan.category = "Readiness"
                $plan.privilegeBoundary = "read-only unless a mutating subcommand is supplied"
                $plan.checksumValidation = "manifest-backed runner/updater integrity where relevant"
                if ($verb -in @("dashboard", "export", "prompt", "extras", "backups", "modules") -and (@($target) -match "fetch|enable|disable|prune|--html|--export").Count -gt 0) {
                    $plan.writesLocalFiles = $true
                }
                [void]$next.Add($commandLine)
                break
            }
            { $_ -in @("repair", "keybindings", "completion", "theme") } {
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
        $InstUrl = "https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_install.ps1"
        $TempInst = Join-Path $env:TEMP ("windo_install_" + [Guid]::NewGuid().ToString("n") + ".ps1")
        try {
            _windo_invoke_rest_with_spinner -Uri $InstUrl -OutFile $TempInst -Label "Downloading latest installer from Genisis (non-elevated)..."
            if (!(Test-Path $TempInst)) { throw "Download failed." }
            _windo_verify_installer_sha256_optional $TempInst
            if ((Get-Item $TempInst).Length -lt 5000) { throw "Installer file size looks invalid." }
            Write-Host "[windo] Download finished; checksum verified when published on Genisis." -ForegroundColor Green
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
            Write-Host "[windo] Could not install from Genisis: $($_.Exception.Message)" -ForegroundColor Red
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
            Write-Host "[windo] Hint: Access was denied or blocked. Check paths and ACLs; run 'windo doctor'. If tasks are missing, re-run the installer elevated once. Elevation remains deliberate — WINDO does not auto-elevate your interactive shell." -ForegroundColor DarkYellow
        }
    }

    function _pretty_print([string]$cmdLine, [int]$exitCode, [string]$output, [int]$durationMs) {
        $output = ($output | Out-String).TrimEnd()
        Write-Host "[windo v$WindoVersion] $cmdLine" -ForegroundColor Cyan
        if ($exitCode -eq 0) { Write-Host "[windo] Status: SUCCESS" -ForegroundColor Green }
        else { Write-Host "[windo] Status: ERROR ($exitCode)" -ForegroundColor Red }
        Write-Host "[windo] Duration: ${durationMs}ms" -ForegroundColor DarkGray
        if ([string]::IsNullOrWhiteSpace($output)) { Write-Host "[windo] Output: <no output>" -ForegroundColor DarkGray }
        else { Write-Host "[windo] Output:" -ForegroundColor Yellow; Write-Host $output }
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
        $m = [regex]::Match($normalized, '^(?<value>\d+)\s*(?<unit>ms|s)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $m.Success) { return $null }
        try {
            $val = [int64]$m.Groups['value'].Value
            $unit = $m.Groups['unit'].Value.ToLowerInvariant()
            if ($unit -eq 'ms') { return [int]$val }
            return [int]($val * 1000)
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
        if ($env:WINDO_NO_SPINNER) { return $false }
        if ($env:CI) { return $false }
        try {
            if ([Console]::IsOutputRedirected) { return $false }
        } catch {
            return $false
        }
        return $true
    }

    function _windo_clear_spinner_line([int]$Width) {
        if (-not (_windo_spinner_enabled)) { return }
        $w = [Math]::Max(20, [Math]::Min($Width, 120))
        [Console]::Write("`r$(' ' * $w)`r")
    }

    function _windo_spinner_line([string]$Label, [int]$Frame) {
        if (-not (_windo_spinner_enabled)) { return }
        $frames = @('|', '/', '-', '\')
        $c = $frames[$Frame % $frames.Length]
        [Console]::Write("`r${Label} ${c} ")
    }

    function _windo_invoke_rest_with_spinner {
        param(
            [Parameter(Mandatory)][string]$Uri,
            [Parameter(Mandatory)][string]$OutFile,
            [Parameter(Mandatory)][string]$Label
        )
        $baseLabel = "[windo] $Label"

        if (-not (_windo_spinner_enabled)) {
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
            _windo_spinner_line $baseLabel $frame
            $frame = ($frame + 1) % 4
            Start-Sleep -Milliseconds 100
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

    function _windo_normalize_published_installer_sha256([string]$Text) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        $m = [regex]::Match($Text, '[A-Fa-f0-9]{64}')
        if (-not $m.Success) { return $null }
        return $m.Value.ToUpperInvariant()
    }

    function _windo_installer_checksum_raw_url {
        return "https://raw.githubusercontent.com/l28bit/windo/Genisis/checksums/installer.sha256"
    }

    function _windo_installer_checksum_api_url {
        return "https://api.github.com/repos/l28bit/windo/contents/checksums/installer.sha256?ref=Genisis"
    }

    function _windo_read_checksum_from_github_contents([string]$Url) {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
        $obj = $resp.Content | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj -or [string]::IsNullOrWhiteSpace([string]$obj.content)) { return $null }
        $base64 = ([string]$obj.content -replace '\s', '')
        $text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
        return (_windo_normalize_published_installer_sha256 $text)
    }

    function _windo_get_published_installer_sha256 {
        $apiUrl = _windo_installer_checksum_api_url
        try {
            $sha = _windo_read_checksum_from_github_contents $apiUrl
            if (_is_sha256_hex $sha) {
                return [pscustomobject]@{ status = "available"; source = "github-api"; url = $apiUrl; sha256 = $sha; error = $null }
            }
        } catch {
            $apiError = $_.Exception.Message
        }

        $rawUrl = _windo_installer_checksum_raw_url
        try {
            $resp = Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
            $sha = _windo_normalize_published_installer_sha256 ([string]$resp.Content)
            if (_is_sha256_hex $sha) {
                return [pscustomobject]@{ status = "available"; source = "raw-fallback"; url = $rawUrl; sha256 = $sha; error = $null }
            }
            return [pscustomobject]@{ status = "invalid"; source = "raw-fallback"; url = $rawUrl; sha256 = $sha; error = "published checksum was reachable but did not contain a valid SHA256" }
        } catch {
            $msg = $_.Exception.Message
            if ($apiError) { $msg = "github-api: $apiError; raw: $msg" }
            return [pscustomobject]@{ status = "unavailable"; source = "none"; url = $rawUrl; sha256 = $null; error = $msg }
        }
    }

    function _windo_verify_installer_sha256_optional([string]$Path) {
        if ($env:WINDO_SKIP_INSTALLER_SHA256) { return }
        if (!(Test-Path $Path)) { return }
        $published = _windo_get_published_installer_sha256
        $expect = $published.sha256
        if ($null -eq $expect) { return }
        $got = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($got -cne $expect) {
            throw "Installer SHA256 does not match published checksum (branch Genisis). Set `$env:WINDO_SKIP_INSTALLER_SHA256=1 to skip. Expected=$expect Got=$got"
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
            [pscustomobject]@{ title = "Launchpad"; command = "windo launchpad --open"; note = "Open the special edition command center." },
            [pscustomobject]@{ title = "Integrity"; command = "windo integrity"; note = "Runner and updater file integrity." },
            [pscustomobject]@{ title = "Audit verify"; command = "windo verify"; note = "DPAPI audit line hash and chain verification." },
            [pscustomobject]@{ title = "Keybinding repair"; command = "windo repair"; note = "Safe-reset stuck prefix/keybinding state." },
            [pscustomobject]@{ title = "Safe upgrade"; command = "windo install-latest"; note = "Non-elevated verified download, then UAC install." }
        )
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
            'function Show-WindoLaunchpadWindow {',
            '    $form = New-Object System.Windows.Forms.Form',
            '    $form.Text = "WINDO Launchpad"',
            '    $form.Size = New-Object System.Drawing.Size(650, 535)',
            '    $form.StartPosition = "CenterScreen"',
            '    $form.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)',
            '    $form.ForeColor = [System.Drawing.Color]::White',
            '    $title = New-Object System.Windows.Forms.Label',
            '    $title.Text = "WINDO Launchpad"',
            '    $title.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)',
            '    $title.AutoSize = $true',
            '    $title.Location = New-Object System.Drawing.Point(20, 18)',
            '    $form.Controls.Add($title)',
            '    $subtitle = New-Object System.Windows.Forms.Label',
            '    $subtitle.Text = "Special Edition tray command center - v$version"',
            '    $subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 10)',
            '    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)',
            '    $subtitle.AutoSize = $true',
            '    $subtitle.Location = New-Object System.Drawing.Point(24, 62)',
            '    $form.Controls.Add($subtitle)',
            '    $y = 105',
            '    foreach ($a in $actions) {',
            '        $btn = New-Object System.Windows.Forms.Button',
            '        $btn.Text = $a.Text',
            '        $btn.Tag = $a.Command',
            '        $btn.Width = 250',
            '        $btn.Height = 34',
            '        $btn.Location = New-Object System.Drawing.Point(24, $y)',
            '        $btn.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)',
            '        $btn.ForeColor = [System.Drawing.Color]::White',
            '        $btn.FlatStyle = "Flat"',
            '        $btn.Add_Click({ Start-WindoTrayCommand ([string]$this.Tag) })',
            '        $form.Controls.Add($btn)',
            '        $cmd = New-Object System.Windows.Forms.Label',
            '        $cmd.Text = $a.Command',
            '        $cmd.Font = New-Object System.Drawing.Font("Consolas", 9)',
            '        $cmd.ForeColor = [System.Drawing.Color]::FromArgb(191, 219, 254)',
            '        $cmd.AutoSize = $true',
            '        $cmd.Location = New-Object System.Drawing.Point(292, ($y + 8))',
            '        $form.Controls.Add($cmd)',
            '        $y += 42',
            '    }',
            '    $hint = New-Object System.Windows.Forms.Label',
            '    $hint.Text = "Commands open in PowerShell windows so output stays visible. Exit from the tray icon menu."',
            '    $hint.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)',
            '    $hint.AutoSize = $true',
            '    $hint.Location = New-Object System.Drawing.Point(24, 460)',
            '    $form.Controls.Add($hint)',
            '    [void]$form.ShowDialog()',
            '}',
            '$notify = New-Object System.Windows.Forms.NotifyIcon',
            '$notify.Text = "WINDO Launchpad v$version"',
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
            '    $notify.BalloonTipTitle = "WINDO Launchpad"',
            '    $notify.BalloonTipText = "Ready. Right-click for preflight, dashboard, integrity, verify, repair, and update actions."',
            '    $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info',
            '    $notify.ShowBalloonTip(6000)',
            '})',
            '$exitItem = $menu.Items.Add("Exit")',
            '$exitItem.Add_Click({',
            '    $notify.Visible = $false',
            '    $notify.Dispose()',
            '    [System.Windows.Forms.Application]::Exit()',
            '})',
            '$notify.ContextMenuStrip = $menu',
            '$notify.Add_DoubleClick({ Show-WindoLaunchpadWindow })',
            '$notify.BalloonTipTitle = "WINDO Launchpad"',
            '$notify.BalloonTipText = "Special Edition tray command center is running. Double-click the shield or right-click for actions."',
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
        $trayIconPath = $null
        $candidateIconPaths = @(
            [string]$env:WINDO_TRAY_ICON,
            (Join-Path $HOME "Documents\GitHub\windo\brand\Enterprise\assets\ico\windo-tray-ready.ico"),
            (Join-Path $HOME "Documents\windo\brand\Enterprise\assets\ico\windo-tray-ready.ico"),
            (Join-Path $HOME "Documents\windo\assets\ico\windo-tray-ready.ico")
        )
        foreach ($candidateIconPath in $candidateIconPaths) {
            if (-not [string]::IsNullOrWhiteSpace($candidateIconPath) -and (Test-Path -LiteralPath $candidateIconPath)) {
                $trayIconPath = $candidateIconPath
                break
            }
        }
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
                Summary     = "Download and run latest installer from Genisis."
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
                Description = "Uses the bundled local uninstaller when present, otherwise downloads it from Genisis, then starts an elevated uninstall."
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
                Summary     = "Show the V5 runway release train."
                Syntax      = @("windo roadmap [--json]")
                Description = "Displays the planned sequence from the current 3.x hardening train through 4.x platform layering and the V5 Special Edition target."
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
                Name        = "syntax"
                Category    = "Planning"
                Summary     = "Map operator intent to exact WINDO commands without executing them."
                Syntax      = @("windo syntax [query] [--json]")
                Description = "Read-only Syntax Forge catalog for common intents like update, trust, health, repair keys, support bundle, recipes, and launchpad."
                Notes       = "Designed as the safe foundation for future command aliases: it shows the command, preview command, risk class, and notes before anything privileged runs."
                Examples    = @("windo syntax", "windo syntax update", "windo syntax proof --json", "windo syntax repair keys")
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
                Summary     = "Show known profile paths and WINDO block presence."
                Syntax      = @("windo profile [--json]")
                Description = "Checks current host profile and standard PowerShell profile files."
                Notes       = "Use this if bindings are not active in a host."
                Examples    = @("windo profile", "windo profile --json")
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
                Summary     = "Open the Special Edition operator command center."
            Syntax      = @("windo launchpad [--json]", "windo launchpad --tray", "windo launchpad --html [--output path|--output=path]", "windo launchpad --open")
                Description = "Generates a local command center with health checks, copy-ready recovery/update commands, recipes, modules, and current paths. --tray starts a native Windows task-tray command center."
                Notes       = "Launchpad is read-only and local-only; tray mode uses Windows Forms and runs until you exit it from the tray icon."
                Examples    = @("windo launchpad", "windo launchpad --tray", "windo launchpad --json", "windo launchpad --open")
            },
            [pscustomobject]@{
                Name        = "export"
                Category    = "Reporting"
                Summary     = "Bundle manifest, config payload, and log excerpt."
                Syntax      = @("windo export [-o zip] [-n N] [--redact] [--json]", "windo --json export …")
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
                Description = "Downloads the published extras index from GitHub (Genisis) and searches entries. Fetch downloads artifacts only from a non-elevated shell and verifies SHA256 when published."
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
                Notes       = "For a full profile refresh from Genisis, run 'windo install-latest' from a non-elevated shell after repair."
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

    if ($Command.Count -ge 1 -and $Command[0] -eq "profile") {
        $paths = @(_windo_profile_path_list | Sort-Object)
        $curPf = $null
        try { $curPf = [System.IO.Path]::GetFullPath([string]$PROFILE) } catch { $curPf = $null }
        $rows = [System.Collections.ArrayList]@()
        foreach ($p in $paths) {
            $st = _windo_read_profile_windo_status $p
            $isCur = $false
            if ($curPf) {
                try { $isCur = ([System.IO.Path]::GetFullPath($p) -eq $curPf) } catch { $isCur = $false }
            }
            [void]$rows.Add([pscustomobject]@{
                path = $p
                filePresent = $st.present
                hasWindoBlock = $st.hasWindoBlock
                isCurrentProfile = $isCur
            })
        }
        if ($JsonOutput) {
            _emit_json "profile" @{ profiles = @($rows); exitCode = 0 }
            _windo_set_exit 0
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
        }
        _windo_set_exit 0
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

    if ($Command.Count -ge 1 -and $Command[0] -eq "syntax") {
        $queryParts = [System.Collections.ArrayList]@()
        $badArgs = [System.Collections.ArrayList]@()
        for ($si = 1; $si -lt $Command.Count; $si++) {
            $sa = [string]$Command[$si]
            if ([string]::IsNullOrWhiteSpace($sa)) { continue }
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
        $jsonEnvNote = "CLI JSON shape: schemaVersion=$($effJson.schemaLabel), meta=$(if ($effJson.includeMeta) { 'on' } else { 'off' }); env wins over $($PrefsFile); see windo theme"
        $keybindingNote = if ($kbPolicy.enabled) { "enabled: chord=$($kbPolicy.chord) (source=$($kbPolicy.chordSource))" } else { "disabled" + $(if ($kbPolicy.disabledSource) { " by $($kbPolicy.disabledSource)" } else { "" }) }
        $rows = [System.Collections.ArrayList]@(
            [pscustomobject]@{ name = "WINDO_NO_SPINNER"; environmentValue = $(if ($env:WINDO_NO_SPINNER) { [string]$env:WINDO_NO_SPINNER } else { $null }); effectiveNote = $(if ($env:WINDO_NO_SPINNER) { "spinners disabled" } else { "default (interactive spinners when stderr is a console)" }) }
            [pscustomobject]@{ name = "CI"; environmentValue = $(if ($env:CI) { [string]$env:CI } else { $null }); effectiveNote = $(if ($env:CI) { "spinners disabled (CI set)" } else { "unset" }) }
            [pscustomobject]@{ name = "WINDO_RUNNER_TIMEOUT_MS"; environmentValue = $(if ($env:WINDO_RUNNER_TIMEOUT_MS) { [string]$env:WINDO_RUNNER_TIMEOUT_MS } else { $null }); effectiveNote = "${tmo} ms (clamped 1..86400000; default 7200000)" }
            [pscustomobject]@{ name = "WINDO_RUNNER_MAX_OUTPUT_BYTES"; environmentValue = $(if ($env:WINDO_RUNNER_MAX_OUTPUT_BYTES) { [string]$env:WINDO_RUNNER_MAX_OUTPUT_BYTES } else { $null }); effectiveNote = "per-stream capture cap ${mcs} chars (derived from env total bytes; see runner)" }
            [pscustomobject]@{ name = "WINDO_MAX_COMMAND_CHARS"; environmentValue = $(if ($env:WINDO_MAX_COMMAND_CHARS) { [string]$env:WINDO_MAX_COMMAND_CHARS } else { $null }); effectiveNote = "${mcc} chars (max 8191)" }
            [pscustomobject]@{ name = "WINDO_SKIP_INSTALLER_SHA256"; environmentValue = $(if ($env:WINDO_SKIP_INSTALLER_SHA256) { [string]$env:WINDO_SKIP_INSTALLER_SHA256 } else { $null }); effectiveNote = $(if ($env:WINDO_SKIP_INSTALLER_SHA256) { "bootstrap/upgrade checksum check skipped" } else { "checksum enforced when published on Genisis" }) }
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
            [pscustomobject]@{ name = "WINDO_EXTRAS_INDEX_URL"; environmentValue = $(if ($env:WINDO_EXTRAS_INDEX_URL) { [string]$env:WINDO_EXTRAS_INDEX_URL } else { $null }); effectiveNote = "resolved extras index: $(_windo_extras_index_url)" }
        )
        if ($JsonOutput) {
            _emit_json "config" @{
                settings = @($rows)
                secureDir = $SecureDir
                keybindingPolicy = $kbPolicy
                completionPolicy = $completionPolicy
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
            targetMajor = "5.0.0"
            releaseTrain = @($releases)
            principles = @(
                "Keep deliberate elevation and auditability as the core.",
                "Ship hardening and shell ergonomics in small verified sub-versions.",
                "Reveal V5 as a polished package after the foundations are already proven."
            )
            docs = "docs/v5-roadmap.md"
            exitCode = 0
        }
        if ($JsonOutput) {
            _emit_json "roadmap" $payload
        } else {
            Write-Host "[windo] V5 runway" -ForegroundColor Cyan
            Write-Host "  Current : $WindoVersion" -ForegroundColor DarkGray
            Write-Host "  Target  : 5.0.0 Special Edition Extravaganza" -ForegroundColor Yellow
            foreach ($r in $releases) {
                $color = if ($r.status -eq "in-progress") { "Green" } elseif ($r.status -eq "target") { "Magenta" } else { "DarkGray" }
                Write-Host ("  {0,-7} {1,-30} {2}" -f $r.version, $r.codename, $r.status) -ForegroundColor $color
                Write-Host ("          {0}" -f $r.theme) -ForegroundColor DarkGray
            }
            Write-Host "  Docs    : docs/v5-roadmap.md" -ForegroundColor DarkGray
        }
        _windo_set_exit 0
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "completion") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }
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
            if ($JsonOutput) { _emit_json "completion" @{ error = "expected status | native-first | hybrid | windo | off | reset"; exitCode = 2 } }
            else {
                Write-Host "[windo] completion: expected status | native-first | hybrid | windo | off | reset" -ForegroundColor Yellow
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
                Write-Host "  (Runner, tasks, and audit security are unchanged—only CLI JSON shape.)" -ForegroundColor DarkGray
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
            Write-Host "  Saved preset  : $(if ($fileMode) { $fileMode } else { '(none → auto)' })"
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
                template = " WINDO {{ if .Env.WINDO_VERSION }}v{{ .Env.WINDO_VERSION }}{{ end }}{{ if .Env.WINDO_LAST_REQUEST_ID }} · {{ .Env.WINDO_LAST_REQUEST_ID }}{{ end }} "
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
  "requiresWindoVersion": "3.6.2"
}
"@
        $lp = @"
# WINDO module $mid — loaded after WINDO core (non-fatal on error)
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
            $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO dashboard</title>')
            $null = $sb.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f5f7fa;color:#172033}.wrap{max-width:1180px;margin:0 auto;padding:28px}h1{margin:0 0 6px}.meta{color:#5d6978}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin:18px 0}.card{background:white;border:1px solid #dde3ea;border-radius:8px;padding:14px}.k{font-size:12px;text-transform:uppercase;color:#667085}.v{font-size:28px;font-weight:700;margin-top:4px}.ok{color:#067647}.warn{color:#b54708}.bad{color:#b42318}.bar{height:12px;background:#e6eaf0;border-radius:3px;overflow:hidden}.fill{height:100%;background:#2563eb}table{border-collapse:collapse;width:100%;background:white;border:1px solid #dde3ea}th,td{padding:8px;border-bottom:1px solid #e6eaf0;text-align:left}th{background:#eef2f6}code{background:#eef2f6;padding:2px 4px;border-radius:4px}</style></head><body><div class="wrap">')
            $null = $sb.AppendLine(("<h1>WINDO dashboard</h1><div class='meta'>Generated {0} on {1}. Local-only HTML; command text may be sensitive.</div>" -f (_html_escape (Get-Date -Format "yyyy-MM-dd HH:mm:ss")), (_html_escape $payload.host)))
            $null = $sb.AppendLine("<div class='grid'>")
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Health</div><div class='v {0}'>{1}</div><div class='bar'><div class='fill' style='width:{2}%'></div></div></div>" -f $statusClass, (_html_escape $status), [int]$score))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Audit entries</div><div class='v'>{0}</div><div class='meta'>verify: {1}</div></div>" -f $entries.Count, $(if ($vf.verifyOk) { 'OK' } else { _html_escape ([string]$vf.error) })))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Integrity</div><div class='v {0}'>{1}</div><div class='meta'>runner {2}, updater {3}</div></div>" -f $(if ($ix.OverallLevel -eq 'OK') { 'ok' } else { 'bad' }), (_html_escape $ix.OverallLevel), (_html_escape $ix.RunnerLevel), (_html_escape $ix.UpdaterLevel)))
            $null = $sb.AppendLine(("<div class='card'><div class='k'>Tasks</div><div class='v'>{0}/{1}</div><div class='meta'>main / self-update</div></div>" -f $(if ($mainTask) { 'ok' } else { 'missing' }), $(if ($updateTask) { 'ok' } else { 'missing' })))
            $null = $sb.AppendLine("</div>")
            if ($issues.Count -gt 0) { $null = $sb.AppendLine(("<div class='card'><div class='k'>Issues</div><p>{0}</p></div>" -f (_html_escape (@($issues) -join '; ')))) }
            $null = $sb.AppendLine("<h2>Audit categories</h2><table><tr><th>Category</th><th>Count</th><th>Visual</th></tr>")
            foreach ($name in @('SUCCESS','NONZERO','ELEVATION_FAILED','OTHER')) {
                $pct = [Math]::Round(([int]$cat[$name] / [double]$maxCat) * 100)
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td><div class='bar'><div class='fill' style='width:{2}%'></div></div></td></tr>" -f $name, [int]$cat[$name], $pct))
            }
            $null = $sb.AppendLine("</table><h2>Recent audit</h2><table><tr><th>Time</th><th>Exit</th><th>Elevation</th><th>Command</th></tr>")
            foreach ($e in $recent) {
                $cmd = [string]$e.command
                if ($cmd.Length -gt 220) { $cmd = $cmd.Substring(0, 220) + "..." }
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>" -f (_html_escape $e.timestamp), (_html_escape ([string]$e.exitCode)), (_html_escape ([string]$e.elevation)), (_html_escape $cmd)))
            }
            $null = $sb.AppendLine(("</table><h2>Paths</h2><p><code>{0}</code><br><code>{1}</code></p></div></body></html>" -f (_html_escape $SecureDir), (_html_escape $LogFile)))
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
            $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO Launchpad</title>')
            $null = $sb.AppendLine('<style>body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#0f172a;color:#e5e7eb}.wrap{max-width:1220px;margin:0 auto;padding:28px}.hero{border-bottom:1px solid #334155;padding-bottom:18px}.brand{max-width:360px;width:100%;height:auto;margin-bottom:8px}.title{font-size:38px;font-weight:800}.sub{color:#94a3b8}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px;margin:18px 0}.card{background:#111827;border:1px solid #334155;border-radius:8px;padding:14px}.k{font-size:12px;text-transform:uppercase;color:#94a3b8}.v{font-size:30px;font-weight:800}.ready{color:#22c55e}.attention{color:#f59e0b}.repair{color:#ef4444}button{background:#2563eb;color:white;border:0;border-radius:6px;padding:7px 10px;cursor:pointer}code{background:#020617;border:1px solid #334155;border-radius:5px;padding:3px 5px;color:#bfdbfe}.row{display:flex;gap:8px;align-items:center;justify-content:space-between;border-top:1px solid #1f2937;padding:10px 0}.muted{color:#94a3b8}table{width:100%;border-collapse:collapse;background:#111827;border:1px solid #334155}th,td{padding:8px;border-bottom:1px solid #1f2937;text-align:left}th{background:#1f2937}</style></head><body><div class="wrap">')
            $brandImg = ""
            if (-not [string]::IsNullOrWhiteSpace($brandLogoPath)) {
                $brandImg = "<img class='brand' alt='WINDO' src='$(_html_escape ([uri]$brandLogoPath).AbsoluteUri)'>"
            }
            $null = $sb.AppendLine(("<div class='hero'>{0}<div class='title'>WINDO Launchpad</div><div class='sub'>Special Edition command center generated {1}. Local-only; command text may be sensitive.</div></div>" -f $brandImg, (_html_escape (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))))
            $cls = $status.ToLowerInvariant()
            $null = $sb.AppendLine(("<div class='grid'><div class='card'><div class='k'>Status</div><div class='v {0}'>{1}</div></div><div class='card'><div class='k'>Score</div><div class='v'>{2}/100</div></div><div class='card'><div class='k'>Checks</div><div class='v'>{3}</div><div class='muted'>{4} need attention</div></div></div>" -f $cls, $status, [int]$score, $checks.Count, $failed.Count))
            $null = $sb.AppendLine("<h2>Quick actions</h2><div class='card'>")
            foreach ($a in $actions) {
                $null = $sb.AppendLine(("<div class='row'><div><strong>{0}</strong><div class='muted'>{1}</div><code>{2}</code></div><button onclick=""copyCmd('{3}')"">Copy</button></div>" -f (_html_escape $a.title), (_html_escape $a.note), (_html_escape $a.command), (_html_escape ($a.command -replace "'", "\'"))))
            }
            $null = $sb.AppendLine("</div><h2>Preflight</h2><table><tr><th>Check</th><th>Status</th><th>Detail</th><th>Fix</th></tr>")
            foreach ($c in $checks) {
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td><code>{3}</code></td></tr>" -f (_html_escape $c.label), $(if ($c.ok) { 'OK' } else { _html_escape $c.severity }), (_html_escape $c.detail), (_html_escape $c.fixCommand)))
            }
            $null = $sb.AppendLine("</table><h2>Recipes</h2><table><tr><th>ID</th><th>Description</th><th>Command</th></tr>")
            foreach ($r in $recipes) {
                $cmd = "windo recipes run $($r.id)"
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td><code>{2}</code></td></tr>" -f (_html_escape $r.id), (_html_escape $r.description), (_html_escape $cmd)))
            }
            $null = $sb.AppendLine("</table><h2>Modules</h2><table><tr><th>ID</th><th>Status</th><th>Entry</th></tr>")
            foreach ($m in $modules) {
                $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>" -f (_html_escape $m.id), $(if ($m.enabled) { 'enabled' } else { 'available' }), (_html_escape $m.entry)))
            }
            $null = $sb.AppendLine("</table><script>")
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
            Write-Host "[windo] ai $sub — AI / local env names only (values never shown)" -ForegroundColor Cyan
            Write-Host "  Elevated         : $($snap.elevated)" -ForegroundColor DarkGray
            Write-Host "  Ollama (set)     : $(if ($snap.ollamaSetNames.Count) { $snap.ollamaSetNames -join ', ' } else { '(none)' })" -ForegroundColor DarkGray
            Write-Host "  Process (set)    : $(if ($snap.processSetNames.Count) { $snap.processSetNames -join ', ' } else { '(none)' })"
            Write-Host "  User scope (set) : $(if ($snap.userSetNames.Count) { $snap.userSetNames -join ', ' } else { '(none)' })"
            Write-Host "  Machine (set)    : $(if ($snap.machineSetNames.Count) { $snap.machineSetNames -join ', ' } else { '(none)' })"
            foreach ($iss in $issues) { Write-Host "  ! $iss" -ForegroundColor Yellow }
            if ($sub -eq "doctor") { foreach ($r in $rec) { Write-Host "  → $r" -ForegroundColor DarkGray } }
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
            "Open a new terminal or run:  . `$PROFILE  — so your profile block matches prefs.",
            "From a normal (non-elevated) window:  windo install-latest  — refreshes the embedded profile from Genisis when you are behind."
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
            Write-Host "[windo] repair ($sub): keybindings safe-reset — legacy WINDO chords cleared this session; prefix preference Alt+w." -ForegroundColor Green
            Write-Host "  Effective: $(if ($pol.enabled) { $pol.chord } else { '(disabled)' }) (source=$($pol.chordSource))" -ForegroundColor DarkGray
            foreach ($h in $hints) { Write-Host "  → $h" -ForegroundColor DarkGray }
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
                Write-Host "[windo] keybindings doctor (advisory — heuristic only)" -ForegroundColor Cyan
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
            $suFrame = 0
            $suLabel = "[windo] Self-update running..."
            while ($sw.Elapsed.TotalSeconds -lt 10) {
                if (Test-Path $UpdateLast) {
                    $current = (Get-Item $UpdateLast).LastWriteTime
                    $content = Get-Content -Raw -Path $UpdateLast -ErrorAction SilentlyContinue
                    if (($before -eq $null -or $current -gt $before) -and $content -match 'SELF-UPDATE END') { break }
                }
                _windo_spinner_line $suLabel $suFrame
                $suFrame = ($suFrame + 1) % 4
                Start-Sleep -Milliseconds 200
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
        Write-Host "    WINDO_NO_SPINNER, WINDO_RUNNER_TIMEOUT_MS, WINDO_RUNNER_MAX_OUTPUT_BYTES" -ForegroundColor DarkGray
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

    $waitFrame = 0
    $waitLabel = "[windo] Waiting for elevated result..."
    while (!(Test-Path $outPath) -and $sw.Elapsed.TotalSeconds -lt 20) {
        _windo_spinner_line $waitLabel $waitFrame
        $waitFrame = ($waitFrame + 1) % 4
        Start-Sleep -Milliseconds 100
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
    if (-not $policy.enabled) { return }
    if ([string]::IsNullOrWhiteSpace($policy.chord)) { return }

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

        if ($null -eq $selectedPrefixChord) { return }
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
            $m = [regex]::Match($line, '^\s*windo\s+', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
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
                if ($mode -eq "native-first") { return }
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
            if ($isExactBuiltin) { return }
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
# WINDO optional modules loader (enabled in %USERPROFILE%\.pwsh_secure\windo_prefs.json → enabledModules)
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
Write-WindoInstallStep -Status ok -Label "WINDO v$WindoVersion Special Edition installed" -Detail "snapshot: $SnapshotDir" -Color Green
Write-Host ""
Write-Host "  Next in a normal shell:" -ForegroundColor Yellow
Write-Host "    . `$PROFILE" -ForegroundColor Yellow
Write-Host "    windo preflight" -ForegroundColor Yellow
Write-Host "    windo dashboard --html" -ForegroundColor Yellow
Write-Host "    windo version" -ForegroundColor Yellow
Write-Host ""
