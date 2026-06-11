param(
    [string]$ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256"),
    [string]$SignaturePath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256.sig"),
    [string]$PrivateKeyPath = (Join-Path $HOME ".windo-release-keys\windo-release-private.rsa.xml")
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $ManifestPath)) { throw "Missing manifest: $ManifestPath" }
if (!(Test-Path -LiteralPath $PrivateKeyPath)) { throw "Missing private key: $PrivateKeyPath" }

$privateXml = [System.IO.File]::ReadAllText($PrivateKeyPath)
$bytes = [System.IO.File]::ReadAllBytes($ManifestPath)
$rsa = [System.Security.Cryptography.RSA]::Create()
$algorithm = "RSA-PSS-SHA256"
try {
    $rsa.FromXmlString($privateXml)
    $signature = $rsa.SignData(
        $bytes,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pss
    )
} catch {
    if ($null -eq $rsa) { throw }
    $algorithm = "RSA-PKCS1-SHA256"
    $signature = $rsa.SignData(
        $bytes,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
} finally {
    if ($rsa) { $rsa.Dispose() }
}

$payload = @(
    "schemaVersion=1"
    "algorithm=$algorithm"
    "signatureBase64=$([Convert]::ToBase64String($signature))"
)
[System.IO.File]::WriteAllText($SignaturePath, ($payload -join "`n"), [System.Text.UTF8Encoding]::new($false))

Write-Host "Signed checksum manifest."
Write-Host "  Manifest : $ManifestPath"
Write-Host "  Signature: $SignaturePath"
