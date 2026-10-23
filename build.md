# Boardest v5.0.9 빌드 및 배포 가이드 (`build.md`)

> **버전**: `5.0.9` (앱 내부 빌드 번호: `5090`, Windows 패키지 버전: `5.0.9.0`)  
> **기준 일시**: 2026-10-23  
> **안드로이드 빌드 범위**: `boardest.apk` (Class Pro) 및 `bst-class-lite.apk` (Class Lite) **2종만 빌드**

---

## 1. 안드로이드 (Android) 빌드

사용자 지정 규칙에 따라 교사용 앱을 제외하고 **Class Pro**와 **Class Lite** 2종만 빌드합니다.

```powershell
# 1-1. Boardest Class Pro APK 빌드
cd c:\Users\jiwho\Documents\boardest\apps\boardest
flutter build apk --release
Copy-Item build\app\outputs\flutter-apk\app-release.apk c:\Users\jiwho\Documents\boardest\infra\download_web\boardest.apk -Force
Copy-Item build\app\outputs\flutter-apk\app-release.apk c:\Users\jiwho\Documents\boardest\infra\downloads_hub_web\boardest.apk -Force

# 1-2. Boardest Class Lite APK 빌드
cd c:\Users\jiwho\Documents\boardest\apps\boardest_class_lite
flutter build apk --release
Copy-Item build\app\outputs\flutter-apk\app-release.apk c:\Users\jiwho\Documents\boardest\infra\download_web\bst-class-lite.apk -Force
Copy-Item build\app\outputs\flutter-apk\app-release.apk c:\Users\jiwho\Documents\boardest\infra\downloads_hub_web\bst-class-lite.apk -Force
```

---

## 2. 웹 (Web) 빌드

각 웹 앱을 빌드하고 호스팅용 정적 디렉터리로 복사합니다.

```powershell
# 2-1. Boardest Class Pro Web
cd c:\Users\jiwho\Documents\boardest\apps\boardest
flutter build web --release --base-href /
Copy-Item -Recurse -Force build\web\* c:\Users\jiwho\Documents\boardest\infra\demo_web\class\

# 2-2. Boardest Teacher Web
cd c:\Users\jiwho\Documents\boardest\apps\boardest_teacher
flutter build web --release --base-href /
Copy-Item -Recurse -Force build\web\* c:\Users\jiwho\Documents\boardest\infra\demo_web\teacher\
Copy-Item -Recurse -Force build\web\* c:\Users\jiwho\Documents\boardest\infra\teacher_timetable_web\

# 2-3. Boardest Teacher Lite Web
cd c:\Users\jiwho\Documents\boardest\apps\boardest_teacher_lite
flutter build web --release --base-href /lite/
Copy-Item -Recurse -Force build\web\* c:\Users\jiwho\Documents\boardest\infra\teacher_timetable_web\lite\
```

---

## 3. Windows 패키지 빌드 (선택 사항)

```powershell
cd c:\Users\jiwho\Documents\boardest
powershell -ExecutionPolicy Bypass -File scripts\build_all_appx.ps1 -AppVersion 5.0.9.0
```

---

## 4. Firebase 호스팅 14개 사이트 배포

```powershell
cd c:\Users\jiwho\Documents\boardest

# 14개 전체 호스팅 타겟 일괄 배포
firebase deploy --only hosting:boardest-hub,hosting:boardest-welcome,hosting:boardest-download,hosting:boardest-downloads,hosting:boardest-tools,hosting:boardest-student,hosting:boardest-launcher,hosting:boardest-app-launcher,hosting:boardest-teacher-oauth,hosting:boardest-demo,hosting:boardest-timetable,hosting:boardest-class-timetable,hosting:boardest-class-lite,hosting:boardest-eat
```

---

## 5. 원클릭 실행 스크립트 (One-Click Runner)

터미널에서 아래 명령을 실행하면 안드로이드 2종 + 웹 빌드 + Firebase 배포까지 자동으로 완료됩니다.

```powershell
cd c:\Users\jiwho\Documents\boardest
powershell -ExecutionPolicy Bypass -Command "
  Write-Host '== [1/3] Android APKs Building... ==' -ForegroundColor Cyan
  Set-Location apps/boardest
  flutter build apk --release
  Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\..\infra\download_web\boardest.apk -Force
  Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\..\infra\downloads_hub_web\boardest.apk -Force

  Set-Location ../boardest_class_lite
  flutter build apk --release
  Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\..\infra\download_web\bst-class-lite.apk -Force
  Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\..\infra\downloads_hub_web\bst-class-lite.apk -Force

  Write-Host '== [2/3] Web Building... ==' -ForegroundColor Cyan
  Set-Location ../boardest
  flutter build web --release --base-href /
  Copy-Item -Recurse -Force build\web\* ..\..\infra\demo_web\class\

  Set-Location ../boardest_teacher
  flutter build web --release --base-href /
  Copy-Item -Recurse -Force build\web\* ..\..\infra\demo_web\teacher\
  Copy-Item -Recurse -Force build\web\* ..\..\infra\teacher_timetable_web\

  Set-Location ../boardest_teacher_lite
  flutter build web --release --base-href /lite/
  Copy-Item -Recurse -Force build\web\* ..\..\infra\teacher_timetable_web\lite\

  Set-Location ../..
  Write-Host '== [3/3] Firebase Deploying... ==' -ForegroundColor Cyan
  firebase deploy --only hosting:boardest-hub,hosting:boardest-welcome,hosting:boardest-download,hosting:boardest-downloads,hosting:boardest-tools,hosting:boardest-student,hosting:boardest-launcher,hosting:boardest-app-launcher,hosting:boardest-teacher-oauth,hosting:boardest-demo,hosting:boardest-timetable,hosting:boardest-class-timetable,hosting:boardest-class-lite,hosting:boardest-eat
  Write-Host '== All 5.0.9 Builds and Deployments Complete! ==' -ForegroundColor Green
"
```
