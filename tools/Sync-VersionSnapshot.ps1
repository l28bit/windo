# Copy frozen release artifacts into versions/v<X.Y.Z>/ (run from repo after bumping $WindoVersion and checksums).
# Usage: ./tools/Sync-VersionSnapshot.ps1 -Version 3.2.3
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$destRoot = Join-Path $root ("versions\v{0}" -f $Version)

$installerSource = Join-Path $root "windo_install.ps1"
$versionMatch = [regex]::Match([System.IO.File]::ReadAllText($installerSource), '\$WindoVersion\s*=\s*"(?<v>\d+\.\d+\.\d+)"')
if (-not $versionMatch.Success) { throw "Could not resolve WindoVersion from $installerSource." }
$installerVersion = $versionMatch.Groups['v'].Value
if ($installerVersion -cne $Version) {
    throw "Snapshot version mismatch: requested=$Version installer=$installerVersion. Bump the installer or pass the matching version."
}

# Refuse to freeze unverified bytes. This validates every shipped script, all
# declared release hashes, the manifest signature, and the embedded trust root.
& (Join-Path $PSScriptRoot "Validate-Windo.ps1")
if (-not $?) { throw "Root release validation failed; snapshot was not created." }

if ((Test-Path -LiteralPath $destRoot) -and -not $Force) {
    throw "Snapshot already exists: $destRoot. Frozen releases are immutable; use -Force only while intentionally rebuilding an unpublished snapshot."
}

$copyPairs = @(
    @{ Src = "bootstrap.ps1"; Dst = "bootstrap.ps1" }
    @{ Src = "windo_install.ps1"; Dst = "windo_install.ps1" }
    @{ Src = "windo_runner.ps1"; Dst = "windo_runner.ps1" }
    @{ Src = "windo_self_update.ps1"; Dst = "windo_self_update.ps1" }
    @{ Src = "windo_uninstall.ps1"; Dst = "windo_uninstall.ps1" }
    @{ Src = "windo_heal.ps1"; Dst = "windo_heal.ps1" }
    @{ Src = "checksums\installer.sha256"; Dst = "checksums\installer.sha256" }
    @{ Src = "checksums\installer.sha256.sig"; Dst = "checksums\installer.sha256.sig" }
    @{ Src = "keys\windo-release-public.rsa.xml"; Dst = "keys\windo-release-public.rsa.xml" }
    @{ Src = "README.md"; Dst = "README.md" }
    @{ Src = "SECURITY.md"; Dst = "SECURITY.md" }
    @{ Src = "CHANGELOG.md"; Dst = "CHANGELOG.md" }
    @{ Src = "docs\json-schema.md"; Dst = "docs\json-schema.md" }
    @{ Src = "docs\build.md"; Dst = "docs\build.md" }
    @{ Src = "docs\modules-and-extras.md"; Dst = "docs\modules-and-extras.md" }
    @{ Src = "docs\framework-wave.md"; Dst = "docs\framework-wave.md" }
    @{ Src = "docs\ai-bridge.md"; Dst = "docs\ai-bridge.md" }
    @{ Src = "docs\v5-roadmap.md"; Dst = "docs\v5-roadmap.md" }
    @{ Src = "extras\index.json"; Dst = "extras\index.json" }
    @{ Src = "extras\samples\hello\Load.ps1"; Dst = "extras\samples\hello\Load.ps1" }
)

$releaseNotes = "docs\releases\RELEASE_NOTES_v$Version.md"
if (Test-Path -LiteralPath (Join-Path $root $releaseNotes)) {
    $copyPairs += @{ Src = $releaseNotes; Dst = $releaseNotes }
}

foreach ($p in $copyPairs) {
    $from = Join-Path $root $p.Src
    if (!(Test-Path -LiteralPath $from)) {
        Write-Error "Missing source: $from"
    }
}

$dirs = @(
    $destRoot
    (Join-Path $destRoot "checksums")
    (Join-Path $destRoot "keys")
    (Join-Path $destRoot "docs")
    (Join-Path $destRoot "docs\releases")
    (Join-Path $destRoot "brand")
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

$brandEnterpriseSource = Join-Path $root "brand\Enterprise"
if (Test-Path -LiteralPath $brandEnterpriseSource) {
    $obsoleteBrandFinalDest = Join-Path $destRoot "brand\final"
    if (Test-Path -LiteralPath $obsoleteBrandFinalDest) {
        Remove-Item -LiteralPath $obsoleteBrandFinalDest -Recurse -Force
    }
    $brandEnterpriseDest = Join-Path $destRoot "brand\Enterprise"
    if (Test-Path -LiteralPath $brandEnterpriseDest) {
        Remove-Item -LiteralPath $brandEnterpriseDest -Recurse -Force
    }
    Copy-Item -LiteralPath $brandEnterpriseSource -Destination $brandEnterpriseDest -Recurse -Force
}

$brandAssetsSource = Join-Path $root "brand\assets"
if (Test-Path -LiteralPath $brandAssetsSource) {
    $brandAssetsDest = Join-Path $destRoot "brand\assets"
    if (Test-Path -LiteralPath $brandAssetsDest) {
        Remove-Item -LiteralPath $brandAssetsDest -Recurse -Force
    }
    Copy-Item -LiteralPath $brandAssetsSource -Destination $brandAssetsDest -Recurse -Force
}

$nativeCompanionSource = Join-Path $root "native-companion"
if (Test-Path -LiteralPath $nativeCompanionSource) {
    $nativeCompanionDest = Join-Path $destRoot "native-companion"
    if (Test-Path -LiteralPath $nativeCompanionDest) {
        Remove-Item -LiteralPath $nativeCompanionDest -Recurse -Force
    }
    Copy-Item -LiteralPath $nativeCompanionSource -Destination $nativeCompanionDest -Recurse -Force
}

Write-Host "Sync-VersionSnapshot: wrote $destRoot ($($copyPairs.Count) files)." -ForegroundColor Cyan

# Re-run the release gate against the frozen copy. Any partial copy, signature
# drift, or line-ending mismatch fails the snapshot command immediately.
& (Join-Path $PSScriptRoot "Validate-Windo.ps1") -RequireCurrentSnapshot
if (-not $?) { throw "Frozen snapshot validation failed: $destRoot" }
