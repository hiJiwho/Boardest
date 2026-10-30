param(
  [string]$AppVersion = '5.3.7'
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
$HtmlFile = Join-Path $InstallerDir 'installer.html'
$AppLogo = Join-Path $RootDir 'apps\boardest\assets\icons\app_logo.png'
$AppIcon = Join-Path $RootDir 'apps\boardest\windows\runner\resources\app_icon.ico'

# Source files
$TeacherUninstCs = Join-Path $InstallerDir 'BoardestTeacherUninstaller.cs'
$TeacherInstallCs = Join-Path $InstallerDir 'BoardestTeacherInstaller.cs'
$ClassInstallCs = Join-Path $InstallerDir 'BoardestClassInstaller.cs'
$CloudInstallCs = Join-Path $InstallerDir 'BoardestCloudInstaller.cs'

foreach ($f in @($CoreDll, $WinFormsDll, $LoaderDll, $HtmlFile, $AppLogo, $AppIcon, $CerFile, $CSharpCompiler, $TeacherUninstCs, $TeacherInstallCs, $ClassInstallCs, $CloudInstallCs)) {
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

$BaseResources = @(
  "/resource:$CoreDll,Microsoft.Web.WebView2.Core.dll",
  "/resource:$WinFormsDll,Microsoft.Web.WebView2.WinForms.dll",
  "/resource:$LoaderDll,WebView2Loader.dll",
  "/resource:$HtmlFile,installer.html",
  "/resource:$AppLogo,app_logo.png"
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

Write-Host "=== Building Dedicated Webview2 Installers & Uninstaller (v$AppVersion) ===" -ForegroundColor Cyan

# 1. Compile Teacher Uninstaller (uninstall.exe)
$UninstExe = Join-Path $OutDir 'uninstall.exe'
Write-Host "Compiling Teacher Uninstaller ($UninstExe)..." -ForegroundColor Yellow
$uninstArgs = @('/nologo', '/target:winexe', "/out:$UninstExe", "/win32icon:$AppIcon") + $BaseReferences + $BaseResources + @($TeacherUninstCs)
& $CSharpCompiler @uninstArgs
if ($LASTEXITCODE -ne 0) { throw "Compilation failed for uninstall.exe" }
Sign-File $UninstExe

# 2. Compile Teacher Installer (boardest-teacher-installer.exe)
$TeacherExe = Join-Path $OutDir 'boardest-teacher-installer.exe'
Write-Host "Compiling Teacher Installer ($TeacherExe)..." -ForegroundColor Yellow
$teacherResources = $BaseResources + @("/resource:$UninstExe,uninstall.exe")
$teacherArgs = @('/nologo', '/target:winexe', "/out:$TeacherExe", "/win32icon:$AppIcon") + $BaseReferences + $teacherResources + @($TeacherInstallCs)
& $CSharpCompiler @teacherArgs
if ($LASTEXITCODE -ne 0) { throw "Compilation failed for boardest-teacher-installer.exe" }
Sign-File $TeacherExe
Copy-Item $TeacherExe (Join-Path $OutDir 'Boardest-Teacher-Setup.exe') -Force

# 3. Compile Class Installer (boardest-class-installer.exe with embedded MSIX)
$ClassMsix = Join-Path $OutDir 'boardest-class.msix'
if (-not (Test-Path $ClassMsix)) {
  $ClassMsix = Join-Path $OutDir 'boardest.msix'
}
if (-not (Test-Path $ClassMsix)) {
  throw "boardest-class.msix not found in $OutDir"
}

$ClassExe = Join-Path $OutDir 'boardest-class-installer.exe'
Write-Host "Compiling Class Installer with embedded MSIX ($ClassExe)..." -ForegroundColor Yellow
$classResources = $BaseResources + @(
  "/resource:$CerFile,BoardestCert.cer",
  "/resource:$ClassMsix,package.msix"
)
$classArgs = @('/nologo', '/target:winexe', "/out:$ClassExe", "/win32icon:$AppIcon") + $BaseReferences + $classResources + @($ClassInstallCs)
& $CSharpCompiler @classArgs
if ($LASTEXITCODE -ne 0) { throw "Compilation failed for boardest-class-installer.exe" }
Sign-File $ClassExe
Copy-Item $ClassExe (Join-Path $OutDir 'Boardest-Class-Setup.exe') -Force

# 4. Compile Cloud Installer (boardest-cloud-installer.exe with embedded MSIX)
$CloudMsix = Join-Path $OutDir 'boardest-cloud.msix'
if (-not (Test-Path $CloudMsix)) {
  $CloudMsix = Join-Path $OutDir 'boardest-class-cloud.msix'
}
if (-not (Test-Path $CloudMsix)) {
  throw "boardest-cloud.msix not found in $OutDir"
}

$CloudExe = Join-Path $OutDir 'boardest-cloud-installer.exe'
Write-Host "Compiling Cloud Installer with embedded MSIX ($CloudExe)..." -ForegroundColor Yellow
$cloudResources = $BaseResources + @(
  "/resource:$CerFile,BoardestCert.cer",
  "/resource:$CloudMsix,package.msix"
)
$cloudArgs = @('/nologo', '/target:winexe', "/out:$CloudExe", "/win32icon:$AppIcon") + $BaseReferences + $cloudResources + @($CloudInstallCs)
& $CSharpCompiler @cloudArgs
if ($LASTEXITCODE -ne 0) { throw "Compilation failed for boardest-cloud-installer.exe" }
Sign-File $CloudExe
Copy-Item $CloudExe (Join-Path $OutDir 'Boardest-Cloud-Setup.exe') -Force

# 5. Distribute to web hubs
$DownloadWeb = Join-Path $RootDir 'infra\download_web'
$DownloadsHubWeb = Join-Path $RootDir 'infra\downloads_hub_web'

$FilesToDeploy = @(
  'boardest-teacher-installer.exe', 'Boardest-Teacher-Setup.exe',
  'boardest-class-installer.exe', 'Boardest-Class-Setup.exe',
  'boardest-cloud-installer.exe', 'Boardest-Cloud-Setup.exe',
  'uninstall.exe'
)

foreach ($f in $FilesToDeploy) {
  $src = Join-Path $OutDir $f
  if (Test-Path $src) {
    if (Test-Path $DownloadWeb) { Copy-Item $src (Join-Path $DownloadWeb $f) -Force }
    if (Test-Path $DownloadsHubWeb) { Copy-Item $src (Join-Path $DownloadsHubWeb $f) -Force }
  }
}

Write-Host "=== All Dedicated Installers & Uninstaller Built and Deployed Successfully! ===" -ForegroundColor Green
