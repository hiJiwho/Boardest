param(
  [string]$Dist = 'dist\appx'
)

$Assets = @(
  'boardest-class-cloud.msix',
  'boardest-class-installer.exe',
  'boardest-class-lite-installer.exe',
  'Boardest-Class-Lite-Setup.exe',
  'boardest-class-lite.apk',
  'boardest-class-lite.exe',
  'boardest-class-lite.msix',
  'Boardest-Class-Setup.exe',
  'boardest-class.apk',
  'boardest-class.appx',
  'boardest-class.exe',
  'boardest-class.msix',
  'boardest-cloud-installer.exe',
  'Boardest-Cloud-Setup.exe',
  'boardest-cloud.apk',
  'boardest-cloud.exe',
  'boardest-cloud.msix',
  'boardest-installer.exe',
  'boardest-student.apk',
  'boardest-teacher-installer.exe',
  'boardest-teacher-lite.apk',
  'Boardest-Teacher-Setup.exe',
  'boardest-teacher-uninstaller.exe',
  'boardest-teacher-windows.zip',
  'boardest-teacher.apk',
  'boardest-teacher.exe',
  'boardest-teacher.msi',
  'boardest-windows.zip',
  'boardest.apk',
  'boardest.appx',
  'boardest.msix',
  'BoardestCert.cer',
  'bst-overlay-panser.msix',
  'bst-teacher-windows.zip',
  'bst-teacher.apk',
  'bst-teacher.msi',
  'installer.exe',
  'install_certificate.bat',
  'install_certificate.ps1',
  'uninstall.exe'
)

$results = foreach ($asset in $Assets) {
  $path = Join-Path $Dist $asset
  $exists = Test-Path $path
  $item = if ($exists) { Get-Item $path } else { $null }
  $sigStatus = 'N/A'
  if ($exists -and ($asset -match '\.(exe|msi|msix|appx)$')) {
    $sig = Get-AuthenticodeSignature $path
    $sigStatus = $sig.Status.ToString()
  }
  [PSCustomObject]@{
    Asset = $asset
    Exists = $exists
    Size = if ($item) { $item.Length } else { 0 }
    Modified = if ($item) { $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'N/A' }
    Signature = $sigStatus
  }
}

$missing = @($results | Where-Object { -not $_.Exists })
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total Assets Expected: $($Assets.Count)" -ForegroundColor Cyan
Write-Host "Total Assets Found:    $($results.Count - $missing.Count)" -ForegroundColor Green
Write-Host "Total Assets Missing:  $($missing.Count)" -ForegroundColor $(if ($missing.Count -eq 0) { 'Green' } else { 'Red' })
Write-Host "==========================================" -ForegroundColor Cyan

$results | Format-Table -AutoSize

if ($missing.Count -gt 0) {
  Write-Host "Missing files:" -ForegroundColor Red
  $missing | Format-Table -AutoSize
  exit 1
} else {
  Write-Host "ALL 40 ASSETS VERIFIED PRESENT AND VALID!" -ForegroundColor Green
}
