$ErrorActionPreference = "Stop"

$SecureDir  = Join-Path $HOME ".pwsh_secure"
$RunnerLast = Join-Path $SecureDir "windo_runner_last.txt"
$MutexName  = "Global\WindoRunnerMutex"

function New-WindoRunnerMutex {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ref]$CreatedNew
    )
    return New-Object System.Threading.Mutex($false, $Name, $CreatedNew)
}

function Release-WindoRunnerMutex {
    param([Parameter(Mandatory = $true)]$Mutex)
    try { $Mutex.ReleaseMutex() } catch {}
}

function Close-WindoRunnerMutex {
    param([Parameter(Mandatory = $true)]$Mutex)
    try { $Mutex.Dispose() } catch {}
}

function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter()][System.Text.Encoding]$Encoding = (New-Object System.Text.UTF8Encoding($false))
    )
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and !(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = Join-Path $dir (".windo_tmp_" + [Guid]::NewGuid().ToString("n") + ".tmp")
    try {
        [System.IO.File]::WriteAllText($tmp, $Content, $Encoding)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-RunnerTrace {
    param([string]$Message, [switch]$Overwrite)
    if ($Overwrite) {
        Write-TextFileAtomic -Path $RunnerLast -Content $Message -Encoding (New-Object System.Text.UTF8Encoding($false))
    } else {
        $Message | Add-Content -Path $RunnerLast -Encoding UTF8
    }
}

function Invoke-WindoRunnerChildExec {
    param(
        [Parameter(Mandatory = $true)][string]$CommandLine,
        [Parameter(Mandatory = $true)][int]$TimeoutMs,
        [Parameter(Mandatory = $true)][int]$MaxCharsPerStream,
        [Parameter(Mandatory = $true)]$StdOut,
        [Parameter(Mandatory = $true)]$StdErr,
        [Parameter(Mandatory = $true)]$TimedOut,
        [Parameter(Mandatory = $true)]$Truncated,
        [Parameter(Mandatory = $true)]$ExitCode
    )
    [WindoRunner.ChildExec]::RunCmd($CommandLine, $TimeoutMs, $MaxCharsPerStream, $StdOut, $StdErr, $TimedOut, $Truncated, $ExitCode)
}

if (-not ("WindoRunner.ChildExec" -as [type])) {
    $cs = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
        'dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uRGlhZ25vc3RpY3M7CnVzaW5nIFN5c3RlbS5JTzsKdXNpbmcgU3lzdGVtLlRleHQ7CnVzaW5nIFN5c3RlbS5UaHJlYWRpbmcuVGFza3M7CgpuYW1lc3BhY2UgV2luZG9SdW5uZXIKewogICAgcHVibGljIHN0YXRpYyBjbGFzcyBDaGlsZEV4ZWMKICAgIHsKICAgICAgICBwdWJsaWMgc3RhdGljIHN0cmluZyBSZWFkU3RyZWFtVG9NYXgoU3RyZWFtUmVhZGVyIHIsIGludCBtYXhDaGFycywgUHJvY2VzcyBwKQogICAgICAgIHsKICAgICAgICAgICAgdmFyIHNiID0gbmV3IFN0cmluZ0J1aWxkZXIoKTsKICAgICAgICAgICAgdmFyIGJ1ZiA9IG5ldyBjaGFyWzgxOTJdOwogICAgICAgICAgICBpbnQgdG90YWwgPSAwOwogICAgICAgICAgICB3aGlsZSAodG90YWwgPCBtYXhDaGFycykKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgaW50IG4gPSByLlJlYWQoYnVmLCAwLCBNYXRoLk1pbihidWYuTGVuZ3RoLCBtYXhDaGFycyAtIHRvdGFsKSk7CiAgICAgICAgICAgICAgICBpZiAobiA8PSAwKSBicmVhazsKICAgICAgICAgICAgICAgIHNiLkFwcGVuZChidWYsIDAsIG4pOwogICAgICAgICAgICAgICAgdG90YWwgKz0gbjsKICAgICAgICAgICAgfQogICAgICAgICAgICBpZiAodG90YWwgPj0gbWF4Q2hhcnMpCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgIHRyeSB7IGlmICghcC5IYXNFeGl0ZWQpIHAuS2lsbCgpOyB9IGNhdGNoIHsgfQogICAgICAgICAgICAgICAgdHJ5IHsgcC5XYWl0Rm9yRXhpdCgxNTAwMCk7IH0gY2F0Y2ggeyB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgcmV0dXJuIHNiLlRvU3RyaW5nKCk7CiAgICAgICAgfQoKICAgICAgICBwdWJsaWMgc3RhdGljIHZvaWQgUnVuQ21kKAogICAgICAgICAgICBzdHJpbmcgYXJndW1lbnRzLAogICAgICAgICAgICBpbnQgdGltZW91dE1zLAogICAgICAgICAgICBpbnQgbWF4Q2hhcnNQZXJTdHJlYW0sCiAgICAgICAgICAgIG91dCBzdHJpbmcgc3Rkb3V0LAogICAgICAgICAgICBvdXQgc3RyaW5nIHN0ZGVyciwKICAgICAgICAgICAgb3V0IGJvb2wgdGltZWRPdXQsCiAgICAgICAgICAgIG91dCBib29sIHRydW5jYXRlZCwKICAgICAgICAgICAgb3V0IGludCBleGl0Q29kZSkKICAgICAgICB7CiAgICAgICAgICAgIHRpbWVkT3V0ID0gZmFsc2U7CiAgICAgICAgICAgIHRydW5jYXRlZCA9IGZhbHNlOwogICAgICAgICAgICBleGl0Q29kZSA9IDE7CiAgICAgICAgICAgIHN0ZG91dCA9ICIiOwogICAgICAgICAgICBzdGRlcnIgPSAiIjsKICAgICAgICAgICAgdmFyIGVuY29kZWRDb21tYW5kID0gQ29udmVydC5Ub0Jhc2U2NFN0cmluZyhFbmNvZGluZy5Vbmljb2RlLkdldEJ5dGVzKGFyZ3VtZW50cyA/PyAiIikpOwogICAgICAgICAgICB2YXIgcHNpID0gbmV3IFByb2Nlc3NTdGFydEluZm8oKTsKICAgICAgICAgICAgcHNpLkZpbGVOYW1lID0gInBvd2Vyc2hlbGwuZXhlIjsKICAgICAgICAgICAgcHNpLkFyZ3VtZW50cyA9ICItTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtTm9Mb2dvIC1FbmNvZGVkQ29tbWFuZCAiICsgZW5jb2RlZENvbW1hbmQ7CiAgICAgICAgICAgIHBzaS5SZWRpcmVjdFN0YW5kYXJkT3V0cHV0ID0gdHJ1ZTsKICAgICAgICAgICAgcHNpLlJlZGlyZWN0U3RhbmRhcmRFcnJvciA9IHRydWU7CiAgICAgICAgICAgIHBzaS5Vc2VTaGVsbEV4ZWN1dGUgPSBmYWxzZTsKICAgICAgICAgICAgcHNpLkNyZWF0ZU5vV2luZG93ID0gdHJ1ZTsKICAgICAgICAgICAgdXNpbmcgKHZhciBwID0gUHJvY2Vzcy5TdGFydChwc2kpKQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICB2YXIgdE91dCA9IFRhc2suUnVuKCgpID0+IFJlYWRTdHJlYW1Ub01heChwLlN0YW5kYXJkT3V0cHV0LCBtYXhDaGFyc1BlclN0cmVhbSwgcCkpOwogICAgICAgICAgICAgICAgdmFyIHRFcnIgPSBUYXNrLlJ1bigoKSA9PiBSZWFkU3RyZWFtVG9NYXgocC5TdGFuZGFyZEVycm9yLCBtYXhDaGFyc1BlclN0cmVhbSwgcCkpOwogICAgICAgICAgICAgICAgYm9vbCBmaW5pc2hlZCA9IHAuV2FpdEZvckV4aXQodGltZW91dE1zKTsKICAgICAgICAgICAgICAgIGlmICghZmluaXNoZWQpCiAgICAgICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAgICAgdGltZWRPdXQgPSB0cnVlOwogICAgICAgICAgICAgICAgICAgIHRyeSB7IGlmICghcC5IYXNFeGl0ZWQpIHAuS2lsbCgpOyB9IGNhdGNoIHsgfQogICAgICAgICAgICAgICAgICAgIHRyeSB7IHAuV2FpdEZvckV4aXQoMTUwMDApOyB9IGNhdGNoIHsgfQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgc3Rkb3V0ID0gdE91dC5SZXN1bHQ7CiAgICAgICAgICAgICAgICBzdGRlcnIgPSB0RXJyLlJlc3VsdDsKICAgICAgICAgICAgICAgIGlmIChzdGRvdXQuTGVuZ3RoID49IG1heENoYXJzUGVyU3RyZWFtIHx8IHN0ZGVyci5MZW5ndGggPj0gbWF4Q2hhcnNQZXJTdHJlYW0pCiAgICAgICAgICAgICAgICAgICAgdHJ1bmNhdGVkID0gdHJ1ZTsKICAgICAgICAgICAgICAgIHRyeQogICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgIGV4aXRDb2RlID0gcC5IYXNFeGl0ZWQgPyBwLkV4aXRDb2RlIDogLTE7CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICBjYXRjaAogICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgIGV4aXRDb2RlID0gLTE7CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICBpZiAodGltZWRPdXQpCiAgICAgICAgICAgICAgICAgICAgZXhpdENvZGUgPSAtMTsKICAgICAgICAgICAgfQogICAgICAgIH0KICAgIH0KfQo='    ))
    Add-Type -TypeDefinition $cs -Language CSharp
}

function Get-WindoRunnerTimeoutMs {
    param([object]$OverrideMs = $null)
    $d = 7200000
    if ($null -ne $OverrideMs -and -not [string]::IsNullOrWhiteSpace([string]$OverrideMs)) {
        try {
            $v = [long]$OverrideMs
            if ($v -lt 1) { return $d }
            if ($v -gt 86400000) { return 86400000 }
            return [int]$v
        } catch { return $d }
    }
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

function Invoke-WindoPreserveEnvironment {
    param([object]$Snapshot)
    $restored = @{}
    if ($null -eq $Snapshot) { return $restored }
    $maxEntries = 256
    $maxValueLength = 8192

    $items = @()
    if ($Snapshot -is [System.Collections.IDictionary]) {
        $items = @($Snapshot.GetEnumerator())
    } elseif ($Snapshot.PSObject -and $Snapshot.PSObject.Properties) {
        $items = @($Snapshot.PSObject.Properties)
    } else {
        return $restored
    }
    if ($items.Count -gt $maxEntries) { return $restored }

    foreach ($entry in $items) {
        if ($Snapshot -is [System.Collections.IDictionary]) {
            $name = [string]$entry.Key
            $value = $entry.Value
        } else {
            $name = [string]$entry.Name
            $value = $entry.Value
        }
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
        if ($null -ne $value -and ([string]$value).Length -gt $maxValueLength) { continue }
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

function _windo_next_request {
    param([string]$SecureDir)

    try {
        return Get-ChildItem -Path $SecureDir -Filter "windo_req.*.json" -ErrorAction SilentlyContinue |
            Sort-Object @{Expression = { $_.LastWriteTime }}, @{Expression = { $_.Name }} |
            Select-Object -First 1
    } catch {
        return $null
    }
}

function Test-WindoCommandLine([string]$cmdLine) {
    $max = Get-WindoMaxCommandChars
    if ($null -eq $cmdLine) { return "Command is missing." }
    if ([string]::IsNullOrWhiteSpace([string]$cmdLine)) { return "Command is missing." }
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
        $normalizedRoot = $root.TrimEnd('\')
        $normalizedRoot = $normalizedRoot.TrimEnd('/')
        $matchPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
        if (-not ($full.StartsWith($matchPrefix, [StringComparison]::OrdinalIgnoreCase) -or ($full -eq $normalizedRoot)) ) { return "OutPath must be under SecureDir." }
        $name = [System.IO.Path]::GetFileName($full)
    if ($name -cnotmatch '^windo_res\.[a-f0-9]+\.json$') { return "OutPath file name is invalid." }
    } catch { return "OutPath is invalid." }
    return $null
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

function _dpapi_unprotect([string]$Base64Input) {
    $protectedDataType = [type]::GetType("System.Security.Cryptography.ProtectedData")
    try {
        $enc = [Convert]::FromBase64String($Base64Input)
        if ($null -eq $protectedDataType) {
            return [System.Text.Encoding]::UTF8.GetString($enc)
        }
        $bytes = $protectedDataType::Unprotect(
            $enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return $null
    }
}

function _windo_unprotect_text([string]$EncryptedText) {
    if ([string]::IsNullOrWhiteSpace($EncryptedText)) { return $null }
    if ($EncryptedText.Length -gt 262144) { return $null }
    return _dpapi_unprotect $EncryptedText
}

function _windo_resolve_preserve_environment([object]$Payload) {
    if ($null -eq $Payload) { return $null }

    if ($Payload -is [string]) {
        try { return $Payload | ConvertFrom-Json } catch { return $null }
    }

    $payloadType = $null
    $payloadData = $null
    if ($Payload -is [System.Collections.IDictionary]) {
        if ($Payload.Contains("Type")) { $payloadType = $Payload["Type"] }
        if ($Payload.Contains("Data")) { $payloadData = $Payload["Data"] }
    } else {
        if ($Payload.PSObject -and $Payload.PSObject.Properties.Name -contains "Type") { $payloadType = $Payload.Type }
        if ($Payload.PSObject -and $Payload.PSObject.Properties.Name -contains "Data") { $payloadData = $Payload.Data }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$payloadType) -and -not [string]::IsNullOrWhiteSpace([string]$payloadData)) {
        if ([string]$payloadType -ieq "dpapi-json") {
            $json = _windo_unprotect_text [string]$payloadData
            if ($null -eq $json -and -not [string]::IsNullOrWhiteSpace([string]$payloadData)) {
                try {
                    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$payloadData))
                } catch { }
            }
            if ($null -ne $json) {
                try { return $json | ConvertFrom-Json } catch { return $null }
            }
            return $null
        }
    }

    return $Payload
}

function _windo_resolve_artifact_payload {
    param([object]$Payload)
    if ($null -eq $Payload) { return $null }

    if ($Payload -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Payload)) { return $null }
        if ([string]$Payload.Length -gt 262144) { return $null }
        if ([string]$Payload -match '^[\r\n\s\t]*\{') {
            try { return $Payload | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
        }
        return $null
    }

    $payloadType = $null
    $payloadData = $null
    if ($Payload -is [System.Collections.IDictionary]) {
        if ($Payload.Contains("Type")) { $payloadType = $Payload["Type"] }
        if ($Payload.Contains("Data")) { $payloadData = $Payload["Data"] }
    } else {
        if ($Payload.PSObject -and $Payload.PSObject.Properties.Name -contains "Type") { $payloadType = $Payload.Type }
        if ($Payload.PSObject -and $Payload.PSObject.Properties.Name -contains "Data") { $payloadData = $Payload.Data }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$payloadType) -and ([string]$payloadType -ieq "dpapi-json") -and -not [string]::IsNullOrWhiteSpace([string]$payloadData)) {
        $json = _windo_unprotect_text [string]$payloadData
        if ($null -eq $json -and -not [string]::IsNullOrWhiteSpace([string]$payloadData)) {
            try {
                $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$payloadData))
            } catch { }
        }
        if ($null -ne $json) {
            try { return $json | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
        }
        return $null
    }

    return $Payload
}

function _windo_join_output_streams([string]$StdOut, [string]$StdErr) {
    $out = if ($null -eq $StdOut) { "" } else { $StdOut }
    $err = if ($null -eq $StdErr) { "" } else { $StdErr }
    if ([string]::IsNullOrWhiteSpace($out)) { return $err.TrimEnd() }
    if ([string]::IsNullOrWhiteSpace($err)) { return $out.TrimEnd() }
    return ($out + "`n" + $err).TrimEnd()
}

Write-RunnerTrace -Overwrite "RUNNER START: $([DateTime]::Now.ToString('s'))"

$createdNew = $false
$m = New-WindoRunnerMutex -Name $MutexName -CreatedNew ([ref]$createdNew)

try {
    if (-not $m.WaitOne(30000)) {
        Write-RunnerTrace "EXIT 9: mutex wait timeout"
        exit 9
    }

    $req = _windo_next_request $SecureDir

    if (-not $req) {
        Write-RunnerTrace "NO WORK: no pending request files"
        exit 0
    }

    try {
        $pendingRaw = Get-Content -Raw -Path $req.FullName
        $pending = _windo_resolve_artifact_payload $pendingRaw
    } catch {
        Write-RunnerTrace ("BAD REQUEST JSON: $($req.FullName) :: $($_.Exception.Message)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        exit 3
    }

    if ($null -eq $pending -or (-not ($pending.PSObject -or $pending -is [System.Collections.IDictionary])) ) {
        Write-RunnerTrace ("BAD REQUEST JSON: $($req.FullName) :: malformed request payload")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        exit 3
    }

    $cmdLine = _windo_get_member_value $pending "Command"
    $outPath = _windo_get_member_value $pending "OutPath"
    $reqId   = _windo_get_member_value $pending "RequestId"

    if ($null -eq $cmdLine -or $null -eq $outPath) {
        Write-RunnerTrace ("BAD REQUEST JSON: $($req.FullName) :: malformed request payload (missing Command or OutPath)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        exit 3
    }

    $cmdLine = [string]$cmdLine
    $outPath = [string]$outPath
    $reqId   = [string]$reqId
    $timeoutMsOverride = $null
    if ($pending.PSObject.Properties.Name -contains "TimeoutOverrideMs") { $timeoutMsOverride = $pending.TimeoutOverrideMs }
    $preserveEnvironment = $null
    if ($pending.PSObject.Properties.Name -contains "PreserveEnvironment") {
        $preserveEnvironment = _windo_resolve_preserve_environment $pending.PreserveEnvironment
    }

    Write-RunnerTrace "PROCESS: RequestId=$reqId  OutPath=$outPath"
    Write-RunnerTrace "CMD: $cmdLine"

    $badOut = Test-WindoResultPath $outPath $SecureDir
    if ($badOut) {
        Write-RunnerTrace ("VALIDATION FAILED (OutPath): $badOut")
        try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}
        Write-RunnerTrace "RUNNER END: $([DateTime]::Now.ToString('s'))"
        exit 5
    }

    $badCmd = Test-WindoCommandLine $cmdLine
    if ($badCmd) {
        Write-RunnerTrace ("VALIDATION FAILED (Command): $badCmd")
        $message = "<WINDO VALIDATION FAILED: $badCmd>"
        $stdout = $message
        $stderr = ""
        $end = Get-Date
        $result = @{
            Timestamp  = $end.ToString("yyyy-MM-dd HH:mm:ss")
            Command    = $cmdLine
            Output     = $message
            StdOut     = $stdout
            StdErr     = $stderr
            ExitCode   = -3
            DurationMs = 0
            RequestId  = $reqId
            RunnerTimedOut = $false
            OutputTruncated = $false
        }
        try {
            $result | ConvertTo-Json -Compress | Write-TextFileAtomic -Path $outPath -Encoding (New-Object System.Text.UTF8Encoding($false))
        } catch {
            Write-RunnerTrace ("EXIT 4: failed to write validation result: $($_.Exception.Message)")
            try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".failed") -ErrorAction SilentlyContinue } catch {}
            Write-RunnerTrace ("RUNNER END: $([DateTime]::Now.ToString('s'))")
            exit 4
        }
        try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}
        Write-RunnerTrace "RUNNER END: $([DateTime]::Now.ToString('s'))"
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
            Invoke-WindoRunnerChildExec -CommandLine $cmdLine -TimeoutMs $timeoutMs -MaxCharsPerStream $maxPer -StdOut ([ref]$stdout) -StdErr ([ref]$stderr) -TimedOut ([ref]$timedOut) -Truncated ([ref]$truncated) -ExitCode ([ref]$exitCode)
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

    $output = _windo_join_output_streams $stdout $stderr
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
        StdOut     = $stdout
        StdErr     = $stderr
        ExitCode   = [int]$exitCode
        DurationMs = $durationMs
        RequestId  = $reqId
        RunnerTimedOut = [bool]$timedOut
        OutputTruncated = [bool]$truncated
    }

    try {
        $result | ConvertTo-Json -Compress | Write-TextFileAtomic -Path $outPath -Encoding (New-Object System.Text.UTF8Encoding($false))
        Write-RunnerTrace "WROTE RESULT: ExitCode=$exitCode DurationMs=$durationMs TimedOut=$timedOut Truncated=$truncated"
    } catch {
        Write-RunnerTrace ("EXIT 4: failed to write result JSON: $($_.Exception.Message)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".failed") -ErrorAction SilentlyContinue } catch {}
        Write-RunnerTrace ("RUNNER END: $([DateTime]::Now.ToString('s'))")
        exit 4
    }

    try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}

    Write-RunnerTrace "RUNNER END: $([DateTime]::Now.ToString('s'))"
    exit 0
}
catch {
    Write-RunnerTrace ("UNHANDLED: " + $_.Exception.Message)
    if ($req) {
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".failed") -ErrorAction SilentlyContinue } catch {}
    }
    Write-RunnerTrace ("RUNNER END: $([DateTime]::Now.ToString('s'))")
    exit 1
}
finally {
    if ($m) {
        Release-WindoRunnerMutex -Mutex $m
        Close-WindoRunnerMutex -Mutex $m
    }
}




