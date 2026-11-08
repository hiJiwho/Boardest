$ErrorActionPreference = 'Stop'
$RootDir = Split-Path $PSScriptRoot -Parent
$DistDir = Join-Path $RootDir 'dist\appx'
$NotesFile = Join-Path $RootDir 'scripts\release_notes_v5.6.2.md'
$Version = '5.6.2'
$Repos = @('hiJiwho/Boardest', 'hiJiwho/Boardest-Source-code')

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

$AssetPaths = @()
foreach ($a in $Assets) {
  $p = Join-Path $DistDir $a
  if (Test-Path $p) {
    $AssetPaths += $p
  } else {
    Write-Warning "Asset not found: $p"
  }
}

Write-Host "Total verified asset paths to upload: $($AssetPaths.Count)" -ForegroundColor Cyan

foreach ($repo in $Repos) {
  Write-Host "Processing release v$Version on $repo..." -ForegroundColor Yellow
  
  # Check if release exists, delete if so for clean publish
  try {
    $existing = & gh release view "v$Version" -R $repo 2>$null
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Deleting existing pre-release / tag for clean upload on $repo..." -ForegroundColor Gray
      & gh release delete "v$Version" -R $repo -y
    }
  } catch {}

  Write-Host "Creating release v$Version on $repo with $($AssetPaths.Count) assets..." -ForegroundColor Cyan
  & gh release create "v$Version" @AssetPaths -R $repo -F $NotesFile -t "🚀 Boardest v$Version [Must update] Official Release"
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create release on $repo"
  }
  Write-Host "Successfully published release v$Version on $repo!" -ForegroundColor Green
}
