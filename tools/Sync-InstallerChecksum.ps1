param(
    [string]$InstallerPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "windo_install.ps1"),
    [string]$UninstallerPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "windo_uninstall.ps1"),
    [string]$ChecksumPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256")
)

$ErrorActionPreference = "Stop"
$script:WindoRepoRoot = Split-Path $PSScriptRoot -Parent

function Get-WindoReleaseBranch {
    param([string]$Branch)

    $rawBranch = if ([string]::IsNullOrWhiteSpace($Branch)) {
        if ([string]::IsNullOrWhiteSpace($env:WINDO_TRACKING_BRANCH)) { "Prometheus" } else { [string]$env:WINDO_TRACKING_BRANCH }
    } else {
        [string]$Branch.Trim()
    }
    $resolved = $rawBranch.Trim()
    if ($resolved -notmatch '^[A-Za-z0-9._-]{1,64}$') {
        return "Prometheus"
    }
    $lower = $resolved.ToLowerInvariant()
    if ($lower -eq "genesis" -or $lower -eq "genisis") { return "Prometheus" }
    return $resolved
}

function Get-WindoGitBranch {
    try {
        $branch = (git -C $script:WindoRepoRoot rev-parse --abbrev-ref HEAD).Trim()
        if ($branch -and $branch -ne "HEAD") { return $branch }
    } catch {}
    return $null
}

function Get-WindoGitCommit {
    try {
        $commit = (git -C $script:WindoRepoRoot rev-parse HEAD).Trim()
        if ($commit -match '^[a-fA-F0-9]{40}$') { return $commit.ToLowerInvariant() }
    } catch {}
    return $null
}

function Resolve-WindoReleaseMetadata {
    param(
        [string]$Commit,
        [string]$Branch
    )

    $branchWasProvided = -not [string]::IsNullOrWhiteSpace($Branch)
    $rawBranch = if ($branchWasProvided) { [string]$Branch.Trim() } else { $null }
    $releaseBranch = Get-WindoReleaseBranch $rawBranch
    if (-not $branchWasProvided) {
        $gitBranch = Get-WindoGitBranch
        if ($gitBranch) {
            $rawBranch = $gitBranch
            $releaseBranch = Get-WindoReleaseBranch $gitBranch
        }
    }

    if ([string]::IsNullOrWhiteSpace($releaseBranch)) {
        $releaseBranch = "Prometheus"
    }

    $commitWasProvided = -not [string]::IsNullOrWhiteSpace($Commit)
    $rawCommit = if ($commitWasProvided) { [string]$Commit.Trim() } else { $null }
    $normalizedCommit = if ($rawCommit) {
        if ($rawCommit -match '^[a-fA-F0-9]{40}$') { $rawCommit.ToLowerInvariant() } else { $rawCommit.Trim() }
    } else { $null }

    if (-not $commitWasProvided -and $null -eq $normalizedCommit) {
        $gitCommit = Get-WindoGitCommit
        if ($gitCommit) {
            $normalizedCommit = $gitCommit
            $rawCommit = if ($rawCommit) { $rawCommit.Trim() } else { $gitCommit }
            if ([string]::IsNullOrWhiteSpace($rawCommit) -or $rawCommit -notmatch '^[a-fA-F0-9]{40}$') {
                $rawCommit = $gitCommit
            }
        }
    }

    return @{
        Branch = $releaseBranch
        BranchRaw = if ([string]::IsNullOrWhiteSpace($rawBranch)) { $releaseBranch } else { $rawBranch }
        Commit = if ([string]::IsNullOrWhiteSpace($normalizedCommit)) { "" } else { $normalizedCommit }
        CommitRaw = if ([string]::IsNullOrWhiteSpace($rawCommit)) { "" } else { $rawCommit.Trim() }
    }
}

function Get-WindoChecksumManifestLine([string]$Key, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "${Key}=" }
    return "${Key}=$Value"
}

function New-WindoSHA256 {
    return [System.Security.Cryptography.SHA256]::Create()
}

function Get-WindoPublishedTextFileSha256([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = New-WindoSHA256
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

$metadata = Resolve-WindoReleaseMetadata -Commit $env:WINDO_RELEASE_COMMIT -Branch $env:WINDO_TRACKING_BRANCH
$branch = $metadata.Branch
$releaseCommit = $metadata.Commit
$generatedAt = (Get-Date -Format "o")
$releaseCommitRaw = if (-not [string]::IsNullOrWhiteSpace($metadata.CommitRaw)) { [string]$metadata.CommitRaw } else { "" }
$releaseBranchRaw = if (-not [string]::IsNullOrWhiteSpace($metadata.BranchRaw)) { [string]$metadata.BranchRaw } else { "" }

$payload = @(
    (Get-WindoChecksumManifestLine "schemaVersion" "2")
    (Get-WindoChecksumManifestLine "generatedAt" $generatedAt)
    (Get-WindoChecksumManifestLine "releaseBranch" $branch)
    (Get-WindoChecksumManifestLine "releaseCommit" $releaseCommit)
    (Get-WindoChecksumManifestLine "releaseBranchRaw" $releaseBranchRaw)
    (Get-WindoChecksumManifestLine "releaseCommitRaw" $releaseCommitRaw)
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
