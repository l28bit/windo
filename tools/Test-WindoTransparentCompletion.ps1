$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$installerPath = Join-Path $root 'windo_install.ps1'
$installerSource = Get-Content -LiteralPath $installerPath -Raw

function Get-WindoVisibleCompletionText {
    param([AllowNull()][object[]]$Matches)
    return @(
        @($Matches) |
            Where-Object { -not ([string]::IsNullOrEmpty([string]$_.CompletionText) -and [string]::IsNullOrEmpty([string]$_.ListItemText)) } |
            ForEach-Object { [string]$_.CompletionText } |
            Sort-Object -Unique
    )
}

function Assert-WindoCompletionParity {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$NativeLine,
        [Parameter(Mandatory = $true)][int]$NativeCursor,
        [Parameter(Mandatory = $true)][string]$Case
    )

    $prefix = 'windo '
    $native = TabExpansion2 -inputScript $NativeLine -cursorColumn $NativeCursor
    $wrappedLine = $prefix + $NativeLine
    $wrapped = TabExpansion2 -inputScript $wrappedLine -cursorColumn ($NativeCursor + $prefix.Length)

    $nativeText = @(Get-WindoVisibleCompletionText -Matches @($native.CompletionMatches))
    $wrappedText = @(Get-WindoVisibleCompletionText -Matches @($wrapped.CompletionMatches))

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

$blockPattern = '(?s)\$WindoCompleterBlock\s*=\s*@''\r?\n(?<body>.*?)\r?\n''@\r?\n\$WindoCompleterBlock\s*=\s*\$WindoCompleterBlock\.Replace'
$blockMatch = [regex]::Match($installerSource, $blockPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $blockMatch.Success) {
    throw 'FAIL: unable to extract shipping WINDO completer block from installer.'
}

$completerBlock = $blockMatch.Groups['body'].Value.Replace('__WINDO_BUILTIN_ARRAY__', "'help','doctor','completion'")

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

    # Establish whether normal command text can be transparent before separately
    # testing the empty-position fallback behavior of Register-ArgumentCompleter.
    Assert-WindoCompletionParity -NativeLine 'Get-Chi' -NativeCursor 7 -Case 'command discovery'
    Assert-WindoCompletionParity -NativeLine 'Get-ChildItem -Fi' -NativeCursor 17 -Case 'parameter completion'

    $midLine = 'Get-ChildItem -Fi -Path .'
    Assert-WindoCompletionParity -NativeLine $midLine -NativeCursor 17 -Case 'mid-line cursor completion'

    Assert-WindoCompletionParity -NativeLine 'Get-ChildItem -Path ".\\"' -NativeCursor 24 -Case 'quoted path completion'

    Assert-WindoCompletionParity -NativeLine '' -NativeCursor 0 -Case 'empty command position'
} finally {
    if ($null -eq $oldMode) { Remove-Item Env:\WINDO_COMPLETION_MODE -ErrorAction SilentlyContinue }
    else { $env:WINDO_COMPLETION_MODE = $oldMode }

    if ($hadOldFlag) { $global:__WindoArgCompleterRegistered = $oldFlag }
    else { Remove-Variable -Name __WindoArgCompleterRegistered -Scope Global -ErrorAction SilentlyContinue }
    Remove-Item Function:\windo -ErrorAction SilentlyContinue
}

Write-Host 'PASS: WINDO completion is transparent to native PowerShell completion.' -ForegroundColor Green
