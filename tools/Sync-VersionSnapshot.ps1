# Copy frozen release artifacts into versions/v<X.Y.Z>/ (run from repo after bumping $WindoVersion and checksums).
# Usage: ./tools/Sync-VersionSnapshot.ps1 -Version 3.2.3
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$destRoot = Join-Path $root ("versions\v{0}" -f $Version)

$copyPairs = @(
    @{ Src = "windo_install.ps1"; Dst = "windo_install.ps1" }
    @{ Src = "checksums\installer.sha256"; Dst = "checksums\installer.sha256" }
    @{ Src = "README.md"; Dst = "README.md" }
    @{ Src = "SECURITY.md"; Dst = "SECURITY.md" }
    @{ Src = "CHANGELOG.md"; Dst = "CHANGELOG.md" }
    @{ Src = "docs\json-schema.md"; Dst = "docs\json-schema.md" }
    @{ Src = "docs\build.md"; Dst = "docs\build.md" }
    @{ Src = "docs\modules-and-extras.md"; Dst = "docs\modules-and-extras.md" }
    @{ Src = "docs\framework-wave.md"; Dst = "docs\framework-wave.md" }
    @{ Src = "extras\index.json"; Dst = "extras\index.json" }
    @{ Src = "extras\samples\hello\Load.ps1"; Dst = "extras\samples\hello\Load.ps1" }
)

foreach ($p in $copyPairs) {
    $from = Join-Path $root $p.Src
    if (!(Test-Path -LiteralPath $from)) {
        Write-Error "Missing source: $from"
    }
}

$dirs = @(
    $destRoot
    (Join-Path $destRoot "checksums")
    (Join-Path $destRoot "docs")
    (Join-Path $destRoot "extras\samples\hello")
)
foreach ($d in $dirs) {
    if (!(Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

foreach ($p in $copyPairs) {
    $from = Join-Path $root $p.Src
    $to = Join-Path $destRoot $p.Dst
    Copy-Item -LiteralPath $from -Destination $to -Force
}

Write-Host "Sync-VersionSnapshot: wrote $destRoot ($($copyPairs.Count) files)." -ForegroundColor Cyan
