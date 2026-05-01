param(
    [string]$InstallerPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "windo_install.ps1"),
    [string]$ChecksumPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256")
)

$ErrorActionPreference = "Stop"

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

$hash = Get-WindoPublishedTextFileSha256 -Path $InstallerPath
[System.IO.File]::WriteAllText($ChecksumPath, $hash, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated checksums/installer.sha256 to $hash" -ForegroundColor Green
