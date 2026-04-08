<# =====================================================================
WINDO v2.7.0 Release-Hardened Installer
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

$WindoVersion = "2.7.0"

# Single source of truth for embedded profile: completer skip-list (plus '!!') and windo last-command first-token exclusions.
$WindoBuiltinVerbs = @(
    'help', 'last', 'stats', 'history', 'report', 'export', 'self-update', 'version',
    'doctor', 'integrity', 'verify', 'log', 'cleanup', 'context', 'trace', 'replay',
    'upgrade', 'uninstall'
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

    $start = Get-Date

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c " + $cmdLine
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true

        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()

        $output   = ($stdout + $stderr).TrimEnd()
        $exitCode = [int]$p.ExitCode
    } catch {
        $output   = ($_ | Out-String).TrimEnd()
        $exitCode = 1
    }

    $end = Get-Date
    $durationMs = [int](($end - $start).TotalMilliseconds)

    $result = @{
        Timestamp  = $end.ToString("yyyy-MM-dd HH:mm:ss")
        Command    = $cmdLine
        Output     = $output
        ExitCode   = $exitCode
        DurationMs = $durationMs
        RequestId  = $reqId
    }

    try {
        $result | ConvertTo-Json -Compress | Set-Content -Path $outPath -Encoding UTF8
        "WROTE RESULT: ExitCode=$exitCode DurationMs=$durationMs" | Add-Content -Path $RunnerLast -Encoding UTF8
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
    $ManifestFile = Join-Path $SecureDir "windo_manifest.json"
    $SchemaVersion = "2.6"

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

    function _json_envelope([string]$commandName, $payload) {
        [ordered]@{
            schemaVersion = $SchemaVersion
            windoVersion = $WindoVersion
            command = $commandName
            generatedAt = (Get-Date -Format "o")
            payload = $payload
        }
    }

    function _emit_json([string]$commandName, $payload) {
        (_json_envelope $commandName $payload) | ConvertTo-Json -Depth 14 | Write-Host
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

    if ($Command.Count -ge 1 -and $Command[0] -eq "help") {
        $helpText = @(
            "windo <command...>         Elevate and run via task bridge",
            "windo !! | windo replay     Re-run last stored elevated command",
            "windo last                  Show last stored command + metadata",
            "windo context [--json]      Shell/WINDO environment summary",
            "windo trace <RequestId>     Find audit log entry by RequestId",
            "windo stats                 Summarize encrypted audit log",
            "windo history [-n N]        Compact recent commands (default N=50)",
            "windo report [-o path]      HTML audit report (summary + categories)",
            "windo export [-o zip] [-n N] [--redact]  Bundle manifest + JSON + log excerpt",
            "windo self-update           Repair/update scheduled task actions",
            "windo version [--json]      Version and paths",
            "windo doctor [--json]       Health / paths / tasks",
            "windo integrity [--json]    Runner vs manifest (OK|DRIFT|TAMPERED|UNKNOWN)",
            "windo verify [--json]       Hash chain validation on log",
            "windo log -n N [--json]     Decrypted log entries",
            "windo cleanup [-w]          Backup log, clear active log",
            "windo upgrade               Download latest installer from Genisis (any prior v2.x)",
            "windo uninstall             Elevated uninstaller (tasks, profile, secure dir)",
            "Append --json or -Json; --dry-run for replay/elevated command (no elevation, no log write)."
        ) -join [Environment]::NewLine
        Write-Host $helpText -ForegroundColor Yellow
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "upgrade") {
        $InstUrl = "https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_install.ps1"
        $TempInst = Join-Path $env:TEMP ("windo_install_" + [Guid]::NewGuid().ToString("n") + ".ps1")
        try {
            Write-Host "[windo] Downloading latest installer from Genisis..." -ForegroundColor Cyan
            Invoke-RestMethod -Uri $InstUrl -OutFile $TempInst
            if (!(Test-Path $TempInst)) { throw "Download failed." }
            if ((Get-Item $TempInst).Length -lt 5000) { throw "Installer file size looks invalid." }
            Write-Host "[windo] Running installer. When it finishes, reload your profile: . `$PROFILE" -ForegroundColor Yellow
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TempInst
        } catch {
            Write-Host "[windo] upgrade failed: $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            if (Test-Path $TempInst) { Remove-Item $TempInst -Force -ErrorAction SilentlyContinue }
        }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "uninstall") {
        $UnUrl = "https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_uninstall.ps1"
        $TempUn = Join-Path $env:TEMP ("windo_uninstall_" + [Guid]::NewGuid().ToString("n") + ".ps1")
        try {
            Write-Host "[windo] Downloading uninstaller..." -ForegroundColor Cyan
            Invoke-RestMethod -Uri $UnUrl -OutFile $TempUn
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
        if (Test-Path $LogFile) {
            $lcWarn = _windo_log_line_count $LogFile
            if ($lcWarn -gt 100000) {
                Write-Host "[windo] Warning: large audit log (~$lcWarn lines); stats may use significant memory. Consider rotation (windo cleanup) or archiving." -ForegroundColor DarkYellow
            }
        }
        $entries = @(_parse_log_entries)
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
            _emit_json "stats" @{ entryCount = $entries.Count; successCount = $okc; nonZeroExitCount = $fail; avgDurationMs = $avg; logFile = $LogFile; categories = $cat }
            return
        }
        Write-Host "[windo] Audit log stats" -ForegroundColor Cyan
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
        if ($JsonOutput) {
            _emit_json "integrity" @{
                manifestPath = $ManifestFile
                overallLevel = $i.OverallLevel
                runner = @{ expected = $i.RunnerExpected; actual = $i.RunnerActual; match = $i.RunnerMatch; level = $i.RunnerLevel }
                selfUpdate = @{ expected = $i.UpdaterExpected; actual = $i.UpdaterActual; match = $i.UpdaterMatch; level = $i.UpdaterLevel }
            }
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
            while ($sw.Elapsed.TotalSeconds -lt 10) {
                if (Test-Path $UpdateLast) {
                    $current = (Get-Item $UpdateLast).LastWriteTime
                    $content = Get-Content -Raw -Path $UpdateLast -ErrorAction SilentlyContinue
                    if (($before -eq $null -or $current -gt $before) -and $content -match 'SELF-UPDATE END') { break }
                }
                Start-Sleep -Milliseconds 200
            }
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
                integrity = @{ overallLevel = $ix.OverallLevel; runnerLevel = $ix.RunnerLevel; updaterLevel = $ix.UpdaterLevel }
            }
            return
        }
        $ixd = _integrity_status
        $mdoc = _read_last_meta
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
        Write-Host "  Tip: 'windo integrity' for hashes; 'windo verify' for audit chain." -ForegroundColor DarkGray
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "verify") {
        if (!(Test-Path $LogFile)) { Write-Host "[windo] No log file found." -ForegroundColor Yellow; return }
        $lines = @(Get-Content -Path $LogFile)
        if ($lines.Count -eq 0) { Write-Host "[windo] Log file is empty." -ForegroundColor Yellow; return }
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
        if ($JsonOutput) {
            _emit_json "verify" @{ verifyOk = $ok; physicalLines = $lines.Count }
            return
        }
        if ($ok) { Write-Host "[windo] VERIFY: OK (hashes + chain intact)" -ForegroundColor Green }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "log") {
        $n = 20
        if ($Command.Count -ge 3 -and $Command[1] -eq "-n") { [int]$n = $Command[2] }
        if (!(Test-Path $LogFile)) { Write-Host "[windo] No log file found." -ForegroundColor Yellow; return }
        if ($JsonOutput) {
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
        Write-Host "Usage: windo help | windo <command...> | windo upgrade | windo uninstall | windo !! | windo replay | ...  (see windo help)" -ForegroundColor Yellow
        return
    }

    try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null } catch { Write-Host "[windo] Task missing: $TaskName (run installer elevated once)" -ForegroundColor Red; return }

    _warn_if_tampered

    $cmdLine = ($Command -join " ").Trim()
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

    while (!(Test-Path $outPath) -and $sw.Elapsed.TotalSeconds -lt 20) { Start-Sleep -Milliseconds 100 }

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
}
'@
$WindoFunctionBody = $WindoFunctionBody.Replace("__WINDO_BUILTIN_ARRAY__", $WindoBuiltinVerbsArrayLiteral)
$WindoFunctionBody = $WindoFunctionBody.Replace("__VERSION__", $WindoVersion)

$WindoPsReadLineBlock = @'
try {
    Import-Module PSReadLine -ErrorAction Stop
    $null = [Microsoft.PowerShell.PSConsoleReadLine]

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
        $m = [regex]::Match($line, '^(\s*)(.*)$')
        $rest = $m.Groups[2].Value
        if ($rest -notmatch '^(?i)windo(\s|$)') {
            $indent = $m.Groups[1].Value
            $newLine = $indent + 'windo ' + $rest
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $newLine)
        }
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }

    Set-PSReadLineKeyHandler -Chord 'w,w' -ScriptBlock $windoPrefixOnly
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

