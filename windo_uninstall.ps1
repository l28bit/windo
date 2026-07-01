<# =====================================================================
WINDO uninstall — removes scheduled tasks, profile block, and WINDO data.

Run elevated (recommended) so scheduled tasks unregister reliably:
  powershell.exe -ExecutionPolicy Bypass -File .\windo_uninstall.ps1 -Confirm

Or interactively (script will prompt):
  .\windo_uninstall.ps1

Removes WINDO marker blocks from known current-user PowerShell profiles
(pwsh and Windows PowerShell) without touching all-users profiles.
===================================================================== #>

param(
    [Alias("Force")]
    [switch]$Confirm,
    [switch]$KeepSnapshots
)

$ErrorActionPreference = "Stop"

$WindoLegacyBeginMarker = "# >>> WINDO-BEGIN >>>"
$WindoLegacyEndMarker   = "# <<< WINDO-END <<<"
$BeginMarker = "# [[ WINDO-BEGIN ]]"
$EndMarker   = "# [[ WINDO-END ]]"
$TaskMain    = "WindoElevatedRunner"
$TaskUpdate  = "WindoSelfUpdate"
$SecureDir   = Join-Path $HOME ".pwsh_secure"
$SnapshotDir = Join-Path (Join-Path $HOME "Documents") "windo"
$TempRoot = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { [System.IO.Path]::GetTempPath() } else { $env:TEMP }
$BackupRoot = Join-Path $TempRoot ("windo-uninstall-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$CleanupSummary = [ordered]@{
    TaskRemoved            = 0
    TaskMissing            = 0
    TaskFailed             = 0
    ProfileScanned         = 0
    ProfileBlocksRemoved   = 0
    ProfileBlocksMissing    = 0
    ProfileBackupFailures   = 0
    SecureFilesFound       = 0
    SecureFilesRemoved     = 0
    SecureFilesBackupFails = 0
    SecureDirRemoved       = $false
    SnapshotKept           = $false
    SnapshotBackupCreated  = $false
    SnapshotRemoved        = $false
    SnapshotFailed         = $false
    FailureCount           = 0
    FailureItems           = [System.Collections.Generic.List[string]]::new()
}

function Write-Utf8NoBomFile {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    Write-TextFileAtomic -Path $Path -Content $Content -Encoding $utf8NoBom
}

function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter()][System.Text.Encoding]$Encoding = (New-Object System.Text.UTF8Encoding($false))
    )
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and !(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = Join-Path $dir (".windo_tmp_" + [Guid]::NewGuid().ToString("n") + ".tmp")
    try {
        [System.IO.File]::WriteAllText($tmp, $Content, $Encoding)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Register-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:CleanupSummary.FailureCount++
    $script:CleanupSummary.FailureItems.Add($Message)
    Write-Warning $Message
}

function Unregister-WindoScheduledTask {
    param([Parameter(Mandatory=$true)][string]$TaskName)
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop | Out-Null
}

function Convert-ToBackupPath {
    param([Parameter(Mandatory = $true)][string]$SourcePath)
    $safe = $SourcePath -replace ":", "" -replace "[\\/]", "__"
    return (Join-Path $script:BackupRoot $safe)
}

function New-BackupParent {
    if (-not (Test-Path -LiteralPath $script:BackupRoot)) {
        New-Item -Path $script:BackupRoot -ItemType Directory -Force | Out-Null
    }
}

function Backup-ForRollback {
    param([Parameter(Mandatory = $true)][string]$SourcePath)

    try {
        if (-not (Test-Path -LiteralPath $SourcePath)) {
            return $null
        }

        New-BackupParent
        $target = Convert-ToBackupPath -SourcePath $SourcePath
        $targetParent = Split-Path -Path $target -Parent
        if (-not (Test-Path -LiteralPath $targetParent)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }

        Copy-Item -LiteralPath $SourcePath -Destination $target -Recurse -Force -ErrorAction Stop
        return $target
    } catch {
        return $null
    }
}

function Get-WindoProfilePathList {
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $addOne = {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        try {
            $full = [System.IO.Path]::GetFullPath($Path)
            [void]$set.Add($full)
        } catch { }
    }

    try {
        if ($PROFILE) {
            & $addOne $PROFILE.CurrentUserCurrentHost
            & $addOne $PROFILE.CurrentUserAllHosts
        }
    } catch {
        & $addOne ([string]$PROFILE)
    }

    foreach ($candidate in @(
        (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $HOME 'Documents\PowerShell\Profile.ps1'),
        (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $HOME 'Documents\WindowsPowerShell\Profile.ps1')
    )) {
        & $addOne $candidate
    }

    return @($set)
}

function Remove-WindoProfileBlockFromPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        Write-Host "[windo uninstall] Profile not present: $Path" -ForegroundColor DarkGray
        if ($null -ne $script:CleanupSummary -and $script:CleanupSummary.PSObject.Properties.Name -contains "ProfileScanned") { $script:CleanupSummary.ProfileScanned++ }
        return $false
    }
    if ($null -ne $script:CleanupSummary -and $script:CleanupSummary.PSObject.Properties.Name -contains "ProfileScanned") { $script:CleanupSummary.ProfileScanned++ }

    try {
        $text = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
    } catch {
        Write-Warning ("Could not read profile " + $Path + ": " + $_.Exception.Message)
        Register-Failure ("Could not read profile for cleanup: " + $Path)
        return $false
    }

    $removedAny = $false
    $updated = $text
    foreach ($pair in @(
            @{ Begin = $BeginMarker; End = $EndMarker },
            @{ Begin = $WindoLegacyBeginMarker; End = $WindoLegacyEndMarker }
        )) {
        $pattern = "(?ms)" + [regex]::Escape($pair.Begin) + ".*?" + [regex]::Escape($pair.End) + "\r?\n?"
        if ($updated -match $pattern) {
            $updated = [regex]::Replace($updated, $pattern, "")
            $removedAny = $true
        }
    }
    if (-not $removedAny) {
        Write-Host "[windo uninstall] No WINDO block found in profile: $Path" -ForegroundColor DarkYellow
        if ($null -ne $script:CleanupSummary -and $script:CleanupSummary.PSObject.Properties.Name -contains "ProfileBlocksMissing") { $script:CleanupSummary.ProfileBlocksMissing++ }
        return $false
    }

    $hasRollback = $false
    $backupPath = $null
    try {
        $hasRollback = [bool](Get-Command Backup-ForRollback -CommandType Function -ErrorAction Stop)
    } catch { $hasRollback = $false }

    if ($hasRollback) {
        $backupPath = Backup-ForRollback -SourcePath $Path
        if (-not $backupPath) {
            if ($null -ne $script:CleanupSummary -and $script:CleanupSummary.PSObject.Properties.Name -contains "ProfileBackupFailures") { $script:CleanupSummary.ProfileBackupFailures++ }
            Register-Failure ("Could not back up profile before cleanup: " + $Path)
            return $false
        }
    }

    $updated = $updated -replace "(\r?\n){3,}", "`r`n`r`n"
    if ([string]::IsNullOrWhiteSpace($updated)) {
        if (Get-Command Write-Utf8NoBomFile -CommandType Function -ErrorAction SilentlyContinue) {
            Write-Utf8NoBomFile -Path $Path -Content ""
        } else {
            [System.IO.File]::WriteAllText($Path, "", [Text.UTF8Encoding]::new($false))
        }
    } else {
        if (Get-Command Write-Utf8NoBomFile -CommandType Function -ErrorAction SilentlyContinue) {
            Write-Utf8NoBomFile -Path $Path -Content ($updated.TrimEnd() + "`r`n")
        } else {
            [System.IO.File]::WriteAllText($Path, ($updated.TrimEnd() + "`r`n"), [Text.UTF8Encoding]::new($false))
        }
    }
    Write-Host "[windo uninstall] Removed WINDO block from profile: $Path" -ForegroundColor Green
    if ($hasRollback) {
        Write-Host "[windo uninstall] Backed up profile to: $backupPath" -ForegroundColor DarkGray
    }
    if ($null -ne $script:CleanupSummary -and $script:CleanupSummary.PSObject.Properties.Name -contains "ProfileBlocksRemoved") { $script:CleanupSummary.ProfileBlocksRemoved++ }
    return $true
}

function Remove-WindoProfileBlocks {
    $removed = 0
    foreach ($path in @(Get-WindoProfilePathList)) {
        if (Remove-WindoProfileBlockFromPath -Path $path) { $removed++ }
    }
    return $removed
}

function Write-CleanupSummary {
    Write-Host ""
    Write-Host "Cleanup summary:" -ForegroundColor Cyan
    Write-Host "  Tasks: removed $($script:CleanupSummary.TaskRemoved), missing $($script:CleanupSummary.TaskMissing), failed $($script:CleanupSummary.TaskFailed)"
    Write-Host "  Profiles: scanned $($script:CleanupSummary.ProfileScanned), blocks removed $($script:CleanupSummary.ProfileBlocksRemoved), blocks missing $($script:CleanupSummary.ProfileBlocksMissing)"
    Write-Host "  Secure files: found $($script:CleanupSummary.SecureFilesFound), removed $($script:CleanupSummary.SecureFilesRemoved), backup failures $($script:CleanupSummary.SecureFilesBackupFails)"
    Write-Host "  Secure directory removed: $($script:CleanupSummary.SecureDirRemoved)"
    Write-Host "  Snapshot folder removed: $($script:CleanupSummary.SnapshotRemoved), kept: $($script:CleanupSummary.SnapshotKept), backup created: $($script:CleanupSummary.SnapshotBackupCreated)"

    if (Test-Path -LiteralPath $script:BackupRoot) {
        Write-Host ("  Rollback backup location: " + $script:BackupRoot) -ForegroundColor DarkGray
    } else {
        Write-Host "  Rollback backup location: not created (nothing removed)"
    }

    if ($script:CleanupSummary.FailureCount -gt 0) {
        Write-Host ""
        Write-Host ("Cleanup had " + $script:CleanupSummary.FailureCount + " failure(s):") -ForegroundColor Yellow
        foreach ($failure in $script:CleanupSummary.FailureItems) {
            Write-Host ("  - " + $failure) -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "WINDO uninstall" -ForegroundColor Cyan
Write-Host "  Tasks: $TaskMain, $TaskUpdate"
Write-Host "  Profiles (current user):"
foreach ($profilePath in @(Get-WindoProfilePathList)) {
    Write-Host "    $profilePath"
}
Write-Host "  Secure dir: $SecureDir"
Write-Host "  Documents snapshot: $SnapshotDir $(if ($KeepSnapshots) { '(keeping)' } else { '(removing)' })"
Write-Host ""

if (-not $Confirm) {
    Write-Host ""
    Write-Host "Planned changes:" -ForegroundColor Cyan
    Write-Host "  - Remove user scheduled tasks: $TaskMain, $TaskUpdate"
    Write-Host "  - Remove WINDO profile blocks from current-user profiles"
    Write-Host "  - Remove WINDO files from: $SecureDir"
    Write-Host "  - Remove snapshot directory: $SnapshotDir $(if ($KeepSnapshots) { '(kept)' } else { '(removed)' })"
    Write-Host "  - Create rollback backup copies in temp before each deletion"
    Write-Host ""
    $choice = $Host.UI.PromptForChoice(
        "",
        "Remove WINDO artifacts for current user?",
        @("&Yes", "&No"),
        1
    )
    if ($choice -ne 0) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

foreach ($tn in @($TaskMain, $TaskUpdate)) {
    try {
        Unregister-WindoScheduledTask -TaskName $tn
        Write-Host "[windo uninstall] Unregistered task: $tn" -ForegroundColor Green
        $CleanupSummary.TaskRemoved++
    } catch {
        if ($_.Exception.Message -match "Cannot find" -or $_.CategoryInfo.Reason -eq "Microsoft.Management.Infrastructure.CimException") {
            Write-Host "[windo uninstall] Task not present: $tn" -ForegroundColor DarkYellow
            $CleanupSummary.TaskMissing++
        } else {
            Register-Failure ("Could not unregister task '" + $tn + "': " + $_.Exception.Message)
            $CleanupSummary.TaskFailed++
            Write-Host "[windo uninstall] Task removal failed: $tn" -ForegroundColor Red
        }
    }
}

$removedProfiles = Remove-WindoProfileBlocks
Write-Host "[windo uninstall] Profile cleanup complete. Removed WINDO blocks from $removedProfiles file(s)." -ForegroundColor Cyan

if (Test-Path $SecureDir) {
    Get-ChildItem -Path $SecureDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "windo*" } | ForEach-Object {
        $CleanupSummary.SecureFilesFound++
        $source = $_.FullName
        $backupPath = Backup-ForRollback -SourcePath $source
        if (-not $backupPath) {
            Register-Failure ("Could not back up secure file before cleanup: " + $source)
            $CleanupSummary.SecureFilesBackupFails++
            return
        }
        try {
            Remove-Item -LiteralPath $source -Force -ErrorAction Stop
            Write-Host "[windo uninstall] Removed secure file: $source" -ForegroundColor DarkGray
            Write-Host "[windo uninstall] Backed up secure file to: $backupPath" -ForegroundColor DarkGray
            $CleanupSummary.SecureFilesRemoved++
        } catch {
            Register-Failure ("Could not remove secure file '" + $source + "': " + $_.Exception.Message)
            Write-Warning ("Could not remove " + $source + ": " + $_.Exception.Message)
        }
    }
    $remaining = @(Get-ChildItem -Path $SecureDir -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        try {
            Remove-Item -Path $SecureDir -Force -ErrorAction Stop
            Write-Host "[windo uninstall] Removed empty directory: $SecureDir" -ForegroundColor Green
            $CleanupSummary.SecureDirRemoved = $true
        } catch {
            Register-Failure ("Could not remove secure directory '" + $SecureDir + "': " + $_.Exception.Message)
            Write-Warning "Could not remove directory $SecureDir : $($_.Exception.Message)"
        }
    } else {
        $nonWindo = $remaining | Where-Object { $_.Name -notlike "windo*" }
        if ($nonWindo.Count -gt 0) {
            Write-Host "[windo uninstall] Secure dir still contains non-WINDO items; left in place: $SecureDir" -ForegroundColor Yellow
        }
    }
}

if (-not $KeepSnapshots -and (Test-Path $SnapshotDir)) {
    try {
        $snapshotBackup = Backup-ForRollback -SourcePath $SnapshotDir
        if (-not $snapshotBackup) {
            Register-Failure ("Could not back up snapshot folder before cleanup: " + $SnapshotDir)
            $CleanupSummary.SnapshotFailed = $true
            throw "Snapshot backup failed"
        }
        $CleanupSummary.SnapshotBackupCreated = $true
        Remove-Item -Path $SnapshotDir -Recurse -Force -ErrorAction Stop
        Write-Host "[windo uninstall] Removed: $SnapshotDir" -ForegroundColor Green
        Write-Host "[windo uninstall] Backed up snapshots to: $snapshotBackup" -ForegroundColor DarkGray
        $CleanupSummary.SnapshotRemoved = $true
    } catch {
        $CleanupSummary.SnapshotFailed = $true
        Register-Failure ("Could not remove snapshot directory '" + $SnapshotDir + "': " + $_.Exception.Message)
        Write-Warning "Could not remove snapshot dir: $($_.Exception.Message)"
    }
} elseif ($KeepSnapshots) {
    Write-Host "[windo uninstall] Kept Documents snapshot folder (--KeepSnapshots)." -ForegroundColor DarkGray
    $CleanupSummary.SnapshotKept = $true
}

Write-Host ""
Write-CleanupSummary

if ($CleanupSummary.FailureCount -eq 0) {
    Write-Host "WINDO uninstall finished. Open a new shell; 'windo' should be undefined until reinstalled." -ForegroundColor Cyan
    exit 0
}

Write-Host "WINDO uninstall finished with partial failure. Review above items before continuing." -ForegroundColor Yellow
exit 1
