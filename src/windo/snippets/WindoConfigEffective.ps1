# Mirrors windo_runner.ps1 and windo_install.ps1 embedded helpers (tests + maintainer reference).
function Get-WindoEffectiveRunnerTimeoutMs {
    param([string]$EnvRaw = $env:WINDO_RUNNER_TIMEOUT_MS)
    $d = 7200000
    if ([string]::IsNullOrWhiteSpace($EnvRaw)) { return $d }
    try {
        $v = [long]$EnvRaw
        if ($v -lt 1) { return $d }
        if ($v -gt 86400000) { return 86400000 }
        return [int]$v
    } catch { return $d }
}

function Get-WindoEffectiveRunnerMaxCharsPerStream {
    param([string]$EnvRaw = $env:WINDO_RUNNER_MAX_OUTPUT_BYTES)
    $d = 2097152
    if ([string]::IsNullOrWhiteSpace($EnvRaw)) { return $d }
    try {
        $v = [long]$EnvRaw
        if ($v -lt 4096) { return [int][Math]::Max(512, $v / 2) }
        if ($v -gt 67108864) { return 33554432 }
        return [int]($v / 2)
    } catch { return $d }
}

function Get-WindoEffectiveMaxCommandChars {
    param([string]$EnvRaw = $env:WINDO_MAX_COMMAND_CHARS)
    $d = 8191
    if ([string]::IsNullOrWhiteSpace($EnvRaw)) { return $d }
    try {
        $v = [int]$EnvRaw
        if ($v -lt 1) { return $d }
        if ($v -gt 8191) { return 8191 }
        return $v
    } catch { return $d }
}
