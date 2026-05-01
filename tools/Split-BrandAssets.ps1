# Split the flattened brand contact sheet into reusable project PNG assets.
# Source artwork is a 24-bit PNG, so outputs preserve the source background rather than inventing transparency.
[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path (Split-Path $PSScriptRoot -Parent) "brand\WINDO_icon_banners_trayicon_avatar.png"),
    [string]$LogoPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "brand\winDO.png"),
    [string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) "brand\assets")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function New-AssetDirectory {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Save-Crop {
    param(
        [System.Drawing.Bitmap]$Source,
        [string]$Name,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )

    $targetPath = Join-Path $OutputRoot $Name
    New-AssetDirectory -Path (Split-Path $targetPath -Parent)
    $rect = [System.Drawing.Rectangle]::new($X, $Y, $Width, $Height)
    $crop = $Source.Clone($rect, $Source.PixelFormat)
    try {
        $crop.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $crop.Dispose()
    }
    return $targetPath
}

function Save-ResizedSquare {
    param(
        [System.Drawing.Bitmap]$Source,
        [string]$Name,
        [int]$X,
        [int]$Y,
        [int]$Size,
        [int]$OutputSize
    )

    $targetPath = Join-Path $OutputRoot $Name
    New-AssetDirectory -Path (Split-Path $targetPath -Parent)
    $cropRect = [System.Drawing.Rectangle]::new($X, $Y, $Size, $Size)
    $crop = $Source.Clone($cropRect, $Source.PixelFormat)
    $resized = [System.Drawing.Bitmap]::new($OutputSize, $OutputSize)
    try {
        $g = [System.Drawing.Graphics]::FromImage($resized)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.DrawImage($crop, 0, 0, $OutputSize, $OutputSize)
        } finally {
            $g.Dispose()
        }
        $resized.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $crop.Dispose()
        $resized.Dispose()
    }
    return $targetPath
}

if (!(Test-Path -LiteralPath $SourcePath)) { throw "Missing source sheet: $SourcePath" }
if (!(Test-Path -LiteralPath $LogoPath)) { throw "Missing logo source: $LogoPath" }

New-AssetDirectory -Path $OutputRoot

$written = [System.Collections.ArrayList]@()
$sheet = [System.Drawing.Bitmap]::FromFile($SourcePath)
try {
    [void]$written.Add((Save-Crop $sheet "logos\hero-lockup-dark.png" 0 0 988 431))
    [void]$written.Add((Save-Crop $sheet "logos\github-avatar-panel.png" 988 0 548 431))

    [void]$written.Add((Save-Crop $sheet "icons\elevate.png" 74 492 92 92))
    [void]$written.Add((Save-Crop $sheet "icons\execute.png" 216 496 88 88))
    [void]$written.Add((Save-Crop $sheet "icons\audit.png" 356 493 86 90))
    [void]$written.Add((Save-Crop $sheet "icons\admin.png" 492 491 84 96))
    [void]$written.Add((Save-Crop $sheet "icons\secure.png" 638 491 84 96))
    [void]$written.Add((Save-Crop $sheet "icons\history.png" 762 490 100 100))
    [void]$written.Add((Save-Crop $sheet "icons\choose.png" 78 638 88 88))
    [void]$written.Add((Save-Crop $sheet "icons\confirm.png" 220 640 82 86))
    [void]$written.Add((Save-Crop $sheet "icons\console.png" 354 640 88 86))
    [void]$written.Add((Save-Crop $sheet "icons\policy.png" 506 639 68 92))
    [void]$written.Add((Save-Crop $sheet "icons\filter.png" 640 640 86 78))
    [void]$written.Add((Save-Crop $sheet "icons\settings.png" 762 634 92 92))

    [void]$written.Add((Save-Crop $sheet "tray\tray-blue.png" 936 498 72 72))
    [void]$written.Add((Save-Crop $sheet "tray\tray-gray.png" 1048 498 72 72))
    [void]$written.Add((Save-Crop $sheet "tray\tray-green.png" 1160 498 72 72))
    [void]$written.Add((Save-Crop $sheet "tray\tray-yellow.png" 1272 498 72 72))
    [void]$written.Add((Save-Crop $sheet "tray\tray-red-alert.png" 1384 498 72 72))
    [void]$written.Add((Save-ResizedSquare $sheet "tray\tray-blue-32.png" 936 498 72 32))
    [void]$written.Add((Save-ResizedSquare $sheet "tray\tray-gray-32.png" 1048 498 72 32))
    [void]$written.Add((Save-ResizedSquare $sheet "tray\tray-green-32.png" 1160 498 72 32))
    [void]$written.Add((Save-ResizedSquare $sheet "tray\tray-yellow-32.png" 1272 498 72 32))
    [void]$written.Add((Save-ResizedSquare $sheet "tray\tray-red-alert-32.png" 1384 498 72 32))

    [void]$written.Add((Save-Crop $sheet "badges\elevated.png" 940 637 126 40))
    [void]$written.Add((Save-Crop $sheet "badges\allowed.png" 1080 637 124 40))
    [void]$written.Add((Save-Crop $sheet "badges\pending.png" 1216 637 132 40))
    [void]$written.Add((Save-Crop $sheet "badges\denied.png" 1356 637 120 40))

    [void]$written.Add((Save-Crop $sheet "brand-elements\shield-check.png" 956 744 62 60))
    [void]$written.Add((Save-Crop $sheet "brand-elements\chevrons.png" 1030 748 162 44))
    [void]$written.Add((Save-Crop $sheet "brand-elements\progress-dots-line.png" 1214 748 268 48))

    [void]$written.Add((Save-Crop $sheet "banners\banner-blue-left.png" 48 860 443 122))
    [void]$written.Add((Save-Crop $sheet "banners\banner-terminal.png" 517 860 493 122))
    [void]$written.Add((Save-Crop $sheet "banners\banner-light.png" 1035 860 453 122))
} finally {
    $sheet.Dispose()
}

$logo = [System.Drawing.Bitmap]::FromFile($LogoPath)
try {
    [void]$written.Add((Save-Crop $logo "logos\windo-square-logo.png" 0 0 $logo.Width $logo.Height))
} finally {
    $logo.Dispose()
}

Write-Host ("Split-BrandAssets: wrote {0} files under {1}" -f $written.Count, $OutputRoot) -ForegroundColor Cyan
$written | ForEach-Object { Write-Host "  $_" }
