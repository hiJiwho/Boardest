param(
  [string]$AppVersion = '5.6.2'
)

$ErrorActionPreference = 'Stop'
$InstallerDir = $PSScriptRoot
$RootDir = Split-Path (Split-Path $InstallerDir -Parent) -Parent
$DistDir = Join-Path $RootDir 'dist'
$OutDir = Join-Path $DistDir 'appx'
$CertFile = Join-Path $RootDir 'certs\BoardestCert.pfx'
$CerFile = Join-Path $RootDir 'certs\BoardestCert.cer'
$CertPassword = $env:BOARDEST_CERT_PASSWORD
$SignTool = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
$CSharpCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

# Locate Assets
$PkgDir = Join-Path $RootDir 'apps\boardest\build\windows\x64\packages\Microsoft.Web.WebView2'
$CoreDll = Join-Path $PkgDir 'lib\net45\Microsoft.Web.WebView2.Core.dll'
$WinFormsDll = Join-Path $PkgDir 'lib\net45\Microsoft.Web.WebView2.WinForms.dll'
$LoaderDll = Join-Path $PkgDir 'build\native\x64\WebView2Loader.dll'
$AppIcon = Join-Path $RootDir 'apps\boardest\windows\runner\resources\app_icon.ico'
$AppManifest = Join-Path $InstallerDir 'app.manifest'

# Source file (단일 통합 인스톨러/언인스톨러)
$UnifiedInstallCs = Join-Path $InstallerDir 'BoardestInstaller.cs'

foreach ($f in @($CoreDll, $WinFormsDll, $LoaderDll, $AppIcon, $AppManifest, $CerFile, $CSharpCompiler, $UnifiedInstallCs)) {
  if (-not (Test-Path $f)) {
    throw "Required file not found for installer build: $f"
  }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$BaseReferences = @(
  '/r:System.dll',
  '/r:System.Core.dll',
  '/r:System.Drawing.dll',
  '/r:System.Windows.Forms.dll',
  '/r:System.IO.Compression.dll',
  '/r:System.IO.Compression.FileSystem.dll',
  "/r:$CoreDll",
  "/r:$WinFormsDll"
)

# 초경량 필수 리소스만 임베딩 (중복 exe 및 거대 html 제거)
$LightResources = @(
  "/resource:$CoreDll,Microsoft.Web.WebView2.Core.dll",
  "/resource:$WinFormsDll,Microsoft.Web.WebView2.WinForms.dll",
  "/resource:$LoaderDll,WebView2Loader.dll",
  "/resource:$CerFile,BoardestCert.cer"
)

function Sign-File([string]$targetFile) {
  if (Test-Path $SignTool) {
    Write-Host "Signing $targetFile..." -ForegroundColor Gray
    if ([string]::IsNullOrWhiteSpace($CertPassword)) {
      $PublicCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CerFile)
      & $SignTool sign /fd SHA256 /s My /sha1 $PublicCertificate.Thumbprint $targetFile
    } else {
      & $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $targetFile
    }
  }
}

Write-Host "=== Building Ultra-Lightweight Boardest Unified Online Installer (v$AppVersion) ===" -ForegroundColor Cyan

# 1. Compile Unified Online Installer (boardest-installer.exe) with requireAdministrator manifest
$UnifiedExe = Join-Path $OutDir 'boardest-installer.exe'
Write-Host "Compiling Unified Online Installer ($UnifiedExe)..." -ForegroundColor Yellow
$unifiedArgs = @(
  '/nologo',
  '/target:winexe',
  "/out:$UnifiedExe",
  "/win32icon:$AppIcon",
  "/win32manifest:$AppManifest"
) + $BaseReferences + $LightResources + @($UnifiedInstallCs)

& $CSharpCompiler @unifiedArgs
if ($LASTEXITCODE -ne 0) { throw "Compilation failed for boardest-installer.exe" }
Sign-File $UnifiedExe

# 2. Duplicate to installer.exe and uninstall.exe (동일 바이너리가 이름 및 인자에 따라 자동 모드 전환)
$InstallerExe = Join-Path $OutDir 'installer.exe'
Copy-Item $UnifiedExe $InstallerExe -Force
$UninstExe = Join-Path $OutDir 'uninstall.exe'
Copy-Item $UnifiedExe $UninstExe -Force

# 3. Create Named Variants (Executable name determines default app: Class / Teacher / Cloud)
$VariantNames = @(
  'boardest-class.exe',
  'boardest-class-lite.exe',
  'boardest-teacher.exe',
  'boardest-cloud.exe',
  'boardest-teacher-uninstaller.exe',
  'boardest-class-installer.exe',
  'boardest-class-lite-installer.exe',
  'boardest-teacher-installer.exe',
  'boardest-cloud-installer.exe',
  'Boardest-Class-Setup.exe',
  'Boardest-Class-Lite-Setup.exe',
  'Boardest-Teacher-Setup.exe',
  'Boardest-Cloud-Setup.exe'
)

foreach ($name in $VariantNames) {
  $dest = Join-Path $OutDir $name
  Copy-Item $UnifiedExe $dest -Force
}

# 4. Distribute to web hubs
$DownloadWeb = Join-Path $RootDir 'infra\download_web'
$DownloadsHubWeb = Join-Path $RootDir 'infra\downloads_hub_web'

$FilesToDeploy = @('boardest-installer.exe', 'installer.exe', 'uninstall.exe') + $VariantNames

foreach ($f in $FilesToDeploy) {
  $src = Join-Path $OutDir $f
  if (Test-Path $src) {
    if (Test-Path $DownloadWeb) { Copy-Item $src (Join-Path $DownloadWeb $f) -Force }
    if (Test-Path $DownloadsHubWeb) { Copy-Item $src (Join-Path $DownloadsHubWeb $f) -Force }
  }
}

Write-Host "=== Unified Online Installer Built and Replicated Successfully! ===" -ForegroundColor Green
