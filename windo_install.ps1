<# =====================================================================
WINDO v3.1.1 Release-Hardened Installer
Run once in an elevated PowerShell session.

Installs:
- $HOME\.pwsh_secure\
- windo_runner.ps1
- windo_self_update.ps1
- windo_manifest.json
- Scheduled tasks:
    - WindoElevatedRunner
    - WindoSelfUpdate
- WINDO profile block in $PROFILE (windo function + PSReadLine keybindings + delegated tab completion)
- Snapshot copies under $HOME\Documents\windo\

Maintainer: new windo subcommands must be added to $WindoBuiltinVerbs (single source for profile completer + last-command exclusions).
===================================================================== #>

$ErrorActionPreference = "Stop"

$WindoVersion = "3.1.1"

# Single source of truth for embedded profile: completer skip-list (plus '!!') and windo last-command first-token exclusions.
$WindoBuiltinVerbs = @(
    'help', 'last', 'stats', 'history', 'report', 'export', 'self-update', 'version',
    'doctor', 'integrity', 'verify', 'log', 'cleanup', 'config', 'backups', 'context', 'trace', 'replay',
    'theme', 'upgrade', 'install-latest', 'uninstall', 'profile'
)
$WindoBuiltinVerbsArrayLiteral = ($WindoBuiltinVerbs | ForEach-Object { "'$_'" }) -join ','
$TaskMain     = "WindoElevatedRunner"
$TaskUpdate   = "WindoSelfUpdate"

$SecureDir    = Join-Path $HOME ".pwsh_secure"
$RunnerPath   = Join-Path $SecureDir "windo_runner.ps1"
$UpdateScript = Join-Path $SecureDir "windo_self_update.ps1"
$RunnerLast   = Join-Path $SecureDir "windo_runner_last.txt"
$UpdateLast   = Join-Path $SecureDir "windo_self_update_last.txt"
$LogFile      = Join-Path $SecureDir "windo_history.enc"
$ManifestFile = Join-Path $SecureDir "windo_manifest.json"
$SnapshotDir  = Join-Path (Join-Path $HOME "Documents") "windo"

$BeginMarker  = "# >>> WINDO-BEGIN >>>"
$EndMarker    = "# <<< WINDO-END <<<"

function Ensure-DirLockedToCurrentUser {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }

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
    $pattern = [regex]::Escape($BeginMarker) + ".*?" + [regex]::Escape($EndMarker)
    if ($text -match $pattern) {
        $text = [regex]::Replace($text, $pattern, "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $text = $text -replace "(\r?\n){3,}", "`r`n`r`n"
        Write-Utf8NoBomFile -Path $PROFILE -Content ($text.TrimEnd() + "`r`n")
    }
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

Import-Module ScheduledTasks -ErrorAction Stop
Ensure-DirLockedToCurrentUser -Path $SecureDir

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
    $timeoutMs = Get-WindoRunnerTimeoutMs
    $maxPer = Get-WindoRunnerMaxCharsPerStream
    $stdout = [string]$null
    $stderr = [string]$null
    $timedOut = $false
    $truncated = $false
    $exitCode = 0

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

$MainActionArgs   = Get-NoWindowActionArgs -ScriptPath $RunnerPath
$UpdateActionArgs = Get-NoWindowActionArgs -ScriptPath $UpdateScript

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

$Manifest = [ordered]@{
    version = $WindoVersion
    files = [ordered]@{
        runner = [ordered]@{
            path = $RunnerPath
            sha256 = Get-FileHashString -Path $RunnerPath
        }
        self_update = [ordered]@{
            path = $UpdateScript
            sha256 = Get-FileHashString -Path $UpdateScript
        }
    }
    generated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}
$Manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestFile -Encoding UTF8

Remove-ExistingWindoBlockFromProfile
Ensure-ProfileExists

$WindoFunctionBody = @'
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
    if ($Command -and $Command.Count -gt 0) {
        $cl = [System.Collections.ArrayList]@($Command)
        for ($xi = $cl.Count - 1; $xi -ge 0; $xi--) {
            $tx = [string]$cl[$xi]
            if ($tx -eq '--json' -or $tx -eq '-Json') {
                $JsonOutput = $true
                $null = $cl.RemoveAt($xi)
            }
        }
        for ($xi = $cl.Count - 1; $xi -ge 0; $xi--) {
            $tx = [string]$cl[$xi]
            if ($tx -eq '--dry-run' -or $tx -eq '-DryRun') {
                $DryRun = $true
                $null = $cl.RemoveAt($xi)
            }
        }
        $Command = @($cl)
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
        } elseif (($env:TERM_PROGRAM -replace '\s', '') -ieq 'vscode') {
            $chord = "Alt+w"
            $chordSource = "auto"
        } else {
            $chord = "w,w"
            $chordSource = "auto"
        }

        if ($disabled) {
            $chord = $null
            $chordSource = $null
        }

        [pscustomobject]@{
            enabled = [bool](-not $disabled)
            disabled = [bool]$disabled
            disabledSource = $disabledSource
            chord = $chord
            chordSource = $chordSource
            prefChord = $prefChord
            envChord = $(if ([string]::IsNullOrWhiteSpace($envChord)) { $null } else { $envChord.Trim() })
        }
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
        $legacyChords = @('w,w', 'Alt+w', 'Shift+Enter', 'Alt+Enter')
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

        try { Set-PSReadLineKeyHandler -Chord $policy.chord -ScriptBlock $windoPrefixOnly } catch { }
        try { Set-PSReadLineKeyHandler -Chord 'Shift+Enter' -ScriptBlock $windoPrefixRun } catch { }
        try { Set-PSReadLineKeyHandler -Chord 'Alt+Enter' -ScriptBlock $windoPrefixRun } catch { }
        return $true
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

    function _windo_run_genisis_installer {
        param(
            [switch]$ForceContinue
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
            } elseif (-not [Environment]::UserInteractive) {
                Write-Host "[windo] Non-interactive session: re-run with --force or set WINDO_INSTALL_NONINTERACTIVE=1" -ForegroundColor Yellow
                Remove-Item -LiteralPath $TempInst -Force -ErrorAction SilentlyContinue
                _windo_set_exit 2
                return
            } else {
                Write-Host "[windo] The installer is ready. You can review the file before continuing: $TempInst" -ForegroundColor Cyan
                $ans = Read-Host "Run the installer now? (UAC may prompt for elevation to register tasks.) [y/N]"
                if ($ans -eq 'y' -or $ans -eq 'Y' -or $ans -eq 'yes') { $runNow = $true }
            }
            if (-not $runNow) {
                Write-Host "[windo] Cancelled; temporary installer removed." -ForegroundColor DarkYellow
                Remove-Item -LiteralPath $TempInst -Force -ErrorAction SilentlyContinue
                _windo_set_exit 0
                return
            }
            $runnerExe = "powershell.exe"
            $pwshExe = Get-Command pwsh.exe -ErrorAction SilentlyContinue
            if ($pwshExe) { $runnerExe = $pwshExe.Source }
            Write-Host "[windo] Starting installer ($runnerExe). When it finishes, reload: . `$PROFILE" -ForegroundColor Yellow
            & $runnerExe -NoProfile -ExecutionPolicy Bypass -File $TempInst
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

    function _windo_verify_installer_sha256_optional([string]$Path) {
        if ($env:WINDO_SKIP_INSTALLER_SHA256) { return }
        if (!(Test-Path $Path)) { return }
        $sumUrl = "https://raw.githubusercontent.com/l28bit/windo/Genisis/checksums/installer.sha256"
        $expect = $null
        try {
            $expect = ([string](Invoke-RestMethod -Uri $sumUrl -TimeoutSec 25)).Trim()
        } catch {
            return
        }
        if ($expect -notmatch '^[A-Fa-f0-9]{64}$') { return }
        $got = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
        if ($got.ToUpperInvariant() -cne $expect.ToUpperInvariant()) {
            throw "Installer SHA256 does not match published checksum (branch Genisis). Set `$env:WINDO_SKIP_INSTALLER_SHA256=1 to skip. Expected=$expect Got=$got"
        }
    }

    # Time filter: keep in sync with src/windo/snippets/StatsTimeFilter.ps1 (Test-WindoLogic covers the snippet).
    function _windo_filter_entries_by_time($entries, $sinceDate, $lastDays) {
        $cutoff = $null
        if ($null -ne $sinceDate) {
            $cutoff = $sinceDate.Date
        } elseif ($null -ne $lastDays -and [int]$lastDays -gt 0) {
            $cutoff = (Get-Date).Date.AddDays(-[int]$lastDays)
        }
        if ($null -eq $cutoff) { return @($entries) }
        $out = [System.Collections.ArrayList]@()
        foreach ($e in $entries) {
            try {
                $ts = [DateTime]::Parse([string]$e.Timestamp, [System.Globalization.CultureInfo]::InvariantCulture)
                if ($ts -ge $cutoff) { [void]$out.Add($e) }
            } catch { }
        }
        return @($out)
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

    if ($Command.Count -ge 1 -and $Command[0] -eq "help") {
        $helpText = @(
            "windo <command...>         Elevate and run via task bridge",
            "windo !! | windo replay     Re-run last stored elevated command",
            "windo last                  Show last stored command + metadata",
            "windo context [--json]      Shell/WINDO environment summary",
            "windo config [--json]       Effective WINDO_* / CI settings (runner semantics)",
            "windo backups [--json]      List windo_history*.enc.bak; --prune --keep N --force",
            "windo keybindings [status|set --chord <chord>|disable|enable|reset]  Configure keyboard shortcuts safely",
            "windo profile [--json]      Which profile paths exist and contain the WINDO block",
            "windo trace <RequestId>     Find audit log entry by RequestId",
            "windo stats [--since YYYY-MM-DD] [--last-days N]   Summarize audit log (Timestamp filter; --last-days is positive int)",
            "windo history [-n N]        Compact recent commands (default N=50)",
            "windo report [-o path]      HTML audit report (summary + categories)",
            "windo export [-o zip] [-n N] [--redact]  Bundle manifest + JSON + log excerpt",
            "windo self-update           Repair/update scheduled task actions",
            "windo version [--json]      Version and paths",
            "windo doctor [--json]       Health / paths / tasks",
            "windo integrity [--json]    Runner vs manifest (OK|DRIFT|TAMPERED|UNKNOWN)",
            "windo verify [--json]       Hash chain validation on log",
            "windo log -n N [--tail] [--json]  Decrypted log entries (--tail: last N physical lines only for JSON)",
            "windo cleanup [-w]          Backup log, clear active log",
            "windo theme [classic|modern|auto]  JSON envelope look for --json (prefs; runner unchanged)",
            "windo install-latest [--force]  Download+verify non-elevated, then prompt; --force skips prompt (CI)",
            "windo upgrade               Alias of install-latest",
            "windo uninstall             Elevated uninstaller (tasks, profile, secure dir)",
            "Exit: `$global:WINDO_EXIT_CODE set by doctor | integrity | verify (0=ok; see README).",
            "Append --json or -Json; --dry-run for replay/elevated command (no elevation, no log write)."
        ) -join [Environment]::NewLine
        Write-Host $helpText -ForegroundColor Yellow
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

    if ($Command.Count -ge 1 -and $Command[0] -eq "uninstall") {
        $UnUrl = "https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_uninstall.ps1"
        $TempUn = Join-Path $env:TEMP ("windo_uninstall_" + [Guid]::NewGuid().ToString("n") + ".ps1")
        try {
            _windo_invoke_rest_with_spinner -Uri $UnUrl -OutFile $TempUn -Label "Downloading uninstaller..."
            if (!(Test-Path $TempUn)) { throw "Download failed." }
            if ((Get-Item $TempUn).Length -lt 400) { throw "Uninstaller file size looks invalid." }
            Write-Host "[windo] Starting elevated uninstall (UAC). Approve the prompt to remove tasks and WINDO data." -ForegroundColor Yellow
            Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $TempUn) -Wait
        } catch {
            Write-Host "[windo] uninstall: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Run manually (elevated): powershell -ExecutionPolicy Bypass -File path\to\windo_uninstall.ps1" -ForegroundColor DarkGray
        } finally {
            if (Test-Path $TempUn) { Remove-Item $TempUn -Force -ErrorAction SilentlyContinue }
        }
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
        $jsonEnvNote = "CLI JSON shape: schemaVersion=$($effJson.schemaLabel), meta=$(if ($effJson.includeMeta) { 'on' } else { 'off' }); env wins over $($PrefsFile); see windo theme"
        $keybindingNote = if ($kbPolicy.enabled) { "enabled: chord=$($kbPolicy.chord) (source=$($kbPolicy.chordSource))" } else { "disabled" + $(if ($kbPolicy.disabledSource) { " by $($kbPolicy.disabledSource)" } else { "" }) }
        $rows = [System.Collections.ArrayList]@(
            [pscustomobject]@{ name = "WINDO_NO_SPINNER"; environmentValue = $(if ($env:WINDO_NO_SPINNER) { [string]$env:WINDO_NO_SPINNER } else { $null }); effectiveNote = $(if ($env:WINDO_NO_SPINNER) { "spinners disabled" } else { "default (interactive spinners when stderr is a console)" }) }
            [pscustomobject]@{ name = "CI"; environmentValue = $(if ($env:CI) { [string]$env:CI } else { $null }); effectiveNote = $(if ($env:CI) { "spinners disabled (CI set)" } else { "unset" }) }
            [pscustomobject]@{ name = "WINDO_RUNNER_TIMEOUT_MS"; environmentValue = $(if ($env:WINDO_RUNNER_TIMEOUT_MS) { [string]$env:WINDO_RUNNER_TIMEOUT_MS } else { $null }); effectiveNote = "${tmo} ms (clamped 1..86400000; default 7200000)" }
            [pscustomobject]@{ name = "WINDO_RUNNER_MAX_OUTPUT_BYTES"; environmentValue = $(if ($env:WINDO_RUNNER_MAX_OUTPUT_BYTES) { [string]$env:WINDO_RUNNER_MAX_OUTPUT_BYTES } else { $null }); effectiveNote = "per-stream capture cap ${mcs} chars (derived from env total bytes; see runner)" }
            [pscustomobject]@{ name = "WINDO_MAX_COMMAND_CHARS"; environmentValue = $(if ($env:WINDO_MAX_COMMAND_CHARS) { [string]$env:WINDO_MAX_COMMAND_CHARS } else { $null }); effectiveNote = "${mcc} chars (max 8191)" }
            [pscustomobject]@{ name = "WINDO_SKIP_INSTALLER_SHA256"; environmentValue = $(if ($env:WINDO_SKIP_INSTALLER_SHA256) { [string]$env:WINDO_SKIP_INSTALLER_SHA256 } else { $null }); effectiveNote = $(if ($env:WINDO_SKIP_INSTALLER_SHA256) { "bootstrap/upgrade checksum check skipped" } else { "checksum enforced when published on Genisis" }) }
            [pscustomobject]@{ name = "WINDO_JSON_ENVELOPE"; environmentValue = $(if ($env:WINDO_JSON_ENVELOPE) { [string]$env:WINDO_JSON_ENVELOPE } else { $null }); effectiveNote = $jsonEnvNote }
            [pscustomobject]@{ name = "WINDO_PREFIX_CHORD"; environmentValue = $(if ($env:WINDO_PREFIX_CHORD) { [string]$env:WINDO_PREFIX_CHORD } else { $null }); effectiveNote = "effective chord: $($kbPolicy.chord)" }
            [pscustomobject]@{ name = "WINDO_DISABLE_PSREADLINE_BINDINGS"; environmentValue = $(if ($env:WINDO_DISABLE_PSREADLINE_BINDINGS) { [string]$env:WINDO_DISABLE_PSREADLINE_BINDINGS } else { $null }); effectiveNote = $keybindingNote }
            [pscustomobject]@{ name = "WINDO_KEYBINDING_POLICY"; environmentValue = $null; effectiveNote = "effective source chord=$($kbPolicy.chordSource); enabled=$($kbPolicy.enabled)" }
        )
        if ($JsonOutput) {
            _emit_json "config" @{ settings = @($rows); secureDir = $SecureDir; keybindingPolicy = $kbPolicy; exitCode = 0 }
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

    if ($Command.Count -ge 1 -and $Command[0] -eq "keybindings") {
        $sub = "status"
        if ($Command.Count -ge 2) { $sub = [string]$Command[1].Trim().ToLowerInvariant() }

        if ($sub -eq "status") {
            $policy = _windo_resolve_keybinding_policy
            $chords = @('w,w', 'Alt+w', 'Shift+Enter', 'Alt+Enter')
            if ($policy.enabled -and ($null -ne $policy.chord) -and ($chords -notcontains $policy.chord)) {
                $chords = @($policy.chord) + $chords
            }
            $registered = [System.Collections.ArrayList]@()
            $hasRh = Get-Command Get-PSReadLineKeyHandler -ErrorAction SilentlyContinue
            foreach ($c in ($chords | Select-Object -Unique)) {
                $isReg = $false
                if ($hasRh) {
                    try {
                        $handler = Get-PSReadLineKeyHandler -Chord $c -ErrorAction Stop
                        if ($null -ne $handler) { $isReg = $true }
                    } catch { }
                }
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
                    psReadLineAvailable = [bool]$hasRh
                    exitCode = 0
                }
            } else {
                Write-Host "[windo] PSReadLine keybindings policy" -ForegroundColor Cyan
                Write-Host "  Policy enabled : $($policy.enabled)" -ForegroundColor DarkGray
                Write-Host "  Effective      : $(if ($policy.enabled) { $policy.chord } else { '(disabled)' })" -ForegroundColor DarkGray
                if ($policy.enabled) {
                    Write-Host "  Source         : chord=$($policy.chordSource), prefs=$($PrefsFile)" -ForegroundColor DarkGray
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
            $map = _windo_read_windo_prefs_map
            $map['keybindingPrefixChord'] = $setChord.Trim()
            $map['keybindingDisabled'] = $false
            if (-not (_windo_save_windo_prefs $map)) {
                Write-Host "[windo] keybindings set: could not update $PrefsFile" -ForegroundColor Red
                _windo_set_exit 2
                return
            }
            _windo_apply_runtime_keybindings | Out-Null
            $policy = _windo_resolve_keybinding_policy
            if ($JsonOutput) {
                _emit_json "keybindings" @{ action = "set"; chord = $setChord.Trim(); profilePath = $PROFILE; prefsFile = $PrefsFile; policy = $policy; exitCode = 0 }
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

        Write-Host "[windo] keybindings: expected status | set --chord <chord> | disable | enable | reset  (got: $sub)" -ForegroundColor Yellow
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
        _windo_run_genisis_installer -ForceContinue:$forceInst
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
        $sb = [System.Text.StringBuilder]::new()
        $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO audit report</title>')
        $null = $sb.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;background:#fafafa;color:#1a1a1a;}h1{border-bottom:1px solid #ccc;} table{border-collapse:collapse;width:100%;max-width:1200px;} th,td{border:1px solid #ddd;padding:6px;text-align:left;} th{background:#eee;} .ok{color:#0a7a0a;} .bad{color:#a00;} code{background:#eee;padding:2px 4px;}</style></head><body>')
        $null = $sb.AppendLine(("<h1>WINDO audit report</h1><p>Generated {0} on {1}</p><p>Local-only HTML; may include sensitive command text. Choose elevation before execution.</p>" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), [System.Net.Dns]::GetHostName()))
        $null = $sb.AppendLine(("<h2>Summary</h2><table><tr><th>Metric</th><th>Value</th></tr><tr><td>Total entries</td><td>{0}</td></tr><tr><td>Exit code 0</td><td class='ok'>{1}</td></tr><tr><td>Non-zero exit</td><td class='bad'>{2}</td></tr></table>" -f $allRep.Count, $okc, $nz))
        $null = $sb.AppendLine(("<h2>Categories</h2><table><tr><th>Category</th><th>Count</th></tr><tr><td>SUCCESS</td><td>{0}</td></tr><tr><td>NONZERO</td><td>{1}</td></tr><tr><td>ELEVATION_FAILED</td><td>{2}</td></tr><tr><td>OTHER</td><td>{3}</td></tr></table>" -f $cat['SUCCESS'], $cat['NONZERO'], $cat['ELEVATION_FAILED'], $cat['OTHER']))
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
                Write-Host "[windo] Export failed: $($_.Exception.Message)" -ForegroundColor Red
                return
            }
        } finally {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (!(Test-Path -LiteralPath $expZip)) {
            Write-Host "[windo] Export did not produce a zip file." -ForegroundColor Red
            return
        }
        $len = (Get-Item -LiteralPath $expZip).Length
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
        Write-Host "    WINDO_MAX_COMMAND_CHARS, WINDO_SKIP_INSTALLER_SHA256, WINDO_JSON_ENVELOPE, WINDO_PREFIX_CHORD, WINDO_DISABLE_PSREADLINE_BINDINGS  (see README / SECURITY)" -ForegroundColor DarkGray
        Write-Host "  Tip: 'windo config' for effective env; 'windo integrity' for hashes; 'windo verify' for audit chain." -ForegroundColor DarkGray
        Write-Host "  Exit code    : $docExitT  (`$global:WINDO_EXIT_CODE; 0=ok, 2=task/runner, 3=integrity, 6=unknown integrity)" -ForegroundColor DarkGray
        _windo_set_exit $docExitT
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "verify") {
        if (!(Test-Path $LogFile)) {
            if ($JsonOutput) {
                _emit_json "verify" @{ verifyOk = $false; physicalLines = 0; exitCode = 2; error = "no log file" }
            } else {
                Write-Host "[windo] No log file found." -ForegroundColor Yellow
            }
            _windo_set_exit 2
            return
        }
        $lines = @(Get-Content -Path $LogFile)
        if ($lines.Count -eq 0) {
            if ($JsonOutput) {
                _emit_json "verify" @{ verifyOk = $false; physicalLines = 0; exitCode = 2; error = "log empty" }
            } else {
                Write-Host "[windo] Log file is empty." -ForegroundColor Yellow
            }
            _windo_set_exit 2
            return
        }
        $ok = $true
        $prevStoredHash = ""
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Split(":", 2)
            if ($parts.Count -lt 2) { Write-Host "[windo] INVALID FORMAT at line $($i+1)" -ForegroundColor Red; $ok = $false; break }
            $storedHash = $parts[0]
            $b64 = $parts[1]
            try { $json = _dpapi_unprotect $b64 } catch { Write-Host "[windo] DECRYPT FAILED at line $($i+1)" -ForegroundColor Red; $ok = $false; break }
            $calc = _sha256_hex $json
            if ($calc -ne $storedHash) { Write-Host "[windo] HASH MISMATCH at line $($i+1)" -ForegroundColor Red; $ok = $false; break }
            try { $obj = $json | ConvertFrom-Json } catch { $obj = $null }
            if ($i -gt 0) {
                if (-not $obj -or -not ($obj.PSObject.Properties.Name -contains "PreviousHash")) { Write-Host "[windo] MISSING PreviousHash at line $($i+1)" -ForegroundColor Red; $ok = $false; break }
                if ([string]$obj.PreviousHash -ne $prevStoredHash) { Write-Host "[windo] CHAIN BREAK at line $($i+1)" -ForegroundColor Red; $ok = $false; break }
            }
            $prevStoredHash = $storedHash
        }
        $vfExit = 0
        if (-not $ok) { $vfExit = 4 }
        if ($JsonOutput) {
            _emit_json "verify" @{ verifyOk = $ok; physicalLines = $lines.Count; exitCode = $vfExit }
            _windo_set_exit $vfExit
            return
        }
        if ($ok) { Write-Host "[windo] VERIFY: OK (hashes + chain intact)" -ForegroundColor Green }
        _windo_set_exit $vfExit
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

    $pending = @{
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        RequestId = $reqId
        Command   = $cmdLine
        OutPath   = $outPath
        Host      = $env:COMPUTERNAME
        User      = "$env:USERDOMAIN\$env:USERNAME"
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
        } elseif (($env:TERM_PROGRAM -replace '\s', '') -ieq 'vscode') {
            $chord = "Alt+w"
        } else {
            $chord = "w,w"
        }

        if ($disabled) { $chord = $null }
        [pscustomobject]@{
            enabled = [bool](-not $disabled)
            chord = $chord
            source = $(if ([string]::IsNullOrWhiteSpace($envChord)) { if (-not [string]::IsNullOrWhiteSpace($prefChord)) { "prefs" } else { "auto" } } else { "env" })
        }
    }

    $legacyChords = @('w,w', 'Alt+w', 'Shift+Enter', 'Alt+Enter')
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
        if ($rest -notmatch '^(?i)windo(\s|$)') {
            $indent = $m.Groups[1].Value
            $newLine = $indent + 'windo ' + $rest
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $newLine)
        }
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
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

    try { Set-PSReadLineKeyHandler -Chord $policy.chord -ScriptBlock $windoPrefixOnly } catch { }
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
function Register-WindoArgumentCompleter {
    if ($global:__WindoArgCompleterRegistered) { return }
    if (-not (Get-Command TabExpansion2 -ErrorAction SilentlyContinue)) {
        Write-Warning "WINDO: TabExpansion2 not available; delegated tab completion skipped."
        return
    }
    Register-ArgumentCompleter -CommandName windo -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $builtin = [string[]]@(__WINDO_BUILTIN_ARRAY__, '!!')
        try {
            if ($null -eq $commandAst) { return }
            $line = $commandAst.Extent.Text
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            $m = [regex]::Match($line, '^\s*windo\s+', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if (-not $m.Success) { return }
            $delegate = $line.Substring($m.Length)
            if ([string]::IsNullOrWhiteSpace($delegate)) { return }
            $firstTok = ($delegate.TrimStart() -split '\s+', 2)[0]
            if ($firstTok) {
                foreach ($b in $builtin) {
                    if ($firstTok -ceq $b -or $firstTok -ieq $b) { return }
                }
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

$profileText = Get-Content -Raw $PROFILE
$block = $BeginMarker + "`r`n" + $WindoFunctionBody + "`r`n" + $WindoPsReadLineBlock + "`r`n" + $WindoCompleterBlock + "`r`n" + $EndMarker + "`r`n"
Write-Utf8NoBomFile -Path $PROFILE -Content ($profileText.TrimEnd() + "`r`n`r`n" + $block)

if (!(Test-Path $SnapshotDir)) { New-Item -ItemType Directory -Path $SnapshotDir | Out-Null }
Copy-Item $RunnerPath (Join-Path $SnapshotDir "windo_runner.ps1") -Force
Copy-Item $UpdateScript (Join-Path $SnapshotDir "windo_self_update.ps1") -Force
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

Write-Host "WINDO v$WindoVersion installed and hardened." -ForegroundColor Green
Write-Host "Snapshot saved to: $SnapshotDir" -ForegroundColor Green
Write-Host "Next (normal shell):" -ForegroundColor Yellow
Write-Host "  . `$PROFILE" -ForegroundColor Yellow
Write-Host "  windo version" -ForegroundColor Yellow
Write-Host "  windo integrity" -ForegroundColor Yellow
Write-Host "  windo self-update" -ForegroundColor Yellow
Write-Host "  windo !!" -ForegroundColor Yellow

