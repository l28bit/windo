[CmdletBinding()]
param(
    [string]$RunnerPath = (Join-Path $PSScriptRoot '..\windo_runner.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not [Environment]::Is64BitProcess) {
    throw 'WINDO DPAPI runtime certification requires a 64-bit PowerShell process.'
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'WINDO DPAPI runtime certification is Windows-only.'
}

$runner = (Resolve-Path -LiteralPath $RunnerPath -ErrorAction Stop).Path
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $runner,
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    throw 'windo_runner.ps1 did not parse cleanly.'
}

$functionAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-WindoProtectedDataType'
}, $true)

if ($null -eq $functionAst) {
    throw 'Could not locate Get-WindoProtectedDataType in windo_runner.ps1.'
}

$initialDirect = $true
try {
    [void][System.Security.Cryptography.ProtectedData]
} catch {
    $initialDirect = $false
}

Write-Host "PowerShell=$($PSVersionTable.PSVersion)"
Write-Host "CLR=$($PSVersionTable.CLRVersion)"
Write-Host "OS=$([Environment]::OSVersion.VersionString)"
Write-Host "ProtectedDataInitiallyResolvable=$initialDirect"

# Import only the exact shipping helper. Do not dot-source the runner because the
# runner contains executable request-handling behavior beyond this function.
$definition = $functionAst.Extent.Text
. ([ScriptBlock]::Create($definition))

$protectedDataType = Get-WindoProtectedDataType
if ($null -eq $protectedDataType) {
    throw 'Shipping Get-WindoProtectedDataType returned null. Issue #8 remains unresolved.'
}

Write-Host "ResolvedProtectedDataType=$($protectedDataType.AssemblyQualifiedName)"

# The shipping helper must leave the runtime in a state where normal static DPAPI
# calls work. This proves more than type-name discovery: it proves usable CurrentUser
# protection in the same fresh process.
$plainText = 'windo-ps51-runtime-certification'
$plainBytes = [Text.Encoding]::UTF8.GetBytes($plainText)
$sealed = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
if ($null -eq $sealed -or $sealed.Length -eq 0) {
    throw 'ProtectedData resolved but CurrentUser Protect returned no ciphertext.'
}

$opened = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $sealed,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
$roundTrip = [Text.Encoding]::UTF8.GetString($opened)
if ($roundTrip -cne $plainText) {
    throw 'DPAPI protect/unprotect round-trip changed the payload.'
}

Write-Host "CipherBytes=$($sealed.Length)"
Write-Host 'WINDO DPAPI runtime certification: PASS'
