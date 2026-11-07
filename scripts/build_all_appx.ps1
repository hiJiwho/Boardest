param(
  [string]$AppVersion = '5.6.1',
  [switch]$SkipApk,
  [switch]$SkipWindowsBuild
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path $PSScriptRoot -Parent
$DistDir = Join-Path $RootDir 'dist'
$PackageDir = Join-Path $DistDir 'packages'
$OutDir = Join-Path $DistDir 'appx'
$TemplateDir = Join-Path $PSScriptRoot 'appx_templates'
$CertFile = Join-Path $RootDir 'certs\BoardestCert.pfx'
$CerFile = Join-Path $RootDir 'certs\BoardestCert.cer'
$CertPassword = $env:BOARDEST_CERT_PASSWORD
$PublicCertificate = $null
$CertificateThumbprint = $null
$UseCertificateStore = [string]::IsNullOrWhiteSpace($CertPassword)

$KitBin = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64'
$MakeAppx = Join-Path $KitBin 'makeappx.exe'
$SignTool = Join-Path $KitBin 'signtool.exe'
$CSharpCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
foreach ($tool in @($MakeAppx, $SignTool, $CertFile, $CerFile, $CSharpCompiler)) {
  if (-not (Test-Path $tool)) { throw "Required build file not found: $tool" }
}
$PublicCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CerFile)
$CertificateThumbprint = $PublicCertificate.Thumbprint
if ($UseCertificateStore) {
  $InstalledSigningCertificate = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Thumbprint -eq $CertificateThumbprint -and $_.HasPrivateKey } |
    Select-Object -First 1
  if (-not $InstalledSigningCertificate) {
    throw 'Set BOARDEST_CERT_PASSWORD or install the matching Boardest signing certificate with its private key.'
  }
}
foreach ($name in @('boardest', 'bst-overlay-panser', 'boardest-class-lite', 'boardest-class-cloud')) {
  $template = Join-Path $TemplateDir $name
  if (-not (Test-Path (Join-Path $template 'AppxManifest.xml'))) { throw "AppX template not found: $template" }
  $package = Join-Path $PackageDir $name
  New-Item -ItemType Directory -Force -Path $package | Out-Null
  Copy-Item (Join-Path $template '*') $package -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $PackageDir 'bst-teacher') | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Set-PackageVersion([string]$Manifest) {
  $apxVer = $AppVersion
  if (($apxVer -split '\.').Count -eq 3) { $apxVer = "$apxVer.0" }
  $xml = Get-Content $Manifest -Raw -Encoding UTF8
  $xml = [regex]::Replace($xml, '(<Identity\b[^>]*\bVersion=")[0-9.]+', ('${1}' + $apxVer))
  if ($xml -notmatch ('<Identity\b[^>]*\bVersion="' + [regex]::Escape($apxVer) + '"')) {
    throw "Could not set AppX version in manifest: $Manifest"
  }
  [System.IO.File]::WriteAllText($Manifest, $xml, [System.Text.UTF8Encoding]::new($false))
}
function Build-Windows([string]$Directory) {
  Push-Location $Directory
  try { & flutter build windows --release --no-tree-shake-icons --obfuscate --split-debug-info=build/debug-info; if ($LASTEXITCODE -ne 0) { throw "Windows build failed: $Directory" } }
  finally { Pop-Location }
}
function Build-Apk([string]$Directory, [string]$Name, [string]$ExtraArgs = '') {
  Push-Location $Directory
  try {
    if ($ExtraArgs) {
      $argList = @('build', 'apk', '--release', '--no-tree-shake-icons') + ($ExtraArgs -split ' ')
      & flutter @argList
    } else {
      & flutter build apk --release --no-tree-shake-icons
    }
    if ($LASTEXITCODE -ne 0) { throw "Android APK build failed: $Directory ($Name)" }
  }
  finally { Pop-Location }
  Copy-Item (Join-Path $Directory 'build\app\outputs\flutter-apk\app-release.apk') (Join-Path $OutDir $Name) -Force
}
function Pack-Signed([string]$Name) {
  $source = Join-Path $PackageDir $Name
  $targetMsix = Join-Path $OutDir "$Name.msix"
  $targetAppx = Join-Path $OutDir "$Name.appx"
  Set-PackageVersion (Join-Path $source 'AppxManifest.xml')
  & $MakeAppx pack /d $source /p $targetMsix /o
  if ($LASTEXITCODE -ne 0) { throw "MSIX packaging failed: $Name" }
  if ($UseCertificateStore) {
    & $SignTool sign /fd SHA256 /s My /sha1 $CertificateThumbprint $targetMsix
  } else {
    & $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $targetMsix
  }
  if ($LASTEXITCODE -ne 0) { throw "MSIX signing failed: $Name" }
  Copy-Item $targetMsix $targetAppx -Force
}

function Pack-TeacherMsi([string]$Version) {
  Write-Host "Packaging Boardest Teacher as MSI installer (v$Version)..." -ForegroundColor Cyan
  $WixDir = Join-Path $RootDir 'tools\wix'
  if (-not (Test-Path "$WixDir\candle.exe")) {
    Write-Host "WiX binaries not found in $WixDir. Downloading WiX v3.11 binaries..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $WixDir | Out-Null
    $ZipPath = Join-Path $DistDir 'wix311-binaries.zip'
    Invoke-WebRequest -Uri 'https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311-binaries.zip' -OutFile $ZipPath
    Expand-Archive -Path $ZipPath -DestinationPath $WixDir -Force
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
  }
  $TeacherSource = Join-Path $PackageDir 'bst-teacher'
  $Template = Join-Path $RootDir 'scripts\wix_templates\bst-teacher'
  $ProductWxs = Join-Path $Template 'Product.wxs'
  $LicenseRtf = Join-Path $Template 'license.rtf'
  $IconPath = Join-Path $Template 'app_icon.ico'
  $MsiOut = Join-Path $OutDir 'bst-teacher.msi'
  $WorkDir = Join-Path $DistDir 'wix_work'
  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

  # Clean unneeded compiler artifacts to reduce package size
  Get-ChildItem -Path $TeacherSource -Filter "*.lib" -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
  Get-ChildItem -Path $TeacherSource -Filter "*.exp" -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue

  # 1. Sign all executables in bst-teacher package before creating MSI
  $Exes = Get-ChildItem -Path $TeacherSource -Filter "*.exe" -Recurse
  foreach ($exe in $Exes) {
    if ($UseCertificateStore) {
      & $SignTool sign /fd SHA256 /s My /sha1 $CertificateThumbprint $exe.FullName
    } else {
      & $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $exe.FullName
    }
  }

  # 2. Harvest files
  $FilesWxs = Join-Path $WorkDir 'files.wxs'
  & "$WixDir\heat.exe" dir $TeacherSource -cg AppFiles -dr INSTALLFOLDER -srd -ag -sreg -scom -var var.SourceDir -out $FilesWxs
  if ($LASTEXITCODE -ne 0) { throw "WiX heat failed for bst-teacher" }

  # 3. Compile
  $msiVer = (($Version -split '\.')[0..2]) -join '.'
  $WixExt = Join-Path $WixDir 'WixUIExtension.dll'
  & "$WixDir\candle.exe" -nologo -arch x64 `
    "-dVersion=$msiVer" `
    "-dSourceDir=$TeacherSource" `
    "-dIconPath=$IconPath" `
    "-dLicenseRtf=$LicenseRtf" `
    -ext $WixExt `
    -out "$WorkDir\" `
    $ProductWxs $FilesWxs
  if ($LASTEXITCODE -ne 0) { throw "WiX candle failed for bst-teacher" }

  # 4. Link
  & "$WixDir\light.exe" -nologo -ext $WixExt -sice:ICE38 -sice:ICE43 -sice:ICE57 -sice:ICE60 -sice:ICE61 -sice:ICE91 `
    -out $MsiOut `
    (Join-Path $WorkDir 'Product.wixobj') (Join-Path $WorkDir 'files.wixobj')
  if ($LASTEXITCODE -ne 0) { throw "WiX light failed for bst-teacher" }

  # 5. Digitally sign the resulting MSI
  if ($UseCertificateStore) {
    & $SignTool sign /fd SHA256 /s My /sha1 $CertificateThumbprint $MsiOut
  } else {
    & $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $MsiOut
  }
  if ($LASTEXITCODE -ne 0) { throw "MSI signing failed: $MsiOut" }

  # 사용자 요청에 맞춘 공식 배포 파일명 통일: boardest-teacher.msi
  $UnifiedMsiOut = Join-Path $OutDir 'boardest-teacher.msi'
  Copy-Item $MsiOut $UnifiedMsiOut -Force
  Write-Host "Successfully built and signed $MsiOut and $UnifiedMsiOut" -ForegroundColor Green
}

Write-Host "Building Boardest official v$AppVersion AppX and APK files..." -ForegroundColor Cyan
if (-not $SkipWindowsBuild) {
  Build-Windows (Join-Path $RootDir 'apps\boardest')
  Build-Windows (Join-Path $RootDir 'apps\boardest_teacher')
  Build-Windows (Join-Path $RootDir 'apps\boardest_class_lite')
}

$BoardestRelease = Join-Path $RootDir 'apps\boardest\build\windows\x64\runner\Release'
$TeacherRelease = Join-Path $RootDir 'apps\boardest_teacher\build\windows\x64\runner\Release'
$ClassLiteRelease = Join-Path $RootDir 'apps\boardest_class_lite\build\windows\x64\runner\Release'
Copy-Item "$BoardestRelease\*" (Join-Path $PackageDir 'boardest') -Recurse -Force
Copy-Item "$BoardestRelease\*" (Join-Path $PackageDir 'boardest-class-cloud') -Recurse -Force
if (Test-Path (Join-Path $PackageDir 'boardest-class-cloud\boardest.exe')) {
  Copy-Item (Join-Path $PackageDir 'boardest-class-cloud\boardest.exe') (Join-Path $PackageDir 'boardest-class-cloud\Boardest-Class-Cloud.exe') -Force
}
Copy-Item "$TeacherRelease\*" (Join-Path $PackageDir 'bst-teacher') -Recurse -Force
Copy-Item "$ClassLiteRelease\*" (Join-Path $PackageDir 'boardest-class-lite') -Recurse -Force
if (Test-Path (Join-Path $PackageDir 'boardest-class-lite\boardest_class_lite.exe')) {
  Copy-Item (Join-Path $PackageDir 'boardest-class-lite\boardest_class_lite.exe') (Join-Path $PackageDir 'boardest-class-lite\Boardest-Class-Lite.exe') -Force
}
Compress-Archive -Path (Join-Path $BoardestRelease '*') -DestinationPath (Join-Path $OutDir 'boardest-windows.zip') -Force
Compress-Archive -Path (Join-Path $TeacherRelease '*') -DestinationPath (Join-Path $OutDir 'bst-teacher-windows.zip') -Force
Copy-Item (Join-Path $RootDir 'infra\class_lite_web\index.html') (Join-Path $PackageDir 'boardest-class-lite\index.html') -Force

if (-not $SkipApk) {
  Build-Apk (Join-Path $RootDir 'apps\boardest') 'boardest.apk'
  Build-Apk (Join-Path $RootDir 'apps\boardest') 'boardest-cloud.apk' '--dart-define=BC_CLOUD_MODE=true'
  Copy-Item (Join-Path $OutDir 'boardest-cloud.apk') (Join-Path $OutDir 'boardest-class-cloud.apk') -Force
  Build-Apk (Join-Path $RootDir 'apps\boardest_teacher') 'bst-teacher.apk'
  Build-Apk (Join-Path $RootDir 'apps\boardest_teacher_lite') 'boardest-teacher-lite.apk'
  Copy-Item (Join-Path $OutDir 'boardest-teacher-lite.apk') (Join-Path $OutDir 'bst-teacher-lite.apk') -Force
  Build-Apk (Join-Path $RootDir 'apps\boardest_class_lite') 'bst-class-lite.apk'
  Copy-Item (Join-Path $OutDir 'bst-class-lite.apk') (Join-Path $OutDir 'boardest-class-lite.apk') -Force
  Build-Apk (Join-Path $RootDir 'apps\boardest_student') 'boardest-student.apk'
  Copy-Item (Join-Path $OutDir 'boardest-student.apk') (Join-Path $OutDir 'bst-student.apk') -Force
} else {
  $boardestFreshApk = Join-Path $RootDir 'apps\boardest\build\app\outputs\flutter-apk\app-release.apk'
  if ((Test-Path $boardestFreshApk) -and (-not (Test-Path (Join-Path $OutDir 'boardest.apk')))) {
    Copy-Item $boardestFreshApk (Join-Path $OutDir 'boardest.apk') -Force
  }
  $classLiteFreshApk = Join-Path $RootDir 'apps\boardest_class_lite\build\app\outputs\flutter-apk\app-release.apk'
  if ((Test-Path $classLiteFreshApk) -and (-not (Test-Path (Join-Path $OutDir 'bst-class-lite.apk')))) {
    Copy-Item $classLiteFreshApk (Join-Path $OutDir 'bst-class-lite.apk') -Force
    Copy-Item $classLiteFreshApk (Join-Path $OutDir 'boardest-class-lite.apk') -Force
  }
}

if (-not (Test-Path (Join-Path $PackageDir 'boardest-class-lite\Boardest-Class-Lite.exe'))) {
  $ClassLiteExe = Join-Path $PackageDir 'boardest-class-lite\Boardest-Class-Lite.exe'
  & $CSharpCompiler /nologo /target:winexe "/out:$ClassLiteExe" (Join-Path $RootDir 'infra\class_lite_win\Boardest-Class-Lite.cs')
  if ($LASTEXITCODE -ne 0) { throw 'Class Lite Windows launcher compilation failed.' }
}

$OverlayPackage = Join-Path $PackageDir 'bst-overlay-panser'
$OverlaySource = Join-Path $RootDir 'apps\boardest'
$WpfLib = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319;$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\WPF"
$WpfReferences = @(
  '/r:System.dll',
  '/r:System.Core.dll',
  '/r:System.Windows.Forms.dll',
  '/r:WindowsBase.dll',
  '/r:PresentationCore.dll',
  '/r:PresentationFramework.dll',
  '/r:System.Xaml.dll'
)
foreach ($overlay in @('boardest_ppt_overlay', 'boardest_hwp_overlay')) {
  & $CSharpCompiler /nologo /target:winexe "/out:$(Join-Path $OverlayPackage "$overlay.exe")" `
    "/lib:$WpfLib" `
    $WpfReferences (Join-Path $OverlaySource "$overlay.cs")
  if ($LASTEXITCODE -ne 0) { throw "Overlay compilation failed: $overlay" }
}
& $CSharpCompiler /nologo /target:exe "/out:$(Join-Path $OverlayPackage 'boardest_ppt_helper.exe')" `
  (Join-Path $OverlaySource 'boardest_ppt_helper.cs')
if ($LASTEXITCODE -ne 0) { throw 'PowerPoint helper compilation failed.' }

foreach ($name in @('boardest', 'bst-overlay-panser', 'boardest-class-lite', 'boardest-class-cloud')) { Pack-Signed $name }
if (Test-Path (Join-Path $OutDir 'boardest-class-cloud.appx')) {
  Copy-Item (Join-Path $OutDir 'boardest-class-cloud.appx') (Join-Path $OutDir 'boardest-cloud.appx') -Force
}
if (Test-Path (Join-Path $OutDir 'boardest-class-cloud.msix')) {
  Copy-Item (Join-Path $OutDir 'boardest-class-cloud.msix') (Join-Path $OutDir 'boardest-cloud.msix') -Force
}
if (Test-Path (Join-Path $OutDir 'boardest.msix')) {
  Copy-Item (Join-Path $OutDir 'boardest.msix') (Join-Path $OutDir 'boardest-class.msix') -Force
}
if (Test-Path (Join-Path $OutDir 'boardest.appx')) {
  Copy-Item (Join-Path $OutDir 'boardest.appx') (Join-Path $OutDir 'boardest-class.appx') -Force
}
Pack-TeacherMsi $AppVersion
Copy-Item $CerFile (Join-Path $OutDir 'BoardestCert.cer') -Force
Copy-Item (Join-Path $RootDir 'certs\install_certificate.bat') (Join-Path $OutDir 'install_certificate.bat') -Force
Copy-Item (Join-Path $RootDir 'certs\install_certificate.ps1') (Join-Path $OutDir 'install_certificate.ps1') -Force

# Build Modern Lightweight WebView2 Online Installers (.exe)
& "$RootDir\tools\installer\build_installer.ps1" -AppVersion $AppVersion

$DownloadDir = Join-Path $RootDir 'infra\download_web'
$DownloadsHubWeb = Join-Path $RootDir 'infra\downloads_hub_web'
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
New-Item -ItemType Directory -Force -Path $DownloadsHubWeb | Out-Null

$FilesToCopy = @(
  'boardest.msix', 'boardest-class.msix', 'boardest-cloud.msix', 'boardest-class-cloud.msix', 'boardest-class-lite.msix',
  'boardest.appx', 'boardest-class.appx', 'boardest-cloud.appx', 'boardest-class-cloud.appx', 'boardest-class-lite.appx',
  'boardest-installer.exe', 'installer.exe',
  'boardest-teacher-installer.exe', 'Boardest-Teacher-Setup.exe', 'boardest-teacher.exe', 'boardest-teacher-uninstaller.exe',
  'boardest-class-installer.exe', 'Boardest-Class-Setup.exe', 'boardest-class.exe',
  'boardest-cloud-installer.exe', 'Boardest-Cloud-Setup.exe', 'boardest-cloud.exe',
  'boardest-class-lite-installer.exe', 'Boardest-Class-Lite-Setup.exe', 'boardest-class-lite.exe',
  'uninstall.exe',
  'boardest-teacher.msi', 'bst-teacher.msi',
  'bst-teacher-windows.zip', 'boardest-windows.zip',
  'boardest.apk', 'boardest-class.apk', 'boardest-cloud.apk', 'boardest-class-cloud.apk',
  'bst-teacher.apk', 'boardest-teacher.apk', 'bst-teacher-lite.apk', 'boardest-teacher-lite.apk',
  'bst-class-lite.apk', 'boardest-class-lite.apk',
  'boardest-student.apk', 'bst-student.apk',
  'BoardestCert.cer', 'install_certificate.bat', 'install_certificate.ps1'
)
foreach ($file in $FilesToCopy) {
  $source = Join-Path $OutDir $file
  if (Test-Path $source) {
    Copy-Item $source (Join-Path $DownloadDir $file) -Force
    Copy-Item $source (Join-Path $DownloadsHubWeb $file) -Force
  }
}
Write-Host 'Official MSIX/EXE/MSI/APK artifacts are ready in dist\appx.' -ForegroundColor Green
