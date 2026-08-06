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
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
}

function Write-Utf8NoBomFile {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-Sha256Hex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Set-CanonicalChildExecPayload {
    param([string]$Text, [string]$CanonicalPayload)

    # Discover large quoted Base64 literals by content rather than depending on
    # one exact FromBase64String parenthesis layout. Decode every candidate and
    # replace only the literal that proves it contains WindoRunner.ChildExec.
    $pattern = '(?s)(?<prefix>'')(?<payload>[A-Za-z0-9+/=\r\n]{10000,})(?<suffix>'')'
    $replacements = [ref]0
    $updated = [regex]::Replace($Text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $candidate = ($match.Groups['payload'].Value -replace '\s', '')
        try {
            $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($candidate))
            if ($decoded -match 'namespace\s+WindoRunner' -and $decoded -match 'class\s+ChildExec') {
                $replacements.Value++
                return $match.Groups['prefix'].Value + $CanonicalPayload + $match.Groups['suffix'].Value
            }
        } catch { }
        return $match.Value
    })
    return [pscustomobject]@{ Text = $updated; Replacements = [int]$replacements.Value }
}

foreach ($required in @($SourcePath, $RunnerPath, $InstallerPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing required file: $required" }
}

$source = [IO.File]::ReadAllText($SourcePath)
$canonicalPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
[IO.File]::WriteAllText($PayloadPath, $canonicalPayload + [Environment]::NewLine, [Text.Encoding]::ASCII)

$runnerText = [IO.File]::ReadAllText($RunnerPath)
$runnerSync = Set-CanonicalChildExecPayload -Text $runnerText -CanonicalPayload $canonicalPayload
if ($runnerSync.Replacements -ne 1) {
    throw "Expected exactly one content-verified WindoRunner ChildExec payload in windo_runner.ps1; found $($runnerSync.Replacements)."
}
Write-Utf8NoBomFile -Path $RunnerPath -Content $runnerSync.Text

$installerText = [IO.File]::ReadAllText($InstallerPath)
$runnerContentPattern = '(?ms)^\$RunnerContent = @''\r?\n.*?^''@\r?\nWrite-Utf8NoBomFile -Path \$RunnerPath -Content \$RunnerContent'
$runnerContentReplacement = '$RunnerContent = @''' + [Environment]::NewLine + $runnerSync.Text.TrimEnd("`r", "`n") + [Environment]::NewLine + '''@' + [Environment]::NewLine + 'Write-Utf8NoBomFile -Path $RunnerPath -Content $RunnerContent'
$updatedInstaller = [regex]::Replace($installerText, $runnerContentPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $runnerContentReplacement }, 1)
if ($updatedInstaller -ceq $installerText) { throw 'Could not locate and synchronize the installer RunnerContent block.' }
Write-Utf8BomFile -Path $InstallerPath -Content $updatedInstaller

$parseFailures = [System.Collections.Generic.List[string]]::new()
foreach ($relative in @(
    'bootstrap.ps1',
    'windo_install.ps1',
    'windo_runner.ps1',
    'windo_uninstall.ps1',
    'tools/Test-WindoLogic.ps1',
    'tools/Validate-Windo.ps1'
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
