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
        if ([string]::IsNullOrWhiteSpace($env:WINDO_TRACKING_BRANCH)) { "Exodus" } else { [string]$env:WINDO_TRACKING_BRANCH }
    } else {
        [string]$Branch.Trim()
    }
    $resolved = $rawBranch.Trim()
    if ($resolved -notmatch '^[A-Za-z0-9._-]{1,64}$') {
        return "Exodus"
    }
    $lower = $resolved.ToLowerInvariant()
    if ($lower -in @('genesis', 'genisis', 'prometheus')) { return "Exodus" }
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

    if ([string]::IsNullOrWhiteSpace($releaseBranch)) {
        $releaseBranch = "Exodus"
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

function New-WindoHashAlgorithm {
    param([Parameter(Mandatory=$true)][ValidateSet("SHA256","SHA384","SHA512")][string]$Algorithm)
    switch ($Algorithm) {
        "SHA256" { return [System.Security.Cryptography.SHA256]::Create() }
        "SHA384" { return [System.Security.Cryptography.SHA384]::Create() }
        "SHA512" { return [System.Security.Cryptography.SHA512]::Create() }
    }
}

function Get-WindoPublishedTextFileHash([string]$Path, [string]$Algorithm = "SHA256") {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $text = $strictUtf8.GetString($bytes)
    $publishedBytes = $utf8NoBom.GetBytes($text.Replace("`r`n", "`n"))
    $sha = New-WindoHashAlgorithm -Algorithm $Algorithm
    try {
        # .gitattributes publishes release scripts with LF. Hash that exact Git
        # text domain even in an existing Windows worktree that still has CRLF.
        $hashBytes = $sha.ComputeHash($publishedBytes)
        -join ($hashBytes | ForEach-Object { $_.ToString("X2") })
    } finally {
        $sha.Dispose()
    }
}

$installerHash = Get-WindoPublishedTextFileHash -Path $InstallerPath -Algorithm SHA256
if ($null -eq $installerHash) { throw "Missing installer path: $InstallerPath" }
$installerHash384 = Get-WindoPublishedTextFileHash -Path $InstallerPath -Algorithm SHA384
$installerHash512 = Get-WindoPublishedTextFileHash -Path $InstallerPath -Algorithm SHA512
$uninstallerHash = Get-WindoPublishedTextFileHash -Path $UninstallerPath -Algorithm SHA256
$uninstallerHash384 = Get-WindoPublishedTextFileHash -Path $UninstallerPath -Algorithm SHA384
$uninstallerHash512 = Get-WindoPublishedTextFileHash -Path $UninstallerPath -Algorithm SHA512

$metadata = Resolve-WindoReleaseMetadata -Commit $env:WINDO_RELEASE_COMMIT -Branch $env:WINDO_TRACKING_BRANCH
$branch = $metadata.Branch

$payload = @(
    (Get-WindoChecksumManifestLine "schemaVersion" "2")
    (Get-WindoChecksumManifestLine "releaseBranch" $branch)
    (Get-WindoChecksumManifestLine "installerSha256" $installerHash)
    (Get-WindoChecksumManifestLine "installerSha384" $installerHash384)
    (Get-WindoChecksumManifestLine "installerSha512" $installerHash512)
    (Get-WindoChecksumManifestLine "uninstallerSha256" ($uninstallerHash -as [string]))
    (Get-WindoChecksumManifestLine "uninstallerSha384" ($uninstallerHash384 -as [string]))
    (Get-WindoChecksumManifestLine "uninstallerSha512" ($uninstallerHash512 -as [string]))
)

[System.IO.File]::WriteAllText($ChecksumPath, ($payload -join "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated checksums/installer.sha256 with manifest:"
Write-Host "  schemaVersion=2" -ForegroundColor Cyan
Write-Host "  releaseBranch=$branch" -ForegroundColor Cyan
Write-Host "  installerSha256=$installerHash" -ForegroundColor Cyan
if ($uninstallerHash) {
    Write-Host "  uninstallerSha256=$uninstallerHash" -ForegroundColor Cyan
}
