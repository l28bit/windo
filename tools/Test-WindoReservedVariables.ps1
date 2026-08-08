[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$targets = Get-ChildItem -LiteralPath $resolvedRoot -Filter '*.ps1' -File -Recurse | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and
    $_.FullName -notmatch '[\\/]\.prometheus[\\/]'
}

$violations = New-Object 'System.Collections.Generic.List[string]'

foreach ($file in $targets) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if ($parseErrors.Count -gt 0) {
        $messages = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "Parse failure in $($file.FullName): $messages"
    }

    $assignments = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    }, $true)

    foreach ($assignment in $assignments) {
        $variables = $assignment.Left.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)

        foreach ($variable in $variables) {
            if ($variable.VariablePath.UserPath -ieq 'IsWindows') {
                $relative = $file.FullName.Substring($resolvedRoot.Length).TrimStart('\\','/')
                $violations.Add(
                    ('{0}:{1}: assignment to read-only automatic variable $IsWindows' -f `
                        $relative,
                        $variable.Extent.StartLineNumber)
                )
            }
        }
    }
}

if ($violations.Count -gt 0) {
    foreach ($violation in $violations) {
        Write-Error $violation
    }
    throw ('Reserved-variable regression detected in {0} assignment(s).' -f $violations.Count)
}

Write-Host ('PASS: scanned {0} PowerShell files; no assignments to $IsWindows.' -f $targets.Count)
