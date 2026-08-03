param(
    [string]$ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256"),
    [string]$SignaturePath = (Join-Path (Split-Path $PSScriptRoot -Parent) "checksums\installer.sha256.sig"),
    [string]$PublicKeyPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "keys\windo-release-public.rsa.xml")
)

$ErrorActionPreference = "Stop"

function Get-NameValueMap([string]$Path) {
    $map = @{}
    foreach ($line in ([System.IO.File]::ReadAllText($Path) -split "`r?`n")) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) { continue }
        if ($trim -match '^(?<key>[^=]+?)=(?<value>.*)$') {
            $map[$Matches.key] = $Matches.value.Trim()
        }
    }
    return $map
}

if (!(Test-Path -LiteralPath $ManifestPath)) { throw "Missing manifest: $ManifestPath" }
if (!(Test-Path -LiteralPath $SignaturePath)) { throw "Missing signature: $SignaturePath" }
if (!(Test-Path -LiteralPath $PublicKeyPath)) { throw "Missing public key: $PublicKeyPath" }

$sigMap = Get-NameValueMap $SignaturePath
if (-not $sigMap.ContainsKey("signatureBase64")) { throw "Signature file missing signatureBase64." }
if (-not $sigMap.ContainsKey("schemaVersion") -or [string]$sigMap.schemaVersion -ne "1") { throw "Signature file schemaVersion must be 1." }
if (-not $sigMap.ContainsKey("algorithm") -or [string]$sigMap.algorithm -notin @("RSA-PSS-SHA256", "RSA-PKCS1-SHA256")) { throw "Signature file algorithm is missing or unsupported." }

$bytes = [System.IO.File]::ReadAllBytes($ManifestPath)
$sig = [Convert]::FromBase64String([string]$sigMap.signatureBase64)
$pubXml = [System.IO.File]::ReadAllText($PublicKeyPath)
$rsa = [System.Security.Cryptography.RSA]::Create()
try {
    $rsa.FromXmlString($pubXml)
    $algorithm = [string]$sigMap.algorithm
    if ($algorithm -eq "RSA-PSS-SHA256") {
        $ok = $rsa.VerifyData(
            $bytes,
            $sig,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pss
        )
    } else {
        $ok = $rsa.VerifyData(
            $bytes,
            $sig,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    }
    if (-not $ok) { throw "Checksum manifest signature is invalid." }
} finally {
    $rsa.Dispose()
}

Write-Host "OK checksum manifest signature"
