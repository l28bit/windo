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

function Restore-PrometheusCleanState {
    param([Parameter(Mandatory = $true)][string]$Head)

    Write-Host ''
    Write-Host 'Rolling staging attempt back to its clean starting point...' -ForegroundColor Yellow
    & git -C $RepoRoot reset --hard $Head | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Automatic rollback failed during git reset --hard.' }

    # The staging flow may create this diagnostic report. The worktree is
    # guaranteed clean before staging starts, so removing this known generated
    # path cannot discard pre-existing user work.
    & git -C $RepoRoot clean -fd -- 'docs/prometheus-generated-repair-report.md' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Automatic rollback failed while removing generated diagnostics.' }

    $remaining = Get-GitText -Arguments @('status', '--porcelain')
    if (-not [string]::IsNullOrWhiteSpace($remaining)) {
        throw "Automatic rollback did not restore a clean worktree:`n$remaining"
    }
    Write-Host 'Rollback complete; worktree is clean.' -ForegroundColor Green
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
    'tools/Test-WindoLogic.ps1'
)

foreach ($path in $donorPaths) {
    & git -C $RepoRoot cat-file -e ("origin/main:{0}" -f $path)
    if ($LASTEXITCODE -ne 0) { throw "Donor main is missing reviewed path: $path" }
}

$generator = Join-Path $RepoRoot 'tools\Prometheus-RepairGeneratedArtifacts.ps1'
if (-not (Test-Path -LiteralPath $generator -PathType Leaf)) {
    throw "Missing branch-owned Prometheus generator: $generator"
}

Write-Host ''
Write-Host 'Prometheus local staging plan:' -ForegroundColor Cyan
foreach ($path in $donorPaths) { Write-Host ('  donor main -> {0}' -f $path) }
Write-Host '  use branch-owned deterministic artifact generator'
Write-Host '  repair PowerShell 7 $IsWindows collision'
Write-Host '  regenerate ChildExec Base64 + runner + installer embedding'
Write-Host '  refresh unsigned checksum manifest for Exodus'
Write-Host '  run dual-host local pre-sign gate (Windows PowerShell 5.1 + PowerShell 7)'
Write-Host '  leave every resulting change uncommitted and unstaged for human review'
Write-Host '  automatically roll back to clean HEAD if any staging gate fails'

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN ONLY. No files were changed.' -ForegroundColor Yellow
    Write-Host 'When ready, rerun:' -ForegroundColor Cyan
    Write-Host '  .\tools\Invoke-PrometheusLocalStage.ps1 -Apply'
    exit 0
}

try {
    Write-Host ''
    Write-Host 'Applying reviewed Prometheus donor files...' -ForegroundColor Cyan
    foreach ($path in $donorPaths) {
        Invoke-Git -Arguments @('restore', '--source=origin/main', '--worktree', '--', $path)
    }

    if (-not [string]::IsNullOrWhiteSpace((Get-GitText -Arguments @('diff', '--cached', '--name-only')))) {
        throw 'Prometheus local staging unexpectedly left staged changes in the index.'
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

    if (-not [string]::IsNullOrWhiteSpace((Get-GitText -Arguments @('diff', '--cached', '--name-only')))) {
        throw 'Generated repair unexpectedly staged files. Local review must remain unstaged.'
    }

    Write-Host ''
    Write-Host 'Running local dual-host pre-sign gate...' -ForegroundColor Cyan
    $validator = Join-Path $RepoRoot 'tools\Invoke-PrometheusLocalValidation.ps1'
    $pwsh = Get-Command pwsh.exe -ErrorAction Stop
    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $validator -Mode PreSign
    $validationExit = $LASTEXITCODE
    if ($validationExit -ne 0) {
        throw "Prometheus local pre-sign validation failed with exit code $validationExit."
    }

    Invoke-Git -Arguments @('diff', '--check')
    $status = Get-GitText -Arguments @('status', '--short')
    $forbidden = @($status -split "`r?`n" | Where-Object { $_ -match '\.prometheus/' })
    if ($forbidden.Count -gt 0) {
        throw ('Recovery scratch files entered the clean lane: {0}' -f ($forbidden -join '; '))
    }
    if (-not [string]::IsNullOrWhiteSpace((Get-GitText -Arguments @('diff', '--cached', '--name-only')))) {
        throw 'Local staging finished with staged changes; refusing review handoff.'
    }

    Write-Host ''
    Write-Host 'PROMETHEUS LOCAL STAGING: PASS' -ForegroundColor Green
    Write-Host 'No commit, push, or signing operation was performed.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Changed files:' -ForegroundColor Cyan
    & git -C $RepoRoot status --short
    Write-Host ''
    Write-Host 'Diff summary:' -ForegroundColor Cyan
    & git -C $RepoRoot diff --stat
    Write-Host ''
    Write-Host 'Review before committing:' -ForegroundColor Cyan
    Write-Host '  git status --short'
    Write-Host '  git diff --check'
    Write-Host '  git diff --stat'
    Write-Host '  git diff -- windo_install.ps1 windo_runner.ps1 src/windo/snippets/ChildExec.cs tools/Test-WindoLogic.ps1 checksums/installer.sha256'
    Write-Host ''
    Write-Host 'The checksum signature is expected to remain pending until the owner signing step.' -ForegroundColor Yellow
}
catch {
    $failure = $_
    try {
        Restore-PrometheusCleanState -Head $localHead
    }
    catch {
        Write-Host ('ROLLBACK FAILURE: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }
    throw $failure
}
