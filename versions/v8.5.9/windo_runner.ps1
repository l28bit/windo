$ErrorActionPreference = "Stop"

$SecureDir  = Join-Path $HOME ".pwsh_secure"
$RunnerLast = Join-Path $SecureDir "windo_runner_last.txt"
$MutexName  = "Global\WindoRunnerMutex"

function Get-WindoRunnerCurrentIdentitySid {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($identity -and $identity.User -and -not [string]::IsNullOrWhiteSpace([string]$identity.User.Value)) {
            return [string]$identity.User.Value
        }
    } catch { }
    return $null
}

function Get-WindoRunnerIdentityScopeToken {
    $sid = Get-WindoRunnerCurrentIdentitySid
    if (-not [string]::IsNullOrWhiteSpace($sid)) { return ($sid -replace '[^A-Za-z0-9_-]', '_') }
    $account = "$env:USERDOMAIN\$env:USERNAME"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($account.ToLowerInvariant())
        $hex = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("X2") })
        return "ACCOUNT-$($hex.Substring(0, 16))"
    } finally { $sha.Dispose() }
}

$MutexName = "$MutexName-$(Get-WindoRunnerIdentityScopeToken)"

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
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [Parameter(Mandatory = $true)][string]$CommandLine,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][int]$TimeoutMs,
        [Parameter(Mandatory = $true)][int]$MaxCharsPerStream,
        [Parameter(Mandatory = $true)]$StdOut,
        [Parameter(Mandatory = $true)]$StdErr,
        [Parameter(Mandatory = $true)]$TimedOut,
        [Parameter(Mandatory = $true)]$Truncated,
        [Parameter(Mandatory = $true)]$ExitCode
    )
    [WindoRunner.ChildExec]::RunPowerShell($PowerShellPath, $CommandLine, $WorkingDirectory, $TimeoutMs, $MaxCharsPerStream, $StdOut, $StdErr, $TimedOut, $Truncated, $ExitCode)
}

if (-not ("WindoRunner.ChildExec" -as [type])) {
    $cs = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
        'dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uRGlhZ25vc3RpY3M7CnVzaW5nIFN5c3RlbS5JTzsKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzOwp1c2luZyBTeXN0ZW0uVGV4dDsKdXNpbmcgU3lzdGVtLlRocmVhZGluZzsKdXNpbmcgU3lzdGVtLlRocmVhZGluZy5UYXNrczsKCm5hbWVzcGFjZSBXaW5kb1J1bm5lcgp7CiAgICBwdWJsaWMgc3RhdGljIGNsYXNzIENoaWxkRXhlYwogICAgewogICAgICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIENoYXJTZXQgPSBDaGFyU2V0LlVuaWNvZGUsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBJbnRQdHIgQ3JlYXRlSm9iT2JqZWN0KEludFB0ciBqb2JBdHRyaWJ1dGVzLCBzdHJpbmcgbmFtZSk7CgogICAgICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgICAgIFtyZXR1cm46IE1hcnNoYWxBcyhVbm1hbmFnZWRUeXBlLkJvb2wpXQogICAgICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBib29sIEFzc2lnblByb2Nlc3NUb0pvYk9iamVjdChJbnRQdHIgam9iLCBJbnRQdHIgcHJvY2Vzcyk7CgogICAgICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgICAgIFtyZXR1cm46IE1hcnNoYWxBcyhVbm1hbmFnZWRUeXBlLkJvb2wpXQogICAgICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBib29sIFRlcm1pbmF0ZUpvYk9iamVjdChJbnRQdHIgam9iLCB1aW50IGV4aXRDb2RlKTsKCiAgICAgICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICAgICAgW3JldHVybjogTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuQm9vbCldCiAgICAgICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgU2V0SW5mb3JtYXRpb25Kb2JPYmplY3QoCiAgICAgICAgICAgIEludFB0ciBqb2IsCiAgICAgICAgICAgIEpvYk9iamVjdEluZm9DbGFzcyBpbmZvQ2xhc3MsCiAgICAgICAgICAgIHJlZiBKb2JPYmplY3RFeHRlbmRlZExpbWl0SW5mb3JtYXRpb24gaW5mbywKICAgICAgICAgICAgdWludCBpbmZvTGVuZ3RoKTsKCiAgICAgICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICAgICAgW3JldHVybjogTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuQm9vbCldCiAgICAgICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgQ2xvc2VIYW5kbGUoSW50UHRyIGhhbmRsZSk7CgogICAgICAgIHByaXZhdGUgY29uc3QgdWludCBKb2JPYmplY3RMaW1pdEtpbGxPbkpvYkNsb3NlID0gMHgwMDAwMjAwMDsKCiAgICAgICAgcHJpdmF0ZSBlbnVtIEpvYk9iamVjdEluZm9DbGFzcwogICAgICAgIHsKICAgICAgICAgICAgRXh0ZW5kZWRMaW1pdEluZm9ybWF0aW9uID0gOQogICAgICAgIH0KCiAgICAgICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXQogICAgICAgIHByaXZhdGUgc3RydWN0IEpvYk9iamVjdEJhc2ljTGltaXRJbmZvcm1hdGlvbgogICAgICAgIHsKICAgICAgICAgICAgcHVibGljIGxvbmcgUGVyUHJvY2Vzc1VzZXJUaW1lTGltaXQ7CiAgICAgICAgICAgIHB1YmxpYyBsb25nIFBlckpvYlVzZXJUaW1lTGltaXQ7CiAgICAgICAgICAgIHB1YmxpYyB1aW50IExpbWl0RmxhZ3M7CiAgICAgICAgICAgIHB1YmxpYyBVSW50UHRyIE1pbmltdW1Xb3JraW5nU2V0U2l6ZTsKICAgICAgICAgICAgcHVibGljIFVJbnRQdHIgTWF4aW11bVdvcmtpbmdTZXRTaXplOwogICAgICAgICAgICBwdWJsaWMgdWludCBBY3RpdmVQcm9jZXNzTGltaXQ7CiAgICAgICAgICAgIHB1YmxpYyBVSW50UHRyIEFmZmluaXR5OwogICAgICAgICAgICBwdWJsaWMgdWludCBQcmlvcml0eUNsYXNzOwogICAgICAgICAgICBwdWJsaWMgdWludCBTY2hlZHVsaW5nQ2xhc3M7CiAgICAgICAgfQoKICAgICAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldCiAgICAgICAgcHJpdmF0ZSBzdHJ1Y3QgSW9Db3VudGVycwogICAgICAgIHsKICAgICAgICAgICAgcHVibGljIHVsb25nIFJlYWRPcGVyYXRpb25Db3VudDsKICAgICAgICAgICAgcHVibGljIHVsb25nIFdyaXRlT3BlcmF0aW9uQ291bnQ7CiAgICAgICAgICAgIHB1YmxpYyB1bG9uZyBPdGhlck9wZXJhdGlvbkNvdW50OwogICAgICAgICAgICBwdWJsaWMgdWxvbmcgUmVhZFRyYW5zZmVyQ291bnQ7CiAgICAgICAgICAgIHB1YmxpYyB1bG9uZyBXcml0ZVRyYW5zZmVyQ291bnQ7CiAgICAgICAgICAgIHB1YmxpYyB1bG9uZyBPdGhlclRyYW5zZmVyQ291bnQ7CiAgICAgICAgfQoKICAgICAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldCiAgICAgICAgcHJpdmF0ZSBzdHJ1Y3QgSm9iT2JqZWN0RXh0ZW5kZWRMaW1pdEluZm9ybWF0aW9uCiAgICAgICAgewogICAgICAgICAgICBwdWJsaWMgSm9iT2JqZWN0QmFzaWNMaW1pdEluZm9ybWF0aW9uIEJhc2ljTGltaXRJbmZvcm1hdGlvbjsKICAgICAgICAgICAgcHVibGljIElvQ291bnRlcnMgSW9JbmZvOwogICAgICAgICAgICBwdWJsaWMgVUludFB0ciBQcm9jZXNzTWVtb3J5TGltaXQ7CiAgICAgICAgICAgIHB1YmxpYyBVSW50UHRyIEpvYk1lbW9yeUxpbWl0OwogICAgICAgICAgICBwdWJsaWMgVUludFB0ciBQZWFrUHJvY2Vzc01lbW9yeVVzZWQ7CiAgICAgICAgICAgIHB1YmxpYyBVSW50UHRyIFBlYWtKb2JNZW1vcnlVc2VkOwogICAgICAgIH0KCiAgICAgICAgcHJpdmF0ZSBzdGF0aWMgYm9vbCBJc1dpbmRvd3MoKQogICAgICAgIHsKICAgICAgICAgICAgdmFyIHBsYXRmb3JtID0gRW52aXJvbm1lbnQuT1NWZXJzaW9uLlBsYXRmb3JtOwogICAgICAgICAgICByZXR1cm4gcGxhdGZvcm0gPT0gUGxhdGZvcm1JRC5XaW4zMk5UIHx8CiAgICAgICAgICAgICAgICAgICBwbGF0Zm9ybSA9PSBQbGF0Zm9ybUlELldpbjMyUyB8fAogICAgICAgICAgICAgICAgICAgcGxhdGZvcm0gPT0gUGxhdGZvcm1JRC5XaW4zMldpbmRvd3MgfHwKICAgICAgICAgICAgICAgICAgIHBsYXRmb3JtID09IFBsYXRmb3JtSUQuV2luQ0U7CiAgICAgICAgfQoKICAgICAgICBwcml2YXRlIHN0YXRpYyBJbnRQdHIgVHJ5QXNzaWduSm9iKFByb2Nlc3MgcHJvY2VzcykKICAgICAgICB7CiAgICAgICAgICAgIGlmICghSXNXaW5kb3dzKCkpIHJldHVybiBJbnRQdHIuWmVybzsKICAgICAgICAgICAgSW50UHRyIGpvYiA9IEludFB0ci5aZXJvOwogICAgICAgICAgICB0cnkKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgam9iID0gQ3JlYXRlSm9iT2JqZWN0KEludFB0ci5aZXJvLCBudWxsKTsKICAgICAgICAgICAgICAgIGlmIChqb2IgPT0gSW50UHRyLlplcm8pCiAgICAgICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIEludFB0ci5aZXJvOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgdmFyIGxpbWl0cyA9IG5ldyBKb2JPYmplY3RFeHRlbmRlZExpbWl0SW5mb3JtYXRpb24oKTsKICAgICAgICAgICAgICAgIGxpbWl0cy5CYXNpY0xpbWl0SW5mb3JtYXRpb24uTGltaXRGbGFncyA9IEpvYk9iamVjdExpbWl0S2lsbE9uSm9iQ2xvc2U7CiAgICAgICAgICAgICAgICBpZiAoIVNldEluZm9ybWF0aW9uSm9iT2JqZWN0KAogICAgICAgICAgICAgICAgICAgICAgICBqb2IsCiAgICAgICAgICAgICAgICAgICAgICAgIEpvYk9iamVjdEluZm9DbGFzcy5FeHRlbmRlZExpbWl0SW5mb3JtYXRpb24sCiAgICAgICAgICAgICAgICAgICAgICAgIHJlZiBsaW1pdHMsCiAgICAgICAgICAgICAgICAgICAgICAgICh1aW50KU1hcnNoYWwuU2l6ZU9mKHR5cGVvZihKb2JPYmplY3RFeHRlbmRlZExpbWl0SW5mb3JtYXRpb24pKSkgfHwKICAgICAgICAgICAgICAgICAgICAhQXNzaWduUHJvY2Vzc1RvSm9iT2JqZWN0KGpvYiwgcHJvY2Vzcy5IYW5kbGUpKQogICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgIENsb3NlSGFuZGxlKGpvYik7CiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIEludFB0ci5aZXJvOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgcmV0dXJuIGpvYjsKICAgICAgICAgICAgfQogICAgICAgICAgICBjYXRjaAogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICBpZiAoam9iICE9IEludFB0ci5aZXJvKSBDbG9zZUhhbmRsZShqb2IpOwogICAgICAgICAgICAgICAgcmV0dXJuIEludFB0ci5aZXJvOwogICAgICAgICAgICB9CiAgICAgICAgfQoKICAgICAgICBwcml2YXRlIHN0YXRpYyB2b2lkIFRlcm1pbmF0ZVByb2Nlc3NUcmVlKFByb2Nlc3MgcHJvY2VzcywgSW50UHRyIGpvYikKICAgICAgICB7CiAgICAgICAgICAgIGJvb2wgam9iVGVybWluYXRlZCA9IGZhbHNlOwogICAgICAgICAgICBpZiAoam9iICE9IEludFB0ci5aZXJvKQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICB0cnkgeyBqb2JUZXJtaW5hdGVkID0gVGVybWluYXRlSm9iT2JqZWN0KGpvYiwgMSk7IH0gY2F0Y2ggeyB9CiAgICAgICAgICAgIH0KCiAgICAgICAgICAgIC8vIFdpbmRvd3MgUG93ZXJTaGVsbCA1LjEgbGFja3MgUHJvY2Vzcy5LaWxsKGJvb2wpLiBJZiBhc3NpZ25tZW50CiAgICAgICAgICAgIC8vIHRvIGEgSm9iIE9iamVjdCB3YXMgYmxvY2tlZCBieSBhbiBleGlzdGluZyBqb2IgcG9saWN5LCB0YXNra2lsbAogICAgICAgICAgICAvLyBwcm92aWRlcyBhIGJvdW5kZWQgbmF0aXZlIHByb2Nlc3MtdHJlZSBmYWxsYmFjay4KICAgICAgICAgICAgaWYgKCFqb2JUZXJtaW5hdGVkICYmIElzV2luZG93cygpKQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICB0cnkKICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICBpZiAoIXByb2Nlc3MuSGFzRXhpdGVkKQogICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgdmFyIHRhc2tLaWxsID0gbmV3IFByb2Nlc3NTdGFydEluZm8oKTsKICAgICAgICAgICAgICAgICAgICAgICAgdGFza0tpbGwuRmlsZU5hbWUgPSBQYXRoLkNvbWJpbmUoRW52aXJvbm1lbnQuR2V0Rm9sZGVyUGF0aChFbnZpcm9ubWVudC5TcGVjaWFsRm9sZGVyLlN5c3RlbSksICJ0YXNra2lsbC5leGUiKTsKICAgICAgICAgICAgICAgICAgICAgICAgdGFza0tpbGwuQXJndW1lbnRzID0gIi9QSUQgIiArIHByb2Nlc3MuSWQgKyAiIC9UIC9GIjsKICAgICAgICAgICAgICAgICAgICAgICAgdGFza0tpbGwuVXNlU2hlbGxFeGVjdXRlID0gZmFsc2U7CiAgICAgICAgICAgICAgICAgICAgICAgIHRhc2tLaWxsLkNyZWF0ZU5vV2luZG93ID0gdHJ1ZTsKICAgICAgICAgICAgICAgICAgICAgICAgdGFza0tpbGwuUmVkaXJlY3RTdGFuZGFyZE91dHB1dCA9IHRydWU7CiAgICAgICAgICAgICAgICAgICAgICAgIHRhc2tLaWxsLlJlZGlyZWN0U3RhbmRhcmRFcnJvciA9IHRydWU7CiAgICAgICAgICAgICAgICAgICAgICAgIHVzaW5nICh2YXIga2lsbGVyID0gUHJvY2Vzcy5TdGFydCh0YXNrS2lsbCkpCiAgICAgICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmIChraWxsZXIgIT0gbnVsbCkga2lsbGVyLldhaXRGb3JFeGl0KDEwMDAwKTsKICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIGNhdGNoIHsgfQogICAgICAgICAgICB9CgogICAgICAgICAgICB0cnkKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgaWYgKCFwcm9jZXNzLkhhc0V4aXRlZCkKICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICB2YXIgdHJlZUtpbGwgPSB0eXBlb2YoUHJvY2VzcykuR2V0TWV0aG9kKCJLaWxsIiwgbmV3W10geyB0eXBlb2YoYm9vbCkgfSk7CiAgICAgICAgICAgICAgICAgICAgaWYgKHRyZWVLaWxsICE9IG51bGwpCiAgICAgICAgICAgICAgICAgICAgICAgIHRyZWVLaWxsLkludm9rZShwcm9jZXNzLCBuZXcgb2JqZWN0W10geyB0cnVlIH0pOwogICAgICAgICAgICAgICAgICAgIGVsc2UKICAgICAgICAgICAgICAgICAgICAgICAgcHJvY2Vzcy5LaWxsKCk7CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgY2F0Y2gKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgdHJ5IHsgaWYgKCFwcm9jZXNzLkhhc0V4aXRlZCkgcHJvY2Vzcy5LaWxsKCk7IH0gY2F0Y2ggeyB9CiAgICAgICAgICAgIH0KICAgICAgICB9CgogICAgICAgIHByaXZhdGUgc3RhdGljIGJvb2wgV2FpdEZvclJlYWRlcnMoVGFzazxzdHJpbmc+IHN0ZG91dFRhc2ssIFRhc2s8c3RyaW5nPiBzdGRlcnJUYXNrLCBpbnQgdGltZW91dE1zKQogICAgICAgIHsKICAgICAgICAgICAgdHJ5IHsgcmV0dXJuIFRhc2suV2FpdEFsbChuZXcgVGFza1tdIHsgc3Rkb3V0VGFzaywgc3RkZXJyVGFzayB9LCB0aW1lb3V0TXMpOyB9CiAgICAgICAgICAgIGNhdGNoIHsgcmV0dXJuIHN0ZG91dFRhc2suSXNDb21wbGV0ZWQgJiYgc3RkZXJyVGFzay5Jc0NvbXBsZXRlZDsgfQogICAgICAgIH0KCiAgICAgICAgcHJpdmF0ZSBzZWFsZWQgY2xhc3MgQ2FwdHVyZVN0YXRlCiAgICAgICAgewogICAgICAgICAgICBwdWJsaWMgdm9sYXRpbGUgYm9vbCBMaW1pdFJlYWNoZWQ7CiAgICAgICAgfQoKICAgICAgICBwcml2YXRlIHN0YXRpYyBzdHJpbmcgQ29tcGxldGVkUmVhZGVyUmVzdWx0KFRhc2s8c3RyaW5nPiB0YXNrKQogICAgICAgIHsKICAgICAgICAgICAgaWYgKCF0YXNrLklzQ29tcGxldGVkIHx8IHRhc2suSXNDYW5jZWxlZCB8fCB0YXNrLklzRmF1bHRlZCkgcmV0dXJuICIiOwogICAgICAgICAgICB0cnkgeyByZXR1cm4gdGFzay5SZXN1bHQgPz8gIiI7IH0gY2F0Y2ggeyByZXR1cm4gIiI7IH0KICAgICAgICB9CgogICAgICAgIHByaXZhdGUgc3RhdGljIHN0cmluZyBSZXNvbHZlV29ya2luZ0RpcmVjdG9yeShzdHJpbmcgcmVxdWVzdGVkUGF0aCkKICAgICAgICB7CiAgICAgICAgICAgIHZhciBjYW5kaWRhdGVzID0gbmV3W10KICAgICAgICAgICAgewogICAgICAgICAgICAgICAgcmVxdWVzdGVkUGF0aCwKICAgICAgICAgICAgICAgIEVudmlyb25tZW50LkdldEZvbGRlclBhdGgoRW52aXJvbm1lbnQuU3BlY2lhbEZvbGRlci5Vc2VyUHJvZmlsZSksCiAgICAgICAgICAgICAgICBQYXRoLkdldFRlbXBQYXRoKCkKICAgICAgICAgICAgfTsKICAgICAgICAgICAgZm9yZWFjaCAodmFyIGNhbmRpZGF0ZSBpbiBjYW5kaWRhdGVzKQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICBpZiAoc3RyaW5nLklzTnVsbE9yV2hpdGVTcGFjZShjYW5kaWRhdGUpIHx8ICFQYXRoLklzUGF0aFJvb3RlZChjYW5kaWRhdGUpKQogICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlOwogICAgICAgICAgICAgICAgdHJ5CiAgICAgICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAgICAgdmFyIGZ1bGxQYXRoID0gUGF0aC5HZXRGdWxsUGF0aChjYW5kaWRhdGUpOwogICAgICAgICAgICAgICAgICAgIGlmIChEaXJlY3RvcnkuRXhpc3RzKGZ1bGxQYXRoKSkKICAgICAgICAgICAgICAgICAgICAgICAgcmV0dXJuIGZ1bGxQYXRoOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgY2F0Y2ggeyB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgdGhyb3cgbmV3IERpcmVjdG9yeU5vdEZvdW5kRXhjZXB0aW9uKCJObyBzYWZlIGNoaWxkLXByb2Nlc3Mgd29ya2luZyBkaXJlY3RvcnkgaXMgYXZhaWxhYmxlLiIpOwogICAgICAgIH0KCiAgICAgICAgcHJpdmF0ZSBzdGF0aWMgc3RyaW5nIFJlYWRTdHJlYW1Ub01heChTdHJlYW1SZWFkZXIgciwgaW50IG1heENoYXJzLCBDYXB0dXJlU3RhdGUgc3RhdGUpCiAgICAgICAgewogICAgICAgICAgICB2YXIgc2IgPSBuZXcgU3RyaW5nQnVpbGRlcigpOwogICAgICAgICAgICB2YXIgYnVmID0gbmV3IGNoYXJbODE5Ml07CiAgICAgICAgICAgIGludCB0b3RhbCA9IDA7CiAgICAgICAgICAgIHRyeQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICB3aGlsZSAodG90YWwgPCBtYXhDaGFycykKICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICBpbnQgbiA9IHIuUmVhZChidWYsIDAsIE1hdGguTWluKGJ1Zi5MZW5ndGgsIG1heENoYXJzIC0gdG90YWwpKTsKICAgICAgICAgICAgICAgICAgICBpZiAobiA8PSAwKSBicmVhazsKICAgICAgICAgICAgICAgICAgICBzYi5BcHBlbmQoYnVmLCAwLCBuKTsKICAgICAgICAgICAgICAgICAgICB0b3RhbCArPSBuOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9CiAgICAgICAgICAgIGNhdGNoIHsgfQogICAgICAgICAgICBpZiAodG90YWwgPj0gbWF4Q2hhcnMpCiAgICAgICAgICAgICAgICBzdGF0ZS5MaW1pdFJlYWNoZWQgPSB0cnVlOwogICAgICAgICAgICByZXR1cm4gc2IuVG9TdHJpbmcoKTsKICAgICAgICB9CgogICAgICAgIHByaXZhdGUgc3RhdGljIHN0cmluZyBCdWlsZEdhdGVkU2NyaXB0KHN0cmluZyBzY3JpcHRUZXh0LCBzdHJpbmcgZ2F0ZU5hbWUpCiAgICAgICAgewogICAgICAgICAgICB2YXIgc2FmZUdhdGVOYW1lID0gKGdhdGVOYW1lID8/ICIiKS5SZXBsYWNlKCInIiwgIicnIik7CiAgICAgICAgICAgIHJldHVybiAiJHdpbmRvR2F0ZT1bU3lzdGVtLlRocmVhZGluZy5FdmVudFdhaXRIYW5kbGVdOjpPcGVuRXhpc3RpbmcoJyIgKyBzYWZlR2F0ZU5hbWUgKyAiJyk7IiArCiAgICAgICAgICAgICAgICAgICAidHJ5e2lmKC1ub3QgJHdpbmRvR2F0ZS5XYWl0T25lKDMwMDAwKSl7ZXhpdCAxMjR9fWZpbmFsbHl7JHdpbmRvR2F0ZS5EaXNwb3NlKCl9OyIgKwogICAgICAgICAgICAgICAgICAgRW52aXJvbm1lbnQuTmV3TGluZSArIChzY3JpcHRUZXh0ID8/ICIiKTsKICAgICAgICB9CgogICAgICAgIHB1YmxpYyBzdGF0aWMgdm9pZCBSdW5Qb3dlclNoZWxsKAogICAgICAgICAgICBzdHJpbmcgZXhlY3V0YWJsZVBhdGgsCiAgICAgICAgICAgIHN0cmluZyBzY3JpcHRUZXh0LAogICAgICAgICAgICBzdHJpbmcgd29ya2luZ0RpcmVjdG9yeSwKICAgICAgICAgICAgaW50IHRpbWVvdXRNcywKICAgICAgICAgICAgaW50IG1heENoYXJzUGVyU3RyZWFtLAogICAgICAgICAgICBvdXQgc3RyaW5nIHN0ZG91dCwKICAgICAgICAgICAgb3V0IHN0cmluZyBzdGRlcnIsCiAgICAgICAgICAgIG91dCBib29sIHRpbWVkT3V0LAogICAgICAgICAgICBvdXQgYm9vbCB0cnVuY2F0ZWQsCiAgICAgICAgICAgIG91dCBpbnQgZXhpdENvZGUpCiAgICAgICAgewogICAgICAgICAgICB0aW1lZE91dCA9IGZhbHNlOwogICAgICAgICAgICB0cnVuY2F0ZWQgPSBmYWxzZTsKICAgICAgICAgICAgZXhpdENvZGUgPSAxOwogICAgICAgICAgICBzdGRvdXQgPSAiIjsKICAgICAgICAgICAgc3RkZXJyID0gIiI7CiAgICAgICAgICAgIGlmIChzdHJpbmcuSXNOdWxsT3JXaGl0ZVNwYWNlKGV4ZWN1dGFibGVQYXRoKSkKICAgICAgICAgICAgICAgIGV4ZWN1dGFibGVQYXRoID0gInBvd2Vyc2hlbGwuZXhlIjsKICAgICAgICAgICAgRXZlbnRXYWl0SGFuZGxlIHN0YXJ0R2F0ZSA9IG51bGw7CiAgICAgICAgICAgIHN0cmluZyBjb21tYW5kVGV4dCA9IHNjcmlwdFRleHQgPz8gIiI7CiAgICAgICAgICAgIGlmIChJc1dpbmRvd3MoKSkKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgdmFyIGdhdGVOYW1lID0gIkxvY2FsXFxXaW5kb1J1bm5lci0iICsgR3VpZC5OZXdHdWlkKCkuVG9TdHJpbmcoIk4iKTsKICAgICAgICAgICAgICAgIGJvb2wgY3JlYXRlZE5ldzsKICAgICAgICAgICAgICAgIHN0YXJ0R2F0ZSA9IG5ldyBFdmVudFdhaXRIYW5kbGUoZmFsc2UsIEV2ZW50UmVzZXRNb2RlLk1hbnVhbFJlc2V0LCBnYXRlTmFtZSwgb3V0IGNyZWF0ZWROZXcpOwogICAgICAgICAgICAgICAgaWYgKCFjcmVhdGVkTmV3KQogICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgIHN0YXJ0R2F0ZS5EaXNwb3NlKCk7CiAgICAgICAgICAgICAgICAgICAgdGhyb3cgbmV3IEludmFsaWRPcGVyYXRpb25FeGNlcHRpb24oIlVuYWJsZSB0byBjcmVhdGUgYSB1bmlxdWUgY2hpbGQtcHJvY2VzcyBzdGFydCBnYXRlLiIpOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgY29tbWFuZFRleHQgPSBCdWlsZEdhdGVkU2NyaXB0KGNvbW1hbmRUZXh0LCBnYXRlTmFtZSk7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgdmFyIGVuY29kZWRDb21tYW5kID0gQ29udmVydC5Ub0Jhc2U2NFN0cmluZyhFbmNvZGluZy5Vbmljb2RlLkdldEJ5dGVzKGNvbW1hbmRUZXh0KSk7CiAgICAgICAgICAgIHZhciBwc2kgPSBuZXcgUHJvY2Vzc1N0YXJ0SW5mbygpOwogICAgICAgICAgICBwc2kuRmlsZU5hbWUgPSBleGVjdXRhYmxlUGF0aDsKICAgICAgICAgICAgcHNpLkFyZ3VtZW50cyA9ICItTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtTm9Mb2dvIC1FbmNvZGVkQ29tbWFuZCAiICsgZW5jb2RlZENvbW1hbmQ7CiAgICAgICAgICAgIGlmIChwc2kuQXJndW1lbnRzLkxlbmd0aCA+IDMyMDAwKQogICAgICAgICAgICAgICAgdGhyb3cgbmV3IEFyZ3VtZW50RXhjZXB0aW9uKCJUaGUgZ2F0ZWQgUG93ZXJTaGVsbCBjb21tYW5kIGV4Y2VlZHMgdGhlIFdpbmRvd3MgcHJvY2VzcyBjb21tYW5kLWxpbmUgbGltaXQuIiwgInNjcmlwdFRleHQiKTsKICAgICAgICAgICAgcHNpLldvcmtpbmdEaXJlY3RvcnkgPSBSZXNvbHZlV29ya2luZ0RpcmVjdG9yeSh3b3JraW5nRGlyZWN0b3J5KTsKICAgICAgICAgICAgcHNpLlJlZGlyZWN0U3RhbmRhcmRPdXRwdXQgPSB0cnVlOwogICAgICAgICAgICBwc2kuUmVkaXJlY3RTdGFuZGFyZEVycm9yID0gdHJ1ZTsKICAgICAgICAgICAgcHNpLlVzZVNoZWxsRXhlY3V0ZSA9IGZhbHNlOwogICAgICAgICAgICBwc2kuQ3JlYXRlTm9XaW5kb3cgPSB0cnVlOwogICAgICAgICAgICBQcm9jZXNzIHAgPSBudWxsOwogICAgICAgICAgICBJbnRQdHIgam9iID0gSW50UHRyLlplcm87CiAgICAgICAgICAgIGJvb2wgZGlzcG9zZVByb2Nlc3NTeW5jaHJvbm91c2x5ID0gdHJ1ZTsKICAgICAgICAgICAgdHJ5CiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgIHAgPSBQcm9jZXNzLlN0YXJ0KHBzaSk7CiAgICAgICAgICAgICAgICBpZiAocCA9PSBudWxsKQogICAgICAgICAgICAgICAgICAgIHRocm93IG5ldyBJbnZhbGlkT3BlcmF0aW9uRXhjZXB0aW9uKCJUaGUgUG93ZXJTaGVsbCBjaGlsZCBwcm9jZXNzIGRpZCBub3Qgc3RhcnQuIik7CgogICAgICAgICAgICAgICAgaWYgKElzV2luZG93cygpKQogICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgIGpvYiA9IFRyeUFzc2lnbkpvYihwKTsKICAgICAgICAgICAgICAgICAgICBpZiAoam9iID09IEludFB0ci5aZXJvKQogICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgdHJ5IHsgaWYgKCFwLkhhc0V4aXRlZCkgcC5LaWxsKCk7IH0gY2F0Y2ggeyB9CiAgICAgICAgICAgICAgICAgICAgICAgIHRocm93IG5ldyBJbnZhbGlkT3BlcmF0aW9uRXhjZXB0aW9uKCJVbmFibGUgdG8gZXN0YWJsaXNoIGNoaWxkLXByb2Nlc3Mgam9iIGNvbnRhaW5tZW50OyBjb21tYW5kIHdhcyBub3QgZXhlY3V0ZWQuIik7CiAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgIHN0YXJ0R2F0ZS5TZXQoKTsKICAgICAgICAgICAgICAgICAgICBzdGFydEdhdGUuRGlzcG9zZSgpOwogICAgICAgICAgICAgICAgICAgIHN0YXJ0R2F0ZSA9IG51bGw7CiAgICAgICAgICAgICAgICB9CgogICAgICAgICAgICAgICAgdHJ5CiAgICAgICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAgICAgdmFyIGNhcHR1cmVTdGF0ZSA9IG5ldyBDYXB0dXJlU3RhdGUoKTsKICAgICAgICAgICAgICAgICAgICB2YXIgdE91dCA9IFRhc2suUnVuKCgpID0+IFJlYWRTdHJlYW1Ub01heChwLlN0YW5kYXJkT3V0cHV0LCBtYXhDaGFyc1BlclN0cmVhbSwgY2FwdHVyZVN0YXRlKSk7CiAgICAgICAgICAgICAgICAgICAgdmFyIHRFcnIgPSBUYXNrLlJ1bigoKSA9PiBSZWFkU3RyZWFtVG9NYXgocC5TdGFuZGFyZEVycm9yLCBtYXhDaGFyc1BlclN0cmVhbSwgY2FwdHVyZVN0YXRlKSk7CiAgICAgICAgICAgICAgICAgICAgdmFyIHdhaXQgPSBTdG9wd2F0Y2guU3RhcnROZXcoKTsKICAgICAgICAgICAgICAgICAgICBib29sIGZpbmlzaGVkID0gZmFsc2U7CiAgICAgICAgICAgICAgICAgICAgd2hpbGUgKCFmaW5pc2hlZCAmJiB3YWl0LkVsYXBzZWRNaWxsaXNlY29uZHMgPCB0aW1lb3V0TXMgJiYgIWNhcHR1cmVTdGF0ZS5MaW1pdFJlYWNoZWQpCiAgICAgICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgICAgICBpbnQgcmVtYWluaW5nID0gdGltZW91dE1zIC0gKGludClNYXRoLk1pbih0aW1lb3V0TXMsIHdhaXQuRWxhcHNlZE1pbGxpc2Vjb25kcyk7CiAgICAgICAgICAgICAgICAgICAgICAgIGZpbmlzaGVkID0gcC5XYWl0Rm9yRXhpdChNYXRoLk1heCgxLCBNYXRoLk1pbihyZW1haW5pbmcsIDEwMCkpKTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgaWYgKGNhcHR1cmVTdGF0ZS5MaW1pdFJlYWNoZWQgJiYgIWZpbmlzaGVkKQogICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgdHJ1bmNhdGVkID0gdHJ1ZTsKICAgICAgICAgICAgICAgICAgICAgICAgVGVybWluYXRlUHJvY2Vzc1RyZWUocCwgam9iKTsKICAgICAgICAgICAgICAgICAgICAgICAgdHJ5IHsgcC5XYWl0Rm9yRXhpdCgxNTAwMCk7IH0gY2F0Y2ggeyB9CiAgICAgICAgICAgICAgICAgICAgICAgIGZpbmlzaGVkID0gdHJ1ZTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgaWYgKCFmaW5pc2hlZCkKICAgICAgICAgICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAgICAgICAgIHRpbWVkT3V0ID0gdHJ1ZTsKICAgICAgICAgICAgICAgICAgICAgICAgVGVybWluYXRlUHJvY2Vzc1RyZWUocCwgam9iKTsKICAgICAgICAgICAgICAgICAgICAgICAgdHJ5IHsgcC5XYWl0Rm9yRXhpdCgxNTAwMCk7IH0gY2F0Y2ggeyB9CiAgICAgICAgICAgICAgICAgICAgfQoKICAgICAgICAgICAgICAgICAgICAvLyBBIGRlc2NlbmRhbnQgY2FuIGluaGVyaXQgcmVkaXJlY3RlZCBoYW5kbGVzIGFmdGVyIHRoZQogICAgICAgICAgICAgICAgICAgIC8vIGRpcmVjdCBjaGlsZCBleGl0cy4gTmV2ZXIgYmxvY2sgaW5kZWZpbml0ZWx5IHdhaXRpbmcgZm9yCiAgICAgICAgICAgICAgICAgICAgLy8gdGhvc2UgaGFuZGxlczogdGVybWluYXRlIHRoZSBhc3NpZ25lZCBqb2IvdHJlZSwgY2xvc2UKICAgICAgICAgICAgICAgICAgICAvLyB0aGUgcmVhZGVycywgYW5kIGFsbG93IG9ubHkgYSBib3VuZGVkIGZpbmFsIGRyYWluLgogICAgICAgICAgICAgICAgICAgIGlmICghV2FpdEZvclJlYWRlcnModE91dCwgdEVyciwgNTAwMCkpCiAgICAgICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgICAgICB0aW1lZE91dCA9IHRydWU7CiAgICAgICAgICAgICAgICAgICAgICAgIFRlcm1pbmF0ZVByb2Nlc3NUcmVlKHAsIGpvYik7CiAgICAgICAgICAgICAgICAgICAgICAgIC8vIENsb3NpbmcgYSBTdHJlYW1SZWFkZXIgY29uY3VycmVudGx5IHdpdGggYSBibG9ja2VkCiAgICAgICAgICAgICAgICAgICAgICAgIC8vIHN5bmNocm9ub3VzIFJlYWQgY2FuIGl0c2VsZiBibG9jay4gS2lsbC1vbi1jbG9zZSBpcwogICAgICAgICAgICAgICAgICAgICAgICAvLyB0aGUgYm91bmRlZCBXaW5kb3dzIHByaW1pdGl2ZSwgc28gcmVsZWFzZSB0aGUgam9iCiAgICAgICAgICAgICAgICAgICAgICAgIC8vIGJlZm9yZSB0aGUgZmluYWwgZHJhaW4gYW5kIG5ldmVyIGNsb3NlIHJlYWRlcnMgaGVyZS4KICAgICAgICAgICAgICAgICAgICAgICAgaWYgKGpvYiAhPSBJbnRQdHIuWmVybykKICAgICAgICAgICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgQ2xvc2VIYW5kbGUoam9iKTsKICAgICAgICAgICAgICAgICAgICAgICAgICAgIGpvYiA9IEludFB0ci5aZXJvOwogICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgICAgIGlmICghV2FpdEZvclJlYWRlcnModE91dCwgdEVyciwgMjAwMCkpCiAgICAgICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgIGRpc3Bvc2VQcm9jZXNzU3luY2hyb25vdXNseSA9IGZhbHNlOwogICAgICAgICAgICAgICAgICAgICAgICAgICAgdmFyIHByb2Nlc3NUb0Rpc3Bvc2UgPSBwOwogICAgICAgICAgICAgICAgICAgICAgICAgICAgVGFzay5XaGVuQWxsKHRPdXQsIHRFcnIpLkNvbnRpbnVlV2l0aCgKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZ25vcmVkID0+IHsgdHJ5IHsgcHJvY2Vzc1RvRGlzcG9zZS5EaXNwb3NlKCk7IH0gY2F0Y2ggeyB9IH0sCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVGFza1NjaGVkdWxlci5EZWZhdWx0KTsKICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICBzdGRvdXQgPSBDb21wbGV0ZWRSZWFkZXJSZXN1bHQodE91dCk7CiAgICAgICAgICAgICAgICAgICAgc3RkZXJyID0gQ29tcGxldGVkUmVhZGVyUmVzdWx0KHRFcnIpOwogICAgICAgICAgICAgICAgICAgIGlmIChzdGRvdXQuTGVuZ3RoID49IG1heENoYXJzUGVyU3RyZWFtIHx8IHN0ZGVyci5MZW5ndGggPj0gbWF4Q2hhcnNQZXJTdHJlYW0pCiAgICAgICAgICAgICAgICAgICAgICAgIHRydW5jYXRlZCA9IHRydWU7CiAgICAgICAgICAgICAgICAgICAgdHJ5CiAgICAgICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgICAgICBleGl0Q29kZSA9IHAuSGFzRXhpdGVkID8gcC5FeGl0Q29kZSA6IC0xOwogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICBjYXRjaAogICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgZXhpdENvZGUgPSAtMTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgaWYgKHRpbWVkT3V0KQogICAgICAgICAgICAgICAgICAgICAgICBleGl0Q29kZSA9IC0xOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgZmluYWxseQogICAgICAgICAgICAgICAgewogICAgICAgICAgICAgICAgICAgIGlmIChqb2IgIT0gSW50UHRyLlplcm8pIENsb3NlSGFuZGxlKGpvYik7CiAgICAgICAgICAgICAgICAgICAgam9iID0gSW50UHRyLlplcm87CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgZmluYWxseQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICBpZiAoc3RhcnRHYXRlICE9IG51bGwpIHN0YXJ0R2F0ZS5EaXNwb3NlKCk7CiAgICAgICAgICAgICAgICBpZiAoam9iICE9IEludFB0ci5aZXJvKSBDbG9zZUhhbmRsZShqb2IpOwogICAgICAgICAgICAgICAgaWYgKHAgIT0gbnVsbCAmJiBkaXNwb3NlUHJvY2Vzc1N5bmNocm9ub3VzbHkpIHAuRGlzcG9zZSgpOwogICAgICAgICAgICB9CiAgICAgICAgfQoKICAgICAgICAvLyBCYWNrd2FyZC1jb21wYXRpYmxlIG92ZXJsb2FkIGZvciBjYWxsZXJzIGNyZWF0ZWQgYmVmb3JlIHdvcmtpbmcKICAgICAgICAvLyBkaXJlY3RvcnkgcHJvcGFnYXRpb24gd2FzIGFkZGVkLgogICAgICAgIHB1YmxpYyBzdGF0aWMgdm9pZCBSdW5Qb3dlclNoZWxsKAogICAgICAgICAgICBzdHJpbmcgZXhlY3V0YWJsZVBhdGgsCiAgICAgICAgICAgIHN0cmluZyBzY3JpcHRUZXh0LAogICAgICAgICAgICBpbnQgdGltZW91dE1zLAogICAgICAgICAgICBpbnQgbWF4Q2hhcnNQZXJTdHJlYW0sCiAgICAgICAgICAgIG91dCBzdHJpbmcgc3Rkb3V0LAogICAgICAgICAgICBvdXQgc3RyaW5nIHN0ZGVyciwKICAgICAgICAgICAgb3V0IGJvb2wgdGltZWRPdXQsCiAgICAgICAgICAgIG91dCBib29sIHRydW5jYXRlZCwKICAgICAgICAgICAgb3V0IGludCBleGl0Q29kZSkKICAgICAgICB7CiAgICAgICAgICAgIFJ1blBvd2VyU2hlbGwoCiAgICAgICAgICAgICAgICBleGVjdXRhYmxlUGF0aCwKICAgICAgICAgICAgICAgIHNjcmlwdFRleHQsCiAgICAgICAgICAgICAgICBFbnZpcm9ubWVudC5DdXJyZW50RGlyZWN0b3J5LAogICAgICAgICAgICAgICAgdGltZW91dE1zLAogICAgICAgICAgICAgICAgbWF4Q2hhcnNQZXJTdHJlYW0sCiAgICAgICAgICAgICAgICBvdXQgc3Rkb3V0LAogICAgICAgICAgICAgICAgb3V0IHN0ZGVyciwKICAgICAgICAgICAgICAgIG91dCB0aW1lZE91dCwKICAgICAgICAgICAgICAgIG91dCB0cnVuY2F0ZWQsCiAgICAgICAgICAgICAgICBvdXQgZXhpdENvZGUpOwogICAgICAgIH0KCiAgICAgICAgLy8gQmFja3dhcmQtY29tcGF0aWJsZSBlbnRyeSBwb2ludCBmb3IgYWxyZWFkeS1pbnN0YWxsZWQgcnVubmVyIGhlbHBlcnMuCiAgICAgICAgcHVibGljIHN0YXRpYyB2b2lkIFJ1bkNtZCgKICAgICAgICAgICAgc3RyaW5nIHNjcmlwdFRleHQsCiAgICAgICAgICAgIGludCB0aW1lb3V0TXMsCiAgICAgICAgICAgIGludCBtYXhDaGFyc1BlclN0cmVhbSwKICAgICAgICAgICAgb3V0IHN0cmluZyBzdGRvdXQsCiAgICAgICAgICAgIG91dCBzdHJpbmcgc3RkZXJyLAogICAgICAgICAgICBvdXQgYm9vbCB0aW1lZE91dCwKICAgICAgICAgICAgb3V0IGJvb2wgdHJ1bmNhdGVkLAogICAgICAgICAgICBvdXQgaW50IGV4aXRDb2RlKQogICAgICAgIHsKICAgICAgICAgICAgUnVuUG93ZXJTaGVsbCgKICAgICAgICAgICAgICAgICJwb3dlcnNoZWxsLmV4ZSIsCiAgICAgICAgICAgICAgICBzY3JpcHRUZXh0LAogICAgICAgICAgICAgICAgRW52aXJvbm1lbnQuQ3VycmVudERpcmVjdG9yeSwKICAgICAgICAgICAgICAgIHRpbWVvdXRNcywKICAgICAgICAgICAgICAgIG1heENoYXJzUGVyU3RyZWFtLAogICAgICAgICAgICAgICAgb3V0IHN0ZG91dCwKICAgICAgICAgICAgICAgIG91dCBzdGRlcnIsCiAgICAgICAgICAgICAgICBvdXQgdGltZWRPdXQsCiAgICAgICAgICAgICAgICBvdXQgdHJ1bmNhdGVkLAogICAgICAgICAgICAgICAgb3V0IGV4aXRDb2RlKTsKICAgICAgICB9CiAgICB9Cn0K'    ))
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

function Resolve-WindoRunnerPowerShellPath {
    param([object]$RequestedPath = $null)

    $currentPath = $null
    try { $currentPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
    foreach ($candidate in @($RequestedPath, $currentPath, "powershell.exe")) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        $value = [string]$candidate
        $name = [System.IO.Path]::GetFileName($value)
        if ($name -notin @("powershell.exe", "pwsh.exe", "pwshw.exe")) { continue }
        if ($value -ieq "powershell.exe") { return $value }
        try {
            $full = [System.IO.Path]::GetFullPath($value)
            if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
        } catch { }
    }
    return "powershell.exe"
}

function Resolve-WindoRunnerWorkingDirectory {
    param(
        [object]$RequestedPath = $null,
        [Parameter(Mandatory = $true)][string]$SecureDirectory
    )

    $userProfile = $null
    try { $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) } catch { }
    foreach ($candidate in @($RequestedPath, $userProfile, $HOME, $SecureDirectory, [System.IO.Path]::GetTempPath())) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        try {
            $value = [string]$candidate
            if (-not [System.IO.Path]::IsPathRooted($value)) { continue }
            $full = [System.IO.Path]::GetFullPath($value)
            if (Test-Path -LiteralPath $full -PathType Container) { return $full }
        } catch { }
    }
    throw "No safe working directory is available for the elevated child process."
}

function Get-WindoTextSha256([string]$Value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
        return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("X2") }))
    } finally {
        $sha.Dispose()
    }
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

function Get-WindoProtectedDataType {
    $typeName = "System.Security.Cryptography.ProtectedData"
    foreach ($qualifiedName in @(
        "$typeName, System.Security.Cryptography.ProtectedData",
        "$typeName, System.Security"
    )) {
        try {
            $resolved = [type]::GetType($qualifiedName, $false)
            if ($null -ne $resolved) { return $resolved }
        } catch { }
    }
    return $null
}

function Get-WindoCurrentUserProtectionScope([type]$ProtectedDataType) {
    if ($null -eq $ProtectedDataType) { return $null }
    try {
        $scopeType = $ProtectedDataType.Assembly.GetType("System.Security.Cryptography.DataProtectionScope", $false, $false)
        if ($null -eq $scopeType) { return $null }
        return [Enum]::Parse($scopeType, "CurrentUser")
    } catch { return $null }
}

function _dpapi_unprotect([string]$Base64Input) {
    if ([string]::IsNullOrWhiteSpace($Base64Input) -or $Base64Input.Length -gt 100663296) { return $null }
    $protectedDataType = Get-WindoProtectedDataType
    $scope = Get-WindoCurrentUserProtectionScope $protectedDataType
    if ($null -eq $protectedDataType -or $null -eq $scope) { return $null }
    try {
        $enc = [Convert]::FromBase64String($Base64Input)
        $bytes = $protectedDataType::Unprotect($enc, $null, $scope)
        (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
    } catch {
        return $null
    }
}

function _windo_unprotect_text([string]$EncryptedText) {
    if ([string]::IsNullOrWhiteSpace($EncryptedText)) { return $null }
    if ($EncryptedText.Length -gt 100663296) { return $null }
    return _dpapi_unprotect $EncryptedText
}

function _dpapi_protect([string]$Text) {
    $protectedDataType = Get-WindoProtectedDataType
    $scope = Get-WindoCurrentUserProtectionScope $protectedDataType
    if ($null -eq $protectedDataType -or $null -eq $scope) { return $null }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        $enc = $protectedDataType::Protect($bytes, $null, $scope)
        return [Convert]::ToBase64String($enc)
    } catch {
        return $null
    }
}

function _windo_build_artifact_payload([object]$Payload) {
    if ($null -eq $Payload) { return $null }
    try {
        $json = $Payload | ConvertTo-Json -Depth 20 -Compress
        $protected = _dpapi_protect $json
        if ([string]::IsNullOrWhiteSpace($protected)) { return $null }
        return [ordered]@{ Version = 1; Type = "dpapi-json"; Data = $protected }
    } catch {
        return $null
    }
}

function _windo_resolve_preserve_environment([object]$Payload) {
    if ($null -eq $Payload) { return $null }
    return (_windo_resolve_artifact_payload $Payload)
}

function _windo_resolve_artifact_payload {
    param([object]$Payload)
    if ($null -eq $Payload) { return $null }

    if ($Payload -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Payload)) { return $null }
        if (([string]$Payload).Length -gt 100663296) { return $null }
        if ([string]$Payload -match '^[\r\n\s\t]*\{') {
            try { return (_windo_resolve_artifact_payload ($Payload | ConvertFrom-Json -ErrorAction Stop)) } catch { return $null }
        }
        return $null
    }

    $payloadVersion = $null
    $payloadType = $null
    $payloadData = $null
    if ($Payload -is [System.Collections.IDictionary]) {
        if ($Payload.Contains("Version")) { $payloadVersion = $Payload["Version"] }
        if ($Payload.Contains("Type")) { $payloadType = $Payload["Type"] }
        if ($Payload.Contains("Data")) { $payloadData = $Payload["Data"] }
    } else {
        if ($Payload.PSObject -and $Payload.PSObject.Properties.Name -contains "Version") { $payloadVersion = $Payload.Version }
        if ($Payload.PSObject -and $Payload.PSObject.Properties.Name -contains "Type") { $payloadType = $Payload.Type }
        if ($Payload.PSObject -and $Payload.PSObject.Properties.Name -contains "Data") { $payloadData = $Payload.Data }
    }
    $version = 0
    try { $version = [int]$payloadVersion } catch { return $null }
    if ($version -eq 1 -and ([string]$payloadType -ceq "dpapi-json") -and -not [string]::IsNullOrWhiteSpace([string]$payloadData) -and ([string]$payloadData).Length -le 100663296) {
        $json = _windo_unprotect_text ([string]$payloadData)
        if ($null -ne $json) {
            try { return $json | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
        }
        return $null
    }

    return $null
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
    $reqId   = _windo_get_member_value $pending "RequestId"

    $currentUserSid = Get-WindoRunnerCurrentIdentitySid
    if ([string]::IsNullOrWhiteSpace([string]$currentUserSid) -or [string]::IsNullOrWhiteSpace([string]$requestUserSid) -or [string]$requestUserSid -ine [string]$currentUserSid) {
        Write-RunnerTrace ("BAD REQUEST IDENTITY: $($req.FullName)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".bad") -ErrorAction SilentlyContinue } catch {}
        $req = $null
        continue
    }

    if ($null -eq $cmdLine -or $null -eq $outPath) {
        Write-RunnerTrace ("BAD REQUEST JSON: $($req.FullName) :: malformed request payload (missing Command or OutPath)")
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

    $badOut = Test-WindoResultPath $outPath $SecureDir
    if ($badOut) {
        Write-RunnerTrace ("VALIDATION FAILED (OutPath): $badOut")
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
    $exitCode = 0

    $envState = @{}
    try {
        $envState = Invoke-WindoPreserveEnvironment -Snapshot $preserveEnvironment
        try {
            Invoke-WindoRunnerChildExec -PowerShellPath $childPowerShellPath -CommandLine $executionCommand -WorkingDirectory $childWorkingDirectory -TimeoutMs $timeoutMs -MaxCharsPerStream $maxPer -StdOut ([ref]$stdout) -StdErr ([ref]$stderr) -TimedOut ([ref]$timedOut) -Truncated ([ref]$truncated) -ExitCode ([ref]$exitCode)
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
        $sealedResult = _windo_build_artifact_payload $result
        if ($null -eq $sealedResult) { throw "Unable to secure result." }
        $sealedResultJson = $sealedResult | ConvertTo-Json -Compress
        Write-TextFileAtomic -Path $outPath -Content $sealedResultJson -Encoding (New-Object System.Text.UTF8Encoding($false))
        Write-RunnerTrace "WROTE RESULT: ExitCode=$exitCode DurationMs=$durationMs TimedOut=$timedOut Truncated=$truncated"
    } catch {
        Write-RunnerTrace ("EXIT 4: failed to write result JSON: $($_.Exception.Message)")
        try { Rename-Item -Path $req.FullName -NewName ($req.Name + ".failed") -ErrorAction SilentlyContinue } catch {}
        $req = $null
        continue
    }

    try { Remove-Item -Path $req.FullName -Force -ErrorAction SilentlyContinue } catch {}

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




