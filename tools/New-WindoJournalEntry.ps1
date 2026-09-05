[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Title,
    [Parameter(Mandatory = $true)][ValidateSet('decision','experiment','incident','architecture','release','security','tooling','process')][string]$Category,
    [Parameter(Mandatory = $true)][ValidateSet('proposed','active','validated','resolved','superseded')][string]$Status,
    [string]$Related,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Context,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Evidence,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Alternatives,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Decision,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Result,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$FollowUp,
    [string]$EntryId,
    [string]$OutputDirectory = 'docs/engineer-journal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-Slug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $normalized = $Value.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -eq [Globalization.UnicodeCategory]::NonSpacingMark) { continue }
        if ([char]::IsLetterOrDigit($char)) {
            [void]$builder.Append([char]::ToLowerInvariant($char))
        } else {
            [void]$builder.Append('-')
        }
    }
    $slug = ([regex]::Replace($builder.ToString(), '-+', '-')).Trim('-')
    if ($slug.Length -gt 64) { $slug = $slug.Substring(0, 64).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'entry' }
    return $slug
}

function ConvertTo-Bullets {
    param([Parameter(Mandatory = $true)][string]$Value)
    $items = @($Value.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($items.Count -eq 0) { return @('- None recorded.') }
    return @($items | ForEach-Object { '- ' + $_ })
}

$root = Split-Path -Parent $PSScriptRoot
$outputRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
} else {
    Join-Path $root $OutputDirectory
}
if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}

$date = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
$slug = ConvertTo-Slug -Value $Title
$idSuffix = ''
if (-not [string]::IsNullOrWhiteSpace($EntryId)) {
    $safeId = ([regex]::Replace($EntryId, '[^A-Za-z0-9._-]+', '-')).Trim('-')
    if ($safeId) { $idSuffix = '-' + $safeId }
}
$fileName = "$date-$slug$idSuffix.md"
$path = Join-Path $outputRoot $fileName
if (Test-Path -LiteralPath $path) {
    throw "Refusing to overwrite existing Engineer Journal entry: $path"
}

$relatedText = if ([string]::IsNullOrWhiteSpace($Related)) { 'None recorded.' } else { $Related.Trim() }
$lines = @(
    "# $date — $($Title.Trim())",
    '',
    "**Category:** $Category  ",
    "**Status:** $Status  ",
    "**Related:** $relatedText",
    '',
    '### Context / question',
    '',
    $Context.Trim(),
    '',
    '### Evidence / observations',
    '',
    $Evidence.Trim(),
    '',
    '### Alternatives considered',
    ''
)
$lines += ConvertTo-Bullets -Value $Alternatives
$lines += @(
    '',
    '### Decision / hypothesis',
    '',
    $Decision.Trim(),
    '',
    '### Result',
    '',
    $Result.Trim(),
    '',
    '### Follow-up',
    ''
)
$lines += ConvertTo-Bullets -Value $FollowUp
$lines += ''

$text = ($lines -join "`n")
[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))

$required = @(
    '### Context / question',
    '### Evidence / observations',
    '### Alternatives considered',
    '### Decision / hypothesis',
    '### Result',
    '### Follow-up'
)
$written = [IO.File]::ReadAllText($path)
foreach ($heading in $required) {
    if (-not $written.Contains($heading)) {
        throw "Generated Engineer Journal entry is missing required heading: $heading"
    }
}

[pscustomobject]@{
    Path = $path
    RelativePath = ('docs/engineer-journal/' + $fileName)
    FileName = $fileName
}
