<# =====================================================================
WINDO v2.5.0 Release-Hardened Installer
Run once in an elevated PowerShell session.

Installs:
- $HOME\.pwsh_secure\
- windo_runner.ps1
- windo_self_update.ps1
- windo_manifest.json
- Scheduled tasks:
    - WindoElevatedRunner
    - WindoSelfUpdate
- WINDO profile block in $PROFILE (windo function + PSReadLine keybindings)
- Snapshot copies under $HOME\Documents\windo\
===================================================================== #>

$ErrorActionPreference = "Stop"

$WindoVersion = "2.5.0"
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
    $ManifestFile = Join-Path $SecureDir "windo_manifest.json"

    if (!(Test-Path $SecureDir)) { New-Item -ItemType Directory -Path $SecureDir | Out-Null }
    $JsonOutput = $false
    if ($Command -and $Command.Count -gt 0) {
        $cl = [System.Collections.ArrayList]@($Command)
        for ($xi = $cl.Count - 1; $xi -ge 0; $xi--) {
            $tx = [string]$cl[$xi]
            if ($tx -eq '--json' -or $tx -eq '-Json') {
                $JsonOutput = $true
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

    function _integrity_status {
        $runnerActual = _file_hash $RunnerPath
        $runnerExpect = _expected_hash "runner"
        $updateActual = _file_hash $UpdatePath
        $updateExpect = _expected_hash "self_update"
        [pscustomobject]@{
            RunnerMatch = ($runnerActual -eq $runnerExpect)
            RunnerActual = $runnerActual
            RunnerExpected = $runnerExpect
            UpdaterMatch = ($updateActual -eq $updateExpect)
            UpdaterActual = $updateActual
            UpdaterExpected = $updateExpect
        }
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
        if (-not $i.RunnerMatch -or -not $i.UpdaterMatch) {
            Write-Host "[windo] WARNING: integrity mismatch detected." -ForegroundColor Red
            if (-not $i.RunnerMatch) { Write-Host "  runner hash mismatch" -ForegroundColor Red }
            if (-not $i.UpdaterMatch) { Write-Host "  self-update hash mismatch" -ForegroundColor Red }
            Write-Host "  Run: windo integrity" -ForegroundColor Yellow
        }
    }


    if ($Command.Count -ge 1 -and $Command[0] -eq "help") {
        $helpText = @(
            "windo <command...>         Elevate and run via task bridge",
            "windo !!                    Re-run last stored elevated command",
            "windo last                  Show last stored command (no execution)",
            "windo stats                 Summarize encrypted audit log",
            "windo history [-n N]        Compact recent commands (default N=50)",
            "windo report [-o path]      Write HTML audit report under Documents\\windo",
            "windo self-update           Repair/update scheduled task actions",
            "windo version [--json]      Version and paths",
            "windo doctor [--json]       Health / paths / tasks",
            "windo integrity [--json]    Runner vs manifest hashes",
            "windo verify [--json]       Hash chain validation on log",
            "windo log -n N [--json]     Decrypted log entries",
            "windo cleanup [-w]          Backup log, clear active log",
            "Append --json or -Json on supported commands for structured output."
        ) -join [Environment]::NewLine
        Write-Host $helpText -ForegroundColor Yellow
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "last") {
        if (!(Test-Path $LastCmdFile)) {
            if ($JsonOutput) { @{ lastCommand = $null } | ConvertTo-Json | Write-Host } else { Write-Host "[windo] No previous command stored." -ForegroundColor Yellow }
            return
        }
        $lc = (Get-Content -Raw -Path $LastCmdFile).Trim()
        if ($JsonOutput) { @{ lastCommand = $lc } | ConvertTo-Json | Write-Host; return }
        Write-Host "[windo] Last stored command (for windo !!):" -ForegroundColor Cyan
        Write-Host $lc
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "stats") {
        $entries = @(_parse_log_entries)
        $okc = 0; $fail = 0; $totalMs = 0; $withDur = 0
        foreach ($e in $entries) {
            try { $ec = [int]$e.ExitCode } catch { $ec = -1 }
            if ($ec -eq 0) { $okc++ } else { $fail++ }
            if ($e.PSObject.Properties.Name -contains 'DurationMs') { $totalMs += [int]$e.DurationMs; $withDur++ }
        }
        $avg = if ($withDur -gt 0) { [math]::Round($totalMs / $withDur) } else { $null }
        if ($JsonOutput) {
            @{ windoVersion = $WindoVersion; entryCount = $entries.Count; successCount = $okc; nonZeroExitCount = $fail; avgDurationMs = $avg; logFile = $LogFile } | ConvertTo-Json -Depth 4 | Write-Host
            return
        }
        Write-Host "[windo] Audit log stats" -ForegroundColor Cyan
        Write-Host "  Entries        : $($entries.Count)"
        Write-Host "  Exit code 0    : $okc"
        Write-Host "  Non-zero exit  : $fail"
        if ($null -ne $avg) { Write-Host "  Avg duration   : ${avg}ms (entries with DurationMs)" -ForegroundColor DarkGray }
        Write-Host "  Log file       : $LogFile"
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "history") {
        $hn = 50
        if ($Command.Count -ge 3 -and $Command[1] -eq "-n") { [int]$hn = $Command[2] }
        $all = @(_parse_log_entries)
        $slice = @($all | Select-Object -Last $hn)
        if ($JsonOutput) { @{ entries = $slice; count = $slice.Count } | ConvertTo-Json -Depth 8 | Write-Host; return }
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
        $ents = @(_parse_log_entries | Select-Object -Last 30)
        $sb = [System.Text.StringBuilder]::new()
        $null = $sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>WINDO audit report</title>')
        $null = $sb.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;background:#fafafa;color:#1a1a1a;}h1{border-bottom:1px solid #ccc;} table{border-collapse:collapse;width:100%;} th,td{border:1px solid #ddd;padding:6px;text-align:left;} th{background:#eee;} .ok{color:#0a7a0a;} .bad{color:#a00;} code{background:#eee;padding:2px 4px;}</style></head><body>')
        $null = $sb.AppendLine(("<h1>WINDO audit report</h1><p>Generated {0} on {1}</p><p>Choose elevation before execution.</p>" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), [System.Net.Dns]::GetHostName()))
        $null = $sb.AppendLine(("<h2>Version</h2><p>{0}</p>" -f (_html_escape $WindoVersion)))
        $null = $sb.AppendLine(("<h2>Paths</h2><table><tr><td>SecureDir</td><td><code>{0}</code></td></tr><tr><td>Log</td><td><code>{1}</code></td></tr><tr><td>Manifest</td><td><code>{2}</code></td></tr></table>" -f (_html_escape $SecureDir), (_html_escape $LogFile), (_html_escape $ManifestFile)))
        $rs = if ($idr.RunnerMatch) { 'ok' } else { 'bad' }
        $us = if ($idr.UpdaterMatch) { 'ok' } else { 'bad' }
        $null = $sb.AppendLine(("<h2>Integrity</h2><table><tr><th>Component</th><th>Status</th></tr><tr><td>Runner</td><td class='{0}'>{1}</td></tr><tr><td>Self-update</td><td class='{2}'>{3}</td></tr></table>" -f $rs, $(if ($idr.RunnerMatch) { 'OK' } else { 'DRIFT' }), $us, $(if ($idr.UpdaterMatch) { 'OK' } else { 'DRIFT' })))
        $null = $sb.AppendLine("<h2>Recent audit entries</h2><table><tr><th>Time</th><th>Exit</th><th>Command</th></tr>")
        foreach ($e in $ents) {
            $cmdStr = [string]$e.Command
            if ($cmdStr.Length -gt 200) { $cmdStr = $cmdStr.Substring(0, 200) + "..." }
            $null = $sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>" -f (_html_escape [string]$e.Timestamp), (_html_escape [string]$e.ExitCode), (_html_escape $cmdStr)))
        }
        $null = $sb.AppendLine("</table><p>Run <code>windo verify</code> for full chain validation. Reports may contain sensitive command text; handle accordingly.</p></body></html>")
        $dir = Split-Path $repOut -Parent
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($repOut, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
        Write-Host "[windo] Report written: $repOut" -ForegroundColor Green
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "integrity") {
        $i = _integrity_status
        if ($JsonOutput) {
            @{ windoVersion = $WindoVersion; manifestPath = $ManifestFile; runner = @{ expected = $i.RunnerExpected; actual = $i.RunnerActual; match = $i.RunnerMatch }; selfUpdate = @{ expected = $i.UpdaterExpected; actual = $i.UpdaterActual; match = $i.UpdaterMatch } } | ConvertTo-Json -Depth 6 | Write-Host
            return
        }
        Write-Host "[windo] Integrity (runner + self-update vs manifest)" -ForegroundColor Cyan
        Write-Host "  Manifest : $ManifestFile" -ForegroundColor DarkGray
        Write-Host "  Runner expected : $($i.RunnerExpected)"
        Write-Host "  Runner actual   : $($i.RunnerActual)"
        if ($i.RunnerMatch) { Write-Host "  Runner status   : OK" -ForegroundColor Green } else { Write-Host "  Runner status   : TAMPER / DRIFT" -ForegroundColor Red }
        Write-Host "  Updater expected: $($i.UpdaterExpected)"
        Write-Host "  Updater actual  : $($i.UpdaterActual)"
        if ($i.UpdaterMatch) { Write-Host "  Updater status  : OK" -ForegroundColor Green } else { Write-Host "  Updater status  : TAMPER / DRIFT" -ForegroundColor Red }
        if (-not ($i.RunnerMatch -and $i.UpdaterMatch)) { Write-Host "  Next: reinstall from windo_install.ps1 or run 'windo self-update' after fixing tasks." -ForegroundColor Yellow }
        return
    }

    if ($Command.Count -ge 1 -and $Command[0] -eq "self-update") {
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
            @{ windoVersion = $WindoVersion; profile = $PROFILE; runnerHash = (_file_hash $RunnerPath); updaterHash = (_file_hash $UpdatePath); logFile = $LogFile; lastCommand = $lcJson; integrityOk = ($i.RunnerMatch -and $i.UpdaterMatch); mainTaskPresent = $mt; updateTaskPresent = $ut } | ConvertTo-Json -Depth 4 | Write-Host
            return
        }
        Write-Host "[windo] Version report" -ForegroundColor Cyan
        Write-Host "  Version      : $WindoVersion"
        Write-Host "  Profile      : $PROFILE"
        Write-Host "  Runner hash  : $(_file_hash $RunnerPath)"
        Write-Host "  Updater hash : $(_file_hash $UpdatePath)"
        Write-Host "  Log file     : $LogFile"
        Write-Host "  Last cmd     : $(if (Test-Path $LastCmdFile) { (Get-Content -Raw $LastCmdFile).Trim() } else { '(none)' })"
        if ($i.RunnerMatch -and $i.UpdaterMatch) { Write-Host "  Integrity    : OK" -ForegroundColor Green } else { Write-Host "  Integrity    : DRIFT / TAMPER" -ForegroundColor Red }
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
            @{ windoVersion = $WindoVersion; secureDir = $SecureDir; logFile = $LogFile; taskMain = $TaskName; taskUpdate = $TaskUpdate; pwshwExe = $pwshwPath; mainTaskOk = $mt; updateTaskOk = $ut; runnerPresent = (Test-Path $RunnerPath); runnerLogPresent = (Test-Path $RunnerLast); updateLogPresent = (Test-Path $UpdateLast); integrity = _integrity_status } | ConvertTo-Json -Depth 6 | Write-Host
            return
        }
        Write-Host "[windo] Doctor (paths, tasks, files)" -ForegroundColor Cyan
        Write-Host "  SecureDir : $SecureDir"
        Write-Host "  LogFile   : $LogFile"
        Write-Host "  TaskMain  : $TaskName"
        Write-Host "  TaskUpd   : $TaskUpdate"
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
            @{ verifyOk = $ok; physicalLines = $lines.Count } | ConvertTo-Json -Depth 4 | Write-Host
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
            @{ entries = $sliceL; count = $sliceL.Count } | ConvertTo-Json -Depth 8 | Write-Host
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

    if ($Command.Count -ge 1 -and $Command[0] -eq "!!") {
        if (!(Test-Path $LastCmdFile)) { Write-Host "[windo] No previous command stored." -ForegroundColor Yellow; return }
        $lastCmd = (Get-Content -Raw -Path $LastCmdFile).Trim()
        if ([string]::IsNullOrWhiteSpace($lastCmd)) { Write-Host "[windo] Previous command file is empty." -ForegroundColor Yellow; return }
        Write-Host "[windo] Re-running last command: $lastCmd" -ForegroundColor Cyan
        $Command = @($lastCmd)
    }

    if (-not $Command -or $Command.Count -eq 0) {
        Write-Host "Usage: windo help | windo <command...> | windo !! | windo last | windo stats | windo history | windo report | windo self-update | windo version | windo doctor | windo integrity | windo verify | windo log -n N | windo cleanup [-w]  (append --json where supported)" -ForegroundColor Yellow
        return
    }

    try { Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null } catch { Write-Host "[windo] Task missing: $TaskName (run installer elevated once)" -ForegroundColor Red; return }

    _warn_if_tampered

    $cmdLine = ($Command -join " ").Trim()
    if ($cmdLine) {
        $firstTok = ($cmdLine -split '\s+', 2)[0]
        if ($firstTok -notin @('self-update', 'version', 'doctor', 'integrity', 'verify', 'log', 'cleanup', 'help', 'last', 'stats', 'history', 'report')) {
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

    _pretty_print $cmdLine ([int]$res.ExitCode) ([string]$res.Output) ([int]$res.DurationMs)
}
'@
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

$profileText = Get-Content -Raw $PROFILE
$block = $BeginMarker + "`r`n" + $WindoFunctionBody + "`r`n" + $WindoPsReadLineBlock + "`r`n" + $EndMarker + "`r`n"
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

