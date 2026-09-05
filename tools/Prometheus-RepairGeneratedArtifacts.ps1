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
$Lf = "`n"

function ConvertTo-CanonicalLfText {
    param([AllowEmptyString()][string]$Content)
    if ($null -eq $Content) { return $null }
    return $Content.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8BomFile {
    param([string]$Path, [string]$Content)
    $canonical = ConvertTo-CanonicalLfText -Content $Content
    [System.IO.File]::WriteAllText($Path, $canonical, (New-Object System.Text.UTF8Encoding($true)))
}

function Write-Utf8NoBomFile {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $canonical = ConvertTo-CanonicalLfText -Content $Content
    [System.IO.File]::WriteAllText($Path, $canonical, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Sha256Hex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-PowerShellTextParses {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput(
        $Text,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $details = @($parseErrors | ForEach-Object {
            'line {0}, column {1}: {2}' -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message
        }) -join '; '
        throw "$Label does not parse: $details"
    }
}

function Set-CanonicalChildExecAssignment {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$CanonicalPayload
    )

    # Do not search for generic FromBase64String calls. WINDO also uses Base64
    # for protected request data. Parse the runner and replace only the unique
    # assignment whose left side is the ChildExec source variable `$cs`.
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Text,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $messages = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "windo_runner.ps1 does not parse before ChildExec synchronization: $messages"
    }

    $assignments = @($ast.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
        if ($node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }
        return ($node.Left.VariablePath.UserPath -ceq 'cs')
    }, $true))

    if ($assignments.Count -ne 1) {
        throw "Expected exactly one `$cs ChildExec assignment in windo_runner.ps1; found $($assignments.Count)."
    }

    $assignment = $assignments[0]
    $previousAssignment = [string]$assignment.Extent.Text
    if ($previousAssignment -notmatch '(?i)FromBase64String' -or
        $previousAssignment -notmatch '(?i)UTF8\.GetString') {
        throw 'The unique $cs assignment is not the expected UTF8/FromBase64String ChildExec loader.'
    }

    # Release artifacts are explicitly LF-pinned in .gitattributes. Always build
    # generated blocks with LF so regeneration is byte-stable on Windows and Linux.
    $replacement = '$cs = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(' +
        $Lf + "        '" + $CanonicalPayload + "'" +
        $Lf + '    ))'

    $start = [int]$assignment.Extent.StartOffset
    $end = [int]$assignment.Extent.EndOffset
    if ($start -lt 0 -or $end -le $start -or $end -gt $Text.Length) {
        throw "ChildExec assignment extent is invalid: start=$start end=$end length=$($Text.Length)."
    }

    $updated = $Text.Substring(0, $start) + $replacement + $Text.Substring($end)
    $updated = ConvertTo-CanonicalLfText -Content $updated
    Assert-PowerShellTextParses -Text $updated -Label 'windo_runner.ps1 after ChildExec synchronization'

    return [pscustomobject]@{
        Text = $updated
        Replacements = 1
        PreviousAssignmentLength = $previousAssignment.Length
    }
}

foreach ($required in @($SourcePath, $RunnerPath, $InstallerPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing required file: $required"
    }
}

$source = ConvertTo-CanonicalLfText -Content ([System.IO.File]::ReadAllText($SourcePath))
$canonicalPayload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($source))
[System.IO.File]::WriteAllText(
    $PayloadPath,
    $canonicalPayload + $Lf,
    [System.Text.Encoding]::ASCII
)

$runnerText = ConvertTo-CanonicalLfText -Content ([System.IO.File]::ReadAllText($RunnerPath))
$runnerSync = Set-CanonicalChildExecAssignment -Text $runnerText -CanonicalPayload $canonicalPayload
Write-Utf8NoBomFile -Path $RunnerPath -Content $runnerSync.Text

# The installer publishes the standalone runner from RunnerContent. Replace the
# complete embedded block from the now-canonical standalone runner so the two
# artifacts cannot drift.
$installerText = ConvertTo-CanonicalLfText -Content ([System.IO.File]::ReadAllText($InstallerPath))
$runnerContentPattern = '(?ms)^\$RunnerContent = @''\r?\n.*?^''@\r?\nWrite-Utf8NoBomFile -Path \$RunnerPath -Content \$RunnerContent'
$runnerContentReplacement = '$RunnerContent = @''' + $Lf +
    $runnerSync.Text.TrimEnd("`r", "`n") + $Lf +
    '''@' + $Lf +
    'Write-Utf8NoBomFile -Path $RunnerPath -Content $RunnerContent'
$updatedInstaller = [regex]::Replace(
    $installerText,
    $runnerContentPattern,
    [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $runnerContentReplacement },
    1
)
if ($updatedInstaller -ceq $installerText) {
    throw 'Could not locate and synchronize the installer RunnerContent block.'
}
Write-Utf8BomFile -Path $InstallerPath -Content $updatedInstaller

$parseFailures = New-Object 'System.Collections.Generic.List[string]'
foreach ($relative in @(
    'bootstrap.ps1',
    'windo_install.ps1',
    'windo_runner.ps1',
    'windo_uninstall.ps1',
    'tools/Test-WindoLogic.ps1',
    'tools/Validate-Windo.ps1',
    'tools/Test-WindoReservedVariables.ps1',
    'tools/Invoke-PrometheusLocalValidation.ps1',
    'tools/Invoke-PrometheusLocalStage.ps1',
    'tools/Prometheus-RepairGeneratedArtifacts.ps1'
)) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $parseFailures.Add("Missing: $relative")
        continue
    }

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $path),
        [ref]$tokens,
        [ref]$errors
    )
    foreach ($parseError in @($errors)) {
        $line = $parseError.Extent.StartLineNumber
        $column = $parseError.Extent.StartColumnNumber
        $errorId = [string]$parseError.ErrorId
        $extentText = ([string]$parseError.Extent.Text -replace '[\r\n]+', ' ')
        if ($extentText.Length -gt 180) {
            $extentText = $extentText.Substring(0, 180) + '...'
        }
        $parseFailures.Add("${relative}: line $line, column $column [$errorId] $($parseError.Message) :: $extentText")
    }
}

$decodedPayload = [System.Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String((([System.IO.File]::ReadAllText($PayloadPath)) -replace '\s', ''))
)
$sourceParity = ($source -ceq $decodedPayload)
$runnerParity = ([System.IO.File]::ReadAllText($RunnerPath) -ceq $runnerSync.Text)
$installerBytes = [System.IO.File]::ReadAllBytes($InstallerPath)
$installerHasBom = $installerBytes.Length -ge 3 -and
    $installerBytes[0] -eq 0xEF -and
    $installerBytes[1] -eq 0xBB -and
    $installerBytes[2] -eq 0xBF

$report = @(
    '# Prometheus Generated Artifact Repair Report',
    '',
    "Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
    '',
    '## Canonical execution helper',
    '',
    "- ChildExec source/payload parity: **$sourceParity**",
    "- Standalone runner synchronized: **$runnerParity**",
    "- Runner ChildExec assignment replacements: **$($runnerSync.Replacements)**",
    "- Previous ChildExec assignment length: **$($runnerSync.PreviousAssignmentLength)**",
    ('- ChildExec source SHA256: `{0}`' -f (Get-Sha256Hex $SourcePath)),
    ('- Runner SHA256: `{0}`' -f (Get-Sha256Hex $RunnerPath)),
    '',
    '## Windows PowerShell encoding',
    '',
    "- Installer has explicit UTF-8 BOM: **$installerHasBom**",
    '- Generated release text uses canonical LF newlines independent of host OS.',
    '',
    '## Parser gate',
    ''
)
if ($parseFailures.Count -eq 0) {
    $report += '- PASS: all declared release entry points and Prometheus tools parse.'
}
else {
    $report += '- FAIL:'
    foreach ($failure in $parseFailures) {
        $report += "  - $failure"
    }
}
$report += @(
    '',
    'Release checksums are regenerated only after the complete Prometheus runtime is finalized. No private signing key is stored in the repository.'
)
Write-Utf8NoBomFile -Path $ReportPath -Content (($report -join $Lf) + $Lf)

if (-not $sourceParity -or -not $runnerParity -or -not $installerHasBom) {
    throw "Generated artifact parity failed. See $ReportPath"
}
if ($parseFailures.Count -gt 0) {
    throw "PowerShell parser gate failed. See $ReportPath"
}

Write-Host 'Prometheus generated artifact repair completed.' -ForegroundColor Green
