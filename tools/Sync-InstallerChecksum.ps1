param(
    [string]$InstallerPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "windo_install.ps1"),
    [string]$UninstallerPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "windo_uninstall.ps1"),
    [string]$ChecksumPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256")
)

$ErrorActionPreference = "Stop"

function Get-WindoReleaseBranch {
    param([string]$Branch)

    $resolved = if ([string]::IsNullOrWhiteSpace($Branch)) { "Exodus" } else { [string]$Branch.Trim() }
    if ($resolved -notmatch '^[A-Za-z0-9._-]{1,64}$') {
        return "Exodus"
    }
    $lower = $resolved.ToLowerInvariant()
    if ($lower -eq "genesis" -or $lower -eq "genisis") { return "Exodus" }
    return $resolved
}

function Get-WindoChecksumManifestLine([string]$Key, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "${Key}=" }
    return "${Key}=$Value"
}

function Get-WindoPublishedTextFileSha256([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        # Runtime verification uses Get-FileHash on raw bytes, so publish the same raw SHA256 domain.
        $hashBytes = $sha.ComputeHash($bytes)
        -join ($hashBytes | ForEach-Object { $_.ToString("X2") })
    } finally {
        $sha.Dispose()
    }
}

$installerHash = Get-WindoPublishedTextFileSha256 -Path $InstallerPath
if ($null -eq $installerHash) { throw "Missing installer path: $InstallerPath" }
$uninstallerHash = Get-WindoPublishedTextFileSha256 -Path $UninstallerPath

$branch = Get-WindoReleaseBranch $env:WINDO_TRACKING_BRANCH
$releaseCommit = if (-not [string]::IsNullOrWhiteSpace($env:WINDO_RELEASE_COMMIT)) {
    [string]$env:WINDO_RELEASE_COMMIT
} else {
    try {
        (git rev-parse HEAD).Trim()
    } catch {
        "unknown"
    }
}
$generatedAt = (Get-Date -Format "o")

$payload = @(
    (Get-WindoChecksumManifestLine "schemaVersion" "2")
    (Get-WindoChecksumManifestLine "generatedAt" $generatedAt)
    (Get-WindoChecksumManifestLine "releaseBranch" $branch)
    (Get-WindoChecksumManifestLine "releaseCommit" $releaseCommit)
    (Get-WindoChecksumManifestLine "installerSha256" $installerHash)
    (Get-WindoChecksumManifestLine "uninstallerSha256" ($uninstallerHash -as [string]))
)

[System.IO.File]::WriteAllText($ChecksumPath, ($payload -join "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated checksums/installer.sha256 with manifest:"
Write-Host "  schemaVersion=2" -ForegroundColor Cyan
Write-Host "  releaseBranch=$branch" -ForegroundColor Cyan
Write-Host "  installerSha256=$installerHash" -ForegroundColor Cyan
if ($uninstallerHash) {
    Write-Host "  uninstallerSha256=$uninstallerHash" -ForegroundColor Cyan
}
