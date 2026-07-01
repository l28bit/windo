# Focused regression harness for installer banner / inline console motion.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$InstallerPath = Join-Path $Root 'windo_install.ps1'
if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "Missing installer: $InstallerPath"
}

$source = Get-Content -LiteralPath $InstallerPath -Raw

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$start = $source.IndexOf('function Test-WindoInstallerMotionEnabled', [StringComparison]::Ordinal)
$end = $source.IndexOf('function Write-WindoEditionBanner', $start, [StringComparison]::Ordinal)
Assert-True ($start -ge 0 -and $end -gt $start) 'installer motion helpers are extractable'
Invoke-Expression $source.Substring($start, $end - $start)

$bannerStart = $source.IndexOf('function Write-WindoEditionBanner', [StringComparison]::Ordinal)
$bannerEnd = $source.IndexOf('Write-WindoEditionBanner -Phase "installer"', $bannerStart, [StringComparison]::Ordinal)
Assert-True ($bannerStart -ge 0 -and $bannerEnd -gt $bannerStart) 'installer banner block is extractable'
Invoke-Expression $source.Substring($bannerStart, $bannerEnd - $bannerStart)

Assert-True ($source.Contains('function Test-WindoInstallerPsReadLineActive') -eq $true) 'installer detects PSReadLine for inline motion guard'
Assert-True ($source.Contains('function _windo_console_inline_safe') -eq $true) 'runtime defines inline console guard'
Assert-True ($source.Contains('Write-WindoInstallerPulse -Label $Label -Frames 6') -eq $false) 'install steps no longer stack pulse inline frames'

Assert-True ($source.Contains('[Console]::Out.Write($Text)') -eq $true) 'inline status uses Console.Out instead of Write-Host'

$env:WINDO_INSTALLER_VISUALS = 'on'
$env:WINDO_REDUCED_MOTION = '0'
Remove-Item Env:\CI -ErrorAction SilentlyContinue
$script:WindoInstallMotionEnabled = $null

# With PSReadLine loaded, inline motion should fail closed to static output.
Import-Module PSReadLine -ErrorAction SilentlyContinue
$script:WindoInstallMotionEnabled = $null
Assert-True ((Test-WindoInstallerPsReadLineActive) -eq $true) 'PSReadLine is active in harness'
Assert-True ((Test-WindoInstallerConsoleInlineSafe) -eq $false) 'inline motion disabled when PSReadLine is loaded'

$script:WindoInstallMotionEnabled = $null
$failures = 0
foreach ($fn in @(
        { Write-WindoInstallerPulse -Label 'pulse-smoke' -Frames 2 -DelayMs 1 },
        { Write-WindoInstallerBootLine -Text '     [sudo] smoke line' -Color DarkGray -DelayMs 1 },
        { Write-WindoInstallerTelemetrySweep },
        { Write-WindoInstallerForge -Cycles 1 }
    )) {
    try {
        & $fn
    } catch {
        $failures++
        Write-Warning $_.Exception.Message
    }
}
Assert-True ($failures -eq 0) 'banner motion helpers complete without exception under PSReadLine guard'

Write-Host 'Test-WindoBannerMotion: OK' -ForegroundColor Green
