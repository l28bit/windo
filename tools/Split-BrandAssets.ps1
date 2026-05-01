# Split the flattened brand contact sheet into reusable project PNG assets.
# Source artwork is a 24-bit PNG, so outputs preserve the source background rather than inventing transparency.
[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path (Split-Path $PSScriptRoot -Parent) "brand\WINDO_icon_banners_trayicon_avatar.png"),
    [string]$LogoPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "brand\winDO.png"),
    [string]$TransparentPackPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "brand\individual_and_Transparent.png"),
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

function Get-AlphaBounds {
    param(
        [System.Drawing.Bitmap]$Source,
        [int]$AlphaThreshold = 8
    )

    $minX = $Source.Width
    $minY = $Source.Height
    $maxX = -1
    $maxY = -1

    for ($y = 0; $y -lt $Source.Height; $y++) {
        for ($x = 0; $x -lt $Source.Width; $x++) {
            if ($Source.GetPixel($x, $y).A -gt $AlphaThreshold) {
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }

    if ($maxX -lt 0 -or $maxY -lt 0) { return $null }
    [System.Drawing.Rectangle]::new($minX, $minY, (($maxX - $minX) + 1), (($maxY - $minY) + 1))
}

function Save-TransparentCrop {
    param(
        [System.Drawing.Bitmap]$Source,
        [string]$Name,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [int]$Padding = 4
    )

    $targetPath = Join-Path $OutputRoot $Name
    New-AssetDirectory -Path (Split-Path $targetPath -Parent)
    $rect = [System.Drawing.Rectangle]::new($X, $Y, $Width, $Height)
    $crop = $Source.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $bounds = Get-AlphaBounds -Source $crop
        if ($null -eq $bounds) { throw "No visible pixels found in crop $Name" }

        $trimX = [Math]::Max(0, $bounds.X - $Padding)
        $trimY = [Math]::Max(0, $bounds.Y - $Padding)
        $trimRight = [Math]::Min($crop.Width, $bounds.Right + $Padding)
        $trimBottom = [Math]::Min($crop.Height, $bounds.Bottom + $Padding)
        $trim = [System.Drawing.Rectangle]::new($trimX, $trimY, ($trimRight - $trimX), ($trimBottom - $trimY))
        $trimmed = $crop.Clone($trim, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $trimmed.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $trimmed.Dispose()
        }
    } finally {
        $crop.Dispose()
    }
    return $targetPath
}

function Save-TransparentIconSet {
    param(
        [System.Drawing.Bitmap]$Source,
        [string]$BaseName,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )

    $basePath = Save-TransparentCrop -Source $Source -Name ("transparent\tray\{0}.png" -f $BaseName) -X $X -Y $Y -Width $Width -Height $Height -Padding 4
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $src = [System.Drawing.Bitmap]::FromFile($basePath)
    try {
        foreach ($size in $sizes) {
            $targetPath = Join-Path $OutputRoot ("transparent\tray\{0}-{1}.png" -f $BaseName, $size)
            New-AssetDirectory -Path (Split-Path $targetPath -Parent)
            $resized = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $g = [System.Drawing.Graphics]::FromImage($resized)
                try {
                    $g.Clear([System.Drawing.Color]::Transparent)
                    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $scale = [Math]::Min($size / $src.Width, $size / $src.Height)
                    $drawW = [int][Math]::Round($src.Width * $scale)
                    $drawH = [int][Math]::Round($src.Height * $scale)
                    $drawX = [int][Math]::Floor(($size - $drawW) / 2)
                    $drawY = [int][Math]::Floor(($size - $drawH) / 2)
                    $g.DrawImage($src, $drawX, $drawY, $drawW, $drawH)
                } finally {
                    $g.Dispose()
                }
                $resized.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $resized.Dispose()
            }
        }
    } finally {
        $src.Dispose()
    }
    return $basePath
}

function New-IcoFromPngSet {
    param(
        [string]$Name,
        [string[]]$PngPaths
    )

    $targetPath = Join-Path $OutputRoot ("transparent\ico\{0}.ico" -f $Name)
    New-AssetDirectory -Path (Split-Path $targetPath -Parent)
    $entries = @()
    foreach ($pngPath in $PngPaths) {
        if (!(Test-Path -LiteralPath $pngPath)) { throw "Missing PNG for ICO: $pngPath" }
        $pngBytes = [System.IO.File]::ReadAllBytes($pngPath)
        $img = [System.Drawing.Bitmap]::FromFile($pngPath)
        try {
            $entries += [pscustomobject]@{
                Width = [int]$img.Width
                Height = [int]$img.Height
                Bytes = $pngBytes
            }
        } finally {
            $img.Dispose()
        }
    }

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$entries.Count)
        $offset = 6 + (16 * $entries.Count)
        foreach ($entry in $entries) {
            $writer.Write([byte]$(if ($entry.Width -ge 256) { 0 } else { $entry.Width }))
            $writer.Write([byte]$(if ($entry.Height -ge 256) { 0 } else { $entry.Height }))
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$entry.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $entry.Bytes.Length
        }
        foreach ($entry in $entries) {
            $writer.Write([byte[]]$entry.Bytes)
        }
        [System.IO.File]::WriteAllBytes($targetPath, $stream.ToArray())
    } finally {
        $writer.Dispose()
        $stream.Dispose()
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

if (Test-Path -LiteralPath $TransparentPackPath) {
    $transparent = [System.Drawing.Bitmap]::FromFile($TransparentPackPath)
    try {
        if (-not [System.Drawing.Image]::IsAlphaPixelFormat($transparent.PixelFormat)) {
            throw "Transparent pack does not have an alpha-capable pixel format: $($transparent.PixelFormat)"
        }

        [void]$written.Add((Save-TransparentCrop $transparent "transparent\logos\full-logo.png" 40 405 455 175 8))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\logos\brand-mark-large.png" 540 410 170 150 8))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\logos\brand-mark-light-128.png" 722 438 78 78 6))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\logos\brand-mark-dark-128.png" 820 434 88 86 6))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\logos\brand-mark-blue-128.png" 924 434 88 86 6))

        [void]$written.Add((Save-TransparentIconSet $transparent "ready-blue-light" 48 642 140 120))
        [void]$written.Add((Save-TransparentIconSet $transparent "ready-blue-dark" 218 660 120 100))
        [void]$written.Add((Save-TransparentIconSet $transparent "ready-blue-small" 360 668 80 78))
        [void]$written.Add((Save-TransparentIconSet $transparent "ready-blue-compact" 474 672 72 72))
        [void]$written.Add((Save-TransparentIconSet $transparent "ready-cyan" 572 672 72 72))
        [void]$written.Add((Save-TransparentIconSet $transparent "ready-teal" 648 672 72 72))
        [void]$written.Add((Save-TransparentIconSet $transparent "allowed-yellow" 736 666 78 78))
        [void]$written.Add((Save-TransparentIconSet $transparent "allowed-green" 836 666 78 78))
        [void]$written.Add((Save-TransparentIconSet $transparent "denied-red" 936 666 78 78))

        $icoSizes = @(16, 24, 32, 48, 64, 128, 256)
        [void]$written.Add((New-IcoFromPngSet "windo-tray-ready" @($icoSizes | ForEach-Object { Join-Path $OutputRoot ("transparent\tray\ready-blue-light-{0}.png" -f $_) })))
        [void]$written.Add((New-IcoFromPngSet "windo-tray-warning" @($icoSizes | ForEach-Object { Join-Path $OutputRoot ("transparent\tray\allowed-yellow-{0}.png" -f $_) })))
        [void]$written.Add((New-IcoFromPngSet "windo-tray-ok" @($icoSizes | ForEach-Object { Join-Path $OutputRoot ("transparent\tray\allowed-green-{0}.png" -f $_) })))
        [void]$written.Add((New-IcoFromPngSet "windo-tray-denied" @($icoSizes | ForEach-Object { Join-Path $OutputRoot ("transparent\tray\denied-red-{0}.png" -f $_) })))

        [void]$written.Add((Save-TransparentCrop $transparent "transparent\status\warning-20.png" 64 858 62 50 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\status\allowed-24.png" 244 858 130 50 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\status\denied-32.png" 398 858 92 54 4))

        [void]$written.Add((Save-TransparentCrop $transparent "transparent\generic\generic-blue-40.png" 548 858 76 70 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\generic\generic-blue-24.png" 642 866 62 58 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\generic\generic-light-24.png" 738 866 62 58 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\generic\generic-dark-32.png" 828 862 70 66 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\generic\generic-dark-48.png" 924 856 82 78 4))

        [void]$written.Add((Save-TransparentCrop $transparent "transparent\badges\brand-light.png" 548 1030 172 136 8))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\badges\wordmark-plate.png" 724 1070 260 76 6))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\brand-name-light.png" 50 1260 120 116 6))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\brand-name-dark.png" 194 1260 120 116 6))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\brand-name-small-blue.png" 328 1260 70 70 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\brand-name-small-gray.png" 410 1260 62 68 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\shield-small.png" 330 1350 50 58 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\lock-small.png" 336 1418 46 48 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\shield-gray-small.png" 404 1350 50 58 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\check-small.png" 404 1418 48 48 4))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\banners\windows-small.png" 478 1350 50 58 4))

        [void]$written.Add((Save-TransparentCrop $transparent "transparent\logos\cube-logo.png" 560 1260 170 160 8))
        [void]$written.Add((Save-TransparentCrop $transparent "transparent\logos\wordmark-tagline.png" 738 1298 220 116 6))
    } finally {
        $transparent.Dispose()
    }
}

Write-Host ("Split-BrandAssets: wrote {0} files under {1}" -f $written.Count, $OutputRoot) -ForegroundColor Cyan
$written | ForEach-Object { Write-Host "  $_" }
