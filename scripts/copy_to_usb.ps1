# ==============================================================================
# Boardest v5.0.13 USB 복사 스크립트
# ==============================================================================

$RootDir = Split-Path $PSScriptRoot -Parent
$DistDir = Join-Path $RootDir 'dist\appx'
$CertsDir = Join-Path $RootDir 'certs'
$CrxZip = Join-Path $RootDir 'apps\boardest\web\downloads\boardbook_extension.zip'

$files = @(
  @{ Src = Join-Path $DistDir 'boardest.apk'; Name = 'boardest.apk' },
  @{ Src = Join-Path $DistDir 'bst-class-lite.apk'; Name = 'bst-class-lite.apk' },
  @{ Src = Join-Path $DistDir 'boardest.appx'; Name = 'boardest.appx' },
  @{ Src = Join-Path $DistDir 'boardest-class-lite.appx'; Name = 'boardest-class-lite.appx' },
  @{ Src = Join-Path $DistDir 'bst-teacher.msi'; Name = 'bst-teacher.msi' },
  @{ Src = Join-Path $DistDir 'bst-overlay-panser.appx'; Name = 'bst-overlay-panser.appx' },
  @{ Src = Join-Path $DistDir 'BoardestCert.cer'; Name = 'BoardestCert.cer' },
  @{ Src = Join-Path $CertsDir 'install_certificate.bat'; Name = 'install_certificate.bat' },
  @{ Src = $CrxZip; Name = 'boardbook_extension.zip' }
)

$targetDrives = @('E:\', 'F:\')
$copiedAny = $false

foreach ($drive in $targetDrives) {
  if (Test-Path $drive) {
    $copiedAny = $true
    Write-Host "`n>>> [USB COPY] Target drive found: $drive" -ForegroundColor Cyan
    $folder = Join-Path $drive 'Boardest_v5.0.13'
    New-Item -ItemType Directory -Force -Path $folder | Out-Null

    foreach ($item in $files) {
      if (Test-Path $item.Src) {
        Write-Host "  -> Copying $($item.Name)..." -ForegroundColor Green
        Copy-Item -Path $item.Src -Destination (Join-Path $drive $item.Name) -Force
        Copy-Item -Path $item.Src -Destination (Join-Path $folder $item.Name) -Force
      } else {
        Write-Warning "  Source file not found: $($item.Src)"
      }
    }
  }
}

if (-not $copiedAny) {
  Write-Host "`n[!] No USB drives (E:, F:) currently detected. Please plug in your USB drives and re-run this script." -ForegroundColor Yellow
} else {
  Write-Host "`n[OK] All v5.0.13 files successfully copied to USB drives!" -ForegroundColor Green
}
