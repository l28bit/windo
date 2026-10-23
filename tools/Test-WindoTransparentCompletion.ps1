$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$installerPath = Join-Path $root 'windo_install.ps1'
$installerSource = Get-Content -LiteralPath $installerPath -Raw

function Assert-WindoCompletionParity {
    param(
        [Parameter(Mandatory = $true)][string]$NativeLine,
        [Parameter(Mandatory = $true)][int]$NativeCursor,
        [Parameter(Mandatory = $true)][string]$Case
    )

    $prefix = 'windo '
    $native = TabExpansion2 -inputScript $NativeLine -cursorColumn $NativeCursor
    $wrappedLine = $prefix + $NativeLine
    $wrapped = TabExpansion2 -inputScript $wrappedLine -cursorColumn ($NativeCursor + $prefix.Length)

    $nativeText = @($native.CompletionMatches | ForEach-Object { [string]$_.CompletionText } | Sort-Object -Unique)
    $wrappedText = @($wrapped.CompletionMatches | ForEach-Object { [string]$_.CompletionText } | Sort-Object -Unique)

    $nativeJoined = $nativeText -join "`n"
    $wrappedJoined = $wrappedText -join "`n"
    if ($nativeJoined -ne $wrappedJoined) {
        throw "FAIL: $Case completion set differs after WINDO prefix.`nNATIVE:`n$nativeJoined`nWINDO:`n$wrappedJoined"
    }

    if ([int]$wrapped.ReplacementIndex -ne ([int]$native.ReplacementIndex + $prefix.Length)) {
        throw "FAIL: $Case replacement index differs. native=$($native.ReplacementIndex) windo=$($wrapped.ReplacementIndex) expected=$([int]$native.ReplacementIndex + $prefix.Length)"
    }
    if ([int]$wrapped.ReplacementLength -ne [int]$native.ReplacementLength) {
        throw "FAIL: $Case replacement length differs. native=$($native.ReplacementLength) windo=$($wrapped.ReplacementLength)"
    }

    Write-Host "PASS: $Case" -ForegroundColor Green
}

# The shipping completer is generated into windo_runtime.ps1 from this installer block.
$blockPattern = '(?s)\$WindoCompleterBlock\s*=\s*@''\r?\n(?<body>.*?)\r?\n''@\r?\n\$WindoCompleterBlock\s*=\s*\$WindoCompleterBlock\.Replace'
$blockMatch = [regex]::Match($installerSource, $blockPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $blockMatch.Success) {
    throw 'FAIL: unable to extract shipping WINDO completer block from installer.'
}

$completerBlock = $blockMatch.Groups['body'].Value.Replace('__WINDO_BUILTIN_ARRAY__', "'help','doctor','completion'")

# Completion happens before invocation, so this function only needs to expose the
# same command shape that the installed runtime exposes.
function global:windo {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Command
    )
}

$oldMode = $env:WINDO_COMPLETION_MODE
$oldFlagVariable = Get-Variable -Name __WindoArgCompleterRegistered -Scope Global -ErrorAction SilentlyContinue
$hadOldFlag = $null -ne $oldFlagVariable
$oldFlag = if ($hadOldFlag) { [bool]$oldFlagVariable.Value } else { $false }
try {
    $env:WINDO_COMPLETION_MODE = 'native-first'
    $global:__WindoArgCompleterRegistered = $false
    Invoke-Expression $completerBlock

    # Empty-prefix behavior is part of the contract. WINDO must not inject its own
    # namespace into a command position that otherwise belongs to PowerShell.
    Assert-WindoCompletionParity -NativeLine '' -NativeCursor 0 -Case 'empty command position'

    # Command discovery must remain native.
    Assert-WindoCompletionParity -NativeLine 'Get-Chi' -NativeCursor 7 -Case 'command discovery'

    # Cmdlet parameter completion must remain native.
    Assert-WindoCompletionParity -NativeLine 'Get-ChildItem -Fi' -NativeCursor 17 -Case 'parameter completion'

    # Completion must honor the actual cursor position rather than assuming the
    # cursor is at the end of the line.
    $midLine = 'Get-ChildItem -Fi -Path .'
    Assert-WindoCompletionParity -NativeLine $midLine -NativeCursor 17 -Case 'mid-line cursor completion'

    # Quoted/provider path completion must remain native too.
    Assert-WindoCompletionParity -NativeLine 'Get-ChildItem -Path ".\\"' -NativeCursor 24 -Case 'quoted path completion'
} finally {
    if ($null -eq $oldMode) { Remove-Item Env:\WINDO_COMPLETION_MODE -ErrorAction SilentlyContinue }
    else { $env:WINDO_COMPLETION_MODE = $oldMode }

    if ($hadOldFlag) { $global:__WindoArgCompleterRegistered = $oldFlag }
    else { Remove-Variable -Name __WindoArgCompleterRegistered -Scope Global -ErrorAction SilentlyContinue }
    Remove-Item Function:\windo -ErrorAction SilentlyContinue
}

Write-Host 'PASS: WINDO completion is transparent to native PowerShell completion.' -ForegroundColor Green
