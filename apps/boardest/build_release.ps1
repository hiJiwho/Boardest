#!/usr/bin/env pwsh
#Requires -Version 5.0

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$appVersion = "1.0.0"
$appName = "Boardest"

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "  >> $Text" -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [FAIL] $Text" -ForegroundColor Red
}

Set-Location $projectRoot

Write-Header "Boardest Full Build Pipeline"
Write-Host "  Project : $projectRoot"
Write-Host "  Version : $appVersion"
Write-Host "  Time    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

# ─────────────────────────────────────────────
# 0. Prerequisites check
# ─────────────────────────────────────────────
Write-Header "Step 0: Checking Prerequisites"

# Flutter
Write-Step "Checking Flutter..."
try {
    $flutterVer = flutter --version 2>&1 | Select-Object -First 1
    Write-OK "Flutter found: $flutterVer"
} catch {
    Write-Fail "Flutter not found. Please install Flutter from https://flutter.dev"
    exit 1
}

# Java / Android SDK (for APK)
Write-Step "Checking Java..."
try {
    $javaVer = java -version 2>&1 | Select-Object -First 1
    Write-OK "Java: $javaVer"
} catch {
    Write-Fail "Java not found. Android APK build may fail."
}

# WiX Toolset (for MSI)
Write-Step "Checking WiX Toolset..."
$wixPath = $null
$wixCandlePath = $null
$wixLightPath = $null

# Try WiX v3 from PATH
$candleTry = Get-Command "candle.exe" -ErrorAction SilentlyContinue
$lightTry  = Get-Command "light.exe"  -ErrorAction SilentlyContinue

if ($candleTry -and $lightTry) {
    $wixCandlePath = $candleTry.Source
    $wixLightPath  = $lightTry.Source
    Write-OK "WiX v3 found in PATH"
} else {
    # Try common install paths
    $wixPaths = @(
        "C:\Program Files (x86)\WiX Toolset v3.11\bin",
        "C:\Program Files\WiX Toolset v3.11\bin",
        "C:\Program Files (x86)\WiX Toolset v3.14\bin",
        "C:\Program Files\WiX Toolset v3.14\bin"
    )
    foreach ($p in $wixPaths) {
        if (Test-Path "$p\candle.exe") {
            $wixCandlePath = "$p\candle.exe"
            $wixLightPath  = "$p\light.exe"
            Write-OK "WiX v3 found at: $p"
            break
        }
    }
}

# Try WiX v4 (dotnet tool)
if (-not $wixCandlePath) {
    Write-Step "Trying WiX v4 (dotnet tool)..."
    $wixV4 = Get-Command "wix.exe" -ErrorAction SilentlyContinue
    if ($wixV4) {
        Write-OK "WiX v4 (dotnet tool) found"
        $useWixV4 = $true
    } else {
        Write-Step "WiX not found. Installing WiX v4 via dotnet tool..."
        try {
            & dotnet tool install --global wix 2>&1 | Out-Null
            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            $wixV4 = Get-Command "wix.exe" -ErrorAction SilentlyContinue
            if ($wixV4) {
                Write-OK "WiX v4 installed successfully"
                $useWixV4 = $true
            } else {
                Write-Fail "WiX v4 install succeeded but wix.exe not found in PATH. Try reopening the terminal."
                $skipMsi = $true
            }
        } catch {
            Write-Fail "Could not install WiX: $_"
            Write-Host "  MSI packaging will be skipped. Install WiX manually:" -ForegroundColor DarkYellow
            Write-Host "    dotnet tool install --global wix" -ForegroundColor DarkYellow
            $skipMsi = $true
        }
    }
}

# ─────────────────────────────────────────────
# 1. Flutter pub get
# ─────────────────────────────────────────────
Write-Header "Step 1: Flutter pub get"
Write-Step "Running flutter pub get..."
& flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Fail "flutter pub get failed"
    exit 1
}
Write-OK "Dependencies resolved"

# ─────────────────────────────────────────────
# 2. Build Android APK (release)
# ─────────────────────────────────────────────
Write-Header "Step 2: Building Android APK (release)"
Write-Step "Running flutter build apk --release..."
try {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "APK build failed (exit $LASTEXITCODE)" }

    $apkSrc = "build\app\outputs\flutter-apk\app-release.apk"
    $apkOutDir = "build\outputs\apk"
    New-Item -Path $apkOutDir -ItemType Directory -Force | Out-Null
    Copy-Item $apkSrc "$apkOutDir\Boardest-$appVersion.apk" -Force

    $apkSize = [math]::Round((Get-Item "$apkOutDir\Boardest-$appVersion.apk").Length / 1MB, 1)
    Write-OK "APK built successfully ($apkSize MB)"
    Write-Host "  Path: $apkOutDir\Boardest-$appVersion.apk" -ForegroundColor White
    $apkSuccess = $true
} catch {
    Write-Fail "Android APK build failed: $_"
    $apkSuccess = $false
}

# Also build split APKs (per-ABI) for lighter installs
Write-Step "Building split APKs per ABI..."
try {
    & flutter build apk --split-per-abi --release
    if ($LASTEXITCODE -eq 0) {
        $splitDir = "build\app\outputs\flutter-apk"
        $splitOut = "build\outputs\apk\split"
        New-Item -Path $splitOut -ItemType Directory -Force | Out-Null
        Get-ChildItem "$splitDir\app-*-release.apk" | ForEach-Object {
            $dest = "$splitOut\" + $_.Name -replace "app-", "Boardest-$appVersion-"
            Copy-Item $_.FullName $dest -Force
            Write-OK "  $($_.Name) -> $dest"
        }
    }
} catch {
    Write-Host "  Split APK skipped: $_" -ForegroundColor DarkYellow
}

# ─────────────────────────────────────────────
# 3. Build Windows EXE (release)
# ─────────────────────────────────────────────
Write-Header "Step 3: Building Windows App (release)"
Write-Step "Stopping any running instances of Boardest to prevent file locks..."
try {
    Stop-Process -Name boardest -Force -ErrorAction SilentlyContinue
    Stop-Process -Name boardest_ppt_overlay -Force -ErrorAction SilentlyContinue
    Stop-Process -Name watchdog -Force -ErrorAction SilentlyContinue
} catch {}
Write-Step "Running flutter build windows --release..."
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Windows build failed (exit $LASTEXITCODE)" }

    $winSrc = "build\windows\x64\runner\Release"
    if (-not (Test-Path $winSrc)) {
        # fallback older path
        $winSrc = "build\windows\runner\Release"
    }

    # Compile and inject the native binaries
    Write-Step "Compiling C# Watchdog and PowerPoint Overlay..."
    try {
        $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
        if (Test-Path $csc) {
            # Compile watchdog
            & $csc /target:exe /out:watchdog.exe watchdog.cs | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Copy-Item "watchdog.exe" "$winSrc\watchdog.exe" -Force
                Write-OK "Watchdog compiled and copied to build source"
            } else {
                Write-Warning "Watchdog compilation failed. Proceeding with existing binary."
            }
            
            # Compile PPT overlay
            Write-Step "Compiling C# PowerPoint Overlay..."
            & $csc /target:winexe /out:boardest_ppt_overlay.exe /lib:C:\Windows\Microsoft.NET\Framework64\v4.0.30319,C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF /r:System.dll,System.Core.dll,WindowsBase.dll,PresentationCore.dll,PresentationFramework.dll,System.Xaml.dll boardest_ppt_overlay.cs | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Copy-Item "boardest_ppt_overlay.exe" "$winSrc\boardest_ppt_overlay.exe" -Force
                Write-OK "PowerPoint Overlay compiled and copied to build source"
            } else {
                Write-Warning "PowerPoint Overlay compilation failed."
            }

            # Compile HWP overlay
            Write-Step "Compiling C# HWP Overlay..."
            & $csc /target:winexe /out:boardest_hwp_overlay.exe /lib:C:\Windows\Microsoft.NET\Framework64\v4.0.30319,C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF /r:System.dll,System.Core.dll,WindowsBase.dll,PresentationCore.dll,PresentationFramework.dll,System.Xaml.dll boardest_hwp_overlay.cs | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Copy-Item "boardest_hwp_overlay.exe" "$winSrc\boardest_hwp_overlay.exe" -Force
                Write-OK "HWP Overlay compiled and copied to build source"
            } else {
                Write-Warning "HWP Overlay compilation failed."
            }

            # Compile PPT helper (COM bridge)
            if (Test-Path "boardest_ppt_helper.cs") {
                Write-Step "Compiling C# PowerPoint COM Helper..."
                & $csc /target:exe /out:boardest_ppt_helper.exe boardest_ppt_helper.cs | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Copy-Item "boardest_ppt_helper.exe" "$winSrc\boardest_ppt_helper.exe" -Force
                    Write-OK "PowerPoint COM Helper compiled and copied to build source"
                } else {
                    Write-Warning "PowerPoint COM Helper compilation failed."
                }
            }
        } else {
            Write-Warning "csc.exe not found at $csc. Proceeding with existing binaries."
        }
    } catch {
        Write-Warning "Failed to compile binaries: $_. Proceeding with existing binaries."
    }

    $winOutDir = "build\outputs\windows\Release"
    New-Item -Path $winOutDir -ItemType Directory -Force | Out-Null
    Copy-Item "$winSrc\*" $winOutDir -Recurse -Force

    # Double check watchdog.exe, boardest_ppt_overlay.exe, boardest_hwp_overlay.exe in output folder
    if (Test-Path "watchdog.exe") {
        Copy-Item "watchdog.exe" "$winOutDir\watchdog.exe" -Force
    }
    if (Test-Path "boardest_ppt_overlay.exe") {
        Copy-Item "boardest_ppt_overlay.exe" "$winOutDir\boardest_ppt_overlay.exe" -Force
    }
    if (Test-Path "boardest_hwp_overlay.exe") {
        Copy-Item "boardest_hwp_overlay.exe" "$winOutDir\boardest_hwp_overlay.exe" -Force
    }
    if (Test-Path "boardest_ppt_helper.exe") {
        Copy-Item "boardest_ppt_helper.exe" "$winOutDir\boardest_ppt_helper.exe" -Force
    }

    Write-OK "Windows app built successfully"
    Write-Host "  Path: $winOutDir" -ForegroundColor White
    $winSuccess = $true
} catch {
    Write-Fail "Windows build failed: $_"
    $winSuccess = $false
}

# ─────────────────────────────────────────────
# 4. Build Windows MSI Installer
# ─────────────────────────────────────────────
Write-Header "Step 4: Building Windows MSI Installer"

if ($skipMsi) {
    Write-Host "  [SKIP] WiX not available - skipping MSI packaging" -ForegroundColor DarkYellow
} elseif (-not $winSuccess) {
    Write-Host "  [SKIP] Windows build failed - cannot create MSI" -ForegroundColor DarkYellow
} else {
    $winBuildDir = Resolve-Path "build\outputs\windows\Release"
    $msiOutDir   = "build\outputs\msi"
    New-Item -Path $msiOutDir -ItemType Directory -Force | Out-Null

    if ($useWixV4) {
        # ── WiX v4 approach ──────────────────────────────
        Write-Step "Packaging with WiX v4..."

        $wixProjDir = "$projectRoot\installer"
        $msiOutput  = "$msiOutDir\Boardest-$appVersion.msi"

        # Generate a simple wxs using wix build
        $wxsContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="$appName"
           Version="$appVersion.0"
           Manufacturer="$appName"
           UpgradeCode="A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
           Scope="perMachine">

    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <Feature Id="Main">
      <ComponentGroupRef Id="AppFiles" />
      <ComponentRef Id="Shortcut_Desktop" />
      <ComponentRef Id="Shortcut_StartMenu" />
    </Feature>

    <StandardDirectory Id="ProgramFilesFolder">
      <Directory Id="INSTALLFOLDER" Name="$appName" />
    </StandardDirectory>

    <StandardDirectory Id="DesktopFolder">
      <Component Id="Shortcut_Desktop" Guid="B1C2D3E4-F5A6-7890-BCDE-F01234567891">
        <Shortcut Id="Sc_Desktop" Name="$appName"
                  Target="[INSTALLFOLDER]boardest.exe"
                  WorkingDirectory="INSTALLFOLDER"
                  Icon="AppIcon" />
        <RegistryValue Root="HKCU" Key="Software\$appName"
                        Name="DesktopShortcut" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </StandardDirectory>

    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="AppMenuDir" Name="$appName">
        <Component Id="Shortcut_StartMenu" Guid="C2D3E4F5-A6B7-8901-CDEF-012345678902">
          <Shortcut Id="Sc_StartMenu" Name="$appName"
                    Target="[INSTALLFOLDER]boardest.exe"
                    WorkingDirectory="INSTALLFOLDER"
                    Icon="AppIcon" />
          <RemoveFolder Id="RemoveAppMenuDir" Directory="AppMenuDir" On="uninstall" />
          <RegistryValue Root="HKCU" Key="Software\$appName"
                          Name="StartMenuShortcut" Type="integer" Value="1" KeyPath="yes" />
        </Component>
      </Directory>
    </StandardDirectory>

    <Icon Id="AppIcon" SourceFile="$winBuildDir\boardest.exe" />
    <Property Id="ARPPRODUCTICON" Value="AppIcon" />

  </Package>
</Wix>
"@
        # Use wix build with directory harvest
        try {
            # Create a v4-compatible wxs
            $wxsV4Path = "$wixProjDir\boardest_v4.wxs"
            $wxsContent | Set-Content $wxsV4Path -Encoding UTF8

            # Modern WiX v4 approach: write a boardest_harvest.wxs using the <Files> element to recursively harvest the build output directory
            $harvestWxs = "$wixProjDir\boardest_harvest.wxs"
            $harvestContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Fragment>
    <ComponentGroup Id="AppFiles" Directory="INSTALLFOLDER">
      <Files Include="`$(var.SourceDir)\**" />
    </ComponentGroup>
  </Fragment>
</Wix>
"@
            $harvestContent | Set-Content $harvestWxs -Encoding UTF8

            if (Test-Path $harvestWxs) {
                Write-Step "Building MSI..."
                & wix.exe build `
                    -arch x64 `
                    "$wxsV4Path" `
                    "$harvestWxs" `
                    -d "SourceDir=$winBuildDir" `
                    -o $msiOutput 2>&1

                if ($LASTEXITCODE -eq 0 -and (Test-Path $msiOutput)) {
                    $msiSize = [math]::Round((Get-Item $msiOutput).Length / 1MB, 1)
                    Write-OK "MSI created: $msiOutput ($msiSize MB)"
                    $msiSuccess = $true
                } else {
                    throw "wix build returned exit code $LASTEXITCODE"
                }
            } else {
                throw "Harvest step failed"
            }
        } catch {
            Write-Fail "WiX v4 MSI build failed: $_"
            $msiSuccess = $false
        }

    } else {
        # ── WiX v3 approach ──────────────────────────────
        Write-Step "Packaging with WiX v3..."
        $msiOutput = "$msiOutDir\Boardest-$appVersion.msi"
        $wixObjDir = "$projectRoot\installer\obj"
        New-Item -Path $wixObjDir -ItemType Directory -Force | Out-Null

        try {
            # 1. Heat: harvest the release directory into a wxs fragment
            $heatWxs   = "$wixObjDir\harvest.wxs"
            $heatWixDir = Split-Path $wixCandlePath

            Write-Step "Harvesting app files with heat..."
            & "$heatWixDir\heat.exe" dir $winBuildDir `
                -o $heatWxs `
                -cg AppFiles `
                -dr INSTALLFOLDER `
                -scom -sreg -sfrag -srd `
                -var var.SourceDir `
                -ag -nologo 2>&1

            if ($LASTEXITCODE -ne 0) { throw "heat.exe failed (exit $LASTEXITCODE)" }
            Write-OK "Heat harvest completed"

            # 2. Candle: compile both wxs files
            Write-Step "Compiling WiX sources..."
            $mainWxs = "$projectRoot\installer\boardest.wxs"
            & "$wixCandlePath" `
                -arch x64 `
                -dSourceDir="$winBuildDir" `
                -dProductVersion="$appVersion.0" `
                -out "$wixObjDir\" `
                -ext WixUIExtension `
                "$mainWxs" "$heatWxs" 2>&1

            if ($LASTEXITCODE -ne 0) { throw "candle.exe failed (exit $LASTEXITCODE)" }
            Write-OK "Compile completed"

            # 3. Light: link into MSI
            Write-Step "Linking MSI..."
            $wixObjs = Get-ChildItem "$wixObjDir\*.wixobj" | ForEach-Object { $_.FullName }
            & "$wixLightPath" `
                -out $msiOutput `
                -ext WixUIExtension `
                -dSourceDir="$winBuildDir" `
                -b "$winBuildDir" `
                -sice:ICE57 `
                $wixObjs 2>&1

            if ($LASTEXITCODE -ne 0) { throw "light.exe failed (exit $LASTEXITCODE)" }

            if (Test-Path $msiOutput) {
                $msiSize = [math]::Round((Get-Item $msiOutput).Length / 1MB, 1)
                Write-OK "MSI created: $msiOutput ($msiSize MB)"
                $msiSuccess = $true
            } else {
                throw "MSI file not found after light.exe"
            }
        } catch {
            Write-Fail "WiX v3 MSI build failed: $_"
            $msiSuccess = $false
        }
    }
}

# ─────────────────────────────────────────────
# 5. Summary
# ─────────────────────────────────────────────
Write-Header "Build Summary"

$results = @()
$results += [PSCustomObject]@{
    Item   = "Android APK (universal)"
    Status = if ($apkSuccess) { "✓ SUCCESS" } else { "✗ FAILED" }
    Path   = if ($apkSuccess) { "build\outputs\apk\Boardest-$appVersion.apk" } else { "-" }
}
$results += [PSCustomObject]@{
    Item   = "Android APK (split ABI)"
    Status = if ($apkSuccess) { "✓ SUCCESS" } else { "✗ FAILED" }
    Path   = if ($apkSuccess) { "build\outputs\apk\split\" } else { "-" }
}
$results += [PSCustomObject]@{
    Item   = "Windows App (EXE)"
    Status = if ($winSuccess) { "✓ SUCCESS" } else { "✗ FAILED" }
    Path   = if ($winSuccess) { "build\outputs\windows\Release\" } else { "-" }
}
$results += [PSCustomObject]@{
    Item   = "Windows Installer (MSI)"
    Status = if ($msiSuccess) { "✓ SUCCESS" } elseif ($skipMsi) { "- SKIPPED" } else { "✗ FAILED" }
    Path   = if ($msiSuccess) { "build\outputs\msi\Boardest-$appVersion.msi" } else { "-" }
}

$results | Format-Table -AutoSize

Write-Host ""
if ($apkSuccess -and $winSuccess) {
    Write-Host "  All core builds completed! " -ForegroundColor Green -NoNewline
    Write-Host "($(Get-Date -Format 'HH:mm:ss'))" -ForegroundColor DarkGray
} else {
    Write-Host "  Some builds failed. Check logs above." -ForegroundColor Red
}
Write-Host ""
