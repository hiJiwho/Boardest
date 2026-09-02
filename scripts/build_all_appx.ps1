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

Write-Host "=== Starting Full AppX & AppInstaller Packaging Pipeline ===" -ForegroundColor Cyan

# 1. Ensure output directory exists
if (-not (Test-Path $AppxOutDir)) {
    New-Item -ItemType Directory -Path $AppxOutDir -Force | Out-Null
}

# Copy public cert to appx folder for distribution
Copy-Item $CerFile (Join-Path $AppxOutDir "BoardestCert.cer") -Force
Copy-Item (Join-Path $RootDir "certs\install_certificate.bat") (Join-Path $AppxOutDir "install_certificate.bat") -Force

# 2. Package 1: Boardest Main App
Write-Host "`n[1/3] Packaging Boardest Main (jiwho.boardest.bst)..." -ForegroundColor Yellow
$BoardestPkgDir = Join-Path $DistDir "packages\boardest"
$BoardestReleaseDir = Join-Path $RootDir "apps\boardest\build\windows\x64\runner\Release"

# Copy release files excluding helper tools
Get-ChildItem -Path $BoardestReleaseDir | Where-Object { 
    $_.Name -notmatch "boardest_ppt.*|boardest_hwp.*|watchdog.*|\.msix$|\.lib$|\.exp$" 
} | Copy-Item -Destination $BoardestPkgDir -Recurse -Force

$BoardestAppx = Join-Path $AppxOutDir "boardest.appx"
& $MakeAppx pack /d $BoardestPkgDir /p $BoardestAppx /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed for Boardest" }

& $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $BoardestAppx
if ($LASTEXITCODE -ne 0) { throw "SignTool failed for Boardest" }
Write-Host "-> Successfully created and signed boardest.appx" -ForegroundColor Green


# 3. Package 2: Boardest Teacher App
Write-Host "`n[2/3] Packaging Boardest Teacher (jiwho.boardest.teacher)..." -ForegroundColor Yellow
$TeacherPkgDir = Join-Path $DistDir "packages\bst-teacher"
$TeacherReleaseDir = Join-Path $RootDir "apps\boardest_teacher\build\windows\x64\runner\Release"

# Copy release files excluding helper tools
Get-ChildItem -Path $TeacherReleaseDir | Where-Object { 
    $_.Name -notmatch "boardest_ppt.*|boardest_hwp.*|watchdog.*|\.lib$|\.exp$" 
} | Copy-Item -Destination $TeacherPkgDir -Recurse -Force

$TeacherAppx = Join-Path $AppxOutDir "bst-teacher.appx"
& $MakeAppx pack /d $TeacherPkgDir /p $TeacherAppx /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed for Boardest Teacher" }

& $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $TeacherAppx
if ($LASTEXITCODE -ne 0) { throw "SignTool failed for Boardest Teacher" }
Write-Host "-> Successfully created and signed bst-teacher.appx" -ForegroundColor Green


# 4. Package 3: BST Overlay Panser (Extension Plugin)
Write-Host "`n[3/3] Packaging BST Overlay Panser (jiwho.boardest.plugin.overlaypanser)..." -ForegroundColor Yellow
$PanserPkgDir = Join-Path $DistDir "packages\bst-overlay-panser"

# Copy helper tools into Panser package
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

$PanserAppx = Join-Path $AppxOutDir "bst-overlay-panser.appx"
& $MakeAppx pack /d $PanserPkgDir /p $PanserAppx /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed for BST Overlay Panser" }

& $SignTool sign /fd SHA256 /f $CertFile /p $CertPassword $PanserAppx
if ($LASTEXITCODE -ne 0) { throw "SignTool failed for BST Overlay Panser" }
Write-Host "-> Successfully created and signed bst-overlay-panser.appx" -ForegroundColor Green


# 5. Create .appinstaller XML files for all 3 packages
Write-Host "`n[4/4] Creating AppInstaller XML files..." -ForegroundColor Yellow

$repoReleaseBase = "https://github.com/hiJiwho/Boardest/releases/latest/download"

# 5.1 boardest.appinstaller
$boardestAppinstaller = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
    xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="2.9.8.2"
    Uri="$repoReleaseBase/boardest.appinstaller">
    <MainPackage
        Name="jiwho.boardest.bst"
        Publisher="CN=jiwho"
        Version="2.9.8.2"
        ProcessorArchitecture="x64"
        Uri="$repoReleaseBase/boardest.appx" />
    <UpdateSettings>
        <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="false" UpdateBlocksActivation="true"/>
        <AutomaticBackgroundTask/>
        <ForceUpdateFromAnyVersion>true</ForceUpdateFromAnyVersion>
    </UpdateSettings>
</AppInstaller>
"@
Set-Content -Path (Join-Path $AppxOutDir "boardest.appinstaller") -Value $boardestAppinstaller -Encoding UTF8
Write-Host "Created: boardest.appinstaller" -ForegroundColor Green

# 5.2 bst-teacher.appinstaller
$teacherAppinstaller = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
    xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="2.9.8.2"
    Uri="$repoReleaseBase/bst-teacher.appinstaller">
    <MainPackage
        Name="jiwho.boardest.teacher"
        Publisher="CN=jiwho"
        Version="2.9.8.2"
        ProcessorArchitecture="x64"
        Uri="$repoReleaseBase/bst-teacher.appx" />
    <UpdateSettings>
        <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="false" UpdateBlocksActivation="true"/>
        <AutomaticBackgroundTask/>
        <ForceUpdateFromAnyVersion>true</ForceUpdateFromAnyVersion>
    </UpdateSettings>
</AppInstaller>
"@
Set-Content -Path (Join-Path $AppxOutDir "bst-teacher.appinstaller") -Value $teacherAppinstaller -Encoding UTF8
Write-Host "Created: bst-teacher.appinstaller" -ForegroundColor Green

# 5.3 bst-overlay-panser.appinstaller
$panserAppinstaller = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
    xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="1.0.0.0"
    Uri="$repoReleaseBase/bst-overlay-panser.appinstaller">
    <MainPackage
        Name="jiwho.boardest.plugin.overlaypanser"
        Publisher="CN=jiwho"
        Version="1.0.0.0"
        ProcessorArchitecture="x64"
        Uri="$repoReleaseBase/bst-overlay-panser.appx" />
    <UpdateSettings>
        <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="false" UpdateBlocksActivation="true"/>
        <AutomaticBackgroundTask/>
        <ForceUpdateFromAnyVersion>true</ForceUpdateFromAnyVersion>
    </UpdateSettings>
</AppInstaller>
"@
Set-Content -Path (Join-Path $AppxOutDir "bst-overlay-panser.appinstaller") -Value $panserAppinstaller -Encoding UTF8
Write-Host "Created: bst-overlay-panser.appinstaller" -ForegroundColor Green

Write-Host "`n=== All AppX Packages and AppInstaller files built and signed successfully! ===" -ForegroundColor Cyan
