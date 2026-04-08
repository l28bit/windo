# Logic tests for shared snippets (no live WINDO profile). Run: ./tools/Test-WindoLogic.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "src\windo\snippets\IntegrityLevels.ps1")

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

if ($failed -gt 0) {
    Write-Host "Test-WindoLogic: $failed failure(s)." -ForegroundColor Red
    exit 1
}
Write-Host "Test-WindoLogic: OK." -ForegroundColor Cyan
