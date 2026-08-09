[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $Root 'src\windo\snippets\ChildExec.cs'
$PayloadPath = Join-Path $Root 'tools\ChildExec.b64.txt'
$RunnerPath = Join-Path $Root 'windo_runner.ps1'
$InstallerPath = Join-Path $Root 'windo_install.ps1'
$ReportPath = Join-Path $Root 'docs\prometheus-generated-repair-report.md'

function Write-Utf8BomFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($true)))
}

function Write-Utf8NoBomFile {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Sha256Hex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Set-CanonicalChildExecPayload {
    param([string]$Text, [string]$CanonicalPayload)

    # The runner legitimately contains other Base64 decoders (for example DPAPI
    # request payloads). Anchor only on the C# ChildExec source assignment.
    $anchor = '$cs = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('
    $anchorIndex = $Text.IndexOf($anchor, [StringComparison]::OrdinalIgnoreCase)
    if ($anchorIndex -lt 0) {
        throw 'ChildExec C# Base64 assignment anchor was not found in windo_runner.ps1.'
    }
    $secondAnchor = $Text.IndexOf($anchor, $anchorIndex + $anchor.Length, [StringComparison]::OrdinalIgnoreCase)
    if ($secondAnchor -ge 0) {
        throw 'Multiple ChildExec C# Base64 assignment anchors were found in windo_runner.ps1.'
    }

    $openQuote = $Text.IndexOf([char]39, $anchorIndex + $anchor.Length)
    if ($openQuote -lt 0) { throw 'ChildExec payload opening quote was not found.' }
    $closeQuote = $Text.IndexOf([char]39, $openQuote + 1)
    if ($closeQuote -lt 0) { throw 'ChildExec payload closing quote was not found.' }

    $candidateRaw = $Text.Substring($openQuote + 1, $closeQuote - $openQuote - 1)
    $candidate = ($candidateRaw -replace '\s', '')
    if ($candidate.Length -lt 10000) {
        throw "ChildExec payload is unexpectedly short: $($candidate.Length) characters."
    }
    if ($candidate -match '[^A-Za-z0-9+/=]') {
        throw 'ChildExec payload contains characters outside the Base64 alphabet.'
    }

    try {
        $decodedCandidate = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($candidate))
        if ($decodedCandidate -notmatch 'namespace\s+WindoRunner' -or $decodedCandidate -notmatch 'class\s+ChildExec') {
            throw 'Decoded payload is not the WindoRunner.ChildExec C# helper.'
        }
    } catch {
        throw "Existing ChildExec payload is not the expected valid C# Base64 payload: $($_.Exception.Message)"
    }

    $updated = $Text.Substring(0, $openQuote + 1) + $CanonicalPayload + $Text.Substring($closeQuote)
    return [pscustomobject]@{ Text = $updated; Replacements = 1; PreviousPayloadLength = $candidate.Length }
}

foreach ($required in @($SourcePath, $RunnerPath, $InstallerPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing required file: $required" }
}

$source = [IO.File]::ReadAllText($SourcePath)
$canonicalPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
[IO.File]::WriteAllText($PayloadPath, $canonicalPayload + [Environment]::NewLine, [Text.Encoding]::ASCII)

$runnerText = [IO.File]::ReadAllText($RunnerPath)
$runnerSync = Set-CanonicalChildExecPayload -Text $runnerText -CanonicalPayload $canonicalPayload
Write-Utf8NoBomFile -Path $RunnerPath -Content $runnerSync.Text

$installerText = [IO.File]::ReadAllText($InstallerPath)
$runnerContentPattern = '(?ms)^\$RunnerContent = @''\r?\n.*?^''@\r?\nWrite-Utf8NoBomFile -Path \$RunnerPath -Content \$RunnerContent'
$runnerContentReplacement = '$RunnerContent = @''' + [Environment]::NewLine + $runnerSync.Text.TrimEnd("`r", "`n") + [Environment]::NewLine + '''@' + [Environment]::NewLine + 'Write-Utf8NoBomFile -Path $RunnerPath -Content $RunnerContent'
$updatedInstaller = [regex]::Replace($installerText, $runnerContentPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $runnerContentReplacement }, 1)
if ($updatedInstaller -ceq $installerText) { throw 'Could not locate and synchronize the installer RunnerContent block.' }
Write-Utf8BomFile -Path $InstallerPath -Content $updatedInstaller

$parseFailures = New-Object System.Collections.Generic.List[string]
foreach ($relative in @(
    'bootstrap.ps1',
    'windo_install.ps1',
    'windo_runner.ps1',
    'windo_uninstall.ps1',
    'tools/Test-WindoLogic.ps1',
    'tools/Validate-Windo.ps1',
    'tools/Test-WindoReservedVariables.ps1',
    'tools/Invoke-PrometheusLocalValidation.ps1'
)) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $parseFailures.Add("Missing: $relative")
        continue
    }
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $path), [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) {
        $line = $parseError.Extent.StartLineNumber
        $column = $parseError.Extent.StartColumnNumber
        $errorId = [string]$parseError.ErrorId
        $extentText = ([string]$parseError.Extent.Text -replace '[\r\n]+', ' ')
        if ($extentText.Length -gt 180) { $extentText = $extentText.Substring(0, 180) + '...' }
        $parseFailures.Add("${relative}: line $line, column $column [$errorId] $($parseError.Message) :: $extentText")
    }
}

$decodedPayload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((([IO.File]::ReadAllText($PayloadPath)) -replace '\s', '')))
$sourceParity = ($source -ceq $decodedPayload)
$runnerParity = ([IO.File]::ReadAllText($RunnerPath) -ceq $runnerSync.Text)
$installerBytes = [IO.File]::ReadAllBytes($InstallerPath)
$installerHasBom = $installerBytes.Length -ge 3 -and $installerBytes[0] -eq 0xEF -and $installerBytes[1] -eq 0xBB -and $installerBytes[2] -eq 0xBF

$report = @(
    '# Prometheus Generated Artifact Repair Report',
    '',
    "Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
    '',
    '## Canonical execution helper',
    '',
    "- ChildExec source/payload parity: **$sourceParity**",
    "- Standalone runner synchronized: **$runnerParity**",
    "- Runner embedded payload replacements: **$($runnerSync.Replacements)**",
    "- Previous embedded payload length: **$($runnerSync.PreviousPayloadLength)**",
    ('- ChildExec source SHA256: `{0}`' -f (Get-Sha256Hex $SourcePath)),
    ('- Runner SHA256: `{0}`' -f (Get-Sha256Hex $RunnerPath)),
    '',
    '## Windows PowerShell encoding',
    '',
    "- Installer has explicit UTF-8 BOM: **$installerHasBom**",
    '',
    '## Parser gate',
    ''
)
if ($parseFailures.Count -eq 0) { $report += '- PASS: all declared release entry points parse.' }
else {
    $report += '- FAIL:'
    foreach ($failure in $parseFailures) { $report += "  - $failure" }
}
$report += @(
    '',
    'Release checksums are regenerated only after the complete Prometheus runtime is finalized. No private signing key is stored in the repository.'
)
Write-Utf8NoBomFile -Path $ReportPath -Content (($report -join [Environment]::NewLine) + [Environment]::NewLine)

if (-not $sourceParity -or -not $runnerParity -or -not $installerHasBom) { throw "Generated artifact parity failed. See $ReportPath" }
if ($parseFailures.Count -gt 0) { throw "PowerShell parser gate failed. See $ReportPath" }
Write-Host 'Prometheus generated artifact repair completed.'
