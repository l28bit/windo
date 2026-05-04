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

$Temp = Join-Path $env:TEMP ("windo_install_" + [Guid]::NewGuid().ToString("n") + ".ps1")

function Write-WindoBootstrapBanner {
    Write-Host ""
    Write-Host "  __        _____ _   _ ____   ___" -ForegroundColor Cyan
    Write-Host "  \ \      / /_ _| \ | |  _ \ / _ \" -ForegroundColor Cyan
    Write-Host "   \ \ /\ / / | ||  \| | | | | | | |" -ForegroundColor Cyan
    Write-Host "    \ V  V /  | || |\  | |_| | |_| |" -ForegroundColor Cyan
    Write-Host "     \_/\_/  |___|_| \_|____/ \___/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  WINDO 3.6.5 Special Edition bootstrap" -ForegroundColor White
    Write-Host "  API-first verified download | UAC handoff | operator launchpad" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-WindoBootstrapStep {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Label,
        [string]$Detail = "",
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    $mark = switch ($Status.ToLowerInvariant()) {
        "ok" { "[OK]" }
        "warn" { "[!!]" }
        "run" { "[..]" }
        default { "[**]" }
    }
    Write-Host ("  {0} {1}" -f $mark, $Label) -ForegroundColor $Color
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host ("       {0}" -f $Detail) -ForegroundColor DarkGray
    }
}

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

function Get-WindoBootstrapInstallerRawUrl {
    "https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_install.ps1"
}

function Get-WindoBootstrapInstallerApiUrl {
    "https://api.github.com/repos/l28bit/windo/contents/windo_install.ps1?ref=Genisis"
}

function Save-WindoBootstrapPublishedInstaller {
    param([Parameter(Mandatory)][string]$OutFile)

    $apiUrl = Get-WindoBootstrapInstallerApiUrl
    try {
        $api = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 35 -ErrorAction Stop
        $obj = $api.Content | ConvertFrom-Json -ErrorAction Stop
        if ($obj.content) {
            $bytes = [Convert]::FromBase64String(([string]$obj.content -replace '\s', ''))
            [IO.File]::WriteAllBytes($OutFile, $bytes)
            return [pscustomobject]@{ Source = "github-api"; Url = $apiUrl }
        }
    } catch {
        $apiError = $_.Exception.Message
    }

    $rawUrl = Get-WindoBootstrapInstallerRawUrl
    Invoke-WindoBootstrapDownload -Uri $rawUrl -OutFile $OutFile -Label "Downloading installer via raw fallback..."
    return [pscustomobject]@{ Source = "raw-fallback"; Url = $rawUrl; ApiError = $apiError }
}

function Get-WindoBootstrapChecksumRawUrl {
    "https://raw.githubusercontent.com/l28bit/windo/Genisis/checksums/installer.sha256"
}

function Get-WindoBootstrapChecksumApiUrl {
    "https://api.github.com/repos/l28bit/windo/contents/checksums/installer.sha256?ref=Genisis"
}

function Get-WindoBootstrapPublishedChecksum {
    $apiUrl = Get-WindoBootstrapChecksumApiUrl
    try {
        $api = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
        $obj = $api.Content | ConvertFrom-Json -ErrorAction Stop
        if ($obj.content) {
            $contentText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$obj.content -replace '\s', '')))
            $m = [regex]::Match($contentText, '[A-Fa-f0-9]{64}')
            if ($m.Success) { return $m.Value.ToUpperInvariant() }
        }
    } catch {}

    $rawUrl = Get-WindoBootstrapChecksumRawUrl
    try {
        $wr = Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
        if ($null -ne $wr.Content) {
            $m = [regex]::Match([string]$wr.Content, '[A-Fa-f0-9]{64}')
            if ($m.Success) { return $m.Value.ToUpperInvariant() }
        }
    } catch {}
    return $null
}

function Start-WindoBootstrapInstaller {
    param(
        [Parameter(Mandatory)][string]$ScriptPath
    )

    $runnerExe = "powershell.exe"
    try {
        $pwshExe = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwshExe -and $pwshExe.Source) { $runnerExe = $pwshExe.Source }
    } catch {}

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    $shouldElevate = [Environment]::UserInteractive -and -not $env:CI

    if ($shouldElevate) {
        Write-Host "[windo] Requesting elevation for installer..." -ForegroundColor DarkCyan
        try {
            Start-Process -FilePath $runnerExe -Verb RunAs -ArgumentList $argList -Wait | Out-Null
            return
        } catch [System.ComponentModel.Win32Exception] {
            if ($_.Exception.NativeErrorCode -eq 1223) {
                throw "Installer elevation was canceled. Re-run bootstrap and approve the UAC prompt, or run the installer from an elevated PowerShell session."
            }
            throw
        }
    }

    Write-Host "[windo] Running installer without elevation (non-interactive or CI session)." -ForegroundColor DarkYellow
    & $runnerExe @argList
}

Write-WindoBootstrapBanner

if (Test-WindoBootstrapProcessElevated) {
    Write-Host ""
    Write-Host "WINDO bootstrap: installer is not downloaded while running as Administrator." -ForegroundColor Yellow
    Write-Host "  Open a normal (non-elevated) PowerShell window and run the bootstrap one-liner again." -ForegroundColor DarkGray
    Write-Host "  After a verified download you will be asked before the installer runs." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

try {

    Write-WindoBootstrapStep -Status run -Label "Downloading installer" -Detail "GitHub API first, raw fallback"
    $downloadSource = Save-WindoBootstrapPublishedInstaller -OutFile $Temp
    Write-WindoBootstrapStep -Status ok -Label "Installer source" -Detail "$($downloadSource.Source): $($downloadSource.Url)" -Color Green

    if (!(Test-Path $Temp)) {
        throw "Installer failed to download."
    }

    if (-not $env:WINDO_SKIP_INSTALLER_SHA256) {
        Write-WindoBootstrapStep -Status run -Label "Verifying installer checksum" -Detail "published checksums/installer.sha256 (GitHub API, raw fallback)"
        try {
            $expect = Get-WindoBootstrapPublishedChecksum
            if ($null -ne $expect) {
                $got = (Get-FileHash -Path $Temp -Algorithm SHA256).Hash.ToUpperInvariant()
                if ($got -cne $expect) {
                    throw "Installer SHA256 does not match published checksum. Set WINDO_SKIP_INSTALLER_SHA256=1 to skip. Expected=$expect Got=$got"
                }
            }
        } catch {
            if ($_.Exception.Message -match 'does not match') { throw }
        }
        Write-WindoBootstrapStep -Status ok -Label "Checksum accepted" -Color Green
    } else {
        Write-WindoBootstrapStep -Status warn -Label "Checksum verification skipped" -Detail "WINDO_SKIP_INSTALLER_SHA256 is set" -Color Yellow
    }

    $size = (Get-Item $Temp).Length
    if ($size -lt 5000) {
        throw "Installer file size looks invalid."
    }

    Write-WindoBootstrapStep -Status ok -Label "Installer ready" -Detail $Temp -Color Green
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

    Write-WindoBootstrapStep -Status run -Label "Launching installer" -Detail "UAC may prompt for elevation"
    Start-WindoBootstrapInstaller -ScriptPath $Temp

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
