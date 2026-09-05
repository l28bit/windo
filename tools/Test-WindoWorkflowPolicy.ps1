[CmdletBinding()]
param(
    [string]$WorkflowRoot = '.github/workflows'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $WorkflowRoot).Path
$files = @(Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in '.yml', '.yaml' } | Sort-Object Name)
if ($files.Count -eq 0) {
    throw "No workflow definitions found beneath $WorkflowRoot"
}

# Only workflows that intentionally create repository state belong here.
# Adding a writer is a security-sensitive architecture decision and must update
# this policy plus the Engineer Journal.
$writerAllowList = @(
    'windo-journal-entry.yml',
    'windo-release.yml',
    'windo-repair-lab.yml'
)

# Diagnostic tools are explicit/manual engineering instruments. They must never
# become push-triggered background CI merely because they happen to be useful.
$manualOnlyWorkflows = @(
    'windo-flake-hunter.yml',
    'windo-journal-entry.yml',
    'windo-regression-bisect.yml',
    'windo-repair-lab.yml'
)

# These immutable pins were valid when introduced but target the deprecated
# Node 20 Action runtime. The workflow estate is moving to verified Node 24
# releases; once this policy lands, old pins cannot drift back in unnoticed.
$deprecatedActionPins = @(
    'actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5',
    'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'
)

# Direct mutation of authoritative/source branches from automation is forbidden.
# Approved writers may publish isolated branches or release state, but never push
# validation results directly into development or release lineages.
$forbiddenPushPatterns = @(
    'git push origin HEAD:fix/ps51-dpapi-resolution-20260904',
    'git push origin HEAD:jonex/windo-production-ready',
    'git push origin HEAD:Exodus',
    'git push --force',
    'git push -f '
)

$violations = New-Object System.Collections.Generic.List[string]
$usesPattern = [regex]'(?m)^\s*-?\s*uses:\s*(?<value>[^#\r\n]+)'
$shaPattern = [regex]'^[^\s@]+@[0-9a-fA-F]{40}$'

foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $relative = ".github/workflows/$($file.Name)"

    if ($text.Contains("`t")) {
        $violations.Add("$relative contains a TAB; workflow YAML must use spaces only.")
    }

    foreach ($match in $usesPattern.Matches($text)) {
        $value = $match.Groups['value'].Value.Trim()
        if ($value.StartsWith('./')) { continue }
        if (-not $shaPattern.IsMatch($value)) {
            $violations.Add("$relative uses an external action without an immutable 40-character SHA: $value")
            continue
        }
        if ($value -in $deprecatedActionPins) {
            $violations.Add("$relative uses a deprecated Node-20 Action pin: $value")
        }
    }

    $declaresWrite = [regex]::IsMatch($text, '(?m)^\s*[A-Za-z-]+:\s*write\s*(?:#.*)?$')
    if ($declaresWrite -and $file.Name -notin $writerAllowList) {
        $violations.Add("$relative declares write permission but is not in the explicit writer allow-list.")
    }

    if ($text -match '(?im)\bgit\s+push\b' -and $file.Name -notin $writerAllowList) {
        $violations.Add("$relative executes git push but is not an approved state-changing workflow.")
    }

    foreach ($pattern in $forbiddenPushPatterns) {
        if ($text.IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $violations.Add("$relative contains forbidden direct source-branch mutation: $pattern")
        }
    }

    if ($file.Name -in $manualOnlyWorkflows) {
        if ([regex]::IsMatch($text, '(?m)^\s{2}push:\s*$')) {
            $violations.Add("$relative is intended to be manual-only but declares a push trigger.")
        }
        if ([regex]::IsMatch($text, '(?m)^\s{2}pull_request:\s*$')) {
            $violations.Add("$relative is intended to be manual-only but declares a pull_request trigger.")
        }
        if (-not [regex]::IsMatch($text, '(?m)^\s{2}workflow_dispatch:\s*$')) {
            $violations.Add("$relative is intended to be manual-only but has no workflow_dispatch trigger.")
        }
    }
}

$presentNames = @($files.Name)
foreach ($writer in $writerAllowList) {
    if ($writer -notin $presentNames) {
        $violations.Add("Workflow writer allow-list contains a nonexistent workflow: $writer")
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'WINDO workflow policy violations:'
    $violations | ForEach-Object { Write-Host " - $_" }
    throw "Workflow policy failed with $($violations.Count) violation(s)."
}

Write-Host "WINDO workflow policy: PASS ($($files.Count) workflow definitions inspected)"
Write-Host "Approved state-changing workflows: $($writerAllowList -join ', ')"
Write-Host "Manual-only diagnostic/capture workflows: $($manualOnlyWorkflows -join ', ')"
