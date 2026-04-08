# Run PSScriptAnalyzer on shipping scripts (excludes versions/). Requires: Install-Module PSScriptAnalyzer
$ErrorActionPreference = "Stop"
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Write-Error "PSScriptAnalyzer required: Install-Module PSScriptAnalyzer -Scope CurrentUser"
    exit 1
}
$root = Split-Path $PSScriptRoot -Parent
$files = @(
    (Join-Path $root "bootstrap.ps1"),
    (Join-Path $root "windo_install.ps1"),
    (Join-Path $root "windo_uninstall.ps1"),
    (Join-Path $root "windo_runner.ps1"),
    (Join-Path $root "windo_self_update.ps1"),
    (Join-Path $root "tools\Validate-Windo.ps1"),
    (Join-Path $root "tools\build.ps1"),
    (Join-Path $root "tools\Test-WindoLogic.ps1"),
    (Join-Path $root "tools\Invoke-PSScriptAnalyzer.ps1")
)
# Severity Error only: WINDO scripts intentionally use Write-Host, empty catch in hot paths, and UTF-8 no BOM.
$allIssues = @()
foreach ($f in $files) {
    if (!(Test-Path -LiteralPath $f)) { continue }
    $allIssues += Invoke-ScriptAnalyzer -Path $f -Severity @("Error")
}
if ($allIssues.Count -gt 0) {
    $allIssues | Format-Table -AutoSize
    exit 1
}
Write-Host "PSScriptAnalyzer: no Error-level issues on analyzed files." -ForegroundColor Cyan
