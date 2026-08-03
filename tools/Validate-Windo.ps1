# Validate WINDO repo scripts (syntax). Run from repo root: ./tools/Validate-Windo.ps1
[CmdletBinding()]
param([switch]$RequireCurrentSnapshot)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

function New-WindoHashAlgorithm {
    param([Parameter(Mandatory = $true)][ValidateSet("SHA256", "SHA384", "SHA512")][string]$Algorithm)
    switch ($Algorithm) {
        "SHA256" { return [System.Security.Cryptography.SHA256]::Create() }
        "SHA384" { return [System.Security.Cryptography.SHA384]::Create() }
        "SHA512" { return [System.Security.Cryptography.SHA512]::Create() }
    }
}

function Get-WindoPublishedTextFileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet("SHA256", "SHA384", "SHA512")][string]$Algorithm
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $text = $strictUtf8.GetString($bytes)
    $publishedBytes = $utf8NoBom.GetBytes($text.Replace("`r`n", "`n"))
    $sha = New-WindoHashAlgorithm -Algorithm $Algorithm
    try {
        # Validate the LF bytes GitHub publishes, independent of local checkout
        # autocrlf settings. Runtime checks still hash downloaded bytes exactly.
        $hashBytes = $sha.ComputeHash($publishedBytes)
        -join ($hashBytes | ForEach-Object { $_.ToString("X2") })
    } finally {
        $sha.Dispose()
    }
}

function Get-WindoPublishedTextFileSha256([string]$Path) {
    return Get-WindoPublishedTextFileHash -Path $Path -Algorithm SHA256
}

function Get-WindoChecksumManifest([string]$Content) {
    $manifest = @{}
    if ($null -eq $Content) { return $manifest }

    $raw = [string]$Content
    if ($raw.Trim() -match '^[A-Fa-f0-9]{64}$') {
        return @{ installerSha256 = $raw.Trim().ToUpperInvariant() }
    }

    foreach ($line in ($raw -split "`r?`n")) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) { continue }
        if ($trim -match '^(?<key>[^=]+?)=(?<value>.*)$') {
            $manifest[$matches.key] = $matches.value.Trim()
        }
    }
    return $manifest
}

function Test-WindoHex64([string]$Value) {
    return ($Value -match '^[A-Fa-f0-9]{64}$')
}

function Test-WindoHexDigest {
    param([AllowNull()][string]$Value, [Parameter(Mandatory = $true)][int]$Length)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ([string]$Value -match ("^[A-Fa-f0-9]{$Length}$"))
}

function Get-WindoReleaseTargetMeta {
    $envBranch = [string]$env:WINDO_TRACKING_BRANCH
    $rawBranch = if ([string]::IsNullOrWhiteSpace($envBranch)) { "Exodus" } else { $envBranch.Trim() }

    if ($rawBranch -match '^(?i:genesis|genisis|prometheus)$') { $rawBranch = "Exodus" }
    if ($rawBranch -notmatch '^[A-Za-z0-9._-]{1,64}$') { $rawBranch = "Exodus" }

    $rawCommit = $null
    try {
        $rawCommit = (git -C $root rev-parse HEAD).Trim()
    } catch {}

    $normalizedCommit = if ($rawCommit -match '^[a-fA-F0-9]{40}$') { $rawCommit.ToLowerInvariant() } else { $null }

    return [pscustomobject]@{
        Branch = $rawBranch
        Commit = $normalizedCommit
    }
}

function Test-WindoChecksumManifestMetadata {
    param(
        [hashtable]$Manifest,
        [string]$Label,
        [string]$ExpectedBranch,
        [string]$ExpectedCommit
    )

    $valid = $true
    $releaseBranch = if ($Manifest.ContainsKey("releaseBranch")) { [string]$Manifest.releaseBranch } else { $null }
    $releaseCommit = if ($Manifest.ContainsKey("releaseCommit")) { [string]$Manifest.releaseCommit } else { $null }
    $releaseBranchRaw = if ($Manifest.ContainsKey("releaseBranchRaw")) { [string]$Manifest.releaseBranchRaw } else { $null }
    $releaseCommitRaw = if ($Manifest.ContainsKey("releaseCommitRaw")) { [string]$Manifest.releaseCommitRaw } else { $null }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedBranch)) {
        if (-not [string]::IsNullOrWhiteSpace($releaseBranch) -and $releaseBranch -ne $ExpectedBranch) {
            Write-Host "FAIL $Label" -ForegroundColor Red
            Write-Host "Manifest releaseBranch does not match local target branch. expected=$ExpectedBranch manifest=$releaseBranch"
            $valid = $false
        } elseif ([string]::IsNullOrWhiteSpace($releaseBranch)) {
            Write-Host "FAIL $Label" -ForegroundColor Red
            Write-Host "Manifest releaseBranch is missing."
            $valid = $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and -not [string]::IsNullOrWhiteSpace($releaseCommit)) {
        $normalizedReleaseCommit = $releaseCommit.ToLowerInvariant()
        if ($normalizedReleaseCommit -ne $ExpectedCommit) {
            Write-Host "FAIL $Label" -ForegroundColor Red
            Write-Host "Manifest releaseCommit does not match local HEAD hash. expected=$ExpectedCommit manifest=$releaseCommit"
            $valid = $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($releaseBranchRaw) -and -not [string]::IsNullOrWhiteSpace($releaseBranch) -and $releaseBranchRaw -ne $releaseBranch) {
        Write-Host "FAIL $Label" -ForegroundColor Red
        Write-Host "Manifest releaseBranchRaw does not match releaseBranch value. branch=$releaseBranch raw=$releaseBranchRaw"
        $valid = $false
    }

    if (-not [string]::IsNullOrWhiteSpace($releaseCommitRaw) -and $releaseCommitRaw -match '^[a-fA-F0-9]{40,64}$') {
        if (-not [string]::IsNullOrWhiteSpace($releaseCommit) -and ($releaseCommitRaw.ToLowerInvariant() -ne $releaseCommit.ToLowerInvariant())) {
            Write-Host "FAIL $Label" -ForegroundColor Red
            Write-Host "Manifest releaseCommitRaw does not match releaseCommit value. commit=$releaseCommit raw=$releaseCommitRaw"
            $valid = $false
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($releaseCommitRaw)) {
        Write-Host "FAIL $Label" -ForegroundColor Red
        Write-Host "Manifest releaseCommitRaw is not a 40-character commit hash."
        $valid = $false
    }
    return $valid
}

function Test-WindoManifestArtifactHashes {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Manifest,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][string]$UninstallerPath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $valid = $true
    if (-not $Manifest.ContainsKey("schemaVersion") -or [string]$Manifest.schemaVersion -cne "2") {
        Write-Host "FAIL $Label" -ForegroundColor Red
        Write-Host "Checksum manifest schemaVersion must be 2."
        $valid = $false
    }
    foreach ($requiredPath in @($InstallerPath, $UninstallerPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            Write-Host "FAIL $Label" -ForegroundColor Red
            Write-Host "Required release artifact is missing: $requiredPath"
            $valid = $false
        }
    }
    if (-not $valid) { return $false }

    $specs = @(
        @{ Key = "installerSha256"; Path = $InstallerPath; Algorithm = "SHA256"; Length = 64 }
        @{ Key = "installerSha384"; Path = $InstallerPath; Algorithm = "SHA384"; Length = 96 }
        @{ Key = "installerSha512"; Path = $InstallerPath; Algorithm = "SHA512"; Length = 128 }
        @{ Key = "uninstallerSha256"; Path = $UninstallerPath; Algorithm = "SHA256"; Length = 64 }
        @{ Key = "uninstallerSha384"; Path = $UninstallerPath; Algorithm = "SHA384"; Length = 96 }
        @{ Key = "uninstallerSha512"; Path = $UninstallerPath; Algorithm = "SHA512"; Length = 128 }
    )
    foreach ($spec in $specs) {
        $key = [string]$spec.Key
        $expected = if ($Manifest.ContainsKey($key)) { [string]$Manifest[$key] } else { $null }
        if (-not (Test-WindoHexDigest -Value $expected -Length ([int]$spec.Length))) {
            Write-Host "FAIL $Label" -ForegroundColor Red
            Write-Host "$key is missing or is not a valid $($spec.Algorithm) digest."
            $valid = $false
            continue
        }
        $actual = Get-WindoPublishedTextFileHash -Path ([string]$spec.Path) -Algorithm ([string]$spec.Algorithm)
        if ($actual -cne $expected) {
            Write-Host "FAIL $Label" -ForegroundColor Red
            Write-Host "$key does not match $([System.IO.Path]::GetFileName([string]$spec.Path))."
            Write-Host "Expected: $expected"
            Write-Host "Found   : $actual"
            $valid = $false
        } else {
            Write-Host "OK   $Label ($key)" -ForegroundColor Green
        }
    }
    return $valid
}

function Test-WindoEmbeddedReleasePublicKey {
    param(
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][string]$PublicKeyPath
    )
    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf) -or -not (Test-Path -LiteralPath $PublicKeyPath -PathType Leaf)) {
        Write-Host "FAIL embedded release public key" -ForegroundColor Red
        Write-Host "Installer or committed public key is missing."
        return $false
    }
    $installerText = [System.IO.File]::ReadAllText($InstallerPath)
    $match = [regex]::Match($installerText, '(?m)^\$WindoReleasePublicKeyB64\s*=\s*"(?<b64>[A-Za-z0-9+/=]+)"\s*$')
    if (-not $match.Success) {
        Write-Host "FAIL embedded release public key" -ForegroundColor Red
        Write-Host "Installer does not contain the generated WindoReleasePublicKeyB64 trust root."
        return $false
    }
    try {
        $embedded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match.Groups['b64'].Value)).Trim()
        $committed = [System.IO.File]::ReadAllText($PublicKeyPath).Trim()
        if ($embedded -cne $committed) {
            Write-Host "FAIL embedded release public key" -ForegroundColor Red
            Write-Host "Installer trust root differs from keys/windo-release-public.rsa.xml."
            return $false
        }
    } catch {
        Write-Host "FAIL embedded release public key" -ForegroundColor Red
        Write-Host "Installer trust root could not be decoded: $($_.Exception.Message)"
        return $false
    }
    Write-Host "OK   embedded release public key" -ForegroundColor Green
    return $true
}

$files = @(
    Get-ChildItem -LiteralPath $root -Filter "*.ps1" -File | Where-Object { -not $_.Name.StartsWith(".tmp", [StringComparison]::OrdinalIgnoreCase) }
    Get-ChildItem -LiteralPath (Join-Path $root "tools") -Filter "*.ps1" -File
    Get-ChildItem -LiteralPath (Join-Path $root "src\windo\snippets") -Filter "*.ps1" -File -Recurse
    Get-ChildItem -LiteralPath (Join-Path $root "extras") -Filter "*.ps1" -File -Recurse
) | Sort-Object FullName -Unique
$ok = $true
$releaseTarget = Get-WindoReleaseTargetMeta
foreach ($file in $files) {
    $p = $file.FullName
    $f = $p.Substring($root.Length).TrimStart([char[]]@('\', '/'))
    if (!(Test-Path $p)) { Write-Warning "Missing: $f"; $ok = $false; continue }
    $err = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$err)
    if ($err) {
        Write-Host "FAIL $f" -ForegroundColor Red
        $err | ForEach-Object { Write-Host ("  ParseError: " + $_.ToString()) -ForegroundColor Yellow }
        Write-Host "  Remediation: fix syntax in $f (quotes, brackets, or encoding), then rerun tools/Validate-Windo.ps1." -ForegroundColor DarkGray
        $ok = $false
    } else {
        Write-Host "OK   $f" -ForegroundColor Green
    }
}
try {
    $installerPath = Join-Path $root "windo_install.ps1"
    $checksumPath = Join-Path $root "checksums\installer.sha256"
    if (!(Test-Path $checksumPath)) {
        Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
        Write-Host "Missing published installer checksum file. Regenerate checksums/installer.sha256 with release tooling after artifacts are refreshed."
        $ok = $false
    } else {
        $checksumContent = [string](Get-Content $checksumPath -Raw)
        $checksumManifest = Get-WindoChecksumManifest -Content $checksumContent
        $uninstallerPath = Join-Path $root "windo_uninstall.ps1"
        if (-not (Test-WindoChecksumManifestMetadata -Manifest $checksumManifest -Label "checksums/installer.sha256" -ExpectedBranch $releaseTarget.Branch -ExpectedCommit $releaseTarget.Commit)) { $ok = $false }
        if (-not (Test-WindoManifestArtifactHashes -Manifest $checksumManifest -InstallerPath $installerPath -UninstallerPath $uninstallerPath -Label "checksums/installer.sha256")) { $ok = $false }
        if (-not (Test-WindoEmbeddedReleasePublicKey -InstallerPath $installerPath -PublicKeyPath (Join-Path $root "keys\windo-release-public.rsa.xml"))) { $ok = $false }

        $signatureCheck = Join-Path $root "tools\Test-WindoChecksumSignature.ps1"
        if (-not (Test-Path -LiteralPath $signatureCheck -PathType Leaf)) {
            Write-Host "FAIL checksums/installer.sha256.sig" -ForegroundColor Red
            Write-Host "Required signature verifier is missing: $signatureCheck"
            $ok = $false
        } else {
            try {
                & $signatureCheck | Out-Null
                Write-Host "OK   checksums/installer.sha256.sig" -ForegroundColor Green
            } catch {
                Write-Host "FAIL checksums/installer.sha256.sig" -ForegroundColor Red
                Write-Host "Published checksum manifest signature is invalid or missing. $_"
                $ok = $false
            }
        }
    }
} catch {
    Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
    Write-Host "Failed to validate published checksum manifest. $_.Exception.Message"
    Write-Host "Remediation: inspect checksums/installer.sha256 formatting and path permissions, then rerun this validator."
    $ok = $false
}

try {
    $versionMatch = [regex]::Match((Get-Content -Raw -LiteralPath (Join-Path $root "windo_install.ps1")), '\$WindoVersion\s*=\s*"(?<v>\d+\.\d+\.\d+)"')
    if ($versionMatch.Success) {
        $version = $versionMatch.Groups['v'].Value
        $snapshotInstaller = Join-Path $root ("versions\v{0}\windo_install.ps1" -f $version)
        $snapshotUninstall = Join-Path $root ("versions\v{0}\windo_uninstall.ps1" -f $version)
        $snapshotChecksum = Join-Path $root ("versions\v{0}\checksums\installer.sha256" -f $version)
        $snapshotSignature = Join-Path $root ("versions\v{0}\checksums\installer.sha256.sig" -f $version)
        $snapshotPublicKey = Join-Path $root ("versions\v{0}\keys\windo-release-public.rsa.xml" -f $version)
        $snapshotComplete = (
            (Test-Path -LiteralPath $snapshotInstaller -PathType Leaf) -and
            (Test-Path -LiteralPath $snapshotUninstall -PathType Leaf) -and
            (Test-Path -LiteralPath $snapshotChecksum -PathType Leaf) -and
            (Test-Path -LiteralPath $snapshotSignature -PathType Leaf) -and
            (Test-Path -LiteralPath $snapshotPublicKey -PathType Leaf)
        )
        if ($snapshotComplete) {
            $snapshotExpectedContent = [string](Get-Content -LiteralPath $snapshotChecksum -Raw)
            $snapshotManifest = Get-WindoChecksumManifest -Content $snapshotExpectedContent
            $snapshotLabel = "versions/v$version/checksums/installer.sha256"
            if (-not (Test-WindoChecksumManifestMetadata -Manifest $snapshotManifest -Label $snapshotLabel -ExpectedBranch $releaseTarget.Branch -ExpectedCommit $releaseTarget.Commit)) { $ok = $false }
            if (-not (Test-WindoManifestArtifactHashes -Manifest $snapshotManifest -InstallerPath $snapshotInstaller -UninstallerPath $snapshotUninstall -Label $snapshotLabel)) { $ok = $false }
            if (-not (Test-WindoEmbeddedReleasePublicKey -InstallerPath $snapshotInstaller -PublicKeyPath $snapshotPublicKey)) { $ok = $false }
            try {
                & (Join-Path $root "tools\Test-WindoChecksumSignature.ps1") -ManifestPath $snapshotChecksum -SignaturePath $snapshotSignature -PublicKeyPath $snapshotPublicKey | Out-Null
                Write-Host "OK   versions/v$version/checksums/installer.sha256.sig" -ForegroundColor Green
            } catch {
                Write-Host "FAIL versions/v$version/checksums/installer.sha256.sig" -ForegroundColor Red
                Write-Host "Snapshot checksum signature is invalid. $_"
                $ok = $false
            }
        } else {
            $snapshotStatus = if ($RequireCurrentSnapshot) { "FAIL" } else { "WARN" }
            $snapshotColor = if ($RequireCurrentSnapshot) { "Red" } else { "Yellow" }
            Write-Host "$snapshotStatus versions/v$version release snapshot" -ForegroundColor $snapshotColor
            Write-Host "Current snapshot is missing installer, uninstaller, manifest, signature, or public key."
            Write-Host "Create it with ./tools/Sync-VersionSnapshot.ps1 -Version $version so future releases can validate installer payload parity."
            if ($RequireCurrentSnapshot) { $ok = $false }
        }
    }
} catch {
    Write-Host "FAIL version snapshot checksum validation" -ForegroundColor Red
    Write-Host "Failed to validate snapshot checksum manifest. $_.Exception.Message"
    Write-Host "Remediation: verify snapshot files exist and are readable, then rerun validation."
    $ok = $false
}
if (-not $ok) { exit 1 }
Write-Host "Validate-Windo: all checks passed." -ForegroundColor Cyan
