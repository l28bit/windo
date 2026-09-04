[CmdletBinding()]
param(
    [string]$ProbePath,
    [string]$LogicTranscriptPath,
    [string]$DeepTranscriptPath,
    [string]$ModuleOutcome = 'success',
    [string]$DpapiOutcome = 'success',
    [string]$ReleaseOutcome = 'success',
    [string]$LogicOutcome = 'success',
    [string]$AnalyzerOutcome = 'success',
    [string]$DeepOutcome = 'success',
    [int]$IssueNumber = 8
)

$ErrorActionPreference = 'Stop'

if ($IssueNumber -ne 8) {
    throw "Unknown PS5.1 baseline issue: #$IssueNumber"
}
if ($PSVersionTable.PSVersion.Major -ne 5) {
    throw "Known-baseline validator must run under Windows PowerShell 5.1; current host is $($PSVersionTable.PSVersion)."
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Known-baseline validator is Windows-only.'
}

foreach ($required in @{
    'PSScriptAnalyzer module setup' = $ModuleOutcome
    'release validation' = $ReleaseOutcome
    'PSScriptAnalyzer' = $AnalyzerOutcome
}.GetEnumerator()) {
    if ([string]$required.Value -ne 'success') {
        throw "PS5.1 baseline #8 cannot waive $($required.Key): outcome=$($required.Value)."
    }
}

$usedBaseline = $false

function Assert-KnownTranscriptFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label failed but transcript is missing: $Path"
    }

    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    $failLines = @(
        ($text -split "`r?`n") |
            Where-Object { $_ -match '^FAIL:\s+' } |
            ForEach-Object { $_.Trim() }
    )

    $allowed = @(
        '^FAIL: installer embeds the maintained uninstaller without runtime drift\b',
        '^FAIL: installer handoff rejects a path that cannot be represented safely\b',
        '^FAIL: DPAPI is available on the supported Windows host\b',
        '^FAIL: .*DPAPI fixture sealing failed\.?$'
    )

    foreach ($line in $failLines) {
        $known = $false
        foreach ($pattern in $allowed) {
            if ($line -match $pattern) {
                $known = $true
                break
            }
        }
        if (-not $known) {
            throw "$Label contains a failure outside known baseline #8: $line"
        }
    }

    if ($text -notmatch 'DPAPI fixture sealing failed') {
        throw "$Label failed without the known #8 DPAPI fixture signature. Refusing to waive it."
    }

    Write-Host "Known baseline #8 matched for $Label."
}

if ($DpapiOutcome -ne 'success') {
    $usedBaseline = $true
    if ([string]::IsNullOrWhiteSpace($ProbePath) -or -not (Test-Path -LiteralPath $ProbePath -PathType Leaf)) {
        throw 'DPAPI probe failed but its forensic probe file is unavailable.'
    }
    $probe = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ProbePath))
    if ($probe -notmatch '(?m)^DirectProtectOk=False\s*$' -or $probe -notmatch '(?m)^WindoResolverFoundType=False\s*$') {
        throw 'DPAPI failure no longer matches issue #8 fresh-process signature.'
    }
}

if ($LogicOutcome -ne 'success') {
    $usedBaseline = $true
    Assert-KnownTranscriptFailure -Path $LogicTranscriptPath -Label 'logic suite'
}

if ($DeepOutcome -ne 'success') {
    $usedBaseline = $true
    Assert-KnownTranscriptFailure -Path $DeepTranscriptPath -Label 'deep pre-sign contract'
}

if ($usedBaseline) {
    # Prove the defect is specifically missing framework assembly loading, not a
    # broader DPAPI/platform failure. This is intentionally diagnostic only; the
    # shipping runtime remains unchanged until the signed repair for issue #8.
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain = [Text.Encoding]::UTF8.GetBytes('windo-issue-8-proof')
    $sealed = [System.Security.Cryptography.ProtectedData]::Protect(
        $plain,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    if ($null -eq $sealed -or $sealed.Length -eq 0) {
        throw 'Issue #8 proof failed: DPAPI still cannot protect after explicitly loading System.Security.'
    }
    $opened = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $sealed,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    $roundTrip = [Text.Encoding]::UTF8.GetString($opened)
    if ($roundTrip -cne 'windo-issue-8-proof') {
        throw 'Issue #8 proof failed: DPAPI round-trip changed after explicit System.Security load.'
    }

    Write-Warning 'WINDO PS5.1 known baseline #8 is active: fresh-process ProtectedData resolution fails, while explicit System.Security loading restores DPAPI. No other failure family was waived.'
    Write-Host 'Tracking: https://github.com/l28bit/windo/issues/8'
} else {
    Write-Host 'PS5.1 checks are fully green; known baseline #8 was not used.'
}
