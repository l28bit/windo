# Run PSScriptAnalyzer on shipping scripts (excludes versions/). Requires: Install-Module PSScriptAnalyzer
$ErrorActionPreference = "Stop"
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Write-Error "PSScriptAnalyzer required: Install-Module PSScriptAnalyzer -Scope CurrentUser"
    exit 1
}
$root = Split-Path $PSScriptRoot -Parent
$files = @(
    @(Get-ChildItem -LiteralPath $root -File -Filter "*.ps1")
    @(Get-ChildItem -LiteralPath (Join-Path $root "tools") -File -Filter "*.ps1")
    @(Get-ChildItem -LiteralPath (Join-Path $root "src") -File -Recurse -Filter "*.ps1")
    @(Get-ChildItem -LiteralPath (Join-Path $root "extras") -File -Recurse -Filter "*.ps1")
) | Select-Object -ExpandProperty FullName -Unique | Sort-Object
# Severity Error only: WINDO scripts intentionally use Write-Host, empty catch in hot paths, and UTF-8 no BOM.
$allIssues = @()
foreach ($f in $files) {
    $allIssues += Invoke-ScriptAnalyzer -Path $f -Severity @("Error")
}
if ($allIssues.Count -gt 0) {
    $allIssues | Format-Table -AutoSize
    exit 1
}
Write-Host "PSScriptAnalyzer: no Error-level issues on analyzed files." -ForegroundColor Cyan
