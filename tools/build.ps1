# Maintainer-only: default = validate. Optional -Concat joins snippet files for review (does not replace the installer).
param(
    [switch]$Concat,
    [string]$ConcatOut = ""
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$validate = Join-Path $PSScriptRoot "Validate-Windo.ps1"
& $validate
if (-not $Concat) {
    Write-Host "build.ps1: validation only. Use -Concat to write a review-only snippet concat under out\." -ForegroundColor Cyan
    exit 0
}

$snipDir = Join-Path $repoRoot "src\windo\snippets"
if (-not (Test-Path $snipDir)) {
    Write-Warning "No snippets directory at $snipDir - nothing to concatenate."
    exit 0
}

$outDir = Join-Path $repoRoot "out"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

if ([string]::IsNullOrWhiteSpace($ConcatOut)) {
    $ConcatOut = Join-Path $outDir "windo_snippets_concat_review.ps1.txt"
}

$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine("# WINDO snippet concat - REVIEW ONLY - do not deploy as installer")
$null = $sb.AppendLine("# Generated: $(Get-Date -Format 'o')")
Get-ChildItem -Path $snipDir -Filter "*.ps1" -File | Sort-Object Name | ForEach-Object {
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("# --- $($_.Name) ---")
    $null = $sb.AppendLine((Get-Content -Raw -LiteralPath $_.FullName))
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ConcatOut, $sb.ToString(), $utf8)
Write-Warning "Wrote $ConcatOut - this does NOT replace windo_install.ps1. Merge changes manually if adopting fragments."
