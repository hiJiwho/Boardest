# Build all AppX packages and create AppInstaller manifests
$ErrorActionPreference = "Stop"

$RootDir = "c:\Users\jiwho\Documents\boardest"
$DistDir = Join-Path $RootDir "dist"
$AppxOutDir = Join-Path $DistDir "appx"
$CertFile = Join-Path $RootDir "certs\BoardestCert.pfx"
$CertPassword = "Boardest2026!"
$CerFile = Join-Path $RootDir "certs\BoardestCert.cer"

$MakeAppx = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\makeappx.exe"
$SignTool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"

$AppVersion = "3.0.2.0"
$repoReleaseBase = "https://github.com/hiJiwho/Boardest/releases/latest/download"

Write-Host "=== Starting Full AppX & AppInstaller Packaging Pipeline (v$AppVersion) ===" -ForegroundColor Cyan

# 1. Ensure output directory exists
if (-not (Test-Path $AppxOutDir)) {
    New-Item -ItemType Directory -Path $AppxOutDir -Force | Out-Null
}

# Copy public cert to appx folder for distribution
Copy-Item $CerFile (Join-Path $AppxOutDir "BoardestCert.cer") -Force
Copy-Item (Join-Path $RootDir "certs\install_certificate.bat") (Join-Path $AppxOutDir "install_certificate.bat") -Force

# Update AppxManifest.xml files to match $AppVersion
foreach ($manifestPath in @(
    (Join-Path $DistDir "packages\boardest\AppxManifest.xml"),
    (Join-Path $DistDir "packages\bst-teacher\AppxManifest.xml"),
    (Join-Path $DistDir "packages\bst-overlay-panser\AppxManifest.xml")
)) {
    if (Test-Path $manifestPath) {
        $xml = Get-Content $manifestPath -Raw -Encoding UTF8
        $xml = [regex]::Replace($xml, 'Version="[0-9.]+"', "Version=""$AppVersion""")
        Set-Content -Path $manifestPath -Value $xml -Encoding UTF8
    }
}

# 2. Create .appinstaller XML files (Quiet mode: ShowPrompt="false" UpdateBlocksActivation="false")
Write-Host "`n[1/6] Generating AppInstaller manifests (v$AppVersion)..." -ForegroundColor Yellow

# 2.1 boardest.appinstaller
$boardestAppinstaller = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
    xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="$AppVersion"
    Uri="https://download-boardest.web.app/boardest.appinstaller">
    <MainPackage
        Name="jiwho.boardest.bst"
        Publisher="CN=jiwho"
        Version="$AppVersion"
        ProcessorArchitecture="x64"
        Uri="$repoReleaseBase/boardest.appx" />
    <UpdateSettings>
        <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="true" UpdateBlocksActivation="true"/>
        <AutomaticBackgroundTask/>
        <ForceUpdateFromAnyVersion>true</ForceUpdateFromAnyVersion>
    </UpdateSettings>
</AppInstaller>
"@
$boardestAppinstallerPath = Join-Path $AppxOutDir "boardest.appinstaller"
Set-Content -Path $boardestAppinstallerPath -Value $boardestAppinstaller -Encoding UTF8
Write-Host "Created: boardest.appinstaller" -ForegroundColor Green

# 2.2 bst-teacher.appinstaller
$teacherAppinstaller = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
    xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="$AppVersion"
    Uri="https://download-boardest.web.app/bst-teacher.appinstaller">
    <MainPackage
        Name="jiwho.boardest.teacher"
        Publisher="CN=jiwho"
        Version="$AppVersion"
        ProcessorArchitecture="x64"
        Uri="$repoReleaseBase/bst-teacher.appx" />
    <UpdateSettings>
        <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="true" UpdateBlocksActivation="true"/>
        <AutomaticBackgroundTask/>
        <ForceUpdateFromAnyVersion>true</ForceUpdateFromAnyVersion>
    </UpdateSettings>
</AppInstaller>
"@
$teacherAppinstallerPath = Join-Path $AppxOutDir "bst-teacher.appinstaller"
Set-Content -Path $teacherAppinstallerPath -Value $teacherAppinstaller -Encoding UTF8
Write-Host "Created: bst-teacher.appinstaller" -ForegroundColor Green

# 2.3 bst-overlay-panser.appinstaller
$panserAppinstaller = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
    xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="$AppVersion"
    Uri="$repoReleaseBase/bst-overlay-panser.appinstaller">
    <MainPackage
        Name="jiwho.boardest.plugin.overlaypanser"
        Publisher="CN=jiwho"
        Version="$AppVersion"
        ProcessorArchitecture="x64"
        Uri="$repoReleaseBase/bst-overlay-panser.appx" />
    <UpdateSettings>
        <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="true" UpdateBlocksActivation="true"/>
        <AutomaticBackgroundTask/>
        <ForceUpdateFromAnyVersion>true</ForceUpdateFromAnyVersion>
    </UpdateSettings>
</AppInstaller>
"@
$panserAppinstallerPath = Join-Path $AppxOutDir "bst-overlay-panser.appinstaller"
Set-Content -Path $panserAppinstallerPath -Value $panserAppinstaller -Encoding UTF8
Write-Host "Created: bst-overlay-panser.appinstaller" -ForegroundColor Green

# Copy manifests to assets for in-app access
Copy-Item $boardestAppinstallerPath (Join-Path $RootDir "apps\boardest\assets\boardest.appinstaller") -Force
Copy-Item $teacherAppinstallerPath (Join-Path $RootDir "apps\boardest_teacher\assets\bst-teacher.appinstaller") -Force

# 3. Package 1: Boardest Main App (Sandboxed)
Write-Host "`n[2/6] Building & Packaging Boardest Main (jiwho.boardest.bst)..." -ForegroundColor Yellow
$BoardestAppDir = Join-Path $RootDir "apps\boardest"
Push-Location $BoardestAppDir
try {
    Write-Host "-> Compiling Boardest Windows Release..." -ForegroundColor Cyan
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Flutter build windows failed for Boardest" }
} finally {
    Pop-Location
}

$BoardestPkgDir = Join-Path $DistDir "packages\boardest"
$BoardestReleaseDir = Join-Path $RootDir "apps\boardest\build\windows\x64\runner\Release"

if (Test-Path $BoardestReleaseDir) {
    Get-ChildItem -Path $BoardestReleaseDir | Where-Object { 
        $_.Name -notmatch "boardest_ppt.*|boardest_hwp.*|watchdog.*|\.msix$|\.lib$|\.exp$" 
    } | Copy-Item -Destination $BoardestPkgDir -Recurse -Force
    Write-Host "-> Synchronized fresh binaries from $BoardestReleaseDir" -ForegroundColor Green
}
# Embed .appinstaller directly into package root
Copy-Item $boardestAppinstallerPath (Join-Path $BoardestPkgDir "boardest.appinstaller") -Force
Write-Host "-> Embedded boardest.appinstaller into package root" -ForegroundColor Cyan

$BoardestAppx = Join-Path $AppxOutDir "boardest.appx"
& $MakeAppx pack /d $BoardestPkgDir /p $BoardestAppx /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed for Boardest" }

& $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $BoardestAppx
if ($LASTEXITCODE -ne 0) { throw "SignTool failed for Boardest" }
Write-Host "-> Successfully created and signed boardest.appx" -ForegroundColor Green


# 4. Package 2: Boardest Teacher App (Sandboxed)
Write-Host "`n[3/6] Building & Packaging Boardest Teacher (jiwho.boardest.teacher)..." -ForegroundColor Yellow
$TeacherAppDir = Join-Path $RootDir "apps\boardest_teacher"
Push-Location $TeacherAppDir
try {
    Write-Host "-> Compiling Boardest Teacher Windows Release..." -ForegroundColor Cyan
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Flutter build windows failed for Boardest Teacher" }
} finally {
    Pop-Location
}

$TeacherPkgDir = Join-Path $DistDir "packages\bst-teacher"
$TeacherReleaseDir = Join-Path $RootDir "apps\boardest_teacher\build\windows\x64\runner\Release"

if (Test-Path $TeacherReleaseDir) {
    Get-ChildItem -Path $TeacherReleaseDir | Where-Object { 
        $_.Name -notmatch "boardest_ppt.*|boardest_hwp.*|watchdog.*|\.lib$|\.exp$" 
    } | Copy-Item -Destination $TeacherPkgDir -Recurse -Force
    Write-Host "-> Synchronized fresh binaries from $TeacherReleaseDir" -ForegroundColor Green
}
# Embed .appinstaller directly into package root
Copy-Item $teacherAppinstallerPath (Join-Path $TeacherPkgDir "bst-teacher.appinstaller") -Force
Write-Host "-> Embedded bst-teacher.appinstaller into package root" -ForegroundColor Cyan

$TeacherAppx = Join-Path $AppxOutDir "bst-teacher.appx"
& $MakeAppx pack /d $TeacherPkgDir /p $TeacherAppx /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed for Boardest Teacher" }

& $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $TeacherAppx
if ($LASTEXITCODE -ne 0) { throw "SignTool failed for Boardest Teacher" }
Write-Host "-> Successfully created and signed bst-teacher.appx" -ForegroundColor Green


# 5. Package 3: BST Overlay Panser (Un-sandboxed FullTrust Extension Plugin)
Write-Host "`n[4/6] Packaging BST Overlay Panser (jiwho.boardest.plugin.overlaypanser)..." -ForegroundColor Yellow
$PanserPkgDir = Join-Path $DistDir "packages\bst-overlay-panser"

$helpers = @(
    (Join-Path $TeacherReleaseDir "boardest_ppt_helper.exe"),
    (Join-Path $TeacherReleaseDir "boardest_ppt_overlay.exe"),
    (Join-Path $TeacherReleaseDir "boardest_hwp_overlay.exe"),
    (Join-Path $TeacherReleaseDir "watchdog.exe"),
    (Join-Path $RootDir "installer\driver_installer.exe")
)

foreach ($h in $helpers) {
    if (Test-Path $h) {
        Copy-Item $h $PanserPkgDir -Force
        Write-Host "Included in Panser: $(Split-Path $h -Leaf)" -ForegroundColor Gray
    }
}
# Embed .appinstaller directly into package root
Copy-Item $panserAppinstallerPath (Join-Path $PanserPkgDir "bst-overlay-panser.appinstaller") -Force

$PanserAppx = Join-Path $AppxOutDir "bst-overlay-panser.appx"
& $MakeAppx pack /d $PanserPkgDir /p $PanserAppx /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed for BST Overlay Panser" }

& $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $PanserAppx
if ($LASTEXITCODE -ne 0) { throw "SignTool failed for BST Overlay Panser" }
Write-Host "-> Successfully created and signed bst-overlay-panser.appx" -ForegroundColor Green


# 6. Synchronize .appinstaller manifests to infra/download_web and infra/welcome_web
Write-Host "`n[5/6] Synchronizing .appinstaller files to web distribution directories..." -ForegroundColor Yellow
$DownloadWebDir = Join-Path $RootDir "infra\download_web"
$WelcomeWebDir = Join-Path $RootDir "infra\welcome_web"

if (Test-Path $DownloadWebDir) {
    Copy-Item (Join-Path $AppxOutDir "boardest.appinstaller") (Join-Path $DownloadWebDir "boardest.appinstaller") -Force
    Copy-Item (Join-Path $AppxOutDir "boardest.appinstaller") (Join-Path $DownloadWebDir "bst.appinstaller") -Force
    Copy-Item (Join-Path $AppxOutDir "bst-teacher.appinstaller") (Join-Path $DownloadWebDir "bst-teacher.appinstaller") -Force
    Copy-Item (Join-Path $AppxOutDir "bst-teacher.appinstaller") (Join-Path $DownloadWebDir "teacher.appinstaller") -Force
    Copy-Item (Join-Path $AppxOutDir "bst-overlay-panser.appinstaller") (Join-Path $DownloadWebDir "bst-overlay-panser.appinstaller") -Force
    Write-Host "-> Synchronized all manifests to infra/download_web" -ForegroundColor Green
}

if (Test-Path $WelcomeWebDir) {
    Copy-Item (Join-Path $AppxOutDir "boardest.appinstaller") (Join-Path $WelcomeWebDir "boardest.appinstaller") -Force
    Copy-Item (Join-Path $AppxOutDir "boardest.appinstaller") (Join-Path $WelcomeWebDir "bst.appinstaller") -Force
    Copy-Item (Join-Path $AppxOutDir "bst-teacher.appinstaller") (Join-Path $WelcomeWebDir "bst-teacher.appinstaller") -Force
    Copy-Item (Join-Path $AppxOutDir "bst-teacher.appinstaller") (Join-Path $WelcomeWebDir "teacher.appinstaller") -Force
    Copy-Item (Join-Path $AppxOutDir "bst-overlay-panser.appinstaller") (Join-Path $WelcomeWebDir "bst-overlay-panser.appinstaller") -Force
    Write-Host "-> Synchronized all manifests to infra/welcome_web" -ForegroundColor Green
}

# 7. Build and synchronize Android Release APK
Write-Host "`n[6/6] Building Android Release APK (boardest.apk)..." -ForegroundColor Yellow
$BoardestAppDir = Join-Path $RootDir "apps\boardest"
Push-Location $BoardestAppDir
try {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "Flutter build apk failed with code $LASTEXITCODE" }
    
    $GeneratedApk = Join-Path $BoardestAppDir "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $GeneratedApk)) { throw "Generated APK not found at $GeneratedApk" }
    
    Copy-Item $GeneratedApk (Join-Path $DistDir "boardest.apk") -Force
    Copy-Item $GeneratedApk (Join-Path $AppxOutDir "boardest.apk") -Force
    Write-Host "-> Successfully built and copied boardest.apk to dist/ and dist/appx/" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host "`n=== All AppX Packages, APK and AppInstaller files built and signed successfully! ===" -ForegroundColor Cyan
