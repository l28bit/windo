[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $Root 'src\windo\snippets\ChildExec.cs'
$PayloadPath = Join-Path $Root 'tools\ChildExec.b64.txt'
$InstallerPath = Join-Path $Root 'windo_install.ps1'
$ReportPath = Join-Path $Root 'docs\prometheus-generated-repair-report.md'

function Write-Utf8BomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Sync-WindoEmbeddedChildExecPayload {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CanonicalPayload
    )

    $text = [System.IO.File]::ReadAllText($Path)
    $pattern = "(?s)(\[Convert\]::FromBase64String\(\s*')(?<payload>[A-Za-z0-9+/=\r\n]+)('\s*\))"
    $replacementCount = 0
    $updated = [System.Text.RegularExpressions.Regex]::Replace(
        $text,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $candidate = ($match.Groups['payload'].Value -replace '\s', '')
            try {
                $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($candidate))
                if ($decoded -match 'namespace\s+WindoRunner' -and $decoded -match 'class\s+ChildExec') {
                    $script:replacementCount++
                    return $match.Groups[1].Value + $CanonicalPayload + $match.Groups[3].Value
                }
            } catch { }
            return $match.Value
        }
    )

    if ($replacementCount -gt 0 -and $updated -cne $text) {
        $hasBom = $false
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 3) {
            $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        }
        if ($hasBom) {
            Write-Utf8BomFile -Path $Path -Content $updated
        } else {
            Write-Utf8NoBomFile -Path $Path -Content $updated
        }
    }

    return $replacementCount
}

if (-not (Test-Path -LiteralPath $SourcePath)) { throw "Missing maintained ChildExec source: $SourcePath" }
if (-not (Test-Path -LiteralPath $InstallerPath)) { throw "Missing installer: $InstallerPath" }

$source = [System.IO.File]::ReadAllText($SourcePath)
$canonicalPayload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($source))
[System.IO.File]::WriteAllText($PayloadPath, $canonicalPayload + [Environment]::NewLine, [System.Text.Encoding]::ASCII)

$payloadTargets = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

$syncResults = New-Object System.Collections.Generic.List[object]
foreach ($file in $payloadTargets) {
    $count = Sync-WindoEmbeddedChildExecPayload -Path $file.FullName -CanonicalPayload $canonicalPayload
    if ($count -gt 0) {
        $syncResults.Add([pscustomobject]@{
            Path = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
            Replacements = $count
        })
    }
}

# Windows PowerShell 5.1 does not reliably infer BOM-less UTF-8. The installer
# intentionally contains Unicode presentation glyphs, so make the encoding
# declaration explicit at the byte level instead of depending on host locale.
$installerText = [System.IO.File]::ReadAllText($InstallerPath)
Write-Utf8BomFile -Path $InstallerPath -Content $installerText

$parseFailures = New-Object System.Collections.Generic.List[string]
$entryPoints = @(
    'bootstrap.ps1',
    'windo_install.ps1',
    'windo_runner.ps1',
    'windo_uninstall.ps1',
    'tools/Test-WindoLogic.ps1',
    'tools/Validate-Windo.ps1'
)
foreach ($relative in $entryPoints) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path)) {
        $parseFailures.Add("Missing: $relative")
        continue
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $path), [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) {
        $parseFailures.Add("${relative}: $($parseError.Message)")
    }
}

$decodedPayload = [System.Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String((([System.IO.File]::ReadAllText($PayloadPath)) -replace '\s', ''))
)
$sourceParity = ($source -ceq $decodedPayload)

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# Prometheus Generated Artifact Repair Report')
$report.Add('')
$report.Add("Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
$report.Add('')
$report.Add('## Canonical ChildExec')
$report.Add('')
$report.Add("- Source/payload byte-equivalent: **$sourceParity**")
$report.Add("- Source SHA256: `$(Get-Sha256Hex -Path $SourcePath)`")
$report.Add("- Payload SHA256: `$(Get-Sha256Hex -Path $PayloadPath)`")
$report.Add('')
$report.Add('## Embedded payload synchronization')
$report.Add('')
if ($syncResults.Count -eq 0) {
    $report.Add('- No embedded WindoRunner payloads required replacement.')
} else {
    foreach ($item in $syncResults) {
        $report.Add("- `$($item.Path)`: $($item.Replacements) replacement(s)")
    }
}
$report.Add('')
$report.Add('## Windows PowerShell encoding')
$report.Add('')
$report.Add('- `windo_install.ps1` written as UTF-8 with BOM for Windows PowerShell 5.1 compatibility.')
$report.Add('')
$report.Add('## Parser gate')
$report.Add('')
if ($parseFailures.Count -eq 0) {
    $report.Add('- PASS: all declared release entry points parse in the executing PowerShell host.')
} else {
    $report.Add('- FAIL:')
    foreach ($failure in $parseFailures) { $report.Add("  - $failure") }
}
$report.Add('')
$report.Add('The checksum manifest and signature are intentionally not rewritten by this repair step. Release integrity artifacts must be regenerated and signed only after the complete Prometheus runtime is finalized.')

Write-Utf8NoBomFile -Path $ReportPath -Content (($report -join [Environment]::NewLine) + [Environment]::NewLine)

if (-not $sourceParity) { throw 'Maintained ChildExec source and regenerated payload are not equivalent.' }
if ($parseFailures.Count -gt 0) { throw "PowerShell parser gate failed. See $ReportPath" }

Write-Host 'Prometheus generated artifact repair completed.'
