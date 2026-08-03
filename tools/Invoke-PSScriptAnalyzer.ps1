# Run PSScriptAnalyzer on shipping scripts (excludes versions/). Requires: Install-Module PSScriptAnalyzer
$ErrorActionPreference = "Stop"
try {
    Import-Module -FullyQualifiedName @{
        ModuleName = "PSScriptAnalyzer"
        RequiredVersion = "1.25.0"
    } -Force -ErrorAction Stop
} catch {
    Write-Error "PSScriptAnalyzer 1.25.0 required: Install-Module PSScriptAnalyzer -Scope CurrentUser -RequiredVersion 1.25.0. $($_.Exception.Message)"
    exit 1
}
$root = Split-Path $PSScriptRoot -Parent
$files = @(
    Get-ChildItem -LiteralPath $root -Filter "*.ps1" -File | Where-Object { -not $_.Name.StartsWith(".tmp", [StringComparison]::OrdinalIgnoreCase) }
    Get-ChildItem -LiteralPath (Join-Path $root "tools") -Filter "*.ps1" -File
    Get-ChildItem -LiteralPath (Join-Path $root "src\windo\snippets") -Filter "*.ps1" -File -Recurse
    Get-ChildItem -LiteralPath (Join-Path $root "extras") -Filter "*.ps1" -File -Recurse
) | Sort-Object FullName -Unique
# Severity Error only: WINDO scripts intentionally use Write-Host, empty catch in hot paths, and UTF-8 no BOM.
$allIssues = @()
foreach ($file in $files) {
    $allIssues += Invoke-ScriptAnalyzer -Path $file.FullName -Severity @("Error")
}
if ($allIssues.Count -gt 0) {
    $allIssues | Format-Table -AutoSize
    exit 1
}
Write-Host "PSScriptAnalyzer: no Error-level issues on analyzed files." -ForegroundColor Cyan
