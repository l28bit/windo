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

# The default completion path must live above command parsing. Register-ArgumentCompleter
# cannot faithfully impersonate the wrapped command: it loses parameter context and an
# empty result falls back to path completion. Install a TabExpansion2 wrapper instead.
$registerAnchor = 'function Register-WindoArgumentCompleter {'
if (-not $installerSource.Contains($registerAnchor)) {
    throw 'Known Register-WindoArgumentCompleter anchor was not found. Refusing an unbounded repair.'
}

if (-not $installerSource.Contains('function Register-WindoTransparentTabExpansion {')) {
    $transparentLines = @(
        'function __windo_invoke_original_tab_expansion2 {',
        '    param(',
        '        [Parameter(Mandatory = $true)][ValidateSet("ScriptInputSet", "AstInputSet")][string]$ParameterSet,',
        '        [AllowEmptyString()][string]$InputScript,',
        '        [int]$CursorColumn,',
        '        [System.Management.Automation.Language.Ast]$Ast,',
        '        [System.Management.Automation.Language.Token[]]$Tokens,',
        '        [System.Management.Automation.Language.IScriptPosition]$PositionOfCursor,',
        '        [hashtable]$Options',
        '    )',
        '    $original = $global:__WindoOriginalTabExpansion2',
        '    if ($null -eq $original) { return $null }',
        '    if ($ParameterSet -eq "AstInputSet") {',
        '        if ($null -ne $Options) { return (& $original -ast $Ast -tokens $Tokens -positionOfCursor $PositionOfCursor -options $Options) }',
        '        return (& $original -ast $Ast -tokens $Tokens -positionOfCursor $PositionOfCursor)',
        '    }',
        '    if ($null -ne $Options) { return (& $original -inputScript $InputScript -cursorColumn $CursorColumn -options $Options) }',
        '    return (& $original -inputScript $InputScript -cursorColumn $CursorColumn)',
        '}',
        '',
        'function Register-WindoTransparentTabExpansion {',
        '    $registered = Get-Variable -Name __WindoTransparentTabExpansionRegistered -Scope Global -ErrorAction SilentlyContinue',
        '    if ($null -ne $registered -and [bool]$registered.Value) { return }',
        '    $current = Get-Command TabExpansion2 -CommandType Function -ErrorAction SilentlyContinue',
        '    if ($null -eq $current -or $null -eq $current.ScriptBlock) {',
        '        Write-Warning "WINDO: TabExpansion2 not available; transparent completion skipped."',
        '        return',
        '    }',
        '',
        '    if ($null -eq (Get-Variable -Name __WindoOriginalTabExpansion2 -Scope Global -ErrorAction SilentlyContinue)) {',
        '        $global:__WindoOriginalTabExpansion2 = $current.ScriptBlock',
        '    }',
        '',
        '    function global:TabExpansion2 {',
        '        [CmdletBinding(DefaultParameterSetName = "ScriptInputSet")]',
        '        param(',
        '            [Parameter(Mandatory = $true, ParameterSetName = "ScriptInputSet", Position = 0)]',
        '            [AllowEmptyString()][string]$inputScript,',
        '            [Parameter(Mandatory = $true, ParameterSetName = "ScriptInputSet", Position = 1)]',
        '            [int]$cursorColumn,',
        '            [Parameter(Mandatory = $true, ParameterSetName = "AstInputSet", Position = 0)]',
        '            [System.Management.Automation.Language.Ast]$ast,',
        '            [Parameter(Mandatory = $true, ParameterSetName = "AstInputSet", Position = 1)]',
        '            [System.Management.Automation.Language.Token[]]$tokens,',
        '            [Parameter(Mandatory = $true, ParameterSetName = "AstInputSet", Position = 2)]',
        '            [System.Management.Automation.Language.IScriptPosition]$positionOfCursor,',
        '            [hashtable]$options',
        '        )',
        '',
        '        if ($PSCmdlet.ParameterSetName -eq "AstInputSet") {',
        '            return (__windo_invoke_original_tab_expansion2 -ParameterSet AstInputSet -Ast $ast -Tokens $tokens -PositionOfCursor $positionOfCursor -Options $options)',
        '        }',
        '',
        '        $mode = __windo_resolve_completion_mode',
        '        if ($mode -ne "native-first") {',
        '            return (__windo_invoke_original_tab_expansion2 -ParameterSet ScriptInputSet -InputScript $inputScript -CursorColumn $cursorColumn -Options $options)',
        '        }',
        '',
        '        # WINDO is a transparent prefix for completion. Only recognize WINDO as',
        '        # the first command token; do not rewrite quoted text, later pipeline',
        '        # elements, or command names that merely begin with "windo".',
        '        $prefix = [regex]::Match($inputScript, ''^(?<lead>[ \t]*)windo(?:(?<sep>[ \t]+)|$)'', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)',
        '        if (-not $prefix.Success -or $cursorColumn -lt $prefix.Length) {',
        '            return (__windo_invoke_original_tab_expansion2 -ParameterSet ScriptInputSet -InputScript $inputScript -CursorColumn $cursorColumn -Options $options)',
        '        }',
        '',
        '        $delegate = $inputScript.Substring($prefix.Length)',
        '        $delegateCursor = [Math]::Max(0, [Math]::Min($delegate.Length, ($cursorColumn - $prefix.Length)))',
        '        $completion = __windo_invoke_original_tab_expansion2 -ParameterSet ScriptInputSet -InputScript $delegate -CursorColumn $delegateCursor -Options $options',
        '        if ($null -eq $completion) { return $null }',
        '',
        '        $matches = [System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]]::new()',
        '        foreach ($match in @($completion.CompletionMatches)) { [void]$matches.Add($match) }',
        '        return [System.Management.Automation.CommandCompletion]::new(',
        '            $matches,',
        '            [int]$completion.CurrentMatchIndex,',
        '            ([int]$completion.ReplacementIndex + [int]$prefix.Length),',
        '            [int]$completion.ReplacementLength',
        '        )',
        '    }',
        '',
        '    $global:__WindoTransparentTabExpansionRegistered = $true',
        '}',
        'Register-WindoTransparentTabExpansion',
        ''
    )
    $transparentBlock = $transparentLines -join $nl
    $installerSource = $installerSource.Replace($registerAnchor, ($transparentBlock + $nl + $registerAnchor))
    Write-Host 'Inserted transparent TabExpansion2 completion layer.' -ForegroundColor Green
} else {
    Write-Host 'Transparent TabExpansion2 completion layer is already present.' -ForegroundColor Yellow
}

$oldModeGate = '            if ($mode -eq "off") { return }'
$newModeGate = '            if ($mode -eq "off" -or $mode -eq "native-first") { return }'
if ($installerSource.Contains($oldModeGate)) {
    $installerSource = $installerSource.Replace($oldModeGate, $newModeGate)
    Write-Host 'Restricted the legacy WINDO argument completer to explicit non-native modes.' -ForegroundColor Green
} elseif (-not $installerSource.Contains($newModeGate)) {
    throw 'Known completion mode gate was not found. Refusing an unbounded repair.'
}

Write-WindoUtf8Text -Path $installerPath -Content $installerSource -Bom $true

$logicSource = Get-Content -LiteralPath $logicPath -Raw
$logicNl = Get-WindoNewline $logicSource
$oldLogic = 'Assert-Equal ($installerSource.Contains(''if ($mode -eq "native-first") { return }'') -eq $false) $true "profile completer offers WINDO verbs at empty windo prefix"'
$newLogicLines = @(
    'Assert-Equal ($installerSource.Contains(''function Register-WindoTransparentTabExpansion {'') -eq $true) $true "profile installs transparent TabExpansion2 completion layer"',
    'Assert-Equal ($installerSource.Contains(''$global:__WindoOriginalTabExpansion2 = $current.ScriptBlock'') -eq $true) $true "profile preserves the pre-WINDO TabExpansion2 implementation"',
    'Assert-Equal ($installerSource.Contains(''$delegate = $inputScript.Substring($prefix.Length)'') -eq $true) $true "profile removes only the WINDO prefix before native completion"',
    'Assert-Equal ($installerSource.Contains(''([int]$completion.ReplacementIndex + [int]$prefix.Length)'') -eq $true) $true "profile remaps native replacement index by only the WINDO prefix"',
    'Assert-Equal ($installerSource.Contains(''if ($mode -eq "off" -or $mode -eq "native-first") { return }'') -eq $true) $true "legacy WINDO argument completer stays out of native-first mode"'
)
$newLogic = $newLogicLines -join $logicNl
if ($logicSource.Contains($oldLogic)) {
    $logicSource = $logicSource.Replace($oldLogic, $newLogic)
    Write-Host 'Replaced the legacy built-in completion assertion with the transparent-prefix contract.' -ForegroundColor Green
} elseif ($logicSource.Contains('profile installs transparent TabExpansion2 completion layer')) {
    Write-Host 'Transparent completion logic assertions are already present.' -ForegroundColor Yellow
} else {
    throw 'Known legacy completion assertion was not found. Refusing an unbounded test rewrite.'
}
Write-WindoUtf8Text -Path $logicPath -Content $logicSource -Bom $false

Write-Host 'Apply-WindoTransparentCompletionRepair: complete.' -ForegroundColor Green
