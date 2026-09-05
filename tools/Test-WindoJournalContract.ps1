[CmdletBinding()]
param(
    [string]$BaseSha,
    [string]$HeadSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$canonicalJournal = Join-Path $root 'docs/ENGINEER_JOURNAL.md'
$modularRoot = Join-Path $root 'docs/engineer-journal'

function Assert-RequiredJournalSections {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }

    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$Label is empty: $Path"
    }

    foreach ($heading in @(
        '### Context / question',
        '### Evidence / observations',
        '### Alternatives considered',
        '### Decision / hypothesis',
        '### Result',
        '### Follow-up'
    )) {
        if (-not $text.Contains($heading)) {
            throw "$Label is missing required section '$heading': $Path"
        }
    }
}

if (-not (Test-Path -LiteralPath $canonicalJournal -PathType Leaf)) {
    throw 'docs/ENGINEER_JOURNAL.md is required.'
}

$canonicalText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $canonicalJournal))
if (-not $canonicalText.Contains('# WINDO Engineer Journal')) {
    throw 'Canonical Engineer Journal heading is missing.'
}
Assert-RequiredJournalSections -Path $canonicalJournal -Label 'Canonical Engineer Journal'

$hasComparison = -not [string]::IsNullOrWhiteSpace($BaseSha) -or -not [string]::IsNullOrWhiteSpace($HeadSha)
if ($hasComparison -and ([string]::IsNullOrWhiteSpace($BaseSha) -or [string]::IsNullOrWhiteSpace($HeadSha))) {
    throw 'BaseSha and HeadSha must either both be supplied or both be omitted.'
}

if (-not $hasComparison) {
    Write-Host 'WINDO Engineer Journal structure: PASS (no comparison range supplied)'
    exit 0
}

Push-Location $root
try {
    & git cat-file -e "$BaseSha^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "BaseSha is not a local commit: $BaseSha" }
    & git cat-file -e "$HeadSha^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "HeadSha is not a local commit: $HeadSha" }

    $changed = @(& git diff --name-only $BaseSha $HeadSha)
    if ($LASTEXITCODE -ne 0) { throw 'Could not calculate Engineer Journal comparison diff.' }

    Write-Host 'Changed files considered by Engineer Journal contract:'
    $changed | ForEach-Object { Write-Host " - $_" }

    $material = $false
    foreach ($path in $changed) {
        if ($path -match '^(\.github/workflows/|src/|tools/|checksums/|versions/|keys/)' -or
            $path -eq 'bootstrap.ps1' -or
            $path -match '^windo_.*\.ps1$' -or
            $path -match '^docs/.*(architecture|contract|security|compatibility|release).*') {
            $material = $true
            break
        }
    }

    if (-not $material) {
        Write-Host 'No material engineering change detected; journal update is optional.'
        exit 0
    }

    $canonicalChanged = $changed -contains 'docs/ENGINEER_JOURNAL.md'
    $modularChanged = @($changed | Where-Object { $_ -match '^docs/engineer-journal/.+\.md$' })

    if (-not $canonicalChanged -and $modularChanged.Count -eq 0) {
        throw 'Material engineering changes require an Engineer Journal update in docs/ENGINEER_JOURNAL.md or docs/engineer-journal/*.md.'
    }

    foreach ($relative in $modularChanged) {
        $path = Join-Path $root ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        Assert-RequiredJournalSections -Path $path -Label 'Modular Engineer Journal entry'
    }

    Write-Host "WINDO Engineer Journal contract: PASS (material=$material canonicalChanged=$canonicalChanged modularEntries=$($modularChanged.Count))"
}
finally {
    Pop-Location
}
