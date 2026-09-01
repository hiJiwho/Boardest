@echo off
cd /d "c:\Users\jiwho\Documents\Boardest"
echo Building Android APK...
call flutter build apk --release
if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful!
    echo APK location: build\app\outputs\flutter-apk\app-release.apk
    
    REM Copy to outputs folder
    if not exist "build\outputs\apk" mkdir "build\outputs\apk"
    copy "build\app\outputs\flutter-apk\app-release.apk" "build\outputs\apk\app-release.apk"
    echo Copied APK to: build\outputs\apk\app-release.apk
) else (
    echo Build failed with error code %ERRORLEVEL%
)
pause
