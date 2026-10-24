$ErrorActionPreference = 'Stop'
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Boardest v5.0.11 Build & Deploy Pipeline" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$rootDir = "c:\Users\jiwho\Documents\boardest"

# 1. Android APK 빌드 (2종: Class Pro & Class Lite)
Write-Host "`n== [1/4] Building Boardest Class Pro APK... ==" -ForegroundColor Yellow
Set-Location "$rootDir\apps\boardest"
cmd.exe /c flutter build apk --release
Copy-Item "$rootDir\apps\boardest\build\app\outputs\flutter-apk\app-release.apk" "$rootDir\infra\download_web\boardest.apk" -Force
Copy-Item "$rootDir\apps\boardest\build\app\outputs\flutter-apk\app-release.apk" "$rootDir\infra\downloads_hub_web\boardest.apk" -Force
Write-Host "✔ Class Pro APK built & copied." -ForegroundColor Green

Write-Host "`n== [2/4] Building Boardest Class Lite APK... ==" -ForegroundColor Yellow
Set-Location "$rootDir\apps\boardest_class_lite"
cmd.exe /c flutter build apk --release
Copy-Item "$rootDir\apps\boardest_class_lite\build\app\outputs\flutter-apk\app-release.apk" "$rootDir\infra\download_web\bst-class-lite.apk" -Force
Copy-Item "$rootDir\apps\boardest_class_lite\build\app\outputs\flutter-apk\app-release.apk" "$rootDir\infra\downloads_hub_web\bst-class-lite.apk" -Force
Write-Host "✔ Class Lite APK built & copied." -ForegroundColor Green

# 2. Web 빌드 (3종)
Write-Host "`n== [3/4] Building Web Apps... ==" -ForegroundColor Yellow
Set-Location "$rootDir\apps\boardest"
cmd.exe /c flutter build web --release --base-href /
Copy-Item -Recurse -Force "$rootDir\apps\boardest\build\web\*" "$rootDir\infra\demo_web\class\"

Set-Location "$rootDir\apps\boardest_teacher"
cmd.exe /c flutter build web --release --base-href /
Copy-Item -Recurse -Force "$rootDir\apps\boardest_teacher\build\web\*" "$rootDir\infra\demo_web\teacher\"
Copy-Item -Recurse -Force "$rootDir\apps\boardest_teacher\build\web\*" "$rootDir\infra\teacher_timetable_web\"

Set-Location "$rootDir\apps\boardest_teacher_lite"
cmd.exe /c flutter build web --release --base-href /lite/
Copy-Item -Recurse -Force "$rootDir\apps\boardest_teacher_lite\build\web\*" "$rootDir\infra\teacher_timetable_web\lite\"
Write-Host "✔ Web apps built & copied." -ForegroundColor Green

# 3. Firebase Hosting 배포
Write-Host "`n== [4/4] Deploying to Firebase Hosting... ==" -ForegroundColor Yellow
Set-Location "$rootDir"
cmd.exe /c firebase deploy --only hosting
Write-Host "✔ Firebase Hosting deploy complete." -ForegroundColor Green

# 4. GitHub Release v5.0.11 생성
Write-Host "`n== Creating GitHub Release v5.0.11... ==" -ForegroundColor Yellow
cmd.exe /c gh release create v5.0.11 infra\download_web\boardest.apk infra\download_web\bst-class-lite.apk infra\download_web\bst-teacher.apk infra\download_web\bst-teacher-lite.apk infra\download_web\BoardestCert.cer infra\download_web\bst-teacher.msi infra\download_web\boardest.appx -R hiJiwho/Boardest --title "Boardest v5.0.11" --notes "### Boardest v5.0.11 Release Notes`n- Unified TBP & HTMLP Engine: 교과서(TBP)와 프레젠터(HTMLP) 단일 dHash 엔진 통합`n- Native Webview Optimization: Windows 및 Android 네이티브 웹뷰 기본 적용`n- hijiwho/boardbook Sync: 5초 포커스 감지 + 페이지 전환 1초 후 자동 판서 교체`n- Cloud Folder as File: TBP/HTMLP 폴더를 탐색기에서 단일 파일로 표출 및 즉시 실행`n- Classroom Bookshelf Modal: Cloud 없이도 지학사/비바샘/엠티처/티셀파/Canva 등 기본 교과서 및 URL 즉시 실행 지원`n- App Header Version Badge: 앱 이름 옆 버전 뱃지를 V.5.0.11로 통일"
Write-Host "✔ GitHub Release v5.0.11 published." -ForegroundColor Green

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host " 🎉 Boardest v5.0.11 Build & Deploy Succeeded!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
