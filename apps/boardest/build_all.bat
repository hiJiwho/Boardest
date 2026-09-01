@echo off

setlocal enabledelayedexpansion



cd /d "%~dp0"



echo ============================================

echo Boardest Build Script (Android APK + Windows MSI)

echo ============================================

echo.



echo [1/4] Building Android APK...

call flutter build apk --release

if %ERRORLEVEL% NEQ 0 (

    echo ERROR: Android APK build failed

    goto end

)

if not exist "build\outputs\apk" mkdir "build\outputs\apk"

copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\outputs\apk\app-release.apk"

echo OK: build\outputs\apk\app-release.apk

echo.



echo [2/4] Building Windows release...

call flutter build windows --release

if %ERRORLEVEL% NEQ 0 (

    echo ERROR: Windows build failed

    goto end

)



set "WIN_SRC=build\windows\x64\runner\Release"

if not exist "%WIN_SRC%" set "WIN_SRC=build\windows\runner\Release"



echo [3/4] Compiling C# helpers...

set "CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if exist "%CSC%" (

    "%CSC%" /target:exe /out:watchdog.exe watchdog.cs

    if exist watchdog.exe copy /Y watchdog.exe "%WIN_SRC%\watchdog.exe"



    set "FRAME=C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
    set "WPF=%FRAME%\WPF"
    "%CSC%" /target:winexe /out:boardest_ppt_overlay.exe /r:System.dll,System.Core.dll,"%WPF%\WindowsBase.dll","%WPF%\PresentationCore.dll","%WPF%\PresentationFramework.dll","%FRAME%\System.Xaml.dll" boardest_ppt_overlay.cs

    if exist boardest_ppt_overlay.exe copy /Y boardest_ppt_overlay.exe "%WIN_SRC%\boardest_ppt_overlay.exe"



    if exist boardest_ppt_helper.cs (

        "%CSC%" /target:exe /out:boardest_ppt_helper.exe boardest_ppt_helper.cs

        if exist boardest_ppt_helper.exe copy /Y boardest_ppt_helper.exe "%WIN_SRC%\boardest_ppt_helper.exe"

    )

) else (

    echo WARNING: csc.exe not found - copy existing helpers manually if needed

)



if not exist "build\outputs\windows" mkdir "build\outputs\windows"

if exist "%WIN_SRC%" (

    xcopy "%WIN_SRC%" "build\outputs\windows\Release" /E /I /Y /Q

)

echo OK: build\outputs\windows\Release\boardest.exe

echo.



echo [4/4] Building MSI (WiX v4)...

where wix >nul 2>&1

if %ERRORLEVEL% EQU 0 (

    wix build installer\boardest_v4.wxs installer\boardest_harvest.wxs -d SourceDir="%CD%\build\outputs\windows\Release" -o build\outputs\Boardest.msi

    if %ERRORLEVEL% EQU 0 (

        echo OK: build\outputs\Boardest.msi

    ) else (

        echo WARNING: MSI build failed - run manually: wix build installer\boardest_v4.wxs installer\boardest_harvest.wxs -d SourceDir=build\outputs\windows\Release -o build\outputs\Boardest.msi

    )

) else (

    echo WARNING: wix CLI not in PATH - skip MSI. Install WiX Toolset v4 and retry.

)



echo.

echo ============================================

echo Build finished

echo ============================================

echo APK: build\outputs\apk\app-release.apk

echo EXE: build\outputs\windows\Release\boardest.exe

echo MSI: build\outputs\Boardest.msi (if WiX succeeded)

echo.



:end

endlocal

