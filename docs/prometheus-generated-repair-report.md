# Prometheus Generated Artifact Repair Report

Generated: 2026-08-06T08:59:44Z

## Canonical execution helper

- ChildExec source/payload parity: **True**
- Standalone runner synchronized: **True**
- Runner embedded payload replacements: **1**
- ChildExec source SHA256: `30CC098860C473861F668F8BE31182EACB18651C0E2CFF415D3FCC3CC01C080F`
- Runner SHA256: `5A70616F09CFF70705FE85F7F9FE7F3B60BC580F7A8C3B43B3ED391E35B37EAD`

## Windows PowerShell encoding

- Installer has explicit UTF-8 BOM: **True**

## Parser gate

- FAIL:
  - windo_runner.ps1: Missing ')' in method call.
  - windo_runner.ps1: Unexpected token '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
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

function Test-WindoExecutionCommand([string]$cmdLine) {
    if ([string]::IsNullOrWhiteSpace([string]$cmdLine)) { return "Execution command is missing." }
    foreach ($ch in $cmdLine.ToCharArray()) {
        $c = [int][char]$ch
        if ($c -eq 9) { continue }
        if ($c -lt 32) { return "Execution command contains disallowed control characters." }
    }
    # CreateProcess limits a Windows command line to 32,767 characters. Leave
    # headroom for the executable path and PowerShell switches.
    $encodedLength = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmdLine)).Length
    if ($encodedLength -gt 30000) { return "Execution command exceeds the Windows process command-line limit." }
    return $null
}

function Test-WindoRequestArtifactPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SecureDirectory,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][ValidateSet("result", "stdout", "stderr", "cancel")][string]$Kind
    )

    if ($RequestId -cnotmatch '^[a-f0-9]' in expression or statement.
  - windo_runner.ps1: The string is missing the terminator: '.
  - windo_runner.ps1: Unexpected token 's'))"

$createdNew = $false
$m = New-WindoRunnerMutex -Name $MutexName -CreatedNew ([ref]$createdNew)

try {
    if (-not $m.WaitOne(30000)) {
        Write-RunnerTrace "EXIT 9: mutex wait timeout"
        exit 9
    }

    # A scheduled task can ignore a second Start request while an instance is
    # already running. Drain all queued requests under the same mutex so every
    # concurrent `windo` caller is eventually serviced.
    while ($true) {
    $req = _windo_next_request $SecureDir

    if (-not $req) {
        Write-RunnerTrace "NO WORK: no pending request files"
        break
    }

    # Claim the queue item before reading or executing it. A timed-out client,
    # a second UAC launch, or a runner restart must never see the same command
    # as a fresh queued request. Rename is atomic within SecureDir.
    $claimedPath = Join-Path $SecureDir ($req.Name -replace '^windo_req\.', 'windo_run.')
    try {
        Move-Item -LiteralPath $req.FullName -Destination $claimedPath -ErrorAction Stop
        $req = Get-Item -LiteralPath $claimedPath -ErrorAction Stop
        Write-RunnerTrace "CLAIMED: $($req.Name)"
    } catch {
        Write-RunnerTrace ("CLAIM FAILED: " + $_.Exception.Message)
        # Cancellation can win between queue selection and the atomic claim.
        # If the selected path is gone, continue draining later requests. A
        # still-present unclaimable file is a real queue/storage fault; stop to
        # avoid a tight retry loop on the same oldest item.
        if (-not (Test-Path -LiteralPath $req.FullName)) {
            $req = $null
            continue
        }
        break
    }

    try {
        $pendingRaw = Get-Content -Raw -Path $req.FullName
        $pending = _windo_resolve_artifact_payload $pendingRaw
    } catch {
        Write-RunnerTrace ("BAD REQUEST JSON: $($req.FullName) :: $($_.Exception.Message)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        $req = $null
        continue
    }

    if ($null -eq $pending -or (-not ($pending.PSObject -or $pending -is [System.Collections.IDictionary])) ) {
        Write-RunnerTrace ("BAD REQUEST JSON: $($req.FullName) :: malformed request payload")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        $req = $null
        continue
    }

    $cmdLine = _windo_get_member_value $pending "Command"
    $executionCommand = _windo_get_member_value $pending "ExecutionCommand"
    $requestedPowerShellPath = _windo_get_member_value $pending "PowerShellPath"
    $requestedWorkingDirectory = _windo_get_member_value $pending "WorkingDirectory"
    $requestUserSid = _windo_get_member_value $pending "UserSid"
    $outPath = _windo_get_member_value $pending "OutPath"
    $stdOutStreamPath = _windo_get_member_value $pending "StdOutStreamPath"
    $stdErrStreamPath = _windo_get_member_value $pending "StdErrStreamPath"
    $cancelPath = _windo_get_member_value $pending "CancelPath"
    $streamProtocolVersion = _windo_get_member_value $pending "StreamProtocolVersion"
    $reqId   = _windo_get_member_value $pending "RequestId"

    $currentUserSid = Get-WindoRunnerCurrentIdentitySid
    if ([string]::IsNullOrWhiteSpace([string]$currentUserSid) -or [string]::IsNullOrWhiteSpace([string]$requestUserSid) -or [string]$requestUserSid -ine [string]$currentUserSid) {
        Write-RunnerTrace ("BAD REQUEST IDENTITY: $($req.FullName)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        $req = $null
        continue
    }

    if ($null -eq $cmdLine -or $null -eq $outPath -or $null -eq $stdOutStreamPath -or $null -eq $stdErrStreamPath -or $null -eq $cancelPath) {
        Write-RunnerTrace ("BAD REQUEST JSON: $($req.FullName) :: malformed request payload (missing command or stream artifact path)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        $req = $null
        continue
    }

    $cmdLine = [string]$cmdLine
    if ($null -eq $executionCommand) { $executionCommand = $cmdLine }
    $executionCommand = [string]$executionCommand
    $childPowerShellPath = Resolve-WindoRunnerPowerShellPath $requestedPowerShellPath
    $childWorkingDirectory = Resolve-WindoRunnerWorkingDirectory -RequestedPath $requestedWorkingDirectory -SecureDirectory $SecureDir
    $outPath = [string]$outPath
    $stdOutStreamPath = [string]$stdOutStreamPath
    $stdErrStreamPath = [string]$stdErrStreamPath
    $cancelPath = [string]$cancelPath
    $reqId   = [string]$reqId
    $timeoutMsOverride = $null
    if ($pending.PSObject.Properties.Name -contains "TimeoutOverrideMs") { $timeoutMsOverride = $pending.TimeoutOverrideMs }
    $preserveEnvironment = $null
    $preserveEnvironmentInvalid = $false
    $preserveEnvironmentMode = _windo_get_member_value $pending "PreserveEnvironmentMode"
    $preserveEnvironmentRequested = -not [string]::IsNullOrWhiteSpace([string]$preserveEnvironmentMode)
    if ($pending.PSObject.Properties.Name -contains "PreserveEnvironment") {
        if ($null -ne $pending.PreserveEnvironment) {
            $preserveEnvironment = _windo_resolve_preserve_environment $pending.PreserveEnvironment
            if ($null -eq $preserveEnvironment) { $preserveEnvironmentInvalid = $true }
        } elseif ($preserveEnvironmentRequested) {
            $preserveEnvironmentInvalid = $true
        }
    } elseif ($preserveEnvironmentRequested) {
        $preserveEnvironmentInvalid = $true
    }

    Write-RunnerTrace "PROCESS: RequestId=$reqId  OutPath=$outPath"
    Write-RunnerTrace "CMD_HASH: $(Get-WindoTextSha256 $cmdLine)  CWD_HASH: $(Get-WindoTextSha256 $childWorkingDirectory)  SHELL: $([System.IO.Path]::GetFileName($childPowerShellPath))"

    $badOut = Test-WindoResultPath $outPath $SecureDir $reqId
    if (-not $badOut) { $badOut = Test-WindoRequestArtifactPath -Path $stdOutStreamPath -SecureDirectory $SecureDir -RequestId $reqId -Kind stdout }
    if (-not $badOut) { $badOut = Test-WindoRequestArtifactPath -Path $stdErrStreamPath -SecureDirectory $SecureDir -RequestId $reqId -Kind stderr }
    if (-not $badOut) { $badOut = Test-WindoRequestArtifactPath -Path $cancelPath -SecureDirectory $SecureDir -RequestId $reqId -Kind cancel }
    $parsedStreamProtocolVersion = 0
    try { $parsedStreamProtocolVersion = [int]$streamProtocolVersion } catch { $parsedStreamProtocolVersion = 0 }
    if (-not $badOut -and $parsedStreamProtocolVersion -ne 1) { $badOut = "StreamProtocolVersion must be 1." }
    if ($badOut) {
        Write-RunnerTrace ("VALIDATION FAILED (Artifacts): $badOut")
        try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}
        Write-RunnerTrace "REQUEST END: invalid result path"
        $req = $null
        continue
    }

    $badCmd = Test-WindoCommandLine $cmdLine
    if (-not $badCmd) { $badCmd = Test-WindoExecutionCommand $executionCommand }
    if (-not $badCmd -and $preserveEnvironmentInvalid) { $badCmd = "PreserveEnvironment protection or validation failed." }
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
            $sealedResult = _windo_build_artifact_payload $result
            if ($null -eq $sealedResult) { throw "Unable to secure validation result." }
            $sealedResultJson = $sealedResult | ConvertTo-Json -Compress
            Write-TextFileAtomic -Path $outPath -Content $sealedResultJson -Encoding (New-Object System.Text.UTF8Encoding($false))
        } catch {
            Write-RunnerTrace ("EXIT 4: failed to write validation result: $($_.Exception.Message)")
            try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".failed") -ErrorAction SilentlyContinue } catch {}
            $req = $null
            continue
        }
        try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}
        Write-RunnerTrace "REQUEST END: $reqId"
        $req = $null
        continue
    }

    $start = Get-Date
    $timeoutMs = Get-WindoRunnerTimeoutMs $timeoutMsOverride
    $maxPer = Get-WindoRunnerMaxCharsPerStream
    $stdout = [string]$null
    $stderr = [string]$null
    $timedOut = $false
    $truncated = $false
    $cancelled = $false
    $streamSinkFailed = $false
    $exitCode = 0

    # The caller removes stale correlated artifacts before queuing the request.
    # Do not delete the cancellation marker here: Ctrl+C can race with the
    # elevated runner between request claim and child startup.
    $envState = @{}
    try {
        $envState = Invoke-WindoPreserveEnvironment -Snapshot $preserveEnvironment
        try {
            Invoke-WindoRunnerChildExec `
                -PowerShellPath $childPowerShellPath `
                -CommandLine $executionCommand `
                -WorkingDirectory $childWorkingDirectory `
                -TimeoutMs $timeoutMs `
                -MaxCharsPerStream $maxPer `
                -StdOutStreamPath $stdOutStreamPath `
                -StdErrStreamPath $stdErrStreamPath `
                -CancelPath $cancelPath `
                -StdOut ([ref]$stdout) `
                -StdErr ([ref]$stderr) `
                -TimedOut ([ref]$timedOut) `
                -Truncated ([ref]$truncated) `
                -Cancelled ([ref]$cancelled) `
                -StreamSinkFailed ([ref]$streamSinkFailed) `
                -ExitCode ([ref]$exitCode)
        } catch {
            $stdout = ""
            $stderr = ($_ | Out-String).TrimEnd()
            $exitCode = 1
            $timedOut = $false
            $truncated = $false
            $cancelled = $false
            $streamSinkFailed = $true
        }
    } finally {
        Restore-WindoPreserveEnvironment -State $envState
    }

    if ($null -eq $stdout) { $stdout = "" }
    if ($null -eq $stderr) { $stderr = "" }

    $output = _windo_join_output_streams $stdout $stderr
    if ($cancelled) {
        $output = ($output + "`n<WINDO: command cancelled by caller>").TrimEnd()
    } elseif ($timedOut) {
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
        RunnerCancelled = [bool]$cancelled
        StreamSinkFailed = [bool]$streamSinkFailed
        StreamProtocolVersion = 1
    }

    try {
        $sealedResult = _windo_build_artifact_payload $result
        if ($null -eq $sealedResult) { throw "Unable to secure result." }
        $sealedResultJson = $sealedResult | ConvertTo-Json -Compress
        Write-TextFileAtomic -Path $outPath -Content $sealedResultJson -Encoding (New-Object System.Text.UTF8Encoding($false))
        Write-RunnerTrace "WROTE RESULT: ExitCode=$exitCode DurationMs=$durationMs TimedOut=$timedOut Truncated=$truncated Cancelled=$cancelled StreamSinkFailed=$streamSinkFailed"
    } catch {
        Write-RunnerTrace ("EXIT 4: failed to write result JSON: $($_.Exception.Message)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".failed") -ErrorAction SilentlyContinue } catch {}
        $req = $null
        continue
    }

    try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -LiteralPath $cancelPath -Force -ErrorAction SilentlyContinue } catch {}

    Write-RunnerTrace "REQUEST END: $reqId"
    $req = $null
    }

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




' in expression or statement.
  - windo_runner.ps1: Missing closing '}' in statement block or type definition.
  - windo_runner.ps1: Missing closing '}' in statement block or type definition.

Release checksums are regenerated only after the complete Prometheus runtime is finalized. No private signing key is stored in the repository.
