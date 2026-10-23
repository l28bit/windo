$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$installerPath = Join-Path $root 'windo_install.ps1'
$logicPath = Join-Path $root 'tools\Test-WindoLogic.ps1'

function Get-WindoNewline([string]$Text) {
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Write-WindoUtf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][bool]$Bom
    )
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($Bom))
}

$installerSource = Get-Content -LiteralPath $installerPath -Raw
$nl = Get-WindoNewline $installerSource

$anchorLines = @(
    '            $delegate = $line.Substring($m.Length)',
    '            $trimmedDelegate = $delegate.TrimStart()'
)
$anchor = $anchorLines -join $nl
$anchorCount = ([regex]::Matches($installerSource, [regex]::Escape($anchor))).Count
if ($anchorCount -lt 1) {
    if ($installerSource.Contains('$delegateCursor = [Math]::Max(0, [Math]::Min($delegate.Length, ([int]$cursorPosition - [int]$m.Length)))')) {
        Write-Host 'Transparent completion repair is already present in installer.' -ForegroundColor Yellow
    } else {
        throw 'Known completion delegation anchor was not found. Refusing an unbounded repair.'
    }
} else {
    $replacementLines = @(
        '            $delegate = $line.Substring($m.Length)',
        '',
        '            # Default completion is intentionally transparent. Treat the text after',
        '            # `windo ` exactly as PowerShell would treat a normal command line:',
        '            # do not inject WINDO verbs, strip WINDO flags, or infer the cursor from',
        '            # the last matching word. Only translate the absolute cursor by the prefix.',
        '            if ($mode -eq "native-first") {',
        '                $delegateCursor = [Math]::Max(0, [Math]::Min($delegate.Length, ([int]$cursorPosition - [int]$m.Length)))',
        '',
        '                # Returning no matches from a native argument completer causes PowerShell',
        '                # to fall back to path completion for the empty argument. Emit one fully',
        '                # invisible no-op result so `windo <Tab>` leaves the line unchanged.',
        '                if ($delegate.Length -eq 0) {',
        '                    [System.Management.Automation.CompletionResult]::new("", "", [System.Management.Automation.CompletionResultType]::Text, "")',
        '                    return',
        '                }',
        '',
        '                $completion = TabExpansion2 -inputScript $delegate -cursorColumn $delegateCursor 2>$null',
        '                if ($null -eq $completion -or $null -eq $completion.CompletionMatches) { return }',
        '                foreach ($cm in @($completion.CompletionMatches)) { $cm }',
        '                return',
        '            }',
        '',
        '            $trimmedDelegate = $delegate.TrimStart()'
    )
    $replacement = $replacementLines -join $nl
    $installerUpdated = $installerSource.Replace($anchor, $replacement)
    $remainingCount = ([regex]::Matches($installerUpdated, [regex]::Escape($anchor))).Count
    if ($remainingCount -ne 0) {
        throw "Transparent completion repair left $remainingCount known anchors unchanged."
    }
    Write-WindoUtf8Text -Path $installerPath -Content $installerUpdated -Bom $true
    Write-Host "Repaired $anchorCount generated completion block occurrence(s) in windo_install.ps1." -ForegroundColor Green
}

$logicSource = Get-Content -LiteralPath $logicPath -Raw
$logicNl = Get-WindoNewline $logicSource
$oldLogic = 'Assert-Equal ($installerSource.Contains(''if ($mode -eq "native-first") { return }'') -eq $false) $true "profile completer offers WINDO verbs at empty windo prefix"'
$newLogicLines = @(
    'Assert-Equal ($installerSource.Contains(''if ($mode -eq "native-first") {'') -eq $true) $true "profile completer has a transparent native-first fast path"',
    'Assert-Equal ($installerSource.Contains(''$delegateCursor = [Math]::Max(0, [Math]::Min($delegate.Length, ([int]$cursorPosition - [int]$m.Length)))'') -eq $true) $true "profile completer translates the real cursor by only the windo prefix"',
    'Assert-Equal ($installerSource.Contains(''if ($delegate.Length -eq 0) {'') -eq $true) $true "profile completer suppresses empty-prefix fallback without inserting text"',
    'Assert-Equal ($installerSource.Contains(''TabExpansion2 -inputScript $delegate -cursorColumn $delegateCursor'') -eq $true) $true "profile completer delegates the unmodified command tail at the translated cursor"'
)
$newLogic = $newLogicLines -join $logicNl
if ($logicSource.Contains($oldLogic)) {
    $logicUpdated = $logicSource.Replace($oldLogic, $newLogic)
    Write-WindoUtf8Text -Path $logicPath -Content $logicUpdated -Bom $false
    Write-Host 'Updated legacy completion assertion to the transparent-prefix contract.' -ForegroundColor Green
} elseif ($logicSource.Contains('profile completer has a transparent native-first fast path')) {
    Write-Host 'Transparent completion logic assertions are already present.' -ForegroundColor Yellow
} else {
    throw 'Known legacy completion assertion was not found. Refusing an unbounded test rewrite.'
}

Write-Host 'Apply-WindoTransparentCompletionRepair: complete.' -ForegroundColor Green
