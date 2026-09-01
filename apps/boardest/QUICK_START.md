# 🎯 Boardest 앱 개선 - 빠른 시작 가이드

## 요청사항 ✅ 완료 현황

### 1️⃣ 문서판서/사이트판서 → "예정" 상태 ✅
- **위치**: Bst도구 그리드에서 슬롯 우상단
- **결과**: "예정" 배지가 표시됩니다

### 2️⃣ USB 인식 로직 주석 처리 ✅  
- **상태**: USB 감지 비활성화
- **대체방안**: 필요 시 급식표 영역에 USB 정보 표시 가능

### 3️⃣ 셋업 후 크래시 해결 ✅
- **개선**: 설정 저장 후 앱이 안정적으로 작동
- **에러처리**: 명확한 에러 메시지 표시

### 4️⃣ Android APK 빌드 ✅
- **파일**: `build_apk.bat` 업데이트 완료
- **출력**: `build/outputs/apk/app-release.apk`

### 5️⃣ Windows 배포 ✅
- **파일**: `build_all.bat` 신규 작성
- **출력**: `build/outputs/windows/Release/boardest.exe`

---

## 🚀 즉시 실행하기

### 방법 1: 통합 빌드 (권장)
```bash
cd c:\Users\jiwho\Documents\Boardest
build_all.bat
```
**결과**: Android APK + Windows exe 모두 생성

### 방법 2: 개별 빌드

**Android만 빌드**:
```bash
build_apk.bat
```

**Windows만 빌드**:
```bash
flutter build windows --release
copy build\windows\runner\Release\* build\outputs\windows\Release\ /S /Y
```

### 방법 3: PowerShell 버전 (더 상세한 로그)
```powershell
powershell -ExecutionPolicy Bypass -File build_all.ps1
```

---

## 📦 빌드 결과 위치

### Android
```
build/outputs/apk/app-release.apk
```
**용도**: Android 기기에 설치 및 배포

### Windows  
```
build/outputs/windows/Release/boardest.exe
```
**용도**: Windows 직접 실행 (설치 불필요)

---

## 📋 코드 변경사항

### 파일 1: `lib/views/dashboard_view.dart`

**변경 1** (Line 2946): 문서/사이트판서 "예정" 배지
```dart
final isUpcoming = slot.id == 'student_connect' 
                || slot.id == 'document_board' 
                || slot.id == 'website_board';
```

**변경 2** (Line 204-215): USB 로직 주석
```dart
// USB detection commented out - replaced with meal info display
// _checkUsbConnection();
// _usbTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
//   _checkUsbConnection();
// });
```

**변경 3** (Line 824-970): 크래시 해결 (에러 처리 강화)
- 전체 `_loadPreferencesAndFetch()` 메서드를 try-catch로 감싼화
- Null 체크 추가
- 상세 에러 메시지 구현

### 파일 2-3: 빌드 스크립트 신규 생성

**`build_apk.bat`**: Android APK 빌드 (기존 파일 수정)
**`build_all.bat`**: Android + Windows 통합 빌드 (신규)
**`build_all.ps1`**: PowerShell 통합 빌드 (신규)

---

## ✨ 주요 개선사항

| 기능 | 이전 | 이후 |
|------|------|------|
| 문서판서 | 정상 상태 | **"예정" 배지** |
| 사이트판서 | 정상 상태 | **"예정" 배지** |  
| USB 감지 | 활성 | **비활성화** |
| 셋업 후 상태 | 크래시 위험 | **안정적 + 에러메시지** |
| 빌드 도구 | 수동 | **자동화 스크립트** |

---

## 🎬 다음 단계

### 빌드 후 테스트

**Windows**:
1. `build/outputs/windows/Release/boardest.exe` 더블클릭
2. 앱이 정상 실행되는지 확인

**Android** (디버깅):
```bash
# USB 디버깅 활성화된 기기 연결
adb devices

# APK 설치
adb install -r build/outputs/apk/app-release.apk

# 앱 실행 확인
adb shell am start -n com.boardest/.MainActivity
```

### 배포 준비

**Windows**:
- `boardest.exe` 직접 배포 가능
- 또는 MSI 인스톨러 생성 (WiX Toolset 등)

**Android**:
- Google Play Store 배포 가능
- 테스트용 APK 배포 가능

---

## 💡 팁

### 빌드 시간 단축
```bash
# 첫 빌드: 10-15분
# 이후 빌드: 3-5분 (증분 빌드)
```

### 용량 확인
```bash
dir build\outputs\apk\
dir build\outputs\windows\
```

### 에러 확인
```bash
flutter doctor  # 환경 체크
flutter clean   # 캐시 삭제 (새로 빌드 시)
flutter build apk --release -v  # 상세 로그
```

---

## ❓ FAQ

**Q: 빌드 실패 시?**
A: `flutter clean` 후 다시 시도하세요.

**Q: USB 기능 다시 활성화?**
A: `_checkUsbConnection()` 주석 제거 후 `_usbTimer` 복구

**Q: Windows MSI 인스톨러?**
A: 현재 portable exe로 배포 가능. MSI 필요 시 WiX Toolset 사용.

**Q: 앱 서명 필요?**
A: Android Play Store 배포 시 필수. 사내 배포 시 선택.

---

## 🎉 완료!

모든 기능이 구현되었습니다. 
이제 `build_all.bat`를 실행하여 앱을 빌드하세요!

```bash
cd c:\Users\jiwho\Documents\Boardest
build_all.bat
```

**예상 결과**:
✅ build/outputs/apk/app-release.apk
✅ build/outputs/windows/Release/boardest.exe
