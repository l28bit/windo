$ErrorActionPreference = "Stop"

function Test-WindoBootstrapProcessElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = [Security.Principal.WindowsPrincipal]$id
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

$Repo = "https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_install.ps1"
$Temp = Join-Path $env:TEMP ("windo_install_" + [Guid]::NewGuid().ToString("n") + ".ps1")

function Test-WindoBootstrapSpinnerEnabled {
    if ($env:WINDO_NO_SPINNER) { return $false }
    if ($env:CI) { return $false }
    try {
        if ([Console]::IsOutputRedirected) { return $false }
    } catch {
        return $false
    }
    return $true
}

function Clear-WindoBootstrapSpinnerLine([int]$Width) {
    if (-not (Test-WindoBootstrapSpinnerEnabled)) { return }
    $w = [Math]::Max(20, [Math]::Min($Width, 120))
    [Console]::Write("`r$(' ' * $w)`r")
}

function Write-WindoBootstrapSpinnerLine([string]$Label, [int]$Frame) {
    if (-not (Test-WindoBootstrapSpinnerEnabled)) { return }
    $frames = @('|', '/', '-', '\')
    $c = $frames[$Frame % $frames.Length]
    [Console]::Write("`r${Label} ${c} ")
}

function Invoke-WindoBootstrapDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string]$Label
    )
    $baseLabel = "[windo] $Label"

    if (-not (Test-WindoBootstrapSpinnerEnabled)) {
        Write-Host $baseLabel -ForegroundColor DarkCyan
        Invoke-RestMethod -Uri $Uri -OutFile $OutFile
        return
    }

    $job = $null
    try {
        $job = Start-Job -ScriptBlock {
            param($u, $o)
            $ErrorActionPreference = "Stop"
            Invoke-RestMethod -Uri $u -OutFile $o
        } -ArgumentList $Uri, $OutFile
    } catch {
        $job = $null
    }

    if ($null -eq $job) {
        Write-Host $baseLabel -ForegroundColor DarkCyan
        Invoke-RestMethod -Uri $Uri -OutFile $OutFile
        return
    }

    $frame = 0
    while ((Get-Job -Id $job.Id -ErrorAction SilentlyContinue).State -eq "Running") {
        Write-WindoBootstrapSpinnerLine $baseLabel $frame
        $frame = ($frame + 1) % 4
        Start-Sleep -Milliseconds 100
    }

    Clear-WindoBootstrapSpinnerLine ($baseLabel.Length + 4)

    try {
        Receive-Job $job -ErrorAction Stop | Out-Null
    } catch {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        throw
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "WINDO bootstrap starting..." -ForegroundColor Cyan

if (Test-WindoBootstrapProcessElevated) {
    Write-Host ""
    Write-Host "WINDO bootstrap: installer is not downloaded while running as Administrator." -ForegroundColor Yellow
    Write-Host "  Open a normal (non-elevated) PowerShell window and run the bootstrap one-liner again." -ForegroundColor DarkGray
    Write-Host "  After a verified download you will be asked before the installer runs." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

try {

    Invoke-WindoBootstrapDownload -Uri $Repo -OutFile $Temp -Label "Downloading installer (non-elevated)..."

    if (!(Test-Path $Temp)) {
        throw "Installer failed to download."
    }

    if (-not $env:WINDO_SKIP_INSTALLER_SHA256) {
        $sumUrl = "https://raw.githubusercontent.com/l28bit/windo/Genisis/checksums/installer.sha256"
        try {
            $expect = ([string](Invoke-RestMethod -Uri $sumUrl -TimeoutSec 25)).Trim()
            if ($expect -match '^[A-Fa-f0-9]{64}$') {
                $got = (Get-FileHash -Path $Temp -Algorithm SHA256).Hash
                if ($got.ToUpperInvariant() -cne $expect.ToUpperInvariant()) {
                    throw "Installer SHA256 does not match published checksum. Set WINDO_SKIP_INSTALLER_SHA256=1 to skip. Expected=$expect Got=$got"
                }
            }
        } catch {
            if ($_.Exception.Message -match 'does not match') { throw }
        }
    }

    $size = (Get-Item $Temp).Length
    if ($size -lt 5000) {
        throw "Installer file size looks invalid."
    }

    Write-Host "[windo] Download verified. Temporary file: $Temp" -ForegroundColor Green
    $doLaunch = $false
    if ($env:WINDO_BOOTSTRAP_FORCE_INSTALL -or $env:CI) {
        $doLaunch = $true
        Write-Host "[windo] Proceeding without prompt (CI or WINDO_BOOTSTRAP_FORCE_INSTALL)." -ForegroundColor DarkGray
    } elseif ([Environment]::UserInteractive) {
        $ans = Read-Host "Launch the installer now? (UAC may prompt for elevation.) [y/N]"
        if ($ans -eq 'y' -or $ans -eq 'Y' -or $ans -eq 'yes') { $doLaunch = $true }
    } else {
        Write-Host "[windo] Non-interactive shell: set WINDO_BOOTSTRAP_FORCE_INSTALL=1 to launch after download, or run interactively." -ForegroundColor Yellow
        throw "Bootstrap: non-interactive without WINDO_BOOTSTRAP_FORCE_INSTALL"
    }

    if (-not $doLaunch) {
        Write-Host "[windo] Cancelled; removing temporary installer." -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
        exit 0
    }

    Write-Host "[windo] Launching installer..." -ForegroundColor DarkCyan
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Temp

}
catch {
    Write-Host ""
    Write-Host "WINDO bootstrap failed:" -ForegroundColor Red
    Write-Host $_
}
finally {

    if (Test-Path $Temp) {
        Remove-Item $Temp -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "Bootstrap finished." -ForegroundColor Green
}
