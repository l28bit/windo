$ErrorActionPreference = 'Stop'
$installerSource = Get-Content -Path 'windo_install.ps1' -Raw
function Get-WindoFunctionTextFromSource([string]$Source, [string]$Name) {
    try {
        $sources = @($Source)
        $matches = [regex]::Matches($Source, '(?s)\$WindoFunctionBody\s*=\s*@''\s*(.*?)\r?\n''@', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($m in $matches) {
            if ($m.Success -and -not [string]::IsNullOrWhiteSpace($m.Groups[1].Value)) {
                $sources += $m.Groups[1].Value
            }
        }

        foreach ($candidate in $sources) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($candidate, [ref]$null, [ref]$errors)
            $matches = $ast.FindAll(
                { param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name },
                $true
            )
            if ($matches -and $matches.Count -gt 0) { return $matches[0].Extent.Text }

            $escapedName = [regex]::Escape($Name)
            $fnPattern = "(?ms)^\s*function\s+$escapedName(?:\s*\([^{}]*\))?\s*\{"
            $m2 = [regex]::Match($candidate, $fnPattern)
            if ($m2.Success) {
                $tail = $candidate.Substring($m2.Index)
                $tailErrors = $null
                $tailAst = [System.Management.Automation.Language.Parser]::ParseInput($tail, [ref]$null, [ref]$tailErrors)
                $tailMatches = $tailAst.FindAll(
                    { param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name },
                    $true
                )
                if ($tailMatches -and $tailMatches.Count -gt 0) { return $tailMatches[0].Extent.Text }

                $start = $m2.Index
                $depth = 0
                $end = -1
                for ($i = $m2.Index + $m2.Length - 1; $i -lt $candidate.Length; $i++) {
                    $char = $candidate[$i]
                    if ($char -eq '{') { $depth++ }
                    elseif ($char -eq '}') {
                        $depth--
                        if ($depth -eq 0) {
                            $end = $i
                            break
                        }
                    }
                }
                if ($end -ge $start) {
                    return $candidate.Substring($start, $end - $start + 1)
                }
            }
        }
    } catch {
        return $null
    }
    return $null
}

$writeTextFileAtomicFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name 'Write-TextFileAtomic'
$controlRootFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name '_windo_control_root'
$controlQueueRootFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name '_windo_control_queue_root'
$controlQueueActionFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name '_windo_control_queue_action'
$controlStartActionFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name '_windo_control_start_action'
if (-not ($writeTextFileAtomicFn -and $controlRootFn -and $controlQueueRootFn -and $controlQueueActionFn -and $controlStartActionFn)) {
    throw ('missing function extraction: ' + [int]([bool]$writeTextFileAtomicFn) + [int]([bool]$controlRootFn) + [int]([bool]$controlQueueRootFn) + [int]([bool]$controlQueueActionFn) + [int]([bool]$controlStartActionFn))
}
Invoke-Expression $writeTextFileAtomicFn
Invoke-Expression $controlRootFn
Invoke-Expression $controlQueueRootFn
Invoke-Expression $controlQueueActionFn
Invoke-Expression $controlStartActionFn

$SecureDir = Join-Path ([IO.Path]::GetTempPath()) ('windo-test-control-' + [Guid]::NewGuid().ToString('N'))
function _windo_control_get_action { param([string]$Id); return [pscustomobject]@{ id = [string]$Id; command = 'exit 11'; title = 'x'; execution = 'visible-shell' } }
function Start-Process {
    param([string]$FilePath, [string[]]$ArgumentList, [switch]$PassThru, [switch]$NoNewWindow)
    return New-Object PSObject
}

$script:controlStartActionExit = _windo_control_start_action 'upgrade-history-open'
$script:controlStartActionExit | Format-List *
