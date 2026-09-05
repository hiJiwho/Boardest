Add-Type -AssemblyName System.Drawing

$rootDir = Split-Path -Parent $PSScriptRoot
$logoPath = Join-Path $rootDir "logo.png"

if (-not (Test-Path $logoPath)) {
    Write-Error "logo.png not found at $logoPath"
    exit 1
}

Write-Host "Processing logo from: $logoPath"
$srcImg = [System.Drawing.Image]::FromFile($logoPath)

function Resize-Png($orig, $width, $height, $outPath) {
    $parentDir = Split-Path -Parent $outPath
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $ratioX = [double]$width / $orig.Width
    $ratioY = [double]$height / $orig.Height
    $ratio = [Math]::Min($ratioX, $ratioY)
    $newW = [int]($orig.Width * $ratio)
    $newH = [int]($orig.Height * $ratio)
    $posX = [int](($width - $newW) / 2)
    $posY = [int](($height - $newH) / 2)

    $g.DrawImage($orig, $posX, $posY, $newW, $newH)
    $g.Dispose()

    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "Created: $outPath ($width x $height)"
}

function Create-Ico($orig, $outPath) {
    $parentDir = Split-Path -Parent $outPath
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Generate 256x256 high quality bitmap and convert to icon
    $size = 256
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $ratioX = [double]$size / $orig.Width
    $ratioY = [double]$size / $orig.Height
    $ratio = [Math]::Min($ratioX, $ratioY)
    $newW = [int]($orig.Width * $ratio)
    $newH = [int]($orig.Height * $ratio)
    $posX = [int](($size - $newW) / 2)
    $posY = [int](($size - $newH) / 2)

    $g.DrawImage($orig, $posX, $posY, $newW, $newH)
    $g.Dispose()

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $fs = [System.IO.FileStream]::new($outPath, [System.IO.FileMode]::Create)
    $icon.Save($fs)
    $fs.Close()
    $fs.Dispose()
    $icon.Dispose()
    $bmp.Dispose()
    Write-Host "Created Icon: $outPath"
}

# 1. Update AppX Assets
$packageDirs = @(
    (Join-Path $rootDir "dist\packages\boardest\Assets"),
    (Join-Path $rootDir "dist\packages\bst-teacher\Assets"),
    (Join-Path $rootDir "dist\packages\bst-overlay-panser\Assets")
)

foreach ($pDir in $packageDirs) {
    Resize-Png $srcImg 44 44 (Join-Path $pDir "Square44x44Logo.png")
    Resize-Png $srcImg 150 150 (Join-Path $pDir "Square150x150Logo.png")
    Resize-Png $srcImg 310 150 (Join-Path $pDir "Wide310x150Logo.png")
    Resize-Png $srcImg 50 50 (Join-Path $pDir "StoreLogo.png")
}

# 2. Update .ico files
$icoPaths = @(
    (Join-Path $rootDir "apps\boardest\windows\runner\resources\app_icon.ico"),
    (Join-Path $rootDir "apps\boardest_teacher\windows\runner\resources\app_icon.ico"),
    (Join-Path $rootDir "apps\boardest_teacher\assets\app_icon.ico"),
    (Join-Path $rootDir "dist\packages\bst-teacher\data\flutter_assets\assets\app_icon.ico")
)

foreach ($icoPath in $icoPaths) {
    Create-Ico $srcImg $icoPath
}

$srcImg.Dispose()
Write-Host "All logo and icon assets updated successfully!" -ForegroundColor Green
