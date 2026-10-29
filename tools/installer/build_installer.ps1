param(
  [string]$AppVersion = '5.3.6'
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

# Locate WebView2 Package DLLs
$PkgDir = Join-Path $RootDir 'apps\boardest\build\windows\x64\packages\Microsoft.Web.WebView2'
$CoreDll = Join-Path $PkgDir 'lib\net45\Microsoft.Web.WebView2.Core.dll'
$WinFormsDll = Join-Path $PkgDir 'lib\net45\Microsoft.Web.WebView2.WinForms.dll'
$LoaderDll = Join-Path $PkgDir 'build\native\x64\WebView2Loader.dll'
$HtmlFile = Join-Path $InstallerDir 'installer.html'
$CsFile = Join-Path $InstallerDir 'BoardestInstaller.cs'

foreach ($f in @($CoreDll, $WinFormsDll, $LoaderDll, $HtmlFile, $CsFile, $CerFile, $CSharpCompiler)) {
  if (-not (Test-Path $f)) {
    throw "Required file not found for installer build: $f"
  }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$References = @(
  '/r:System.dll',
  '/r:System.Core.dll',
  '/r:System.Drawing.dll',
  '/r:System.Windows.Forms.dll',
  '/r:System.IO.Compression.dll',
  '/r:System.IO.Compression.FileSystem.dll',
  "/r:$CoreDll",
  "/r:$WinFormsDll"
)

$Resources = @(
  "/resource:$CoreDll,Microsoft.Web.WebView2.Core.dll",
  "/resource:$WinFormsDll,Microsoft.Web.WebView2.WinForms.dll",
  "/resource:$LoaderDll,WebView2Loader.dll",
  "/resource:$HtmlFile,installer.html",
  "/resource:$CerFile,BoardestCert.cer"
)

# Product targets to build
$Targets = @(
  @{ Name = 'boardest-teacher-installer.exe'; Alias = 'Boardest-Teacher-Setup.exe' },
  @{ Name = 'boardest-class-installer.exe'; Alias = 'Boardest-Class-Setup.exe' },
  @{ Name = 'boardest-cloud-installer.exe'; Alias = 'Boardest-Cloud-Setup.exe' }
)

Write-Host "=== Building Lightweight WebView2 Online Installers (v$AppVersion) ===" -ForegroundColor Cyan

foreach ($target in $Targets) {
  $outExe = Join-Path $OutDir $target.Name
  Write-Host "Compiling $($target.Name)..." -ForegroundColor Yellow

  $cscArgs = @('/nologo', '/target:winexe', "/out:$outExe") + $References + $Resources + @($CsFile)
  & $CSharpCompiler @cscArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed for $($target.Name)"
  }

  # Digital Signing with Boardest Certificate
  if (Test-Path $SignTool) {
    Write-Host "Signing $($target.Name)..." -ForegroundColor Gray
    if ([string]::IsNullOrWhiteSpace($CertPassword)) {
      $PublicCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CerFile)
      & $SignTool sign /fd SHA256 /s My /sha1 $PublicCertificate.Thumbprint $outExe
    } else {
      & $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $outExe
    }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Signing warning (continuing): $outExe" -ForegroundColor Yellow
    }
  }

  if ($target.Alias) {
    $aliasExe = Join-Path $OutDir $target.Alias
    Copy-Item $outExe $aliasExe -Force
  }
}

# Copy to web distribution hubs
$DownloadWeb = Join-Path $RootDir 'infra\download_web'
$DownloadsHubWeb = Join-Path $RootDir 'infra\downloads_hub_web'

foreach ($target in $Targets) {
  $file = Join-Path $OutDir $target.Name
  if (Test-Path $DownloadWeb) { Copy-Item $file (Join-Path $DownloadWeb $target.Name) -Force }
  if (Test-Path $DownloadsHubWeb) { Copy-Item $file (Join-Path $DownloadsHubWeb $target.Name) -Force }
  if ($target.Alias) {
    $aliasFile = Join-Path $OutDir $target.Alias
    if (Test-Path $DownloadWeb) { Copy-Item $aliasFile (Join-Path $DownloadWeb $target.Alias) -Force }
    if (Test-Path $DownloadsHubWeb) { Copy-Item $aliasFile (Join-Path $DownloadsHubWeb $target.Alias) -Force }
  }
}

Write-Host "=== All Installers Built and Deployed Successfully! ===" -ForegroundColor Green
