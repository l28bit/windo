[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ExpectedBranch = 'repair/prometheus-final'

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & git -C $RepoRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ('git {0} failed with exit code {1}' -f ($Arguments -join ' '), $LASTEXITCODE)
    }
}

function Get-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $result = @(& git -C $RepoRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ('git {0} failed: {1}' -f ($Arguments -join ' '), (($result | ForEach-Object { [string]$_ }) -join '; '))
    }
    return (($result | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

if ($null -eq (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw 'git.exe is required.'
}

$branch = Get-GitText -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
if ($branch -ne $ExpectedBranch) {
    throw "Prometheus staging must run from $ExpectedBranch. Current branch: $branch"
}

$dirty = Get-GitText -Arguments @('status', '--porcelain')
if (-not [string]::IsNullOrWhiteSpace($dirty)) {
    Write-Host $dirty
    throw 'Working tree must be clean before Prometheus staging. Commit, stash, or discard unrelated changes first.'
}

Write-Host 'Refreshing repair, donor, and release refs...' -ForegroundColor Cyan
Invoke-Git -Arguments @('fetch', 'origin', 'main', $ExpectedBranch, 'Exodus')

$localHead = Get-GitText -Arguments @('rev-parse', 'HEAD')
$remoteHead = Get-GitText -Arguments @('rev-parse', ('origin/{0}' -f $ExpectedBranch))
if ($localHead -ne $remoteHead) {
    throw "Local branch is not exactly at origin/$ExpectedBranch. Run: git pull --ff-only origin $ExpectedBranch"
}

$donorPaths = @(
    'windo_install.ps1',
    'windo_runner.ps1',
    'src/windo/snippets/ChildExec.cs',
    'tools/Test-WindoLogic.ps1',
    'tools/Prometheus-RepairGeneratedArtifacts.ps1'
)

foreach ($path in $donorPaths) {
    & git -C $RepoRoot cat-file -e ("origin/main:{0}" -f $path)
    if ($LASTEXITCODE -ne 0) { throw "Donor main is missing reviewed path: $path" }
}

Write-Host ''
Write-Host 'Prometheus local staging plan:' -ForegroundColor Cyan
foreach ($path in $donorPaths) { Write-Host ('  donor main -> {0}' -f $path) }
Write-Host '  repair PowerShell 7 $IsWindows collision'
Write-Host '  regenerate ChildExec Base64 + runner + installer embedding'
Write-Host '  refresh unsigned checksum manifest for Exodus'
Write-Host '  run dual-host local pre-sign gate (Windows PowerShell 5.1 + PowerShell 7)'
Write-Host '  leave the resulting diff uncommitted for human review'

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN ONLY. No files were changed.' -ForegroundColor Yellow
    Write-Host 'When ready, rerun:' -ForegroundColor Cyan
    Write-Host '  .\tools\Invoke-PrometheusLocalStage.ps1 -Apply'
    exit 0
}

Write-Host ''
Write-Host 'Applying reviewed Prometheus donor files...' -ForegroundColor Cyan
foreach ($path in $donorPaths) {
    Invoke-Git -Arguments @('checkout', 'origin/main', '--', $path)
}

$installerPath = Join-Path $RepoRoot 'windo_install.ps1'
$installerText = [System.IO.File]::ReadAllText($installerPath)
$assignmentMatches = [regex]::Matches($installerText, '(?im)^\s*\$isWindows\s*=')
if ($assignmentMatches.Count -lt 1) {
    throw 'Expected WINDO-owned $isWindows assignment was not found in the donor installer.'
}
$updatedInstaller = [regex]::Replace($installerText, '(?i)\$isWindows\b', '$windoIsWindows')
if ($updatedInstaller -ceq $installerText) {
    throw 'PowerShell automatic-variable collision repair made no change.'
}
if ([regex]::IsMatch($updatedInstaller, '(?im)^\s*\$isWindows\s*=')) {
    throw 'Installer still assigns to $IsWindows after repair.'
}
[System.IO.File]::WriteAllText($installerPath, $updatedInstaller, (New-Object System.Text.UTF8Encoding($true)))
Write-Host 'Repaired installer $IsWindows collision and wrote explicit UTF-8 BOM.' -ForegroundColor Green

$generator = Join-Path $RepoRoot 'tools\Prometheus-RepairGeneratedArtifacts.ps1'
if (-not (Test-Path -LiteralPath $generator -PathType Leaf)) { throw "Missing generator: $generator" }
& $generator
if ($LASTEXITCODE -ne 0) { throw 'Prometheus generated-artifact repair failed.' }

$syncChecksum = Join-Path $RepoRoot 'tools\Sync-InstallerChecksum.ps1'
if (-not (Test-Path -LiteralPath $syncChecksum -PathType Leaf)) { throw "Missing checksum synchronizer: $syncChecksum" }
$oldTrackingBranch = $env:WINDO_TRACKING_BRANCH
try {
    $env:WINDO_TRACKING_BRANCH = 'Exodus'
    & $syncChecksum
    if ($LASTEXITCODE -ne 0) { throw 'Checksum manifest refresh failed.' }
}
finally {
    if ($null -eq $oldTrackingBranch) { Remove-Item Env:WINDO_TRACKING_BRANCH -ErrorAction SilentlyContinue }
    else { $env:WINDO_TRACKING_BRANCH = $oldTrackingBranch }
}

Write-Host ''
Write-Host 'Running local dual-host pre-sign gate...' -ForegroundColor Cyan
$validator = Join-Path $RepoRoot 'tools\Invoke-PrometheusLocalValidation.ps1'
& $validator -Mode PreSign
$validationExit = $LASTEXITCODE
if ($validationExit -ne 0) {
    Write-Host ''
    Write-Host 'Prometheus staging stopped on a local validation failure.' -ForegroundColor Red
    Write-Host 'The working tree was intentionally left unchanged for diagnosis.' -ForegroundColor Yellow
    Write-Host 'To discard this staging attempt (only after reviewing status): git reset --hard HEAD' -ForegroundColor DarkGray
    exit $validationExit
}

Invoke-Git -Arguments @('diff', '--check')
$status = Get-GitText -Arguments @('status', '--short')
$forbidden = @($status -split "`r?`n" | Where-Object { $_ -match '\.prometheus/' })
if ($forbidden.Count -gt 0) {
    throw ('Recovery scratch files entered the clean lane: {0}' -f ($forbidden -join '; '))
}

Write-Host ''
Write-Host 'PROMETHEUS LOCAL STAGING: PASS' -ForegroundColor Green
Write-Host 'No commit or push was performed.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Changed files:' -ForegroundColor Cyan
& git -C $RepoRoot status --short
Write-Host ''
Write-Host 'Diff summary:' -ForegroundColor Cyan
& git -C $RepoRoot diff --stat
Write-Host ''
Write-Host 'Review before committing:' -ForegroundColor Cyan
Write-Host '  git diff --check'
Write-Host '  git diff --stat'
Write-Host '  git diff -- windo_install.ps1 windo_runner.ps1 src/windo/snippets/ChildExec.cs tools/Test-WindoLogic.ps1 checksums/installer.sha256'
Write-Host ''
Write-Host 'The checksum signature is expected to remain pending until the owner signing step.' -ForegroundColor Yellow
