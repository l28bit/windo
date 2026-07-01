# Regression harness for the static carrot-free installer plate banner.
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

$start = $source.IndexOf('function Get-WindoEditionLabel', [StringComparison]::Ordinal)
$end = $source.IndexOf('Write-WindoEditionBanner -Phase "installer"', [StringComparison]::Ordinal)
Assert-True ($start -ge 0 -and $end -gt $start) 'installer banner helpers are extractable'
Invoke-Expression $source.Substring($start, $end - $start)

Assert-True ($source.Contains('function Write-WindoInstallerPlateLine') -eq $true) 'installer uses plate banner lines'
Assert-True ($source.Contains('function Write-WindoInstallerPulse') -eq $false) 'legacy pulse banner removed'
Assert-True ($source.Contains('function Write-WindoInstallerBootLine') -eq $false) 'legacy boot-line transfer removed'
Assert-True ($source.Contains('windo do -- [command]') -eq $true) 'banner example uses bracket placeholder not carrots'
Assert-True ($source.Contains('sudo -> consent') -eq $false) 'banner flow line avoids carrot arrows'

$WindoVersion = '8.5.9'
$env:WINDO_INSTALLER_VISUALS = 'on'
Remove-Item Env:CI -ErrorAction SilentlyContinue
Remove-Item Env:WINDO_NO_SPINNER -ErrorAction SilentlyContinue
Write-WindoEditionBanner -Phase 'test'

$env:WINDO_INSTALLER_VISUALS = 'quiet'
Write-WindoEditionBanner -Phase 'quiet'

Write-Host 'Test-WindoBannerMotion: OK' -ForegroundColor Green
