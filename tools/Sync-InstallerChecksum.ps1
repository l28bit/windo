param(
    [string]$InstallerPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "windo_install.ps1"),
    [string]$UninstallerPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "windo_uninstall.ps1"),
    [string]$ChecksumPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256")
)

$ErrorActionPreference = "Stop"

function Get-WindoReleaseBranch {
    param([string]$Branch)

    $resolved = if ([string]::IsNullOrWhiteSpace($Branch)) { "v6" } else { [string]$Branch.Trim() }
    if ($resolved -notmatch '^[A-Za-z0-9._-]{1,64}$') {
        return "v6"
    }
    return $resolved
}

function Get-WindoChecksumManifestLine([string]$Key, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "${Key}=" }
    return "${Key}=$Value"
}

function Get-WindoPublishedTextFileSha256([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $normalized = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13 -and ($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) {
            continue
        }
        $null = $normalized.Add($bytes[$i])
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($normalized.ToArray())
        -join ($hashBytes | ForEach-Object { $_.ToString("X2") })
    } finally {
        $sha.Dispose()
    }
}

$installerHash = Get-WindoPublishedTextFileSha256 -Path $InstallerPath
if ($null -eq $installerHash) { throw "Missing installer path: $InstallerPath" }
$uninstallerHash = Get-WindoPublishedTextFileSha256 -Path $UninstallerPath

$branch = Get-WindoReleaseBranch $env:WINDO_TRACKING_BRANCH
$releaseCommit = if ([string]::IsNullOrWhiteSpace($env:WINDO_RELEASE_COMMIT)) { "unknown" } else { $env:WINDO_RELEASE_COMMIT }
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
