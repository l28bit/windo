[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $root 'windo_runner.ps1'
$generatorPath = Join-Path $PSScriptRoot 'Prometheus-RepairGeneratedArtifacts.ps1'

$before = @'
function Get-WindoProtectedDataType {
    $typeName = "System.Security.Cryptography.ProtectedData"
    foreach ($qualifiedName in @(
        "$typeName, System.Security.Cryptography.ProtectedData",
        "$typeName, System.Security"
    )) {
        try {
            $resolved = [type]::GetType($qualifiedName, $false)
            if ($null -ne $resolved) { return $resolved }
        } catch { }
    }
    return $null
}
'@

$after = @'
function Get-WindoProtectedDataType {
    $typeName = "System.Security.Cryptography.ProtectedData"
    $qualifiedNames = @(
        "$typeName, System.Security.Cryptography.ProtectedData",
        "$typeName, System.Security"
    )

    foreach ($qualifiedName in $qualifiedNames) {
        try {
            $resolved = [type]::GetType($qualifiedName, $false)
            if ($null -ne $resolved) { return $resolved }
        } catch { }
    }

    # Windows PowerShell 5.1 on a fresh .NET Framework process does not load
    # System.Security merely because an assembly-qualified type name is probed.
    # Load the framework assembly explicitly, then repeat the exact lookup. The
    # PowerShell 7 path normally returns above and is left unchanged.
    if ($PSVersionTable.PSVersion.Major -le 5) {
        try {
            Add-Type -AssemblyName System.Security -ErrorAction Stop
        } catch {
            return $null
        }

        foreach ($qualifiedName in $qualifiedNames) {
            try {
                $resolved = [type]::GetType($qualifiedName, $false)
                if ($null -ne $resolved) { return $resolved }
            } catch { }
        }
    }

    return $null
}
'@

if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "Missing canonical runner: $runnerPath"
}
if (-not (Test-Path -LiteralPath $generatorPath -PathType Leaf)) {
    throw "Missing generated-artifact repair tool: $generatorPath"
}

$text = [IO.File]::ReadAllText($runnerPath)
$oldCount = ([regex]::Matches($text, [regex]::Escape($before))).Count
$newCount = ([regex]::Matches($text, [regex]::Escape($after))).Count

if ($oldCount -eq 0 -and $newCount -eq 1) {
    Write-Host 'Issue #8 canonical source repair is already present.'
} elseif ($oldCount -ne 1 -or $newCount -ne 0) {
    throw "Refusing Issue #8 repair: expected exactly one known pre-fix helper (old=$oldCount new=$newCount)."
} else {
    $updated = $text.Replace($before, $after)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($runnerPath, $updated, $utf8NoBom)
    Write-Host 'Applied the exact Issue #8 canonical source repair to windo_runner.ps1.'
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $runnerPath),
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Error $_.Message }
    throw 'Canonical runner does not parse after Issue #8 repair.'
}

& $generatorPath
if ($LASTEXITCODE -ne 0) {
    throw "Generated-artifact repair failed with exit code $LASTEXITCODE."
}

Write-Host 'Issue #8 source repair and generated-artifact propagation completed.' -ForegroundColor Green
