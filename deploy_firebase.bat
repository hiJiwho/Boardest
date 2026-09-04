@echo off
chcp 65001 > nul
cd /d "%~dp0"
echo ========================================================
echo  Boardest Release Build + Firebase 배포 스크립트
echo ========================================================
echo.

:: ── Web Build ─────────────────────────────────────────────
echo [1/5] Web 릴리즈 빌드 중...
cd /d "%~dp0apps\boardest"
call flutter clean
call flutter pub get
call flutter build web --release
if errorlevel 1 (
  echo [ERROR] Web 빌드 실패
  pause
  exit /b 1
)

:: ── Windows Build ─────────────────────────────────────────
echo.
echo [2/5] Windows 릴리즈 빌드 중...
call flutter build windows --release
if errorlevel 1 (
  echo [ERROR] Windows 빌드 실패
  pause
  exit /b 1
)

:: ── Android Build ─────────────────────────────────────────
echo.
echo [3/5] Android 릴리즈 빌드 중 (APK)...
call flutter build apk --release
if errorlevel 1 (
  echo [ERROR] Android APK 빌드 실패
  pause
  exit /b 1
)

:: ── Teacher App Web Build ─────────────────────────────────
echo.
echo [4/5] Teacher 앱 Web 릴리즈 빌드 중...
cd /d "%~dp0apps\boardest_teacher"
call flutter clean
call flutter pub get
call flutter build web --release
if errorlevel 1 (
  echo [ERROR] Teacher Web 빌드 실패
  pause
  exit /b 1
)

:: ── Firebase Deploy ───────────────────────────────────────
echo.
echo [5/5] Firebase 배포 중 (hosting + functions + storage)...
cd /d "%~dp0Boadest-Firebase.pub"
call npx -y firebase-tools login
call npx -y firebase-tools deploy --only hosting,functions,storage
if errorlevel 1 (
  echo [ERROR] Firebase 배포 실패
  pause
  exit /b 1
)

echo.
echo ✅ 모든 빌드 및 배포가 완료되었습니다!
pause
