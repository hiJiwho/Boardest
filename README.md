# 🚀 Boardest Pro & Board Suite

> **스마트 교육을 위한 차세대 교사용 수업 보조 & 전자칠판 통합 에듀테크 플랫폼**
> 
> Boardest Pro는 교사를 위한 학학/수업 도구(주간 시간표, 급식, 학사달력, BoardBook 디지털 교과서, 판서 뷰어)와 전자칠판 전용 판서 솔루션을 제공하는 Flutter 기반 크로스 플랫폼 대시보드입니다.

---

## 📌 프로젝트 구성 (Subprojects Overview)

| 프로젝트 명 | 역할 및 설명 | 주요 기술 스택 |
| :--- | :--- | :--- |
| **`Boardest-Teacher`** | **교사용 스마트 대시보드 & BoardBook 런처**<br>- 개인/반 주간 시간표, NEIS 급식/쪽지, BoardBook 교과서, 웹판서, Google Drive Cloud 연동 | Flutter (Windows Desktop / Android), Win32 API, WebView2 |
| **`Boardest-board`** | **전자칠판 전용 판서 & 뷰어**<br>- 캔버스 판서, PDF/PPT/HWP 오버레이 판서, USB 동기화, 스마트 수업 도구 | Flutter (Desktop / Android), C# HWP/PPT Helper |
| **`BoardBook`** | **BoardBook 스마트 교과서 엔진**<br>- .bb 디지털 교과서 패키지, 5초 주기 dHash 기반 자동 판서/핫스팟 스위처 | Dart, HTML5, JSON |
| **`Boadest-Firebase.pub`** | **BST Web & Firebase Cloud Service**<br>- 웹 브라우저 연동, bst-t:// 프로토콜, 급식/쪽지 서비스 웹 호스팅 | Firebase Hosting, JavaScript, HTML5 |
| **`Boadest-Plus.edit`** | **Plus 에디터 백엔드 자산** | Node.js, Web Engine |

---

## ✨ 핵심 주요 기능 (Key Features)

1. **🎨 감각적인 macOS 커스텀 창틀 & WM_NCHITTEST 8px 리사이즈**:
   - DWM Rounded Corners (`12px` 모서리 곡선)와 C++ `WM_NCHITTEST` 마우스 테두리 히트 테스트 적용.
   - 창 4개 변과 4개 모서리 마우스 창 크기 조절(`↔`, `↕`, `⤢`)이 100% 부드럽고 수월하게 동작.
2. **📖 BoardBook 5초 주기 dHash 자동 판서/핫스팟 스위처**:
   - 교과서 페이지 전환 시 5초마다 dHash를 자동 추적하여 해당 페이지에 맞는 판서 스트로크와 우클릭 핫스팟 핀을 즉시 불러오고 자동 저장.
3. **📍 우클릭(Secondary Tap) 인터랙티브 핫스팟 핀 (Hotspot Link)**:
   - 판서 레이어 우클릭 시 웹 링크(URL), 로컬 파일(PDF/HWP/PPT), 수업 도구(타이머/계산기/기본판서), 텍스트 메모 핀 생성 및 1-Tap 즉시 실행.
4. **🔑 127.0.0.1:8080 OAuth 루프백 간편 구글 로그인**:
   - 외부 브라우저(Chrome) 인증 후 CORS 및 URL 해시(#) 파라미터 자동 추출 landing page를 통해 안심 토큰 수신 및 로그인 자동 완료.
5. **☁️ BST Cloud `boardest-cloud-connect` 폴더 격리 & BSTpen 중복 방지**:
   - Google Drive 연동 시 `boardest-cloud-connect` 폴더 내 파일만 표시하고, `BSTpen` 폴더 중복 생성을 탐색 쿼리로 완벽 차단.

---

## 🛠️ 개발 및 빌드 환경 (Development & Build)

### Prerequisites
- Flutter SDK `3.x` 이상
- Windows 10 / 11 64-bit (Visual Studio 2022 C++ Desktop Development Component)

### 빌드 및 실행 명령 (Build Commands)
```bash
# 교사용 앱 (Boardest-Teacher) 빌드 및 실행
cd Boardest-Teacher
flutter pub get
flutter build windows --debug --no-pub
start build\windows\x64\runner\Debug\boardest_teacher.exe

# 전자칠판 보드 앱 (Boardest-board) 빌드 및 실행
cd Boardest-board
flutter pub get
flutter build windows --debug --no-pub
```

---

## 🤖 이어서 개발할 차세대 AI 어시스턴트를 위한 안내 (Handover Note for Next AI)

> [!IMPORTANT]
> **Dear Next Agent / AI Assistant:**
> Welcome to the Boardest codebase! All existing features are 100% implemented, compiled, and verified cleanly. When continuing development on this workspace, please strictly follow these technical guidelines:

### 1. 🖼️ Window Frame & Titlebar Styling
- The application uses a strictly defined **macOS custom titlebar** with `WM_NCHITTEST` border hit testing in C++ (`flutter_window.cpp`) and 12px DWM rounded corners.
- **Do NOT** call `SetWindowTheme(hwnd, L"", L"")` in C++, as it forces Windows OS to fall back to legacy Windows 95 grey visual styles. Keep `SetWindowTheme(hwnd, nullptr, nullptr)` and `windowManager.setTitleBarStyle(TitleBarStyle.hidden)`.

### 2. 📝 Annotation & dHash Persistence
- Document & Website annotations are saved via `AnnotationStorageService.instance.saveDocumentAnnotations('WEBSITE', cleanUrl, metadata, pageAnnotations)`.
- BoardBook periodic 5-second dHash checking is handled by `_dHashCheckTimer` inside `website_board_view.dart`.

### 3. 🌐 Cloud Drive & OAuth Server
- Cloud Drive OAuth uses an internal loopback HTTP server (`http://127.0.0.1:8080/callback`) inside `cloud_drive_service.dart`.
- Cloud Drive queries must always scope files inside `boardest-cloud-connect`, and folder duplication must be prevented via `findFolderByName()` checks before creation.

### 4. ⚡ Build & DLL Lock Resolution
- Always verify compilation using `flutter build windows --debug --no-pub`.
- If MSBuild fails due to `WebView2Loader.dll` being locked by a previous running process, execute:
  ```powershell
  taskkill /F /IM boardest_teacher.exe /T
  ```
  before retrying the build.

---
*Created and maintained with ❤️ for Teachers & Classrooms.*
