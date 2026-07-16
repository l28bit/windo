<# 
WINDO Heal (standalone healer for profile/runtime recovery)
Run from normal (non-elevated) PowerShell even if your profile is broken:
  powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.pwsh_secure\windo_heal.ps1" --profile
  powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.pwsh_secure\windo_heal.ps1" --all

This script:
- Strips any (old bloated or malformed) WINDO blocks from your current-user profiles using the same repair logic as the installer.
- Writes a fresh, tiny, safe thin loader block (v3+ contract) that loads windo_runtime.ps1.
- Backs up before changes and runs syntax guard before writing.
- If runtime is missing, offers to bootstrap a full repair (will prompt for UAC if needed).
- Can launch full installer handoff for tasks/integrity.

This is the "built-in healer" surface. `windo heal` (or `windo midflightfuel`) prefers lighter lanes first.
#>

[CmdletBinding()]
param(
    [switch]$Profile,
    [switch]$All,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$HOME = $env:USERPROFILE
$SecureDir = Join-Path $HOME ".pwsh_secure"
$RuntimePath = Join-Path $SecureDir "windo_runtime.ps1"
$SnapshotDir = Join-Path (Join-Path $HOME "Documents") "windo"
$SnapshotRuntime = Join-Path $SnapshotDir "windo_runtime.ps1"

$WindoLegacyBeginMarker = "# >>> WINDO-BEGIN >>>"
$WindoLegacyEndMarker = "# <<< WINDO-END <<<"
$BeginMarker = "# [[ WINDO-BEGIN ]]"
$EndMarker = "# [[ WINDO-END ]]"
$ProfileBlockVersion = "4"

function Get-WindoProfileMarkerPairs {
    return @(
        @{ Begin = $BeginMarker; End = $EndMarker },
        @{ Begin = $WindoLegacyBeginMarker; End = $WindoLegacyEndMarker }
    )
}

function Write-Utf8NoBomFile {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and !(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $temp = Join-Path $dir (".windo_heal_tmp_" + [Guid]::NewGuid().ToString("n") + ".tmp")
    try {
        [System.IO.File]::WriteAllText($temp, $Content, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Test-ProfileSyntax {
    param([Parameter(Mandatory=$true)][string]$Content, [string]$Path = "<profile>")
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $detail = ($errors | Select-Object -First 3 | ForEach-Object { $_.Message }) -join " | "
        throw "Profile syntax validation failed for $Path : $detail"
    }
    return $true
}

function Repair-WindoProfileTextForMarkerPair {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$BlockBeginMarker,
        [Parameter(Mandatory = $true)][string]$BlockEndMarker
    )
    $anchorPattern = '(?ms)(?:^|\r?\n)(?:"\s*\r?\n|function\s+Invoke-WindoBundledUninstall\b|function\s+windo\b|\s*\$WindoVersion\s*=|\s*if\s*\(\!\(Test-Path\s+\$SecureDir\)\))'
    $beginLinePattern = '(?m)^[ \t]*' + [regex]::Escape($BlockBeginMarker) + '[ \t]*\r?$'
    $endLinePattern = '(?m)^[ \t]*' + [regex]::Escape($BlockEndMarker) + '[ \t]*\r?$'

    $firstBeginMatch = [regex]::Match($Text, $beginLinePattern)
    while ($firstBeginMatch.Success) {
        $prefix = $Text.Substring(0, $firstBeginMatch.Index)
        $matches = [regex]::Matches($prefix, $anchorPattern)
        if ($matches.Count -eq 0) { break }
        $start = $matches[$matches.Count - 1].Index
        if ($Text[$start] -eq "`r") { $start++; if ($start -lt $Text.Length -and $Text[$start] -eq "`n") { $start++ } } elseif ($Text[$start] -eq "`n") { $start++ }
        $Text = $Text.Remove($start, $firstBeginMatch.Index - $start)
        $firstBeginMatch = [regex]::Match($Text, $beginLinePattern)
    }
    $wellFormedBlockPattern = '(?ms)^[ \t]*' + [regex]::Escape($BlockBeginMarker) + '[ \t]*\r?\n.*?^[ \t]*' + [regex]::Escape($BlockEndMarker) + '[ \t]*\r?\n?'
    $Text = [regex]::Replace($Text, $wellFormedBlockPattern, '')
    $firstBeginMatch = [regex]::Match($Text, $beginLinePattern)
    $firstEndMatch = [regex]::Match($Text, $endLinePattern)
    while ($firstEndMatch.Success -and (-not $firstBeginMatch.Success -or $firstEndMatch.Index -lt $firstBeginMatch.Index)) {
        $prefix = $Text.Substring(0, $firstEndMatch.Index)
        $matches = [regex]::Matches($prefix, $anchorPattern)
        if ($matches.Count -eq 0) { break }
        $start = $matches[$matches.Count - 1].Index
        if ($Text[$start] -eq "`r") { $start++; if ($start -lt $Text.Length -and $Text[$start] -eq "`n") { $start++ } } elseif ($Text[$start] -eq "`n") { $start++ }
        $end = $firstEndMatch.Index + $firstEndMatch.Length
        if ($end -lt $Text.Length -and $Text[$end] -eq "`r") { $end++ }
        if ($end -lt $Text.Length -and $Text[$end] -eq "`n") { $end++ }
        $Text = $Text.Remove($start, $end - $start)
        $firstBeginMatch = [regex]::Match($Text, $beginLinePattern)
        $firstEndMatch = [regex]::Match($Text, $endLinePattern)
    }
    return $Text
}

function Repair-WindoProfileText {
    param([Parameter(Mandatory=$true)][string]$Text)
    foreach ($pair in (Get-WindoProfileMarkerPairs)) {
        $Text = Repair-WindoProfileTextForMarkerPair -Text $Text -BlockBeginMarker $pair.Begin -BlockEndMarker $pair.End
    }
    return ($Text -replace "(\r?\n){3,}", "`r`n`r`n")
}

function Remove-WindoProfileBlockFromPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { return $false }
    try {
        $text = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
    } catch {
        Write-Warning ("Could not read profile " + $Path + ": " + $_.Exception.Message)
        return $false
    }
    $removedAny = $false
    $updated = $text
    foreach ($pair in (Get-WindoProfileMarkerPairs)) {
        $pattern = "(?ms)" + [regex]::Escape($pair.Begin) + ".*?" + [regex]::Escape($pair.End) + "\r?\n?"
        if ($updated -match $pattern) {
            $updated = [regex]::Replace($updated, $pattern, "")
            $removedAny = $true
        }
    }
    if (-not $removedAny) { return $false }
    $updated = $updated -replace "(\r?\n){3,}", "`r`n`r`n"
    if ([string]::IsNullOrWhiteSpace($updated)) {
        Write-Utf8NoBomFile -Path $Path -Content ""
    } else {
        Write-Utf8NoBomFile -Path $Path -Content ($updated.TrimEnd() + "`r`n")
    }
    Write-Host "[windo heal] Removed old WINDO block from: $Path" -ForegroundColor Green
    return $true
}

function Get-WindoProfilePaths {
    $paths = @()
    try {
        if ($PROFILE -and $PROFILE.CurrentUserCurrentHost) { $paths += [string]$PROFILE.CurrentUserCurrentHost }
        if ($PROFILE -and $PROFILE.CurrentUserAllHosts) { $paths += [string]$PROFILE.CurrentUserAllHosts }
    } catch {}
    $paths += @(
        (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $HOME 'Documents\WindowsPowerShell\Profile.ps1')
    )
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $paths) { if ($p) { [void]$set.Add($p) } }
    return @($set)
}

function Backup-Profile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $backupRoot = Join-Path $SecureDir "profile_backups"
    if (!(Test-Path -LiteralPath $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupRoot ("Microsoft.PowerShell_profile.ps1.$stamp.heal.bak")
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    return $backupPath
}

function Write-ThinLoaderBlockToPath {
    param([Parameter(Mandatory=$true)][string]$Path, [switch]$ForceWrite)
    $thin = @"
# [[ WINDO-BEGIN ]]
# WINDO-MANAGED-BLOCK: BEGIN
# WINDO-PROFILE-BLOCK-VERSION: $ProfileBlockVersion
# WINDO-PROFILE-VERSION: 8.5.9
# WINDO-CUSTOM-PROFILE-D: $(Join-Path (Join-Path $HOME 'Documents') 'windo\profile.d')
# WINDO-CUSTOM-SECURE-PROFILE-D: $(Join-Path $SecureDir 'profile.d')
# WINDO-NOTE: Do not edit this managed block. Put custom PowerShell in profile.d. Implementation is in windo_runtime.ps1 under .pwsh_secure.
# WINDO thin loader (profile block v$ProfileBlockVersion). Real logic lives in windo_runtime.ps1 (managed, updated on install-latest).
`$__windoSecureDir = Join-Path `$HOME ".pwsh_secure"
`$__windoRuntime = Join-Path `$__windoSecureDir "windo_runtime.ps1"
`$__windoRuntimeCandidates = @(`$__windoRuntime, (Join-Path (Join-Path `$HOME "Documents") "windo\windo_runtime.ps1"))
`$__windoRuntimeLoaded = `$false
foreach (`$__windoCandidate in `$__windoRuntimeCandidates) {
    if (`$__windoRuntimeLoaded -or -not (Test-Path -LiteralPath `$__windoCandidate)) { continue }
    try {
        . `$__windoCandidate
        `$__windoRuntimeLoaded = `$true
    } catch {
        Write-Warning ("[windo] runtime load failed from " + `$__windoCandidate + ": " + `$_.Exception.Message)
    }
}
if (-not `$__windoRuntimeLoaded) { Write-Warning "[windo] WINDO runtime is missing or invalid -- run 'windo heal --profile' or 'windo install-latest' from a normal shell." }
# WINDO-MANAGED-BLOCK: END
# [[ WINDO-END ]]
"@
    $thin = $thin.Trim() + "`r`n"

    if (-not $ForceWrite) {
        if (Test-Path -LiteralPath $Path) {
            $existing = Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue
            if ($existing -and $existing -match [regex]::Escape($BeginMarker)) {
                # already has a block; caller should have removed first
            }
        }
    }

    Test-ProfileSyntax -Content $thin -Path $Path | Out-Null

    $backup = Backup-Profile -Path $Path
    if (Test-Path -LiteralPath $Path) {
        $cur = Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue
        $cur = if ($cur) { Repair-WindoProfileText -Text $cur } else { "" }
        $newText = $cur.TrimEnd() + "`r`n`r`n" + $thin
    } else {
        $dir = Split-Path -Parent $Path
        if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $newText = $thin
    }
    Test-ProfileSyntax -Content $newText -Path $Path | Out-Null
    Write-Utf8NoBomFile -Path $Path -Content $newText
    if ($backup) {
        Write-Host "[windo heal] Wrote thin loader to $Path (backup: $backup)" -ForegroundColor Green
    } else {
        Write-Host "[windo heal] Wrote thin loader to $Path" -ForegroundColor Green
    }
}

Write-Host "WINDO Heal" -ForegroundColor Cyan
Write-Host "  Secure dir: $SecureDir"
Write-Host "  Runtime   : $RuntimePath $(if (Test-Path $RuntimePath) { '(present)' } else { '(MISSING)' })"
Write-Host ""

$doProfile = $Profile -or $All -or (-not ($Profile -or $All))  # default to profile if no flags
$doAll = $All

if ($doProfile) {
    Write-Host "[windo heal] Repairing profile loader blocks (thin v$ProfileBlockVersion)..." -ForegroundColor Yellow
    $paths = Get-WindoProfilePaths
    foreach ($p in $paths) {
        if ($DryRun) {
            Write-Host "  (dry) would repair: $p" -ForegroundColor DarkGray
            continue
        }
        try {
            [void](Remove-WindoProfileBlockFromPath -Path $p)
            Write-ThinLoaderBlockToPath -Path $p -ForceWrite:$Force
        } catch {
            Write-Warning "Heal profile failed for ${p}: $($_.Exception.Message)"
        }
    }
}

if ($doAll -or -not (Test-Path $RuntimePath)) {
    Write-Host "[windo heal] Runtime check..." -ForegroundColor Yellow
    if (-not (Test-Path $RuntimePath) -and (Test-Path $SnapshotRuntime)) {
        try {
            Copy-Item $SnapshotRuntime $RuntimePath -Force
            Write-Host "[windo heal] Restored runtime from snapshot." -ForegroundColor Green
        } catch { Write-Warning "Could not restore runtime: $_" }
    }
    if (-not (Test-Path $RuntimePath)) {
        Write-Host "[windo heal] Runtime still missing. Will need a full verified installer handoff." -ForegroundColor Yellow
        if (-not $DryRun -and -not $NonInteractive) {
            $ans = Read-Host "Launch 'windo install-latest --force' now (downloads verified installer, may UAC)? [y/N]"
            if ($ans -match '^[yY]') {
                & (Join-Path $SecureDir "windo_self_update.ps1") -Force -NonInteractive:$false 2>$null | Out-Null
                # fallthrough to try install-latest via bootstrap if needed
            }
        }
    }
}

Write-Host ""
Write-Host "Next: open a *new* terminal (or . `$PROFILE), then:" -ForegroundColor Yellow
Write-Host "  windo preflight" -ForegroundColor Yellow
Write-Host "  windo version" -ForegroundColor Yellow
Write-Host "  windo heal --all   # if more repairs needed" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Rescue (always works, even with broken profile):" -ForegroundColor DarkGray
Write-Host "  iex (irm https://raw.githubusercontent.com/l28bit/windo/Exodus/bootstrap.ps1)" -ForegroundColor DarkGray

if ($global:WINDO_EXIT_CODE) { $global:WINDO_EXIT_CODE = 0 }
exit 0
