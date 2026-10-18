@echo off
setlocal
cd /d "%~dp0.."
set "VERSION=4.1.2"
set "APPX_VERSION=4.1.2.0"
set "PROJECT=jiwhosboardest"

echo [1/7] Building Boardest and Teacher web releases...
if /I "%~2"=="--skip-web" goto :web_build_skipped
pushd apps\boardest
call flutter pub get || goto :fail
call flutter build web --release --no-tree-shake-icons || goto :fail
popd

pushd apps\boardest_teacher
call flutter pub get || goto :fail
call flutter build web --release --no-tree-shake-icons || goto :fail
popd

echo [2/7] Building Teacher Lite web release...
pushd apps\boardest_teacher_lite
call flutter pub get || goto :fail
call flutter build web --release --base-href /lite/ --no-tree-shake-icons || goto :fail
popd
if not exist apps\boardest_teacher\build\web\lite mkdir apps\boardest_teacher\build\web\lite
xcopy /E /I /Y apps\boardest_teacher_lite\build\web\* apps\boardest_teacher\build\web\lite\ >nul || goto :fail

:web_build_skipped
if /I "%~2"=="--skip-web" echo Web builds already passed; using their artifacts.
if /I "%~1"=="--skip-native" goto :native_build_skipped
echo [3/7] Preparing Class Lite Android WebView app...
pushd apps\boardest_class_lite
call flutter pub get || goto :fail
popd

echo [4/7] Building Windows packages and all Android APKs...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\build_all_appx.ps1 -AppVersion %APPX_VERSION% || goto :fail
goto :native_build_done

:native_build_skipped
echo [3/7] Windows and all Android builds already passed; using their artifacts.
:native_build_done

echo [5/7] Deploying all Firebase Hosting sites...
call firebase.cmd deploy --only hosting --project %PROJECT% || goto :fail

echo [6/7] Committing and pushing complete source to GitHub...
for %%E in (appx apk cer zip) do for /f "delims=" %%F in ('git ls-files "infra/download_web/*.%%E"') do git rm --cached --ignore-unmatch -- "%%F" || goto :fail
git add -A || goto :fail
git diff --cached --quiet || git commit -m "release: Boardest v%VERSION%" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" || goto :fail
git push origin main || goto :fail

echo [7/7] Publishing binary builds to GitHub Releases...
gh release view v%VERSION% --repo hiJiwho/Boardest >nul 2>&1
if errorlevel 1 (
  gh release create v%VERSION% dist\appx\boardest-windows.zip dist\appx\bst-teacher-windows.zip dist\appx\boardest.appx dist\appx\bst-teacher.appx dist\appx\bst-overlay-panser.appx dist\appx\boardest-class-lite.appx dist\appx\boardest.apk dist\appx\bst-teacher.apk dist\appx\bst-teacher-lite.apk dist\appx\bst-class-lite.apk dist\appx\BoardestCert.cer --repo hiJiwho/Boardest --title "Boardest v%VERSION%" --generate-notes || goto :fail
) else (
  gh release upload v%VERSION% dist\appx\boardest-windows.zip dist\appx\bst-teacher-windows.zip dist\appx\boardest.appx dist\appx\bst-teacher.appx dist\appx\bst-overlay-panser.appx dist\appx\boardest-class-lite.appx dist\appx\boardest.apk dist\appx\bst-teacher.apk dist\appx\bst-teacher-lite.apk dist\appx\bst-class-lite.apk dist\appx\BoardestCert.cer --repo hiJiwho/Boardest --clobber || goto :fail
)

echo [7/7] Verifying GitHub release assets and every published website...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\verify_release.ps1 -Version %VERSION% || goto :fail
echo Completed: v%VERSION% source, Windows, Android, web, hosting, and GitHub uploads verified.
exit /b 0

:fail
echo Build or deployment failed. See the message above; no later release step was run.
exit /b 1
