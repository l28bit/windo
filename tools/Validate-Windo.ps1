# Validate WINDO repo scripts (syntax). Run from repo root: ./tools/Validate-Windo.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

function New-WindoSHA256 {
    return [System.Security.Cryptography.SHA256]::Create()
}

function Get-WindoPublishedTextFileSha256([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = New-WindoSHA256
    try {
        # Validate against the same raw SHA256 domain used by bootstrap/install hash checks.
        $hashBytes = $sha.ComputeHash($bytes)
        -join ($hashBytes | ForEach-Object { $_.ToString("X2") })
    } finally {
        $sha.Dispose()
    }
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

    $releaseBranch = if ($Manifest.ContainsKey("releaseBranch")) { [string]$Manifest.releaseBranch } else { $null }
    $releaseCommit = if ($Manifest.ContainsKey("releaseCommit")) { [string]$Manifest.releaseCommit } else { $null }
    $releaseBranchRaw = if ($Manifest.ContainsKey("releaseBranchRaw")) { [string]$Manifest.releaseBranchRaw } else { $null }
    $releaseCommitRaw = if ($Manifest.ContainsKey("releaseCommitRaw")) { [string]$Manifest.releaseCommitRaw } else { $null }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedBranch)) {
        if (-not [string]::IsNullOrWhiteSpace($releaseBranch) -and $releaseBranch -ne $ExpectedBranch) {
            Write-Host "WARN $Label" -ForegroundColor Yellow
            Write-Host "Manifest releaseBranch does not match local target branch. expected=$ExpectedBranch manifest=$releaseBranch"
        } elseif ([string]::IsNullOrWhiteSpace($releaseBranch)) {
            Write-Host "WARN $Label" -ForegroundColor Yellow
            Write-Host "Manifest releaseBranch is missing."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and -not [string]::IsNullOrWhiteSpace($releaseCommit)) {
        $normalizedReleaseCommit = $releaseCommit.ToLowerInvariant()
        if ($normalizedReleaseCommit -ne $ExpectedCommit) {
            Write-Host "WARN $Label" -ForegroundColor Yellow
            Write-Host "Manifest releaseCommit does not match local HEAD hash. expected=$ExpectedCommit manifest=$releaseCommit"
        }
    }

    if ([string]::IsNullOrWhiteSpace($releaseBranchRaw)) {
        Write-Host "WARN $Label" -ForegroundColor Yellow
        Write-Host "Manifest releaseBranchRaw is missing; install metadata is using normalized branch only."
    } elseif (-not [string]::IsNullOrWhiteSpace($releaseBranch) -and $releaseBranchRaw -ne $releaseBranch) {
        Write-Host "WARN $Label" -ForegroundColor Yellow
        Write-Host "Manifest releaseBranchRaw does not match releaseBranch value. branch=$releaseBranch raw=$releaseBranchRaw"
    }

    if ([string]::IsNullOrWhiteSpace($releaseCommitRaw)) {
        Write-Host "WARN $Label" -ForegroundColor Yellow
        Write-Host "Manifest releaseCommitRaw is missing; install metadata is using normalized commit only."
    } elseif ($releaseCommitRaw -match '^[a-fA-F0-9]{40,64}$') {
        if (-not [string]::IsNullOrWhiteSpace($releaseCommit) -and ($releaseCommitRaw.ToLowerInvariant() -ne $releaseCommit.ToLowerInvariant())) {
            Write-Host "WARN $Label" -ForegroundColor Yellow
            Write-Host "Manifest releaseCommitRaw does not match releaseCommit value. commit=$releaseCommit raw=$releaseCommitRaw"
        }
    } else {
        Write-Host "WARN $Label" -ForegroundColor Yellow
        Write-Host "Manifest releaseCommitRaw is not a 40-character commit hash."
    }
}

$files = @(
    "bootstrap.ps1",
    "windo_install.ps1",
    "windo_uninstall.ps1",
    "windo_runner.ps1",
    "windo_self_update.ps1",
    "src\windo\snippets\StatsTimeFilter.ps1",
    "src\windo\snippets\WindoConfigEffective.ps1"
)
$ok = $true
$releaseTarget = Get-WindoReleaseTargetMeta
foreach ($f in $files) {
    $p = Join-Path $root $f
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
        $manifestHasSchema = $checksumManifest.ContainsKey("schemaVersion")
        if ($manifestHasSchema) {
            if (-not ($checksumManifest.ContainsKey("releaseBranch") -and $checksumManifest.ContainsKey("releaseCommit") -and $checksumManifest.ContainsKey("generatedAt"))) {
                Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
                Write-Host "Published checksum manifest missing required metadata keys."
                $ok = $false
            }
        }
        Test-WindoChecksumManifestMetadata -Manifest $checksumManifest -Label "checksums/installer.sha256" -ExpectedBranch $releaseTarget.Branch -ExpectedCommit $releaseTarget.Commit
        $expectedInstaller = $checksumManifest.installerSha256
        $expectedUninstaller = $checksumManifest.uninstallerSha256

        if (-not (Test-WindoHex64 $expectedInstaller)) {
            Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
            Write-Host "Published installer checksum is not a valid 64-char SHA256 value. Regenerate checksums/installer.sha256 from the checked-in installer source."
            $ok = $false
        } else {
            $actual = Get-WindoPublishedTextFileSha256 -Path $installerPath
            if ($actual -cne $expectedInstaller) {
                Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
                Write-Host "Published installer checksum does not match the installer payload."
                Write-Host "Expected: $expectedInstaller"
                Write-Host "Found   : $actual"
                Write-Host "Remediation: run tools/Sync-InstallerChecksum.ps1 and commit the updated checksums file if release artifacts are correct."
                $ok = $false
            } else {
                Write-Host "OK   checksums/installer.sha256 (installer)" -ForegroundColor Green
            }
        }

        if ([string]::IsNullOrWhiteSpace($expectedUninstaller)) {
            Write-Host "WARN checksums/installer.sha256" -ForegroundColor Yellow
            Write-Host "Published uninstaller checksum entry is missing."
            $ok = $false
        } elseif (-not (Test-WindoHex64 $expectedUninstaller)) {
            Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
            Write-Host "Published uninstaller checksum is not a valid SHA256 value."
            $ok = $false
        } else {
            $uninstallerPath = Join-Path $root "windo_uninstall.ps1"
            if (Test-Path $uninstallerPath) {
                $actualUninstaller = Get-WindoPublishedTextFileSha256 -Path $uninstallerPath
                if ($actualUninstaller -cne $expectedUninstaller) {
                    Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
                    Write-Host "Published uninstaller checksum does not match the uninstaller payload."
                    Write-Host "Expected: $expectedUninstaller"
                    Write-Host "Found   : $actualUninstaller"
                    Write-Host "Remediation: re-run tools/Sync-InstallerChecksum.ps1 after rebuilding release artifacts."
                    $ok = $false
                } else {
                    Write-Host "OK   checksums/installer.sha256 (uninstaller)" -ForegroundColor Green
                }
            } else {
                Write-Host "WARN checksums/installer.sha256" -ForegroundColor Yellow
                Write-Host "windo_uninstall.ps1 missing; skipping uninstaller checksum validation."
            }
        }

        if ($manifestHasSchema) {
            [datetime]$generatedAt = [datetime]::MinValue
            if (-not [datetime]::TryParse($checksumManifest.generatedAt, [ref]$generatedAt)) {
                Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
                Write-Host "Published checksum manifest generatedAt is invalid."
                $ok = $false
            }
            if ($generatedAt -gt (Get-Date).ToUniversalTime().AddMinutes(5)) {
                Write-Host "WARN checksums/installer.sha256" -ForegroundColor Yellow
                Write-Host "Published checksum manifest generatedAt is in the future."
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
        if ((Test-Path -LiteralPath $snapshotInstaller) -and (Test-Path -LiteralPath $snapshotChecksum)) {
            $snapshotExpectedContent = [string](Get-Content -LiteralPath $snapshotChecksum -Raw)
            $snapshotManifest = Get-WindoChecksumManifest -Content $snapshotExpectedContent
            $snapshotHasSchema = $snapshotManifest.ContainsKey("schemaVersion")
            if ($snapshotHasSchema -and -not ($snapshotManifest.ContainsKey("releaseBranch") -and $snapshotManifest.ContainsKey("releaseCommit") -and $snapshotManifest.ContainsKey("generatedAt"))) {
                Write-Host "FAIL versions/v$version/checksums/installer.sha256" -ForegroundColor Red
                Write-Host "Snapshot checksum manifest missing required metadata keys."
                $ok = $false
            }
            Test-WindoChecksumManifestMetadata -Manifest $snapshotManifest -Label "versions/v$version/checksums/installer.sha256" -ExpectedBranch $releaseTarget.Branch -ExpectedCommit $releaseTarget.Commit
            $snapshotExpectedInstaller = $snapshotManifest.installerSha256
            $snapshotExpectedUninstaller = $snapshotManifest.uninstallerSha256

            if (-not (Test-WindoHex64 $snapshotExpectedInstaller)) {
                Write-Host "FAIL versions/v$version/checksums/installer.sha256" -ForegroundColor Red
                Write-Host "Snapshot installer checksum does not contain a valid SHA256."
                $ok = $false
            } else {
                $snapshotActual = Get-WindoPublishedTextFileSha256 -Path $snapshotInstaller
                if ($snapshotActual -cne $snapshotExpectedInstaller) {
                    Write-Host "FAIL versions/v$version/checksums/installer.sha256" -ForegroundColor Red
                    Write-Host "Snapshot installer checksum does not match expected content."
                    Write-Host "Expected: $snapshotExpectedInstaller"
                    Write-Host "Found   : $snapshotActual"
                    Write-Host "Remediation: rebuild snapshot checksums with tools/Sync-InstallerChecksum.ps1 for the snapshot branch."
                    $ok = $false
                } else {
                    Write-Host "OK   versions/v$version/checksums/installer.sha256" -ForegroundColor Green
                }
            }

            if (-not (Test-WindoHex64 $snapshotExpectedUninstaller)) {
                Write-Host "WARN versions/v$version/checksums/installer.sha256" -ForegroundColor Yellow
                Write-Host "Snapshot uninstaller checksum does not contain a valid SHA256 or is missing."
            } else {
                if (Test-Path -LiteralPath $snapshotUninstall) {
                    $snapshotActualUninstaller = Get-WindoPublishedTextFileSha256 -Path $snapshotUninstall
                    if ($snapshotActualUninstaller -cne $snapshotExpectedUninstaller) {
                        Write-Host "FAIL versions/v$version/checksums/installer.sha256" -ForegroundColor Red
                        Write-Host "Snapshot uninstaller checksum does not match expected content."
                        Write-Host "Expected: $snapshotExpectedUninstaller"
                        Write-Host "Found   : $snapshotActualUninstaller"
                        Write-Host "Remediation: rebuild snapshot checksums with tools/Sync-InstallerChecksum.ps1 for the snapshot branch."
                        $ok = $false
                    }
                } else {
                    Write-Host "WARN versions/v$version/checksums/installer.sha256" -ForegroundColor Yellow
                    Write-Host "versions/v$version/windo_uninstall.ps1 missing; skipping snapshot uninstaller checksum validation."
                }
            }

            if ($snapshotHasSchema) {
            [datetime]$snapshotGeneratedAt = [datetime]::MinValue
                if (-not [datetime]::TryParse($snapshotManifest.generatedAt, [ref]$snapshotGeneratedAt)) {
                    Write-Host "FAIL versions/v$version/checksums/installer.sha256" -ForegroundColor Red
                    Write-Host "Snapshot checksum manifest generatedAt is invalid."
                    $ok = $false
                }
            }
        } else {
            Write-Host "WARN versions/v$version/checksums/installer.sha256" -ForegroundColor Yellow
            Write-Host "No versions/v$version snapshot exists for this branch. Skipping snapshot checksum validation."
            Write-Host "Create it with ./tools/Sync-VersionSnapshot.ps1 -Version $version so future releases can validate installer payload parity."
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
