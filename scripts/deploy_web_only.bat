@echo off
setlocal
cd /d "%~dp0.."
set "PROJECT=jiwhosboardest"

echo [1/4] Checking apps\boardest web build...
if not exist apps\boardest\build\web\index.html (
  echo Error: apps\boardest\build\web not found!
  exit /b 1
)

echo [2/4] Building apps\boardest_teacher web release...
pushd apps\boardest_teacher
call flutter pub get || exit /b 1
call flutter build web --release --no-tree-shake-icons || exit /b 1
popd

echo [3/4] Building apps\boardest_teacher_lite web release...
pushd apps\boardest_teacher_lite
call flutter pub get || exit /b 1
call flutter build web --release --base-href /lite/ --no-tree-shake-icons || exit /b 1
popd
if not exist apps\boardest_teacher\build\web\lite mkdir apps\boardest_teacher\build\web\lite
xcopy /E /I /Y apps\boardest_teacher_lite\build\web\* apps\boardest_teacher\build\web\lite\ >nul || exit /b 1

echo [4/4] Deploying to Firebase Hosting (%PROJECT%)...
call firebase.cmd deploy --only hosting --project %PROJECT% || exit /b 1

echo ========================================================
echo Web deployment completed successfully to boardest.web.app!
echo ========================================================
