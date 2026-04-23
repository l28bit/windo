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
    [switch]$Confirm,
    [switch]$KeepSnapshots
)

$ErrorActionPreference = "Stop"

$BeginMarker = "# >>> WINDO-BEGIN >>>"
$EndMarker   = "# <<< WINDO-END <<<"
$TaskMain    = "WindoElevatedRunner"
$TaskUpdate  = "WindoSelfUpdate"
$SecureDir   = Join-Path $HOME ".pwsh_secure"
$SnapshotDir = Join-Path (Join-Path $HOME "Documents") "windo"

function Write-Utf8NoBomFile {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
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
        return $false
    }

    try {
        $text = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
    } catch {
        Write-Warning ("Could not read profile " + $Path + ": " + $_.Exception.Message)
        return $false
    }

    $pattern = "(?ms)" + [regex]::Escape($BeginMarker) + ".*?" + [regex]::Escape($EndMarker) + "\r?\n?"
    if ($text -notmatch $pattern) {
        Write-Host "[windo uninstall] No WINDO block found in profile: $Path" -ForegroundColor DarkYellow
        return $false
    }

    $updated = [regex]::Replace($text, $pattern, "")
    $updated = $updated -replace "(\r?\n){3,}", "`r`n`r`n"
    if ([string]::IsNullOrWhiteSpace($updated)) {
        Write-Utf8NoBomFile -Path $Path -Content ""
    } else {
        Write-Utf8NoBomFile -Path $Path -Content ($updated.TrimEnd() + "`r`n")
    }
    Write-Host "[windo uninstall] Removed WINDO block from profile: $Path" -ForegroundColor Green
    return $true
}

function Remove-WindoProfileBlocks {
    $removed = 0
    foreach ($path in @(Get-WindoProfilePathList)) {
        if (Remove-WindoProfileBlockFromPath -Path $path) { $removed++ }
    }
    return $removed
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
    $choice = $Host.UI.PromptForChoice(
        "",
        "Remove WINDO tasks, profile block, and data from this user?",
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
        Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Host "[windo uninstall] Unregistered task: $tn" -ForegroundColor Green
    } catch {
        Write-Host "[windo uninstall] Task not present or could not remove: $tn" -ForegroundColor DarkYellow
    }
}

$removedProfiles = Remove-WindoProfileBlocks
Write-Host "[windo uninstall] Profile cleanup complete. Removed WINDO blocks from $removedProfiles file(s)." -ForegroundColor Cyan

if (Test-Path $SecureDir) {
    Get-ChildItem -Path $SecureDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "windo*" } | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            Write-Host "[windo uninstall] Removed: $($_.Name)" -ForegroundColor DarkGray
        } catch {
            Write-Warning "Could not remove $($_.FullName): $($_.Exception.Message)"
        }
    }
    $remaining = @(Get-ChildItem -Path $SecureDir -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        try {
            Remove-Item -Path $SecureDir -Force -ErrorAction Stop
            Write-Host "[windo uninstall] Removed empty directory: $SecureDir" -ForegroundColor Green
        } catch {
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
        Remove-Item -Path $SnapshotDir -Recurse -Force -ErrorAction Stop
        Write-Host "[windo uninstall] Removed: $SnapshotDir" -ForegroundColor Green
    } catch {
        Write-Warning "Could not remove snapshot dir: $($_.Exception.Message)"
    }
} elseif ($KeepSnapshots) {
    Write-Host "[windo uninstall] Kept Documents snapshot folder (--KeepSnapshots)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "WINDO uninstall finished. Open a new shell; 'windo' should be undefined until reinstalled." -ForegroundColor Cyan
exit 0
