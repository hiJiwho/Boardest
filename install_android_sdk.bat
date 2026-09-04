@echo off
REM ========================================================
REM Boardest Suite - Android SDK & Command Line Tools Installer
REM ========================================================

set SDK_PATH=C:\Android\sdk

echo [1/5] Creating Android SDK directory at %SDK_PATH%...
if not exist "%SDK_PATH%" mkdir "%SDK_PATH%"

echo [2/5] Setting ANDROID_HOME environment variable...
set ANDROID_HOME=%SDK_PATH%

echo [3/5] Downloading Android Command Line Tools...
set ZIP_PATH=%TEMP%\commandlinetools.zip
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -OutFile '%ZIP_PATH%'"

echo [4/5] Extracting Command Line Tools...
if not exist "%SDK_PATH%\cmdline-tools" mkdir "%SDK_PATH%\cmdline-tools"
powershell -Command "Expand-Archive -Path '%ZIP_PATH%' -DestinationPath '%SDK_PATH%\cmdline-tools' -Force"
if exist "%SDK_PATH%\cmdline-tools\cmdline-tools" (
    if exist "%SDK_PATH%\cmdline-tools\latest" rmdir /s /q "%SDK_PATH%\cmdline-tools\latest"
    move "%SDK_PATH%\cmdline-tools\cmdline-tools" "%SDK_PATH%\cmdline-tools\latest" >nul
)

echo [5/5] Installing SDK Platform Tools, Android-34, and Build-Tools...
call "%SDK_PATH%\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="%SDK_PATH%" "platform-tools" "platforms;android-34" "build-tools;34.0.0"

echo Accepting Android licenses...
cmd /c "echo y | %SDK_PATH%\cmdline-tools\latest\bin\sdkmanager.bat --sdk_root=%SDK_PATH% --licenses"

echo Configuring Flutter Android SDK path...
call flutter config --android-sdk "%SDK_PATH%"

echo ========================================================
echo Android SDK installation completed successfully!
echo Run 'flutter doctor' to verify setup.
echo ========================================================
pause
