$ErrorActionPreference = "Stop"

$Repo = "https://raw.githubusercontent.com/l28bit/windo/Genisis/windo_install.ps1"
$Temp = Join-Path $env:TEMP "windo_install.ps1"

Write-Host ""
Write-Host "WINDO bootstrap starting..." -ForegroundColor Cyan

try {

    Write-Host "[windo] Downloading installer..." -ForegroundColor DarkCyan
    Invoke-RestMethod -Uri $Repo -OutFile $Temp

    if (!(Test-Path $Temp)) {
        throw "Installer failed to download."
    }

    $size = (Get-Item $Temp).Length
    if ($size -lt 5000) {
        throw "Installer file size looks invalid."
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