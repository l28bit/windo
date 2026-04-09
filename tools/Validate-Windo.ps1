# Validate WINDO repo scripts (syntax). Run from repo root: ./tools/Validate-Windo.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$files = @(
    "bootstrap.ps1",
    "windo_install.ps1",
    "windo_uninstall.ps1",
    "windo_runner.ps1",
    "windo_self_update.ps1",
    "src\windo\snippets\StatsTimeFilter.ps1"
)
$ok = $true
foreach ($f in $files) {
    $p = Join-Path $root $f
    if (!(Test-Path $p)) { Write-Warning "Missing: $f"; $ok = $false; continue }
    $err = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$err)
    if ($err) {
        Write-Host "FAIL $f" -ForegroundColor Red
        $err | ForEach-Object { Write-Host $_.ToString() }
        $ok = $false
    } else {
        Write-Host "OK   $f" -ForegroundColor Green
    }
}
if (-not $ok) { exit 1 }
Write-Host "Validate-Windo: all checks passed." -ForegroundColor Cyan
