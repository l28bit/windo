param(
    [string]$PrivateKeyPath = (Join-Path ([Environment]::GetFolderPath('UserProfile')) ".windo-release-keys\windo-release-private.rsa.xml"),
    [string]$PublicKeyPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "keys\windo-release-public.rsa.xml"),
    [int]$KeySize = 3072,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($KeySize -lt 3072) {
    throw "Use at least a 3072-bit RSA key for release signing."
}
if ((Test-Path -LiteralPath $PrivateKeyPath) -and -not $Force) {
    throw "Private key already exists: $PrivateKeyPath. Use -Force only if you intend to rotate the release key."
}

$privateDir = Split-Path -Parent $PrivateKeyPath
$publicDir = Split-Path -Parent $PublicKeyPath
if ($privateDir -and -not (Test-Path -LiteralPath $privateDir)) {
    New-Item -ItemType Directory -Path $privateDir -Force | Out-Null
}
if ($publicDir -and -not (Test-Path -LiteralPath $publicDir)) {
    New-Item -ItemType Directory -Path $publicDir -Force | Out-Null
}

$rsa = [System.Security.Cryptography.RSA]::Create($KeySize)
try {
    [System.IO.File]::WriteAllText($PrivateKeyPath, $rsa.ToXmlString($true), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($PublicKeyPath, $rsa.ToXmlString($false), [System.Text.UTF8Encoding]::new($false))
} finally {
    $rsa.Dispose()
}

try {
    $acl = Get-Acl -LiteralPath $PrivateKeyPath
    $acl.SetAccessRuleProtection($true, $false)
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
        "FullControl",
        "Allow"
    )
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $PrivateKeyPath -AclObject $acl
} catch {
    Write-Warning "Could not lock private key ACL automatically: $($_.Exception.Message)"
}

Write-Host "Created WINDO release signing key pair."
Write-Host "  Private: $PrivateKeyPath"
Write-Host "  Public : $PublicKeyPath"
Write-Host "Keep the private key offline/secured. Commit only the public key."
