param(
    [Parameter(Mandatory = $true)][string]$pptPath,
    [Parameter(Mandatory = $true)][string]$outputFolder
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $pptPath)) {
    Write-Error "PPT file not found: $pptPath"
    exit 1
}

New-Item -ItemType Directory -Force -Path $outputFolder | Out-Null

$ppt = New-Object -ComObject PowerPoint.Application
$ppt.Visible = [Microsoft.Office.Core.MsoTriState]::msoFalse

try {
    $pres = $ppt.Presentations.Open($pptPath, $true, $true, $false)
    $metadata = @()

    for ($i = 1; $i -le $pres.Slides.Count; $i++) {
        $slide = $pres.Slides.Item($i)
        $imgPath = Join-Path $outputFolder ("slide_{0:D3}.png" -f $i)
        $slide.Export($imgPath, "PNG", 1920, 1080)

        $animCount = 0
        try {
            $animCount = $slide.TimeLine.MainSequence.Count
        } catch {
            $animCount = 0
        }

        $metadata += [ordered]@{
            slideIndex     = $i - 1
            animationCount = $animCount
            imagePath      = $imgPath
        }
    }

    $pres.Close()
    $jsonPath = Join-Path $outputFolder 'metadata.json'
    $metadata | ConvertTo-Json -Depth 4 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-Output "OK:$jsonPath"
}
finally {
    $ppt.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) | Out-Null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
