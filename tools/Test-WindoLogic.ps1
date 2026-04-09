# Logic tests for shared snippets (no live WINDO profile). Run: ./tools/Test-WindoLogic.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "src\windo\snippets\IntegrityLevels.ps1")
. (Join-Path $root "src\windo\snippets\StatsTimeFilter.ps1")
. (Join-Path $root "src\windo\snippets\WindoConfigEffective.ps1")

$failed = 0
function Assert-Equal($a, $b, $msg) {
    if ($a -ne $b) {
        Write-Host "FAIL: $msg  (expected '$b', got '$a')" -ForegroundColor Red
        $script:failed++
    }
}

Assert-Equal (Get-WindoIntegrityComponentLevel "a" "a") "OK" "exact match"
Assert-Equal (Get-WindoIntegrityComponentLevel "(missing)" "abc") "UNKNOWN" "missing file"
Assert-Equal (Get-WindoIntegrityComponentLevel "(hash-error)" "abc") "UNKNOWN" "hash error"
Assert-Equal (Get-WindoIntegrityComponentLevel "x" "(manifest-missing)") "UNKNOWN" "manifest token"
$hexA = "0" * 64
$hexB = "f" * 64
Assert-Equal (Get-WindoIntegrityComponentLevel $hexA $hexB) "TAMPERED" "two hex mismatch"
Assert-Equal (Get-WindoIntegrityComponentLevel "nothex" "alsonot") "DRIFT" "non-hex drift"

$cutSince = Get-WindoStatsTimeCutoff -SinceDate ([datetime]"2024-06-15T14:00:00Z") -LastDays $null
Assert-Equal $cutSince ([datetime]"2024-06-15").Date "since uses date only"
$cutDays = Get-WindoStatsTimeCutoff -SinceDate $null -LastDays 3
Assert-Equal ($null -eq (Get-WindoStatsTimeCutoff -SinceDate $null -LastDays $null)) $true "no cutoff when no filter"
$e1 = [pscustomobject]@{ Timestamp = "2024-01-01T12:00:00Z"; ExitCode = 0 }
$e2 = [pscustomobject]@{ Timestamp = "2024-06-01T08:00:00Z"; ExitCode = 1 }
$co = [datetime]"2024-05-01"
$filt = Invoke-WindoFilterAuditEntriesByTime -Entries @($e1, $e2) -CutoffDate $co
Assert-Equal $filt.Count 1 "filter keeps entries on/after cutoff"
Assert-Equal ([string]$filt[0].Timestamp) "2024-06-01T08:00:00Z" "filtered row is june"
$all = Invoke-WindoFilterAuditEntriesByTime -Entries @($e1) -CutoffDate $null
Assert-Equal $all.Count 1 "null cutoff passes through"

Assert-Equal (Get-WindoEffectiveRunnerTimeoutMs "") 7200000 "timeout default"
Assert-Equal (Get-WindoEffectiveRunnerTimeoutMs "86400001") 86400000 "timeout cap"
Assert-Equal (Get-WindoEffectiveMaxCommandChars "100") 100 "max cmd respects small"
Assert-Equal (Get-WindoEffectiveMaxCommandChars "999999") 8191 "max cmd cap 8191"

$installerSource = Get-Content -Path (Join-Path $root "windo_install.ps1") -Raw
$runnerSource = Get-Content -Path (Join-Path $root "windo_runner.ps1") -Raw

Assert-Equal (($installerSource -match "function _windo_parse_timeout_override_ms") -eq $true) $true "installer parses timeout override"
Assert-Equal (($installerSource -match "PreserveEnvironment") -eq $true) $true "installer captures preserve-env payload"
Assert-Equal (($installerSource -match "TimeoutOverrideMs") -eq $true) $true "installer stores timeout override in request"
Assert-Equal (($runnerSource -match "function Get-WindoRunnerTimeoutMs") -eq $true) $true "runner exposes timeout resolution helper"
Assert-Equal (($runnerSource -match "PreserveEnvironment") -eq $true) $true "runner reads preserve-environment payload"
Assert-Equal (($runnerSource -match "Invoke-WindoPreserveEnvironment") -eq $true) $true "runner applies preserved environment"
Assert-Equal (($runnerSource -match "Restore-WindoPreserveEnvironment") -eq $true) $true "runner restores preserved environment"

if ($failed -gt 0) {
    Write-Host "Test-WindoLogic: $failed failure(s)." -ForegroundColor Red
    exit 1
}
Write-Host "Test-WindoLogic: OK." -ForegroundColor Cyan
