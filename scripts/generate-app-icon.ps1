# UNIQ app icon — 1024x1024 PNG (siyah zemin, sari U)
$ErrorActionPreference = "Stop"
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) "assets\app_icon"
$outFile = Join-Path $outDir "app_icon.png"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Add-Type -AssemblyName System.Drawing
$size = 1024
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::FromArgb(10, 10, 10))

$font = New-Object System.Drawing.Font "Arial", 480, ([System.Drawing.FontStyle]::Bold)
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 255, 0))
$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center
$rect = New-Object System.Drawing.RectangleF 0, 30, $size, $size
$g.DrawString("U", $font, $brush, $rect, $format)

$lineY = 680
$lineBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(153, 200, 255, 0))
$g.FillRectangle($lineBrush, 280, $lineY, 464, 8)

$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $font.Dispose(); $brush.Dispose()

Write-Host "Olusturuldu: $outFile" -ForegroundColor Green
Write-Host "Sonra: dart run flutter_launcher_icons"
