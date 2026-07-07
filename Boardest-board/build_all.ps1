#!/usr/bin/env pwsh
#Requires -Version 5.0

$ErrorActionPreference = "Stop"
$projectRoot = "c:\Users\jiwho\Documents\Boardest"

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Status {
    param([string]$Text)
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Text" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Text)
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] ERROR: $Text" -ForegroundColor Red
}

Set-Location $projectRoot
Write-Header "Boardest Build Script (Android + Windows)"

# Check Flutter
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Status "Flutter: $flutterVersion"
}
catch {
    Write-Error-Custom "Flutter not found. Please install Flutter."
    exit 1
}

# Build Android APK
Write-Status "[1/2] Building Android APK..."
try {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build apk failed"
    }
    Write-Status "Android APK built successfully"
    
    # Copy to outputs
    $outputDir = "build\outputs\apk"
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$outputDir\app-release.apk" -Force
    Write-Status "Saved to: $outputDir\app-release.apk"
}
catch {
    Write-Error-Custom "Android build failed: $_"
    exit 1
}

Write-Host ""

# Build Windows Release
Write-Status "[2/2] Building Windows release..."
try {
    Stop-Process -Name boardest -Force -ErrorAction SilentlyContinue
    Stop-Process -Name boardest_ppt_overlay -Force -ErrorAction SilentlyContinue
    Stop-Process -Name watchdog -Force -ErrorAction SilentlyContinue
} catch {}
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build windows failed"
    }
    Write-Status "Windows release built successfully"
    
    # Copy to outputs
    $outputDir = "build\outputs\windows"
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    $winSrc = "build\windows\x64\runner\Release"
    if (-not (Test-Path $winSrc)) {
        $winSrc = "build\windows\runner\Release"
    }

    # Compile and inject the native C# binaries (Watchdog & PowerPoint Overlay)
    Write-Status "Compiling C# Watchdog and PowerPoint Overlay..."
    try {
        $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
        if (Test-Path $csc) {
            # Compile watchdog
            & $csc /target:exe /out:watchdog.exe watchdog.cs | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Copy-Item "watchdog.exe" "$winSrc\watchdog.exe" -Force
                Write-Status "Watchdog compiled and copied to build source"
            } else {
                Write-Error-Custom "Watchdog compilation failed. Proceeding with existing binary."
            }
            
            # Compile PPT overlay
            & $csc /target:winexe /out:boardest_ppt_overlay.exe /lib:C:\Windows\Microsoft.NET\Framework64\v4.0.30319,C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF /r:System.dll,System.Core.dll,WindowsBase.dll,PresentationCore.dll,PresentationFramework.dll,System.Xaml.dll boardest_ppt_overlay.cs | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Copy-Item "boardest_ppt_overlay.exe" "$winSrc\boardest_ppt_overlay.exe" -Force
                Write-Status "PowerPoint Overlay compiled and copied to build source"
            } else {
                Write-Error-Custom "PowerPoint Overlay compilation failed."
            }
            
            # Compile PPT helper (COM bridge)
            if (Test-Path "boardest_ppt_helper.cs") {
                & $csc /target:exe /out:boardest_ppt_helper.exe boardest_ppt_helper.cs | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Copy-Item "boardest_ppt_helper.exe" "$winSrc\boardest_ppt_helper.exe" -Force
                    Write-Status "PowerPoint COM Helper compiled and copied to build source"
                } else {
                    Write-Error-Custom "PowerPoint COM Helper compilation failed."
                }
            }
        } else {
            Write-Error-Custom "csc.exe not found at $csc"
        }
    } catch {
        Write-Error-Custom "Failed to compile C# helpers: $_"
    }

    Copy-Item "$winSrc\*" "$outputDir\Release\" -Recurse -Force
    Write-Status "Saved to: $outputDir\Release"
}
catch {
    Write-Error-Custom "Windows build failed: $_"
    exit 1
}

Write-Header "All builds completed successfully!"
Write-Host "Android APK:`n  build\outputs\apk\app-release.apk"
Write-Host ""
Write-Host "Windows App:`n  build\outputs\windows\Release\boardest.exe"
Write-Host ""
