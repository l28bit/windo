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

# Workflows on this allow-list are intentionally capable of creating repository
# state. Every other workflow is expected to remain read-only. Adding a writer is
# a security-sensitive architecture decision and must update this policy + journal.
$writerAllowList = @(
    'prometheus-repair-sync.yml',
    'prometheus-stage-repair.yml',
    'windo-issue8-apply-repair.yml',
    'windo-journal-entry.yml',
    'windo-regression-bisect.yml',
    'windo-release.yml',
    'windo-repair-lab.yml'
)

# Direct branch mutation from a validation workflow is forbidden. Approved
# writers may create isolated branches/PRs or release state, but the workflow text
# must not contain the known unsafe source-branch mutation pattern.
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

    # Workflows described as laboratories or capture tools should not run on every
    # push. Their role is explicit/manual experimentation, not authoritative CI.
    if ($file.Name -in @('windo-repair-lab.yml', 'windo-journal-entry.yml')) {
        if ([regex]::IsMatch($text, '(?m)^\s{2}push:\s*$')) {
            $violations.Add("$relative is intended to be manual-only but declares a push trigger.")
        }
        if (-not [regex]::IsMatch($text, '(?m)^\s{2}workflow_dispatch:\s*$')) {
            $violations.Add("$relative is intended to be manual-only but has no workflow_dispatch trigger.")
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'WINDO workflow policy violations:'
    $violations | ForEach-Object { Write-Host " - $_" }
    throw "Workflow policy failed with $($violations.Count) violation(s)."
}

Write-Host "WINDO workflow policy: PASS ($($files.Count) workflow definitions inspected)"
Write-Host "Approved state-changing workflows: $($writerAllowList -join ', ')"
