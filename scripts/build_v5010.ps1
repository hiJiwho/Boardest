$ErrorActionPreference = 'Stop'
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Boardest v5.0.10 Release Build Pipeline" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$rootDir = "c:\Users\jiwho\Documents\boardest"

# 1. Android APK 빌드 (2종: Class Pro & Class Lite)
Write-Host "`n== [1/4] Building Boardest Class Pro APK... ==" -ForegroundColor Yellow
Set-Location "$rootDir\apps\boardest"
flutter build apk --release
Copy-Item "$rootDir\apps\boardest\build\app\outputs\flutter-apk\app-release.apk" "$rootDir\infra\download_web\boardest.apk" -Force
Copy-Item "$rootDir\apps\boardest\build\app\outputs\flutter-apk\app-release.apk" "$rootDir\infra\downloads_hub_web\boardest.apk" -Force
Write-Host "✔ Class Pro APK built & copied." -ForegroundColor Green

Write-Host "`n== [2/4] Building Boardest Class Lite APK... ==" -ForegroundColor Yellow
Set-Location "$rootDir\apps\boardest_class_lite"
flutter build apk --release
Copy-Item "$rootDir\apps\boardest_class_lite\build\app\outputs\flutter-apk\app-release.apk" "$rootDir\infra\download_web\bst-class-lite.apk" -Force
Copy-Item "$rootDir\apps\boardest_class_lite\build\app\outputs\flutter-apk\app-release.apk" "$rootDir\infra\downloads_hub_web\bst-class-lite.apk" -Force
Write-Host "✔ Class Lite APK built & copied." -ForegroundColor Green

# 2. Web 빌드 (3종)
Write-Host "`n== [3/4] Building Web Apps... ==" -ForegroundColor Yellow
Set-Location "$rootDir\apps\boardest"
flutter build web --release --base-href /
Copy-Item -Recurse -Force "$rootDir\apps\boardest\build\web\*" "$rootDir\infra\demo_web\class\"

Set-Location "$rootDir\apps\boardest_teacher"
flutter build web --release --base-href /
Copy-Item -Recurse -Force "$rootDir\apps\boardest_teacher\build\web\*" "$rootDir\infra\demo_web\teacher\"
Copy-Item -Recurse -Force "$rootDir\apps\boardest_teacher\build\web\*" "$rootDir\infra\teacher_timetable_web\"

Set-Location "$rootDir\apps\boardest_teacher_lite"
flutter build web --release --base-href /lite/
Copy-Item -Recurse -Force "$rootDir\apps\boardest_teacher_lite\build\web\*" "$rootDir\infra\teacher_timetable_web\lite\"
Write-Host "✔ Web apps built & copied." -ForegroundColor Green

Set-Location "$rootDir"
Write-Host "`n==========================================" -ForegroundColor Green
Write-Host " 🎉 Boardest v5.0.10 Build Completed Successfully!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
