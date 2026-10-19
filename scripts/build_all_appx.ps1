param(
  [string]$AppVersion = '4.1.2.0',
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
foreach ($name in @('boardest', 'bst-overlay-panser', 'boardest-class-lite')) {
  $template = Join-Path $TemplateDir $name
  if (-not (Test-Path (Join-Path $template 'AppxManifest.xml'))) { throw "AppX template not found: $template" }
  $package = Join-Path $PackageDir $name
  New-Item -ItemType Directory -Force -Path $package | Out-Null
  Copy-Item (Join-Path $template '*') $package -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $PackageDir 'bst-teacher') | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Set-PackageVersion([string]$Manifest) {
  $xml = Get-Content $Manifest -Raw -Encoding UTF8
  $xml = [regex]::Replace($xml, '(<Identity\b[^>]*\bVersion=")[0-9.]+', ('${1}' + $AppVersion))
  if ($xml -notmatch ('<Identity\b[^>]*\bVersion="' + [regex]::Escape($AppVersion) + '"')) {
    throw "Could not set AppX version in manifest: $Manifest"
  }
  [System.IO.File]::WriteAllText($Manifest, $xml, [System.Text.UTF8Encoding]::new($false))
}
function Build-Windows([string]$Directory) {
  Push-Location $Directory
  try { & flutter build windows --release --no-tree-shake-icons --obfuscate --split-debug-info=build/debug-info; if ($LASTEXITCODE -ne 0) { throw "Windows build failed: $Directory" } }
  finally { Pop-Location }
}
function Build-Apk([string]$Directory, [string]$Name) {
  Push-Location $Directory
  try { & flutter build apk --release --no-tree-shake-icons --obfuscate --split-debug-info=build/debug-info; if ($LASTEXITCODE -ne 0) { throw "Android APK build failed: $Directory" } }
  finally { Pop-Location }
  Copy-Item (Join-Path $Directory 'build\app\outputs\flutter-apk\app-release.apk') (Join-Path $OutDir $Name) -Force
}
function Pack-Signed([string]$Name) {
  $source = Join-Path $PackageDir $Name
  $target = Join-Path $OutDir "$Name.appx"
  Set-PackageVersion (Join-Path $source 'AppxManifest.xml')
  & $MakeAppx pack /d $source /p $target /o
  if ($LASTEXITCODE -ne 0) { throw "AppX packaging failed: $Name" }
  if ($UseCertificateStore) {
    & $SignTool sign /fd SHA256 /s My /sha1 $CertificateThumbprint $target
  } else {
    & $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $target
  }
  if ($LASTEXITCODE -ne 0) { throw "AppX signing failed: $Name" }
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
  $WixExt = Join-Path $WixDir 'WixUIExtension.dll'
  & "$WixDir\candle.exe" -nologo -arch x64 `
    "-dVersion=$Version" `
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

  Write-Host "Successfully built and signed $MsiOut" -ForegroundColor Green
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
  Build-Apk (Join-Path $RootDir 'apps\boardest_teacher') 'bst-teacher.apk'
  Build-Apk (Join-Path $RootDir 'apps\boardest_teacher_lite') 'bst-teacher-lite.apk'
  Build-Apk (Join-Path $RootDir 'apps\boardest_class_lite') 'bst-class-lite.apk'
  Copy-Item (Join-Path $OutDir 'bst-class-lite.apk') (Join-Path $OutDir 'boardest-class-lite.apk') -Force
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

foreach ($name in @('boardest', 'bst-overlay-panser', 'boardest-class-lite')) { Pack-Signed $name }
Pack-TeacherMsi $AppVersion
Copy-Item $CerFile (Join-Path $OutDir 'BoardestCert.cer') -Force

$DownloadDir = Join-Path $RootDir 'infra\download_web'
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
foreach ($file in @('boardest.appx', 'bst-teacher.msi', 'bst-overlay-panser.appx', 'boardest-class-lite.appx', 'boardest.apk', 'bst-teacher.apk', 'bst-teacher-lite.apk', 'bst-class-lite.apk', 'boardest-class-lite.apk', 'BoardestCert.cer')) {
  $source = Join-Path $OutDir $file
  if (Test-Path $source) { Copy-Item $source (Join-Path $DownloadDir $file) -Force }
}
Write-Host 'Official AppX/MSI/APK artifacts are ready in dist\appx.' -ForegroundColor Green
