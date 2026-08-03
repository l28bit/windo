param(
    [string]$ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256"),
    [string]$SignaturePath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256.sig"),
    [string]$PrivateKeyPath = (Join-Path ([Environment]::GetFolderPath('UserProfile')) ".windo-release-keys\windo-release-private.rsa.xml"),
    [ValidateSet("RSA-PKCS1-SHA256", "RSA-PSS-SHA256")]
    [string]$Algorithm = "RSA-PKCS1-SHA256"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $ManifestPath)) { throw "Missing manifest: $ManifestPath" }
if (!(Test-Path -LiteralPath $PrivateKeyPath)) { throw "Missing private key: $PrivateKeyPath" }

$privateXml = [System.IO.File]::ReadAllText($PrivateKeyPath)
$bytes = [System.IO.File]::ReadAllBytes($ManifestPath)
$rsa = [System.Security.Cryptography.RSA]::Create()
try {
    $rsa.FromXmlString($privateXml)
    $padding = if ($Algorithm -eq "RSA-PSS-SHA256") {
        [System.Security.Cryptography.RSASignaturePadding]::Pss
    } else {
        # PKCS#1 v1.5 with SHA-256 is the deterministic cross-runtime default:
        # it verifies on Windows PowerShell 5.1's legacy RSA provider and on
        # PowerShell 7. PSS remains an explicit opt-in for CNG-capable estates.
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    }
    $signature = $rsa.SignData(
        $bytes,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        $padding
    )
} finally {
    if ($rsa) { $rsa.Dispose() }
}

$payload = @(
    "schemaVersion=1"
    "algorithm=$Algorithm"
    "signatureBase64=$([Convert]::ToBase64String($signature))"
)
[System.IO.File]::WriteAllText($SignaturePath, ($payload -join "`n"), [System.Text.UTF8Encoding]::new($false))

Write-Host "Signed checksum manifest."
Write-Host "  Manifest : $ManifestPath"
Write-Host "  Signature: $SignaturePath"
