<# =====================================================================
WINDO uninstall — removes scheduled tasks, profile block, and WINDO data.

Run elevated (recommended) so scheduled tasks unregister reliably:
  powershell.exe -ExecutionPolicy Bypass -File .\windo_uninstall.ps1 -Confirm

Or interactively (script will prompt):
  .\windo_uninstall.ps1

Only the current host's $PROFILE is edited (same scope as windo_install.ps1).
If you use both Windows PowerShell 5.1 and pwsh, run this once per profile.
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

function Ensure-ProfileExists {
    if (!(Test-Path $PROFILE)) {
        $dir = Split-Path $PROFILE -Parent
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        New-Item -ItemType File -Path $PROFILE | Out-Null
    }
}

function Remove-WindoProfileBlock {
    Ensure-ProfileExists
    $text = Get-Content -Raw $PROFILE
    $pattern = [regex]::Escape($BeginMarker) + ".*?" + [regex]::Escape($EndMarker)
    if ($text -match $pattern) {
        $text = [regex]::Replace($text, $pattern, "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $text = $text -replace "(\r?\n){3,}", "`r`n`r`n"
        Write-Utf8NoBomFile -Path $PROFILE -Content ($text.TrimEnd() + "`r`n")
        Write-Host "[windo uninstall] Removed WINDO block from profile: $PROFILE" -ForegroundColor Green
    } else {
        Write-Host "[windo uninstall] No WINDO block found in profile: $PROFILE" -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "WINDO uninstall" -ForegroundColor Cyan
Write-Host "  Tasks: $TaskMain, $TaskUpdate"
Write-Host "  Profile (this host): $PROFILE"
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

Remove-WindoProfileBlock

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
