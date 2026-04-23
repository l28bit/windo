# Validate WINDO repo scripts (syntax). Run from repo root: ./tools/Validate-Windo.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

function Get-WindoPublishedTextFileSha256([string]$Path) {
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
foreach ($f in $files) {
    $p = Join-Path $root $f
    if (!(Test-Path $p)) { Write-Warning "Missing: $f"; $ok = $false; continue }
    $err = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$err)
    if ($err) {
        Write-Host "FAIL $f" -ForegroundColor Red
        $err | ForEach-Object { Write-Host $_.ToString() }
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
        Write-Host "Missing published installer checksum file."
        $ok = $false
    } else {
        $checksumContent = [string](Get-Content $checksumPath -Raw)
        $match = [regex]::Match($checksumContent, '[A-Fa-f0-9]{64}')
        if (-not $match.Success) {
            Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
            Write-Host "Published installer checksum does not contain a valid SHA256."
            $ok = $false
        } else {
            $expected = $match.Value.ToUpperInvariant()
            $actual = Get-WindoPublishedTextFileSha256 -Path $installerPath
            if ($actual -cne $expected) {
                Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
                Write-Host "Published installer checksum is stale."
                Write-Host "Expected: $actual"
                Write-Host "Found   : $expected"
                $ok = $false
            } else {
                Write-Host "OK   checksums/installer.sha256" -ForegroundColor Green
            }
        }
    }
} catch {
    Write-Host "FAIL checksums/installer.sha256" -ForegroundColor Red
    Write-Host $_.Exception.Message
    $ok = $false
}
if (-not $ok) { exit 1 }
Write-Host "Validate-Windo: all checks passed." -ForegroundColor Cyan
