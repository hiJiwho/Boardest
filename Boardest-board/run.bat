@echo off
chcp 65001 > nul
title Boardest Build Tools

:menu
cls
echo ==================================================
echo              Boardest Build Tools
echo ==================================================
echo  [1] Windows Release Build
echo  [2] Windows Installer Creation Only (EXE - Inno Setup)
echo  [3] Android APK Build + Install and Run on Emulator
echo  [4] Windows Test Run (flutter run -d windows)
echo  [5] Run Existing Windows Build (boardest.exe)
echo  [6] Run / Open Existing Android APK
echo  [Q] Exit
echo ==================================================
set /p choice="Enter your choice: "

if "%choice%"=="1" goto win_build
if "%choice%"=="2" goto win_installer_only
if "%choice%"=="3" goto android_build_run
if "%choice%"=="4" goto win_run_dev
if "%choice%"=="5" goto win_run_existing
if "%choice%"=="6" goto android_run_existing
if /i "%choice%"=="q" exit
goto menu

:win_build
echo.
echo ==================================================
echo [1/2] Compiling C# helper binaries...
echo ==================================================
call :compile_helpers
echo.
echo ==================================================
echo [2/2] Building Windows Release...
echo ==================================================
call flutter build windows --release
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Windows build failed.
) else (
    echo.
    echo [SUCCESS] Windows build completed! (build\windows\x64\runner\Release)
    if exist "build\windows\x64\runner\Release" (
        copy /Y watchdog.exe "build\windows\x64\runner\Release\watchdog.exe" >nul 2>&1
        copy /Y boardest_ppt_overlay.exe "build\windows\x64\runner\Release\boardest_ppt_overlay.exe" >nul 2>&1
        copy /Y boardest_ppt_helper.exe "build\windows\x64\runner\Release\boardest_ppt_helper.exe" >nul 2>&1
    )
    if exist "build\windows\runner\Release" (
        copy /Y watchdog.exe "build\windows\runner\Release\watchdog.exe" >nul 2>&1
        copy /Y boardest_ppt_overlay.exe "build\windows\runner\Release\boardest_ppt_overlay.exe" >nul 2>&1
        copy /Y boardest_ppt_helper.exe "build\windows\runner\Release\boardest_ppt_helper.exe" >nul 2>&1
    )
    if not exist "build\outputs\windows\Release" mkdir "build\outputs\windows\Release"
    copy /Y watchdog.exe "build\outputs\windows\Release\watchdog.exe" >nul 2>&1
    copy /Y boardest_ppt_overlay.exe "build\outputs\windows\Release\boardest_ppt_overlay.exe" >nul 2>&1
    copy /Y boardest_ppt_helper.exe "build\outputs\windows\Release\boardest_ppt_helper.exe" >nul 2>&1
)
pause
goto menu

:win_installer_only
echo.
echo ==================================================
echo [1/1] Generating Inno Setup Installer (EXE)...
echo ==================================================
set "ISCC_PATH="
if exist "%LocalAppData%\Programs\Inno Setup 6\iscc.exe" (
    set "ISCC_PATH=%LocalAppData%\Programs\Inno Setup 6\iscc.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 6\iscc.exe" (
    set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 6\iscc.exe"
) else if exist "C:\Program Files\Inno Setup 6\iscc.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 6\iscc.exe"
)

if "%ISCC_PATH%"=="" (
    echo [ERROR] Inno Setup Compiler (iscc.exe) not found.
    echo Please make sure Inno Setup is installed.
) else (
    echo Inno Setup Path: "%ISCC_PATH%"
    if not exist "dist" mkdir "dist"
    "%ISCC_PATH%" "installer\boardest_setup.iss"
    if %errorlevel% neq 0 (
        echo [ERROR] Installer compilation failed.
    ) else (
        echo [SUCCESS] Installer generated! (dist\Boardest-Setup-1.0.0.exe)
    )
)
pause
goto menu

:android_build_run
echo.
echo ==================================================
echo [1/2] Building Android APK Release...
echo ==================================================
call flutter build apk --release
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Android APK build failed.
    pause
    goto menu
)

echo.
echo ==================================================
echo [2/2] Installing and Running APK on Emulator...
echo ==================================================
set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"

:run_apk_on_emu
where adb >nul 2>nul
if %errorlevel% neq 0 (
    echo [INFO] adb not found. Launching APK via default system handler (Bluestacks, etc.)...
    start "" "%APK_PATH%"
) else (
    adb devices | findstr /r /c:"\	device$" >nul
    if %errorlevel% neq 0 (
        echo [INFO] No active emulator detected. Launching APK via default system handler...
        start "" "%APK_PATH%"
    ) else (
        echo [INFO] Active emulator detected. Installing APK...
        adb install -r "%APK_PATH%"
        if %errorlevel% neq 0 (
            echo [WARNING] APK installation failed. Launching APK via default handler...
            start "" "%APK_PATH%"
        ) else (
            echo [SUCCESS] Installation successful! Launching app...
            adb shell monkey -p com.boardest.comcigan.boardest -c android.intent.category.LAUNCHER 1
        )
    )
)
pause
goto menu

:win_run_dev
echo.
echo ==================================================
echo [1/2] Compiling C# helper binaries...
echo ==================================================
call :compile_helpers
echo.
echo ==================================================
echo [2/2] Running Windows Dev mode (flutter run -d windows)...
echo ==================================================
:: Create debug directories beforehand if possible, so helpers can be copied
if not exist "build\windows\x64\runner\Debug" mkdir "build\windows\x64\runner\Debug" 2>nul
if exist "build\windows\x64\runner\Debug" (
    copy /Y watchdog.exe "build\windows\x64\runner\Debug\watchdog.exe" >nul 2>&1
    copy /Y boardest_ppt_overlay.exe "build\windows\x64\runner\Debug\boardest_ppt_overlay.exe" >nul 2>&1
    copy /Y boardest_ppt_helper.exe "build\windows\x64\runner\Debug\boardest_ppt_helper.exe" >nul 2>&1
)
call flutter run -d windows
pause
goto menu

:win_run_existing
echo.
echo ==================================================
echo Running existing Windows release build...
echo ==================================================
set "RELEASE_DIR="
if exist "build\windows\x64\runner\Release\boardest.exe" (
    set "RELEASE_DIR=build\windows\x64\runner\Release"
) else if exist "build\outputs\windows\Release\boardest.exe" (
    set "RELEASE_DIR=build\outputs\windows\Release"
) else if exist "build\windows\runner\Release\boardest.exe" (
    set "RELEASE_DIR=build\windows\runner\Release"
)

if "%RELEASE_DIR%"=="" goto win_run_existing_missing

start "" /d "%RELEASE_DIR%" "boardest.exe"
echo [SUCCESS] boardest.exe launched from %RELEASE_DIR%!
goto win_run_existing_end

:win_run_existing_missing
echo [ERROR] Built file not found. Please build Windows first (Option 1).

:win_run_existing_end
pause
goto menu

:android_run_existing
echo.
echo ==================================================
echo Running/Opening existing Android APK...
echo ==================================================
set "APK_PATH="
if exist "build\outputs\apk\Boardest-1.0.0.apk" (
    set "APK_PATH=build\outputs\apk\Boardest-1.0.0.apk"
) else if exist "build\app\outputs\flutter-apk\app-release.apk" (
    set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
) else if exist "build\outputs\apk\app-release.apk" (
    set "APK_PATH=build\outputs\apk\app-release.apk"
)

if "%APK_PATH%"=="" (
    echo [ERROR] Existing APK file not found. Please build Android first (Option 3).
    pause
    goto menu
)

echo [SUCCESS] Found existing APK: %APK_PATH%
goto run_apk_on_emu


:compile_helpers
set "CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if exist "%CSC%" (
    echo Compiling watchdog.cs...
    "%CSC%" /target:exe /out:watchdog.exe watchdog.cs >nul 2>&1
    
    echo Compiling boardest_ppt_overlay.cs...
    set "FRAME=C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
    set "WPF=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF"
    "%CSC%" /target:winexe /out:boardest_ppt_overlay.exe /r:System.dll,System.Core.dll,"!WPF!\WindowsBase.dll","!WPF!\PresentationCore.dll","!WPF!\PresentationFramework.dll","!FRAME!\System.Xaml.dll" boardest_ppt_overlay.cs >nul 2>&1
    
    if exist boardest_ppt_helper.cs (
        echo Compiling boardest_ppt_helper.cs...
        "%CSC%" /target:exe /out:boardest_ppt_helper.exe boardest_ppt_helper.cs >nul 2>&1
    )
    echo [SUCCESS] C# helpers compiled successfully.
) else (
    echo [WARNING] csc.exe not found at %CSC%. Using existing binaries.
)
exit /b

