# 📜 Boardest Platform — Version Release & Change Log

> **현재 시스템 버전**: **v3.0.1** (App: v3.0.1 / Web: v3.0.1)  
> *이 문서는 각 패치 및 메이저 업데이트 시 수행된 핵심 작업 내역을 종합 기록합니다.*

---

## 📌 v3.0.1 (2026-09-06) — 🚀 Boardest 3.0.1 Quickfix & Package Alignment

### 1. 🍱 boardest-eat 웹 UI 및 에셋 교사용 MealView 완벽 동기화
- **공식 에셋 적용**: `boardest-eat.web.app`에 교사용 공식 로고 및 파비콘(`logo.png`, `favicon.ico`, `favicon.png`) 적용.
- **UI 1:1 일치**: 급식실 선택(1~9) 칩 바, 실시간 온라인 학급 목록, NEIS 급식 식단 카드로 전면 개편.

### 2. 🪟 Windows AppInstaller 패키지 3.0.1.0 갱신 및 재빌드
- `boardest.appx`, `bst-teacher.appx`, `boardest.apk` 전체 재빌드 및 서명.
- AppInstaller의 3.0.1.0 버전 증가를 통한 업데이트 강제 적용.

---

## 📌 v3.0.0 (2026-09-06) — 🚀 Boardest 3.0 Official Release

### 1. ☁️ Cloud 기능 안전 비활성화 & USB 대체 생태계 단일화
- **기존 Cloud 코드 100% 보존**: `BstCloudService` 및 `BstCloudModal` 등 레거시 연동 코드를 일체 삭제하지 않고 `isCloudFeatureDisabled = true` 플래그로 기능만 안전하게 비활성화.
- **USB 최우선 대체**: 수업 자료 및 파일 접근은 USB 연결 시 즉시 반응하는 와이드 USB 탐색기(`_buildFullUsbPanel`)로 완전 대체.

### 2. 🍱 전자칠판 하단 flex: 4 슬롯 '오늘의 급식 식단' 상시 배치
- **광고판 및 OTP 창 ➔ 급식 정보 카드 교체**: 수업 중 및 평상시 대시보드 하단 우측(flex: 4) 영역에 광고판 대신 `_buildNeisMealCard`를 상시 배치하여 당일 급식 식단표 및 배정 급식실 정보를 시원하고 선명하게 제공.
- **급식실 원터치 변경**: 급식 카드 우측 설정 아이콘을 통해 1~9 급식실을 즉시 변경하고 Neis 식단과 실시간 동기화.

### 3. 🍱 독립 급식 지도 관제 시스템 (`boardest-eat.web.app`) 공식 호스팅 분리 & 쿼리스트링 고도화
- **독립 전용 웹사이트 배포**: `boardest-eat`을 Firebase Hosting 전용 타깃으로 신규 등록하여 독립 서비스로 단일화.
- **3대 쿼리스트링 완전 지원**:
  - 학교 ID: `?schoolId=...` / `?schoolCode=...`
  - 지도 교사명: `?callerName=...` / `?teacherName=...` / `?teacher=...`
  - 급식실 번호: `?cafeteria=...` / `?caf=...`
- **리다이렉트 최신화**: `welcome-to-boardest.web.app/eat` 접속 시 `boardest-eat.web.app`으로 302 직결.

### 4. 🚫 웹 사이트 4종 403 Forbidden 차단 (코드 제거 없이 서빙 격리)
- **차단 대상**: `boardest.web.app`, `boardest-teacher.web.app`, `boardest-teacher-lite.web.app`, `boardest-teacher-oauth.web.app`.
- **안전한 403 격리**: 소스코드는 온전히 보존한 채 `infra/forbidden_403_web` 전용 403 차단 안내 페이지를 서빙하도록 `firebase.json` 구성.

### 5. 👩‍🏫 `welcome-to-boardest` 교사용 다운로드 비활성화
- 교사용 카드(`card-teacher`)에 `[다운로드 일시 중단]` 배지 적용 및 시각적 비활성화.
- Windows 설치 탭 내 AppInstaller 다운로드 버튼 및 PowerShell 명령어 비활성화.

---

## 📌 B 2.9.9.9 (2026-09-05)

### 1. 🧠 교사용 및 전자칠판 앱 데이터 영구 저장 ("기억상실증" 완전 박멸)
- **Roaming 디렉터리 자동 삭제 차단**: 샌드박스 초기화 과정에서 SharedPreferences가 저장되던 Roaming 디렉터리가 삭제되던 문제를 해결하여 앱 재실행 시 로그인 정보 및 설정 유실 원천 방지.
- **`school_config.json` & `teacher_session.json` 디스크 이중 백업**: 앱 설정과 교사 세션(Google OAuth 토큰, 프로필 정보)을 샌드박스 내부 디스크 파일 및 실행 경로에 실시간 파일 백업 및 자동 복원(Failover Recovery) 지원.

### 2. 📢 교사용 앱 전자칠판 광고판/알림판 관리 기능 신설
- **직접 이미지 업로드 & 일정 지정**: 교사용 앱에서 전자칠판에 게시할 공지/광고 이미지를 파일 탐색기에서 선택 후 Base64 압축 data URL로 Firestore에 실시간 업로드 및 삭제 관리 지원.
- **날짜 정규화 및 즉시 노출**: 광고판 이미지 업로드 시 날짜 및 시간 범위 정규화, 404 폴백 자동 복구로 "광고할 거 없음" 오류 완전 해결.

### 3. 🪟 교사용 앱 네이티브 창 컨트롤 복원 및 미니 오버레이(다음 교시 팝업)
- **창 컨트롤 복원**: 최소화(`─`), 최대화/복원(`□`), 닫기(`✕`) 버튼을 상단에 확실하게 배치하여 창 닫기 유실 문제 해결.
- **다음 교시 간이 확인 팝업/미니 모드**: 창이 닫히거나 최소화된 상태에서도 시스템 트레이 및 팝업 모드로 다음 교시와 과목을 즉시 확인 가능.

### 4. 📅 교사용 앱 상단 주간 시간표 (월~금) 전면 전환
- 기존 일과 시간표 대신 월요일부터 금요일까지 전체 주간 시간표 그리드로 전환하여 교사가 한눈에 주간 수업 계획을 파악할 수 있도록 개편.

### 5. ☁️ 교사용 앱 하단 좌측 Cloud 기능 대폭 확장
- Google Drive 실시간 스토리지 사용량/쿼터 프로그레스 바, 빠른 업로드, 새 폴더 생성, 클라우드 재동기화 버튼 배치.

### 6. 🎨 공식 BST 로고 Windows EXE 리소스 & AppInstaller 반영
- 공식 BST 브랜드 아이콘을 Windows runner 리소스 및 AppX 패키지 매니페스트에 전면 적용.

---

## 📌 B 2.9.9.8 (2026-09-05)

### 1. 🖼️ 교과서 표지 복구 및 샌드박스 경로 동적 리졸버 적용
- **표지 실종 복원**: 샌드박스 마이그레이션 과정에서 기존 Roaming 경로가 삭제되어 교과서 표지가 뜨지 않던 문제를 해결.
- **인메모리 캐싱 & 자동 동적 탐색**: `%LOCALAPPDATA%\Packages\...\LocalState\textbooks` 디렉터리를 앱 기동 시 선제 스캔하고, 설정 상의 경로가 깨져도 과목명을 기준으로 실시간 매칭 복원.

### 2. 📢 광고판 / Cloud 시간표 분리 및 수업 외 시간 알림판 안내
- **수업 외 시간 Cloud 오표시 차단**: 광고가 등록되지 않았을 때 나타나던 "교사용 Cloud 연결하기" fallback을 제거하고, 우아한 교내 알림판 포스터("📢 교내 알림판: 오늘 하루도 활기차고 행복한 시간 되세요! 🌟")로 대체.
- **수업 시간과 비수업 시간 엄격 분리**: 수업 중일 때만 OTP/QR 연결 패널이 노출되며, 쉬는 시간·점심시간·방과 후·주말에는 알림판과 시간표가 안정적으로 노출됨.

### 3. ⌨️ 전자칠판 Cloud 접속 UI 전면 개편 (QR + 6자리 OTP + 2자리 교사 ID 터치패드)
- **듀얼 분할 입력 도크**: 상단 35%에 스마트폰 카메라 스캔용 QR 코드, 하단에 `[ 6자리 OTP ]` 및 `[ 2자리 교사 ID ]` 입력 칸과 3x4 전용 터치 키패드를 배치하여 전자칠판에서 번호를 직접 터치해 간편 접속.

### 4. 🌐 교사용 웹 OAuth ➔ Windows 앱 루프백 PNA 헤더 및 원클릭 인증 통과
- **Chrome Private Network Access (PNA) 해결**: 로컬 루프백 서버(`http://127.0.0.1:1217`) 응답에 `Access-Control-Allow-Private-Network: true` 헤더를 추가하여 크롬 브라우저의 PNA 프리플라이트 차단 문제 해결.
- **웹 프로필 미작성 시에도 즉시 통과**: Windows 타깃 로그인 시 웹에서 프로필 미등록 상태여도 대기 없이 로컬 앱 루프백으로 즉각 세션을 전달하여 데스크톱 앱 내 마법사로 연계.
- **웹 상단 OTP 텍스트 전면 제거**: OAuth 웹 페이지 상에서 1회용 OTP 관련 문구 및 잔여 연산 로직을 완전히 정리.

### 5. 🪟 Windows 네이티브 윈도우 프레임 복귀
- 교사용 앱(`boardest_teacher`)의 비표준 커스텀 타이틀바 및 트래픽 라이트를 제거하고, 표준 Windows 네이티브 타이틀바(`TitleBarStyle.normal`)로 복귀하여 Windows 11 스냅 레이아웃 및 시스템 윈도우 컨트롤 복원.

---

## 📌 B 2.9.9.7 (2026-09-05)

### 1. 🛡️ Windows AppX 완전 샌드박스 격리 및 흔적 없는 앱 삭제 (Zero-Trace Uninstall)
- **로컬 데이터 100% 샌드박스 감금**: `boardest` (`jiwho.boardest.bst`)와 `boardest_teacher` (`jiwho.boardest.teacher`)의 모든 데이터(교사 계정 토큰, 보안 시크릿, 학교 설정, 판서 및 캐시)를 Windows 공식 패키지 격리 저장소인 `%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalState` 내부로 전면 이전.
- **레거시 Roaming 데이터 자동 이전 및 완전 삭제**: 기존 `%APPDATA%\Roaming`에 남아있던 폴더 데이터를 샌드박스로 자동 마이그레이션 후 Roaming 폴더를 영구 소거하여, 앱 외부에 데이터가 남지 않도록 정리.
- **앱 삭제 시 0-Trace 보장**: 사용자가 Windows 설정/제어판에서 Boardest를 제거(Uninstall)하면 Windows OS 커널이 패키지 컨테이너를 통째로 지우므로 PC에 교사 계정 정보나 설정 흔적이 100% 완전 소거됨.

### 2. ⚡ 무중단 인앱 자동 업데이트 & 조용한 백그라운드 배포 (Silent Auto-Update & Self-Exit)
- **앱 실행 시 OS 설치 관리자 간섭 차단**: `Set-AppxPackageAutoUpdateSettings`를 `-CheckOnLaunch $false -ShowPrompt $false -UpdateBlocksActivation $false`로 설정하여, 부팅/실행 시 Windows OS App Installer 창이 먼저 떠서 닫히거나 실행을 방해하던 문제 원천 차단.
- **Flutter 실행 ➔ 최신 버전 감지 ➔ 백그라운드 갱신 ➔ 앱 자살(Exit)**: Flutter 앱이 정상 실행된 후 백그라운드에서 GitHub 최신 릴리즈와 Firebase 매니페스트를 대조하여, 새 버전이 발견되면 즉시 숨김 모드(`-WindowStyle Hidden`) PowerShell을 구동하고 앱을 즉시 종료(`exit(0)`).
- **`'Main'을(를) 찾을 수 없습니다` 오류 완전 해결**: `cmd.exe /c start`의 따옴표 파싱 충돌을 제거하고 PowerShell 프로세스를 안전하게 Detached 모드로 직결 호출하여 Windows 팝업 에러 원천 방지.
- **AppX 배포 후 자동 재실행**: PowerShell 스크립트가 앱 프로세스 종료를 확인한 후 `Add-AppxPackage`로 최신 버전을 배포하고 `shell:AppsFolder\...`를 통해 앱을 자동 재실행.

### 3. 📦 앱 패키지 내 `.appinstaller` 매니페스트 직접 내장 (Bundled AppInstaller)
- `boardest.appinstaller`, `bst-teacher.appinstaller`, `bst-overlay-panser.appinstaller`를 패키지 루트 디렉터리와 Flutter `assets/`에 직접 번들링하여 MakeAppx 패키징.

---

## 📌 B 2.9.9.6 (2026-09-05)

### 1. 🔄 교사 클라우드 연결 시 레이아웃 스마트 스왑 (시간표 ↔ 클라우드)
- **광활한 교안 탐색 공간 확보**: 교사 디바이스(OTP/QR)가 연결되면, Google Drive 클라우드 파일 탐색기가 **좌측 광활한 메인 영역(`flex: 7`)**으로 확장되어 PPT, PDF, Canva 교안을 시원하게 탐색 및 실행.
- **시간표 우측 광고판 컴팩트 전환**: 클라우드가 메인 자리를 차지하는 동안 '지금 시간표' 카드는 **우측 광고판(`flex: 4`)** 위치로 부드럽게 이동하여, 수업 중에도 학생들과 교사가 현재 교시와 과목 정보를 놓치지 않고 상시 확인 가능.
- **클라우드 닫기 시 원복**: 클라우드를 숨기거나 닫으면, 시간표가 다시 좌측 메인(`flex: 7`)으로 복귀하고 우측은 수업 도구/광고판으로 자동 복귀.

### 2. 🪟 Windows 네이티브 AppInstaller UI 연동 및 파일 잠금(Exit) 완벽 처리
- **업데이트 시 앱 무조건 즉시 종료 (`exit(0)`)**: 앱이 실행 중인 상태에서 업데이트가 진행되면 발생하는 Windows AppX 파일 잠금(`0x80073D02`) 오류를 원천 차단하기 위해, 업데이트 트리거 즉시 프로세스를 안전 종료.
- **네이티브 Windows App Installer 창 팝업**: `ms-appinstaller:?source=...` 프로토콜을 백그라운드 호출하여 OS 공식 업데이트 창을 사용자에게 명확히 제시.
- **PowerShell `Add-AppxPackage` 파라미터 문법 오류 수정**: `-AppInstallerFile` 스위치와 `-Path` 매개변수 바인딩을 올바르게 교정하여 커맨드라인 자동 배포 100% 보장.

### 3. 🏷️ Beta 테스트 기간 버전 규격 고정 (`2.9.9.X`)
- `AGENT.md`에 Beta 공식 종료 전까지 버전 체계를 `2.9.9.X`로 유지하는 규칙 명문화.


### 1. 📢 수업 시간 Cloud 창 "광고판(Billboard)" 영역 분리 배치
- **시간표 카드 가독성 보존**: 수업 시작 시 시간표 카드를 찌그러뜨리며 OTP 패널을 주입하던 구조를 제거하여, 수업 시간 중에도 시원하고 큰 과목명 타이포그래피와 실시간 상태 배지를 유지.
- **광고판(`flex: 4`) 지능형 전환**: 수업 시간에 교사 클라우드가 미연결 상태일 때 광고판 위치에 **스마트폰 QR 스캔 & 3x4 OTP 키패드 패널**을 표시하고, 인증 완료 시 해당 자리에서 부드럽게 **클라우드 파일 탐색기**로 연결 전환.

### 2. 📱 Android APK 업데이트 무한 루프 해결 및 버전 완전 일치화
- **Android Gradle 버전 통일**: `android/app/build.gradle.kts`에 `versionName = "2.9.9.5"`, `versionCode = 2995`를 고정 설정하여 4자리 버전 표기 완전 일원화.
- **최신 릴리즈 APK 갱신**: 구버전 빌드가 남아있어 최신 상태임에도 반복 알림이 뜨던 문제를 최신 소스 기반의 `boardest.apk` 정식 빌드 및 배포로 해결.
- **`UpdateService` 비교 안정화**: Android와 Windows 모두 `defaultVersion = '2.9.9.5'`로 동기화하여 불필요한 인앱 업데이트 팝업 차단.

### 3. 🚀 멀티플랫폼 일괄 빌드 자동화 파이프라인
- `scripts/build_all_appx.ps1`에 Android Release APK 자동 빌드(`flutter build apk --release`) 단계를 통합하여, 릴리즈 시 Windows AppX와 Android APK가 반드시 동시에 최신 소스로 동기화되어 배포되도록 보장.

---

## 📌 B 2.9.9.4 (2026-09-05)

### 1. 🪟 Windows OS 네이티브 "앱 설치 관리자" (AppInstaller) 매번 실행 시 자동 업데이트 전담
- **Flutter 인앱 시작 팝업 완전 제거**: 앱 시작 시 Flutter 코드(`UpdateService.checkAndUpdate`)가 자체적으로 업데이트를 체크하거나 다이얼로그를 띄우지 않도록 정리하여, OS 네이티브 설치 관리자가 업데이트를 100% 전담하도록 일원화.
- **매번 실행 시 차단 및 업데이트 확인 (`UpdateBlocksActivation="true"`, `HoursBetweenUpdateChecks="0"`)**:
  - `boardest.appinstaller`, `bst-teacher.appinstaller` 등 모든 매니페스트에 `UpdateBlocksActivation="true"` 및 `ShowPrompt="true"`, `HoursBetweenUpdateChecks="0"` 전면 적용.
  - Windows OS가 앱 아이콘 클릭 즉시 "앱 설치 관리자" UI를 통해 GitHub 최신 버전을 대조하고, 새 버전이 있으면 네이티브 업데이트 다이얼로그를 즉각 띄워 업데이트 후 실행되도록 보장.
- **OS 레지스트리 자동 설정 보장 (`Set-AppxPackageAutoUpdateSettings`)**:
  - `RegistryService` 및 `UpdateService.ensureNativeAppInstallerSettings()`를 통해 앱 구동 시 Windows OS에 AppInstaller 자동 업데이트 정책(`CheckOnLaunch`, `ShowPrompt`, `UpdateBlocksActivation`, `ForceUpdateFromAnyVersion`)을 영구 주입.
  - 신규 설치 스크립트(`install.ps1`, `cer.ps1`)에도 자동 업데이트 설정 명령 포함.

---

## 📌 B 2.9.9.3 (2026-09-05)

### 1. 🔄 GitHub + Firebase CDN 듀얼 소스 인앱 자동 업데이트 (`UpdateService` 2.9.9.3)
- **GitHub Rate-Limit & 무응답 원천 차단**: GitHub API 최신 릴리즈 조회 실패(레이트 리밋 HTTP 403, 타임아웃 등) 시 Firebase Hosting CDN(`download-boardest.web.app/*.appinstaller`)에서 실시간 최신 버전을 100% 무중단 판독하는 폴백 메커니즘 구축.
- **풍부한 진단 로깅 탑재**: 콘솔에 `[UpdateService]` 상세 로그(조회 시작, HTTP 상태코드, 감지된 버전, 비교 판정 결과 등)를 실시간 출력하여 무반응 의구심 완전 해소.
- **PowerShell 프로세스 잠금 해제 루프 (`0x80073D02` 방지)**: 앱이 종료되기 전에 `Add-AppxPackage`가 실행되어 발생하던 패키지 파일 잠금 에러를 차단하기 위해 프로세스 종료 대기 루프(`Get-Process`) 및 `-UseBasicParsing` 적용.
- **AppInstaller 매니페스트 `ShowPrompt="true"` 전면 적용**: Windows 네이티브 AppInstaller 및 Flutter 인앱 모달 양방향으로 릴리즈 업데이트 알림 보장.

### 2. 🧹 "반 맵핑" (Class Mapping) 기능 전면 삭제 & 클라우드 안심 연동 허브 개편
- **구형 반 맵핑 UI/데이터 전면 삭제**: `teacher_view.dart` 내 `_classroomFolderMappings`, `_classMappings`, `_targetClasses`, 매핑 다이얼로그, 카드 내 학급 드롭다운 및 레거시 패널 완전 제거.
- **하단 좌측 독 개편 ("클라우드 안심 연동 & 신뢰 기기 허브")**: 기존 반 맵핑 패널 위치에 Google 계정 상태 배지, 연동 기기 관리 바로가기, 실시간 수동 업데이트 확인 버튼, 드라이브 새로고침이 결합된 통합 허브 배치.
- **Auto-PT 간소화**: 정적 맵핑 설정 파일 의존성을 제거하고 현재 교시의 학년/반 폴더를 다이렉트로 자동 탐색하도록 정돈.
- **백엔드/서비스 레거시 API 제거**: `cloud_drive_service.dart`의 `fetchClassroomMappings`, `downloadClassroomMappingsFile`, `fetchSubjectMappings`, `saveSubjectMappings`, `saveFolderMappings` 완전 제거.
- **웹 자산 텍스트 정비**: `cloud_lite.html`, `welcome_web/index.html` 내 잔존 매핑 문구를 직관적인 클라우드 동기화로 변경.

### 3. 📦 전체 패키지 & AppX 매니페스트 일괄 동기화 (v2.9.9.3)
- `boardest`, `boardest_teacher`, `boardest_teacher_lite`의 `pubspec.yaml` 버전 일괄 `2.9.9+2993` 승격.
- `dist/packages/*/AppxManifest.xml`, `dist/appx/*.appinstaller`, `infra/download_web/*.appinstaller`, `infra/welcome_web/*.appinstaller` 버전 `2.9.9.3` 동기화 및 `scripts/build_all_appx.ps1` 갱신.

---

## 📌 B 2.9.9.2 (2026-09-05)

### 1. 👩‍🏫 교사용 앱 (`boardest_teacher`) OTP & Drive 통합 제어 및 24:76 와이드 클라우드 탐색기 대개편
- **OTP & 빠른 도구 초슬림 통합 (`flex: 24`)**: 하단 좌측 제어 영역을 38%에서 24%로 압축하고, [업로드 / Canva / 새 폴더 / 동기화] 4개 주요 동작을 컴팩트 1열 가로 툴바(`_buildSlimActionBtn`)로 슬림화.
- **Google Drive 클라우드 탐색기 초대형 확장 (`flex: 76`)**: 수업 교안 탐색 영역을 62%에서 76%로 전폭 확장하여, 파일명 및 카테고리가 쾌적하게 한눈에 들어오는 와이드 브라우징 환경 완성.
- **메인 레이아웃 밸런스 조정**: 주간 시간표 영역(`flex: 4`)과 하단 도구/탐색기 영역(`flex: 6`)의 황금 분할 적용.

### 2. 🖥️ 전자칠판 (`boardest`) 급식 요소 완전 분리 및 시계/시간표 대폭 확대
- **대시보드 급식 완전 분리**: 급식 기능을 독립 웹앱(`boardest-eat.web.app`)으로 단일화하고, 전자칠판 메인 화면의 급식실 선택 버튼을 제거.
- **시간표 & 시계 최적화 비율 개편**:
  - 디지털 시계 카드: `flex: 1` $\rightarrow$ `flex: 5`로 시인성 대폭 강화.
  - 하단 섹션: '지금 시간표'를 `flex: 3` $\rightarrow$ `flex: 7` (63.6%)로 확대, 우측 광고판/컨텍스트를 `flex: 2` $\rightarrow$ `flex: 4` (36.4%)로 정돈하여 수업 진행 집중도 극대화.

### 3. 📁 파일 실행 방식 엄격 분리 및 웹 인덱스 소스 노출 결함 해결
- **웹 뷰어 HTML 소스 노출 버그 차단**: `WebHwpPptView`에 로컬 파일 전달 시 구글 뷰어가 `boardest.web.app/viewer?file=...`를 호출하면서 웹 `index.html` 소스코드가 노출되던 취약점 원천 수정.
- **엄격한 파일 분기 실행**:
  - **PPT / PPTX / HWP / HWPX**: 웹 뷰어를 우회하고 네이티브 WPF 오버레이 또는 OS 기본 실행 프로그램(`launchUrl(Uri.file)`)으로 직접 구동 (웹 환경은 구글 드라이브 공식 뷰어로 연결).
  - **PDF / TBP / Canva**: Boardest 내장 전용 뷰어로 부드럽게 전체화면 렌더링.
  - **기타 확장자**: OS 기본 연결 프로그램 또는 다운로드로 실행.

### 4. 📱 시크릿 QR 코드 기반 자동 로그인 기기 등록 & 401 자가 치유 (Self-Healing)
- **8자리 텍스트 코드 $\rightarrow$ 시크릿 QR 전환**: 전자칠판 [자동 로그인 기기 등록]을 난수 텍스트 입력 방식에서 카메라 즉시 스캔이 가능한 역방향 페어링 QR 코드로 전환 (`waitForReversePairAuth`).
- **Google OAuth 401 Unauthorized 자가 치유**:
  - `BstCloudService`에 `activeRefreshToken` 필드를 신설하여 페어링 세션 완료 시 리프레시 토큰을 안전하게 보관.
  - Google Drive 파일 탐색(`fetchDriveFiles`) 중 1시간 만료로 인한 `401 Unauthorized` 발생 시, 보관된 `refreshToken`을 사용해 자동으로 새 Access Token을 교환받아 요청을 재시도하는 자가 치유(Self-healing) 로직 구현.
- **교사 OAuth 포털 토큰 검증**: `boardest-teacher-oauth`에서 로컬스토리지 캐시 토큰의 만료 여부를 사전 검증하고 리프레시 토큰으로 갱신 후 페어링 세션에 기록하도록 보강.

### 5. 🔄 Windows & Android 인앱 실시간 자동 업데이트 완전 복구
- **Windows 조기 리턴 가드 제거**: `kIsWeb || Platform.isWindows` 조기 종료로 인해 데스크톱 환경에서 업데이트 감지가 무시되던 문제를 해결하고, Windows 환경에서도 GitHub 최신 릴리즈 자동 감지 완비.
- **AppInstaller & AppX 무인 갱신 파이프라인**:
  - 최신 릴리즈 출시 시 전자칠판(`boardest`)과 교사용(`boardest_teacher`) 모두 원클릭 업데이트 모달 표시.
  - `Add-AppxPackage -AppInstallerFile ... -ForceUpdateFromAnyVersion` (실패 시 fallback 최신 .appx 직결 다운로드 설치) 백그라운드 PowerShell 스크립트로 자동 갱신 및 재실행.
- **설정 메뉴 내 수동 확인 지원**: 전자칠판 설정 바텀시트 및 교사용 메뉴에 [시스템 업데이트 확인] 버튼을 제공하여 최신 버전 여부 실시간 안내.

---

## 📌 B 2.9.9.1 (2026-09-05)

### 1. 📥 `download-boardest.web.app` 공식 다운로드 및 단축 스크립트 허브 구축
- **원클릭 설치 명령어**: `irm https://download-boardest.web.app/bst.ps1 | iex`
- **다운로드 출처 URL 지원**: 크롬 주소창/다운로드 버튼 클릭 시 GitHub 최신 릴리즈(`latest`) 파일로 302 리다이렉트 (`/bst.apk`, `/bst.appinstaller`, `/bst.appx`, `/bst-teacher.appx`, `/bst.cer`).
- **온보딩 포털 분리**: `welcome-to-boardest.web.app` (접속 기기 UA 자동 감지 및 설치 안내).

### 2. 👩‍🏫 교사용 앱 (`boardest_teacher`) Web PDF 에러 해결 & 38:62 레이아웃 개편
- **Web PDF `Unsupported operation: _Namespace` 원천 해결**: `kIsWeb` 조건에서 파일 시스템 검사를 우회하고 메모리 바이트를 직접 `PdfBoardView`로 바인딩.
- **하단 패널 통합**: [좌측 38% 통합 도구] (시간표, 칠판 메모, QR 스캔 & 기기 관리, 폴더 맵핑) : [우측 62% 클라우드 파일 탐색기]로 개편.
- **불필요 기능 정리**: '다른 기기 주기' 및 'Google OTP 등록' 완전 제거 (전자칠판 QR 코드로 통합).

### 3. 🍱 독립 급식 지도 웹앱 (`boardest-eat.web.app`) 분리 & 쿼리스트링 지원
- Teacher Lite 리다이렉트가 아닌, **전용 실시간 급식 관제 웹 애플리케이션**으로 전면 구축.
- `?schoolCode=ydm&cafeteria=1&callerName=지도교사` 등 쿼리스트링 완전 지원 및 공유/북마크 지원.
- 1~9급식실 탭별 실시간 온라인 학급 카운트, Web Audio 신디사이저 차임벨, 학년 일괄 호출, 전체 호출 취소, 전자칠판 쪽지 전송.

### 4. 🔐 교사 포털 (`boardest-teacher-oauth.web.app`) 시크릿 관리 허브 전환
- 6자리 일회용 OTP 표시를 제거하고 **보안 시크릿 키 관리/생성/저장 전용 허브**로 개편.
- `[🎲 새 시크릿 생성]` 및 `[💾 시크릿 저장]` 기능으로 Firestore(`teacher_profiles`, `teacher_cloud_tokens`) 및 브라우저에 안전하게 영구 저장.

### 5. 🖥️ 전자칠판 (`boardest`) 3:2 레이아웃 & 클라우드 세션 보존
- 메인 대시보드에서 급식 카드를 분리하고, **3:2 = [지금 시간표 (flex: 3)] : [광고판 / Cloud / USB (flex: 2)]**로 단일화.
- 클라우드 패널을 닫아도 `activeToken = null`이 아닌 `_hideCloudPanel = true`를 적용하여 교사 로그인 세션이 끊기지 않고 유지됨.

---

## 📌 B 2.9.8.9 (2026-09-04)

### 1. 🚀 AppX 자체 무인 업데이트 & 순수 AppX 생태계 확립
- **Setup.exe 완전 배제**: 불필요한 설치형 외부 실행 파일(.exe)을 일체 배제하고 순수 Windows 샌드박스 보안 규격인 AppX 및 `.appinstaller` 구조 완비.
- **앱 기동 시 자동 업데이트 감지**: 최신 릴리즈 v2.9.8.9 체크 후 PowerShell `Add-AppxPackage` 무인 백그라운드 갱신 및 즉각 앱 자동 재시작.

### 2. 🕒 수업 시간 중 '지금 수업' 카드 하단 광고판 크기 OTP Cloud 바로가기 탑재
- **수업 중 (`isClass && !isCloudActive`) 전용 키패드**: 지금 수업 카드 상단에 상태 뱃지 및 과목명을 일렬 배치하고, 하단에 광고판 크기만큼의 OTP 6자리 원터치 입력 키패드 컨테이너 탑재.
- **Cloud 접속 시 자동 전환**: OTP 인증 완료 시 키패드가 사라지며 대시보드가 1:3 와이드 클라우드 탐색기 모드로 자동 전환.

### 3. 💾 USB 연결 시 1:3 와이드 전면 탐색기 탑재
- **Cloud 탐색기와 대등한 와이드 뷰**: USB 연결 시 좌측 세로형 수업 카드(flex: 1)와 우측 와이드 전면 USB 탐색기(flex: 3)로 넓고 시원하게 파일 탐색 및 원클릭 실행.

### 4. 🔑 Cloud OTP 시간 디버깅 완벽 격리 & 실시간 동기화
- **실제 현재 시각 강제**: `_debugTimeOverride` 등 디버그 모드와 무관하게 모든 TOTP 및 Steganography OTP 생성/검증 시 무조건 `DateTime.now()`(실제 현재 시각) 사용 강제.
- **Worker + Firestore 2중 Fallback 연동**: Cloudflare Worker 통신 지연 시에도 Firestore `teacher_cloud_tokens` 컬렉션을 즉시 직접 조회하여 6자리 Stegano OTP 검증 및 Refresh Token 교환 100% 성공 보장.
- **교사용 앱 60초 OTP 주기 타이머 & 게이지 완벽 동기화**: `_remainingSeconds` 및 6자리 코드 실시간 반영.

### 5. 📂 Teacher 앱 Cloud 파일함 전면 쾌적화 & Boardest 네이티브 파일 열기
- **폴더 브라우징 격리**: `fetchDriveFiles`에서 하위 폴더 탐색 시 AppDataFolder 파일이 혼합되던 결함을 제거하고, 현재 폴더 직계 파일/폴더만 표시.
- **새 폴더 만들기**: 상단 헤더에 '새 폴더 만들기' 기능 추가.
- **Boardest 전용 파일 뷰어 연동**: PDF, 판서(.pen, .bstpen, .iwb), 교과서(.tbp), Canva(.canva)는 플랫폼(Web, Windows, Android) 불문 Boardest 내장 뷰어로 즉시 열기, Windows 한정 PPT/HWP는 전용 오버레이로 열기, 미지원 파일은 기본 앱/다운로드 실행.
- **PC 파일 백그라운드 자동 동기화**: 사용자 지정 로컬 폴더에서 판서 파일을 제외한 수업 자료를 Google Drive로 백그라운드 자동 업로드 지원.

### 6. 🎨 대시보드 광고판 및 급식 최적 비율 확장
- **광고판 폭 & 높이 확대**: 하단 중앙 수업 카드와 급식/광고판 비율을 최적화하고, 급식(3) : 광고판(4) 비율로 광고판 크기를 시원하게 확장.

---


## 📌 B 2.9.8.7 (2026-09-03)

### 1. Boardest 메인 대시보드 기하학적 레이아웃 & 3:1 황금 비율 완성
- **우측 런처 패널 초슬림화 (`flex: 14`)**:
  - Windows Desktop(EXE) 환경에서도 우측 런처 폭을 대폭 축소하여 Web의 2열 폭(`flex: 14`)과 동일하게 압축.
  - 2열(수업 도구 7행)과 3열(시스템 앱 7행)을 컴팩트한 M3 그리드 타일로 재정돈하여 공간 낭비 제거.
- **지금 수업 카드 vs 광고판 3:1 비율 (`flex: 75 : 25`)**:
  - 하단 행의 지금 수업 카드가 `flex: 75`, 광고판이 `flex: 25`를 차지하여 **정확한 3:1 비율** 달성.
  - 기존에 좁아터져 세로 1글자 단위로 깨지던 수업 상태 뱃지(`[방과 후 (다음 수업 준비)]`)와 교과서 표지, 대형 과목명이 시원한 가로 와이드 공간에 여유롭게 렌더링.
  - 상단 행(시계 75 : 1열 상단 3행 25 = 3:1)과 하단 행이 완벽한 수직 정렬선으로 일치.

### 2. Boardest Teacher Cloud 파일 통합 디스패처 탑재
- **Boardest 전용 포맷 무조건 Boardest 뷰어로 실행**:
  - PDF 문서 (`.pdf`) $\rightarrow$ `PdfBoardView` 판서 뷰어
  - 판서 파일 (`.pen`, `.bstpen`, `.iwb`) $\rightarrow$ `BoardestPenView`
  - 교과서 (`.tbp`, `.bsttbp`) $\rightarrow$ `TbpViewerRoute`
  - Canva 디자인 (`.canva`, `.bstcanva`, `.canvaboard`) $\rightarrow$ `CanvaBoardView`
  - 파워포인트 (`.pptx`, `.ppt`) $\rightarrow$ `PptOverlayView` (웹: `WebHwpPptView`)
  - 한글 문서 (`.hwpx`, `.hwp`) $\rightarrow$ `HwpOverlayView` (웹: `WebHwpPptView`)
  - 동영상 (`.mp4`, `.mkv`, `.avi`, `.mov`) $\rightarrow$ `VideoBoardView`
  - 기타 미지원 파일 $\rightarrow$ OS 기본 연결 프로그램으로 안전 실행
- **화이트보드 및 PDF 보드 실행 복원**:
  - 빈 함수 스텁이었던 `_openWhiteboard()` 및 `_openPdfBoard()` 정상 연동.
- **클라우드 드라이브 파일 탭 시 즉시 다운로드 후 해당 포맷 뷰어로 원스톱 오픈**.

---

## 📌 B 2.9.8.6 (2026-09-03)

### 1. Windows AppX / AppInstaller 전용 업데이트 체계 전환 (Setup.exe 완전 퇴출)
- **Setup.exe 폐기 & AppX 단일화**:
  - 기존 exe 설치 프로그램 방식을 완전히 제거하고, Windows OS 표준 샌드박스 패키지인 **`AppX` / `AppInstaller` 체계로 일원화**.
  - 레지스트리나 파일 찌꺼기 없는 100% 안전하고 깔끔한 설치/삭제/갱신 보장.
- **앱 종료 $\rightarrow$ AppInstaller 다운로드 핸드오프**:
  - Flutter 앱이 GitHub 최신 릴리즈 조회 후 업데이트 알림 다이얼로그 표시.
  - [업데이트 시작] 클릭 시 `ms-appinstaller:?source=...` 프로토콜을 호출하고 앱을 즉시 종료(`exit(0)`).
  - 파일 잠금이 해제된 상태에서 Windows OS AppInstaller가 `boardest.appx` / `bst-teacher.appx`를 다운로드하여 샌드박스를 갱신하고 앱을 재실행.

---

## 📌 B 2.9.8.5 (2026-09-03)

### 1. Boardest 메인 전자칠판 대시보드 레이아웃 완성
- **1열 3행 압축 + 와이드 A4 광고판 레이아웃 완성**:
  - 1열: 상단 3행(날씨, 학사달력, 앱서랍)만 점유.
  - 하단: 광고판(`_buildAdBannerOrContextCard`)이 1열 4~7행 높이에서 좌측(지금 수업 카드 영역)으로 `flex: 54`만큼 넓게 확장되어 **A4 비율의 넉넉한 가로폭(450px 이상)**을 안정적으로 확보.
  - 2열(도구 7행) & 3열(시스템 앱 7행, Desktop 전용)이 우측에서 전고 7행을 깔끔하게 유지.
  - **웹(Web) 최적화**: 3열(시스템 앱)만 완전히 생략되고 2열 도구 패널과 확장 광고판이 완벽한 반응형 폼팩터로 렌더링.

### 2. Boardest Teacher 하단 3단 패널 테마 & 기능 고도화
- **라이트 모드 가독성 전면 개선**:
  - 액션 타일([파일 올리기], [Canva 등록], [새 폴더], [폴더 맵핑]) 및 온라인/인증 기기 리스트 텍스트가 흰색으로 증발하던 버그를 해결하고 테마 색상(`_textColor`, `_textColor54`)으로 동적 바인딩.
  - 타일 내부 텍스트에 `maxLines: 1`, `TextOverflow.ellipsis`를 적용하여 창 크기가 작거나 고배율 환경에서의 세로 오버플로 원천 방지.
- **실시간 온라인 칠판 감지 & 학교 코드 동적 연동**:
  - `_fetchOnlineClassrooms`에 교사 설정의 학교 코드(`_settings.schoolId`)를 동적으로 전달하여 교내 5분 이내 활성 전자칠판만 🟢 뱃지로 필터링.
- **Teacher 앱 자동 업데이트 활성화**:
  - 비어 있던 `_checkForAppUpdates` 스텁을 `UpdateService.instance.checkForUpdate(context)`로 완전 연동하여 교사용 PC에서도 릴리즈 감지 및 원클릭 업데이트 지원.

### 3. 무인 자동 업데이트 & GitHub Release 파이프라인 개편
- **자동 업데이트 감지 원인 해결**:
  - GitHub API 요청 시 `User-Agent: Boardest-Client/2.9.8.5` 필수 헤더 추가로 학교 네트워크 Rate Limit 및 403 차단 방지.
  - 전자칠판 앱과 교사용 앱의 인스톨러/ZIP 애셋 필터링을 엄격히 분리하여 상호 교차 다운로드/설치 사고 원천 차단.
- **Cloudflare Worker 인증 & Steganography OTP 강화**:
  - 8자리 OTP 검증 시 modulo $10^8$ 정상 반영.
  - 6자리 Stegano OTP 검증 시 현재 분(`minute`) 기준 ±1분 후보 윈도우를 탐색하여 정각/분 경계 롤오버 시의 404 실패 원천 해결.

---

## 📌 B 2.9.8.4 (2026-09-02)

### 1. Boardest 메인 전자칠판 런처 & 광고판 레이아웃 개편
- **1열 3행 압축 & 광고판 통합**:
  - 1열: 1행(날씨), 2행(학사달력), 3행(앱서랍) 3개 도구만 배치.
  - 4~7행: 광고판(`_buildAdBannerOrContextCard`)이 1열 4~7행과 좌측 여백을 통합 차지하여 A4 비율의 넓은 가로폭 확보.
  - 수업/일과 상태에 따라 컴팩트 USB 파일탐색기, 지금 수업 카드, Cloud OTP 키패드, A4 공지 배너 자동 스위칭.
- **2열 7행 유지**: 판서하기, 교과서, Canva, Cloud, 플러그인, 학생연결, 설정.
- **3열 시스템 앱 등록 슬롯 (데스크톱/안드로이드)**:
  - 7개 슬롯에 명확한 테두리와 `+ 앱 등록` 라벨을 노출하여 시스템 앱 등록 영역임을 시각적으로 직관화.
  - **웹(Web) 환경 최적화**: Web 버전에서는 3열만 깔끔하게 생략되어 1열(3행+광고판)과 2열(7행)만 표시.

### 2. Boardest Teacher 하단 3단 패널 전면 재설계
- **좌측 (flex: 33) — OTP & 보안 인증 관리**:
  - 상단: 6자리 Stegano OTP 대형 카드 (코드 복사, 60초 프로그레스 바, Cloud ID 배지, Auto-PT 스위치).
  - 하단: `[📡 다른 기기 OTP 주기]` / `[🔐 인증 기기 & 로그]` 2개 서브 탭 탑재.
  - **실시간 온라인 기기 필터링**: 교내 등록된 전자칠판 중 `lastActive` 기준 5분 이내 하트비트가 확인된 **실제 온라인 전자칠판만** 🟢 뱃지와 함께 노출하며, [8자리 전송] 버튼으로 자동 OTP Secret 직통 푸시.
- **중간 (flex: 37) — 파일 탐색기**:
  - Google Drive `bst-save` 보관함 파일 브라우저.
  - 실시간 파일 검색창, 카테고리 필터 칩 (`[전체]`, `[📄 PDF]`, `[🎨 Canva]`, `[📊 PPT]`, `[📝 판서]`).
  - 파일 클릭 시 바로 열기/다운로드/삭제.
- **우측 (flex: 30) — 파일 업로드 & 폴더 맵핑**:
  - 4개 액션 버튼: [📁 파일 올리기], [🎨 Canva 등록], [📂 새 폴더], [🔄 폴더 맵핑].
  - 현재 교과 / 반별 폴더 맵핑 현황 요약 리스트 제공.

### 3. 업데이트 서비스 안정화 & 정책 일원화
- **중복 다이얼로그 가드**: `UpdateService._isChecking` static guard 탑재로 exe 실행 시 업데이트 창이 2번 뜨는 문제 완벽 해결.
- **명시적 팝업 알림**: 업데이트 발견 시 버전 번호와 함께 명확한 다이얼로그 팝업을 띄우고 즉시 업데이트 유도.

---

## 📌 B 2.9.8.3 (2026-09-02)

### 1. Teacher 앱 시간표 상단 + 하단 2단 레이아웃 분리
- 상단 시간표 패널과 하단 드라이브/OTP 분리.
- Boardest 대시보드 3열 시스템 앱 슬롯 도입.

---

### 1. 버전 체계 공식화 및 동기화 (B 2.9.8)
- 0.9.X (Electron 베타) $\rightarrow$ 1.X.X (Electron 정식) $\rightarrow$ 1.9.X (Flutter 초기) $\rightarrow$ 2.X.X (Flutter 정식) $\rightarrow$ **2.9.X (Cloud/Teacher 베타)** $\rightarrow$ 3.X.X (정식 LMS 연동 버전 예정)
- `pubspec.yaml` 및 앱 전체 버전 `2.9.8+298` 동기화.

### 2. Windows & Android GitHub Releases 자동 업데이트 파이프라인
- **GitHub Actions 워크플로우 (`.github/workflows/release_app.yml`) 탑재**: `v*` 태그 푸시 시 Windows 배포 zip 및 Android APK 자동 빌드 & 릴리즈 생성.
- **앱 내 실시간 업데이트 감지 & 자동 설치 지원 (`UpdateService`)**: Windows(zip 자동 해제 및 재실행) & Android(APK 자동 다운로드 및 설치 유도).

### 3. Cloudflare Worker CORS 버그 완벽 해결
- `Access-Control-Allow-Methods`에 `DELETE, PUT` 추가 및 클라이언트 `removeDevice` `POST/DELETE` 다중 지원.

### 4. 자동 OTP 직통 FCM 등록 시스템 구축
- 교사앱에서 반 선택 시 Cloudflare Worker가 8자리 TOTP Secret을 생성하고 FCM 직통 푸시로 전자칠판에 전달하여 무인 자동 OTP 등록 체결.

### 5. FCM 오프라인 수신 알림 시각화 & 로그인 반 타겟팅
- 기기가 꺼져있을 때 수신된 알림을 도착 시각과 함께 기록하여 기기 부팅 시 **"부재 중 수신된 알림"** 모달로 정확하게 안내.

### 6. PDF 및 파일 판서 학급별 완전 격리 (레거시 Fallback 제거)
- 전자칠판: `{classCode}_{pdfName}.file.pen` / 교사용: `Teacher_{pdfName}.file.pen`
- 본인 학급 판서 데이터만 로드하도록 엄격하게 격리.

### 7. Teacher 홈화면 및 BST 도구 Cloud / 인증 관리 탭 정돈
- 홈화면 드래그 앤 드롭 업로드 지원 및 BST 도구 인증 관리(`[신뢰 기기]` + `[자동 로그인 등록]`) 탭 구조 개편.

---

## 📌 B 2.7.7 (2026-08-30)

### 1. 판서 2원화 (file.pen in bst-pen & Free.pen in bst-Free)
- **파일 위 판서**: `{fileName}.file.pen` $\rightarrow$ **`bst-pen`** 폴더에 저장. (일반 파일 목록에 비노출, 원본 파일 실행 시에만 자동 로드/복원)
- **화이트보드 자유 판서**: `[학급] YYYY-MM-DD_HHmm.Free.pen` $\rightarrow$ **`bst-Free`** 폴더에 저장. (화이트보드 앱 및 3번 탭에서 단독 실행)

### 2. Cloud 독 3-Tab 스위처 구축
- **`[📁 수업 자료 (Save)]`**: 순수 교안 파일 (PDF, PPT, Canva 등)
- **`[📖 TBP 교과서]`**: `.bsttbp` / `.tbp` 교과서 목록
- **`[🎨 판서보드 (Free)]`**: `bst-Free` 폴더의 `.Free.pen` 판서 목록 및 원클릭 칠판 복원

### 3. PDF 판서 날아감 문제 해결 & 실시간 Cloud 백업 복원
- PDF 판서 시 `bst-pen` 폴더에 실시간 자동 동기화 및 PDF 재열람 시 Cloud `fetchFilePenBytes`, Web 저장소에서 100% 완벽 복원.

### 4. Google Drive 멀티스페이스 검색 (appDataFolder + spaces=drive) & 401 자동 리프레시
- 교사용 앱에서 파일이 비어보이던 현상을 appDataFolder와 일반 Drive 양방향 통합 검색으로 완벽 해결.

### 5. 미지원 파일 Web 브라우저 다운로드 연동
- 전용 뷰어가 없는 파일 선택 시 안내 모달을 통해 브라우저 직접 다운로드 실행.

---

## 📌 B 2.7.6 (2026-08-30)

### 1. 학급 쪽지 발송 시스템 및 칭호 중복 수정 (급식 문자급 프리미엄 UI 개편)
- **교사 호칭 중복 완전 해결**: '선생님 선생님'처럼 칭호가 중복 결합되는 오류를 칭호 정규화 로직으로 완벽하게 방지.
- **급식 알림 스타일의 프리미엄 쪽지 알림 팝업**: 세련된 네온 액센트, 고대비 메시지 카드, 원터치 확인 및 즉시 읽음 동기화 제공.

### 2. Google Drive 판서 오버레이/주석 파일 은닉
- **파일 위 판서 주석 파일 분리**: `.annot.json`, `_annot.`, `.sync.json` 등 파일 위에 덧그린 주석/필기 데이터는 드라이브 파일 목록에서 자동 필터링하여 순수 교안/자료만 정돈되어 노출.

### 3. Google OAuth 401 토큰 만료 시 즉각 세션 리셋 & Cloud 칸 자동 롤백
- **1시간 토큰 만료 자동 처리**: Drive API에서 401 권한 만료 감지 시 즉시 세션을 파기하고 대시보드를 평상시 광고판 배너 상태로 안전하게 롤백.

### 4. 교사용 앱(Boardest Teacher) 홈 화면 Cloud 드라이브 파일 관리 센터 완성
- **홈 화면 실시간 Drive 파일 탐색기 탑재**: 홈 화면 Cloud 패널 내에서 실시간 파일 목록 조회, 파일 업로드(`[파일 올리기]`), 새 폴더 생성(`[새 폴더]`), 학급별 폴더 맵핑 및 진도 연동 제공.
- **OTP 및 인증 관리 허브 바로가기 연동**: 홈 화면에서 원클릭으로 6자리 Stegano OTP 및 신뢰 기기 보안 관리 접근 가능.

### 5. Canva 임베딩 CSP 이슈 해결
- **임베딩 전용 URL 자동 변환**: Canva 디자인 ID 추출 및 `https://www.canva.com/design/{id}/view?embed` 포맷 자동 변환을 적용하여 `frame-ancestors` CSP 차단 문제 완벽 해결.

---

## 📌 B 2.7.5 (2026-08-30)

### 1. Boardest 판서 데이터 격리 & 화이트보드 날짜/시각 파일명 및 획 단위 Cloud 실시간 동기화
- **판서 기록 은닉 및 화이트보드 캔버스 정상 작동**: 전자칠판(`boardest`)에서 타인의 이전 판서 목록 조회를 제한하고 오직 현재 캔버스에 집중.
- **날짜/시각 기반 고유 파일명 생성**: 화이트보드 진입 시 `[101] 2026-08-30_1620.pen`과 같은 날짜·시각 명명 체계로 새 판서 생성.
- **획(Stroke) 단위 실시간 Cloud 동기화**: 필기 시 획이 그어질 때마다(`_autoSaveBoard`) 비동기로 교사 Google Drive에 실시간 저장되어 교사용 앱 및 Cloud 도구에서 즉시 열람 가능.

### 2. Boardest Teacher 인증 & 보안 제어 센터 전면 리뉴얼
- **초대형 6자리 Stegano OTP 카드**: 30초 잔여 시간 프로그레스 바, 원터치 번호 복사, Google Authenticator QR 등록 버튼 제공.
- **외부 네트워크 표준 시각 동기화 바**: 표준 UTC 오프셋 실시간 모니터링 및 `[⚡ 지금 재동기화]` 버튼 탑재.
- **전자칠판 기기 신뢰 (자동 로그인) 및 Auto Lesson Flow 토글**: 1회 인증 후 자동 연결 및 종 칠 때 자동 PPT 진도 기능 지원.
- **보안 비상 초기화 & OTP 시크릿 재생성**: 기존 전자칠판 세션 일괄 무효화 및 새 키 발급.

### 3. 전자칠판 자동 로그인(신뢰 기기) 세션 보존 & 1:1 대칭 및 Cloud 파일 즉시 로드 안정화
- **OTP 검증 시 교사 정보(`activeTeacherName`, `activeOwnerEmail`, `activeTotpSecret`) 완벽 보존**으로 `[🔒 자동로그인 등록]` 100% 정상 작동.
- **Cloud 파일 목록 Future 캐싱**: `_cloudFilesFuture` 캐싱을 통해 무한 로딩 스피너 현상을 해결하고 새로고침 및 모달 닫힘 시 즉시 파일 목록 렌더링.
- **지금 수업 카드 vs Cloud 카드 1:1 동일 폭 (`flex: 36` : `flex: 36`) 완벽 대칭**.

---

## 📌 B 2.7.4 (2026-08-30)

### 1. Cloud 독 내 TBP 완전 통합 & 상단 2-Tab 스위처
- **[📁 Cloud 파일] | [📖 TBP 교과서] 상단 탭 스위처 탑재**:
  - `📁 Cloud 파일`: 일반 수업 교안, PDF, PPT, Canva, 필기 노트(.pen) 실시간 열람.
  - `📖 TBP 교과서`: 교사 Google Drive에 저장된 `.BSTtbp`, `.tbp`, `교과서` 파일 목록을 실시간으로 가져와 클릭 시 TBP 전자교과서 뷰어 즉시 실행.
- **클라우드 연결 시 1:1 대칭 완벽 유지**:
  - Cloud 사용 시 **지금 수업 카드 (`flex: 36`) : Cloud 독 (`flex: 36`)**의 **1:1 동일 폭**으로 확장.
  - 평상시(미사용 시)에는 지금 수업 카드(`flex: 54`), 광고판(`flex: 18`, A4 슬림), 도구(`flex: 28`)로 최적 비율 유지.
- **[🔒 자동 로그인 (신뢰 기기)] 원터치 등록 버튼 탑재**:
  - Cloud 독 상단 헤더에 **[🔒 자동로그인 등록]** 버튼 추가.
  - 클릭 시 해당 전자칠판 기기를 교사의 신뢰 기기로 즉시 등록하여 다음 수업부터 매번 OTP 입력 없이 자동 로그인 수행.
- **우측 하단 BST 도구 3x2 (6개) 대칭 정렬**:
  - TBP가 Cloud 독 내부로 완전 통합됨에 따라, 도구 그리드를 `[달력]`, `[주간 시간표]`, `[클라우드]`, `[급식 식단/호출]`, `[판서하기]`, `[플러그인]` 6개로 알차게 정돈.

---

## 📌 B 2.7.3 (2026-08-30)

### 1. 외부 네트워크 표준 시각 기반 OTP 동기화 (`NetworkTimeService`)
- 시스템 로컬 시각 오차를 보정하기 위해 외부 시간 API(`Cloudflare Worker`, `WorldTimeAPI`, `timeapi.io`, HTTP Date Header)를 통한 UTC 시간 오프셋 자동 산출.
- `TotpService` 및 Steganography 6자리 동적 셔플 OTP(Cloud ID 2자리 + TOTP 4자리) 전반에 표준 보정 시각 적용으로 클라이언트 기기 간 시각 불일치 문제 완전 해결.

### 2. Boardest 전자칠판 대시보드 레이아웃 고도화 & TBP 클라우드 전용 연동
- **평상시 vs Cloud 연결 시 레이아웃 동적 최적화**:
  - **평상시 (Cloud/USB 미사용)**: 지금 수업 카드(`flex: 54`), 광고판(`flex: 18`, A4 세로 슬림 비율), 도구(`flex: 28`)로 광고판이 작고 아담하게 배치되어 지금 수업 화면을 넓게 제공.
  - **Cloud/USB 사용 시**: 지금 수업 카드가 `flex: 36`으로 축소되고, 광고판 위치의 Cloud 파일 탐색기 위젯이 `flex: 36`으로 확장되어 **1:1 대칭 동일 폭**을 완벽 유지.
- **TBP 전자교과서 순수 교사 Cloud 연동 & 외부 URL 완전 제거**:
  - 모든 하드코딩된 출판사 웹 교과서 URL을 **완전 영구 삭제**.
  - TBP는 교사용 Cloud(Google Drive)에 연결된 상태에서만 교사의 드라이브에 업로드된 `.BSTtbp` / TBP 교과서 목록을 실시간으로 가져와 작동하도록 전면 개편.
  - 클라우드 미연결 시 교사용 Cloud 연결 유도 모달 제공.

### 3. Boardest Teacher 앱 전면 대개편
- **USB 기능 완전 제거**: 교사용 앱에서 USB 인식/폴링/패널을 완전히 제거하여 순수 클라우드 중심의 안정적인 교사용 앱으로 전환.
- **메인 4대 카드 나란히 배치**: 메인 대시보드에 **[시간표], [Cloud], [OTP], [Bst 도구]**를 아름답고 조화롭게 배치.
- **BST 도구 메뉴 고도화**: 도구란에 **Cloud 설정, OTP 설정, 시간표 전문 보기(주간)** 버튼 탑재.
- **선택형 팝업 / 미니 모드 일원화 (Web/Desktop)**: 웹 및 데스크톱 모두에서 탭 전환 시 **OTP / 교사 시간표 / 교실 시간표** 3대 선택 탭을 갖춘 팝업/미니 위젯 제공.
- **로그인 즉시 자동 OTP 활성화**: 로그인 완료 시 지체 없이 Stegano OTP 및 2자리 Cloud ID 자동 활성화.

### 4. 정규 학급 ID 체계 및 실시간 온라인 학급 필터링 규격
- **순수 숫자 교실 ID만 허용**: `101`, `105`, `123` 등 순수 숫자로만 구성된 교실 ID를 정규 학급으로 처리 (`105` $\rightarrow$ 1학년 05반, `123` $\rightarrow$ 1학년 23반).
- **비정규 학급 완전 배제**: 알파벳이 포함된 교실 ID(`Music1`, `LabA`, `Sci2`, `special` 등) 및 교수학습실/특별실을 완전 제외.
- **실시간 활성 학급만 표시**: 최근 하트비트 신호가 유효한 실시간 활성(온라인) 학급만 목록에 노출.

### 5. 판서 데이터 학급별 격리 및 권한 정책
- **Boardest (전자칠판)**: 현재 설정된 학급으로 자동 고정되며, 판서 데이터 전환 드롭다운/버튼 완전 제거.
- **Boardest Teacher (교사용)**: 기본값은 `teacher`이며, 실제로 열람/생성된 적이 있는 반 목록만 동적으로 탐색하여 해당 반 판서 데이터만 열람/수정 가능.

---

## 📌 B 2.7.2 (2026-08-27)

### 1. .pen 차세대 통합 판서 저장 및 Cloud 폴더 규격화 (3가지 실행 환경 기준)
- **판서 사용하는 모든 도구(기본칠판, PDF, PPT, HWP Overlay, 사이트, TBP, Canva)에 `.pen` 표준화**:
  - **1) Teacher 앱으로 실행 (`isTeacherApp`)**: Cloud/Local 무관하게 항상 `[Teacher]` 접두사 적용 (`[Teacher] {날짜_시간}.pen` / `[Teacher] {파일명}.pen`).
  - **2) 전자칠판 로컬 저장 (`boardest` Local)**: 시간표 기준 `[교사ID]` 접두사 적용 (`[교사ID] {날짜_시간}.pen` / `[교사ID] {파일명}.pen`). 시간표 교사가 들어와서 화이트보드를 누르면 최근 화이트보드 자동 로드 및 **교사별 화이트보드 관리 다이얼로그** (Cloud 사용 교사 제외) 제공.
  - **3) 전자칠판 Cloud 연동 (`boardest` Cloud/OTP)**: `[교실ID]` 접두사 적용 (`[교실ID] {날짜_시간}.pen` / `[교실ID] {파일명}.pen`)하여 Google Drive `bst-pen` 폴더에 동기화.
- **판서 보관함 (`SavedInkView`) 및 교사별 화이트보드 관리 고도화**:
  - Google Drive `bst-pen` 폴더 및 로컬/USB 디스크의 `.pen` 판서를 실시간 스캔.
  - 반별(`[101]`, `[203]`, `[Teacher]`, 교사명), 유형별(PDF, PPT, HWP, 칠판, TBP, Canva) 필터링 및 다중 페이지 스트로크 열람/미리보기 제공.
- **영상 진도 로그 정리 & TBP/Canva 클라우드 폴더화**: `AGENT.md` 규격에 맞춰 불필요한 영상 진도 로그(`*.vidlog.bstsave`)를 정리하고 TBP/Canva 클라우드 폴더 기반 표준 정립.

### 2. Teacher 앱 UI 개선 & 타이틀바 Windows/Web 최적화
- **Web 브라우저**: 상단 타이틀바를 완전 제거(`const SizedBox.shrink()`)하여 온전한 웹 SaaS 포털 화면 제공.
- **Windows Desktop (EXE)**: 창 드래그 및 최소화/최대화/닫기/AOT 핀 컨트롤이 유실되거나 숨겨지지 않도록 메인 뷰 및 OOBE 설정 마법사(`TeacherSetupWizardView`) 전체에 드래그 헤더 및 윈도우 컨트롤 영구 고정.

### 3. Google Drive 401 권한 오류 및 Web 파일 업로드 픽스
- **드라이브 공간 검색 분리**: `findFolderByName` 및 `fetchDriveFoldersInParent`에서 일반 드라이브 폴더(`bst-save`, `bst-pen`, `bst-canva`) 검색 시 `spaces=appDataFolder`를 강제하지 않고 일반 사용자 드라이브 영역을 정상 검색하도록 수정하여 401 오류 해결.
- **Web 업로드 호환성 강화**: `uploadFileToDrive`가 Web/데스크톱 공용으로 `Uint8List`, `List<int>`, `String`, `File` 등 모든 포맷을 자동 감지하여 바이트 단위로 안전 업로드 처리.

### 4. OTP 인증 강화 & 런타임 Null-Safety 무결성 확보
- **OTP 실시간 연동 강화**: 60초 주기 부드러운 진행 게이지, 원터치 클립보드 복사, 시크릿 즉각 재발급 및 Firestore `teacher_cloud_tokens` 자동 동기화.
- **Web 런타임 크래시 방지**: `AppSettings.fromJson`, `StorageService.getSyncConfigs`, `NeisService` 등에서 발생하던 non-string/null 형변환 에러(`TypeError: null is not a subtype of type String`)를 100% null-safe하게 보강.

### 1. FCM (Firebase Cloud Messaging) Service Worker & 푸시 파이프라인 완비
- **Web / PWA FCM Service Worker (`firebase-messaging-sw.js`) 탑재**: `boardest`, `boardest_teacher`, `boardest_teacher_lite` 전반에 FCM 백그라운드 푸시 서비스 워커 구축.
- **Firebase Messaging Compat SDK 연동**: PWA 및 브라우저에서 FCM 토큰 발급 및 백그라운드 푸시 알림 & 진동 연동.
- **FCM 연결 기반 실시간 수신**: 칠판 및 교사용 PWA가 켜져 있는 동안 FCM 소켓 채널을 유지하여 쿼터 소모 없이 0.1초 즉시 알림 수신.

---

## 📌 B 2.7.0 (2026-08-23)

### 1. 순수 Firebase 기반 제로-토큰 하트비트 최적화
- **상시 펄스 제거 & 라이프사이클 쓰기(시작 1회, 종료 1회) 전환**: 100~200개 교실 대상 하트비트 폭증을 원천 차단하여 쓰기 횟수를 99% 절감 (교실 200개 하루 총 수백 회 쓰기 수준).
- **10분 주기 Presence 터치 & 15분 감지 윈도우**: 칠판 실행 중에는 실시간 스트림 채널을 유지하며, 10분에 1회만 완만하게 갱신하여 쿼터를 극대화 절약.

---

## 📌 B 2.6.9 (2026-08-23)

### 1. 전자칠판 Firestore 실시간 푸시 스트림(`documents:listen`) 탑재
- **유휴 상태 읽기 0회**: 칠판 앱(`boardest`)이 켜져 있는 동안 단일 실시간 푸시 스트림 연결 유지 (평상시 읽기 0회, 데이터 소모 0).
- **0.1초 즉시 팝업 수신**: 교사가 급식 호출 또는 쪽지 전송 시 Firestore 스트림을 통해 지연 없이 0.1초 만에 팝업 트리거.
- **앱 종료 시 즉시 해제**: 칠판 앱 닫힐 때 스트림 및 리소스 100% 완전 해제.

### 2. 교사 PWA Web Notification & 교사용 앱 알림 수신 안내
- **Teacher Lite (PWA)**: 스마트폰 홈 화면 추가 시 Web Notification 및 진동(`navigator.vibrate`) 연동 지원.
- **Teacher EXE / Web**: 쪽지/메시지 화면 상단에 `💡 문자 및 쪽지 받기는 스마트폰에서 Teacher Lite를 PWA로 저장해주세요.` 안내 배너 탑재.

---

## 📌 B 2.6.8 (2026-08-23)

### 1. 전자칠판 수업 시간표 기반 지능형 폴링 & Firebase 무료 쿼터 극대화 최적화
- **수업 중(조회 10분 전 ~ 종례 10분 후) 지능형 모니터링**:
  - **집중 수업 시간 (수업 시작 5분 후 ~ 종료 5분 전)**: 1분(60초) 주기 폴링으로 트래픽 최소화.
  - **쉬는 시간 / 급식 / 교시 전후 5분**: 10초 주기 실시간 고감도 폴링으로 즉각 반응.
- **수업 시간 외 (방과 후, 야간, 주말/휴일) 완전 절전 & 자동 오프라인 처리**:
  - 폴링 및 Firestore `lastActive` 펄스를 전면 중단하여 교사 호출 앱(Teacher Lite / App)에서 불필요하게 온라인으로 뜨지 않도록 처리.
- **대시보드 상단 5시간 수동 켜기 모드 (`⚡ 수동 켜기`)**:
  - 상단 시계 영역에 수동 켜기 토글 버튼 탑재. 켜면 5시간 동안(또는 직접 끌 때까지) 20초 주기로 상시 갱신 및 펄스 전송.
- **Firebase 할당량 안전성**: 교실당 일일 약 900~1,000회 읽기로 Spark 무료 한도(50,000회/일)의 2% 수준으로 극히 안전함.

---

## 📌 B 2.6.7 (2026-08-22)

### 1. Boardest Eat 급식 호출 무결성 및 9번/1번 급식실 격리
- **칠판 하트비트 덮어쓰기 방지**: 전자칠판 주기적 존재 펄스(`_registerClassroom`)에서 `called` 필드를 제거하여 교사의 호출 신호가 즉시 덮어씌워지지 않도록 수정.
- **급식실 2분 실시간 윈도우 & 엄격 격리**: 15분 지연 윈도우를 2분 윈도우로 개편하여 급식실 변경 시 이전 급식실 잔여 카드가 즉시 사라지도록 처리.

### 2. Teacher Lite 실시간 컴시간 시간표 & OTP 시크릿 통합 동기화
- **컴시간 Cloudflare Worker 정밀 파싱**: `https://comcigan.jiwho.workers.dev/api/comcigan/lookup` 연동으로 교사 시간표 및 수업 목록 100% 로드.
- **TOTP 시크릿 통일**: `teacher_cloud_tokens`의 Firestore 시크릿을 Teacher Lite 및 EXE 앱이 동일하게 공유하여 6자리 OTP 코드 완벽 일치.

### 3. Teacher Web 로그인 루프 해결 & 자동 시작 설정 복구
- **`TeacherSetupWizardView` 무한 루프 제거**: Web 진입 시 로그인 콜백 감지 및 기본 학교 정보 자동 완성을 통해 불필요한 설정 리다이렉션 차단.

### 4. 전자칠판 교사 Cloud 연동 동일 학교 필터링
- **타 학교 교사 필터링**: `BstCloudService.getCloudTeachers` 및 Cloud Modal에서 현재 전자칠판 학교와 일치하는 등록 교사만 선별 표시.
- **Firestore Security Rules**: `audit_logs` 권한 추가 및 배포 완료.

---

## 📌 B 2.6.6 (2026-08-22)

### 1. Boardest Teacher Lite 급식 호출 UX 전면 개편 & 1~9 급식실 퀵 실렉터
- **학급 순번 직접 호출 Grid 완전 제거**: 1~8반 수동 호출 버튼을 삭제하고 실제 온라인으로 접속된 전자칠판 카드 중심으로 UI 단순화.
- **상단 1~9 급식실 빠른 전환 버튼 바 탑재**:
  - `[1급식실] ~ [9급식실]` 원터치 탭 버튼을 상단에 배치하여 즉시 전환 및 저장.
  - 급식실별 실시간 온라인 전자칠판 접속 대수 카운트 배지 및 🟢 라이브 인디케이터 표시.
- **온라인 교실 감지 무결성 해결 (학교 코드 & docId 직접 매칭)**:
  - `ydm`, `양동중학교`, `schoolCode` 상호 매칭 유연화 및 Firestore `eat_calls`의 원본 `docId`(`ydm_9_2_8` 등) 직접 타겟팅 패치 적용.
  - 타임스탬프 UTC 파싱 및 15분 활성 윈도우 지원으로 접속 중인 모든 전자칠판 100% 정상 표시.

### 2. Boardest Teacher (Web / Desktop / Lite) 실시간 프로필 서버 조회 & 시간표 자동 로드
- **서버 실시간 프로필 동기화**: OAuth 토큰과 이메일만 전달받아도 앱/웹이 스스로 Firestore `teacher_profiles/{docId}`를 조회하여 교사명, 담당학급, 학교코드, 급식실 번호를 실시간 로드.
- **로그인 루프 방지 & 즉시 시간표 표시**: 로그인 성공 후 추가 설정 요구 없이 컴시간 시간표가 즉시 로드되도록 개편.
- **비로그인 쪽지 발송 잠금**: 25% 회색 비활성화 + 중앙 `"로그인 후 사용 가능"` 잠금 오버레이 유지.

### 3. 전자칠판 3열 시스템 실행 파일(.exe / .apk / .lnk) 직접 파일 등록 지원
- **사용자 지정 앱 직접 선택 탑재**: 3열 바로가기 슬롯 추가 다이얼로그에 `[📂 직접 파일(.exe/.apk/.lnk) 선택]` 버튼을 추가하여 원하는 모든 프로그램을 원터치로 등록 가능.

---

## 📌 B 2.6.5 (2026-08-22)

### 1. Boardest Eat 실시간 급식 호출 무결성 & 선택된 급식실 전용 학급 필터링
- **전자칠판 실시간 동기화 (`eat_calls` 표준화)**:
  - 교사용 앱/웹과 전자칠판(`MealCallService`) 간 Firestore 컬렉션 경로를 `eat_calls/{connName}_{cafeteria}_{grade}_{classNum}`으로 100% 일치시켜 호출 즉시 칠판 팝업 알림이 트리거되도록 전면 개편.
- **선택된 급식실 전용 실시간 온라인 학급 필터링**:
  - `eat_calls` 컬렉션에서 최근 5분 이내 활동한 온라인 전자칠판 중, **현재 선택한 급식실 번호(`cafeteriaNum`)와 일치하는 학급만 선별 필터링**하여 실시간 카드(🟢 온라인 배지, 호출/호출취소 버튼)로 표시.
  - '같은 급식실 온라인 학급 전체 호출' 기능 탑재.
  - 학년 탭(1, 2, 3학년) 및 1~8반 수동 호출 그리드에도 실시간 접속 여부(초록 닷) 및 호출 상태 연동.

### 2. Boardest Teacher Lite 목업 데이터 완전 제거 & 실시간 컴시간 연동
- **목업 시간표 데이터 전면 제거**: 더미 시간표 제거 후 컴시간 실시간 시간표 프록시(`boardest-timetable-proxy.jiwho.workers.dev`) 연동.
- **급식 비로그인 설정과 호출 화면 분리**:
  - `/eat` 진입 시 비로그인 게스트 모드에서 학교명/ID, 당번 교사 성함, 급식실 번호를 직관적으로 입력하는 설정 화면과 실시간 급식 호출 화면을 명확히 분리.
  - URL 파라미터(`school`, `caf`, `name`, `schoolId`, `teacherName`, `cafeteriaNum`) 또는 로컬 캐시를 통해 자동 우회 진입 지원.
- **비로그인 시 쪽지 발송 잠금 UI**: 쪽지 발송 영역을 회색 비활성화(투명도 25%) 처리하고 중앙에 `"로그인 후 사용 가능"` 오버레이 및 Google 로그인 버튼 배치.

### 3. Boardest Teacher 앱 실시간 Firestore 프로필 조회 & 설정 포털(`/edit`) 연동
- **`school_config.json` 로컬 쓰기 기능 제거**: 매번 실시간으로 Firestore `teacher_profiles/{docId}`에서 프로필 및 학교 정보를 직접 쿼리하여 최신 상태 유지.
- **설정 버튼 외부 웹 포털 연동**: 앱 내 설정 제거 후 설정 클릭 시 기본 웹브라우저로 Direct OAuth 포털 수정 페이지(`https://boardest-teacher-oauth.web.app/edit`) 즉시 호출.

### 4. 전체 웹 배포 및 Windows Release 빌드 완료
- **Firebase Hosting 배포 완료**:
  - `https://boardest-teacher-lite.web.app` (Live)
  - `https://boardest-teacher.web.app` (Live)
  - `https://boardest-teacher-oauth.web.app` (Live)
- **Windows Release 실행 파일 빌드 완료**: `boardest_teacher.exe` 최신 빌드 컴파일 완료.

---

## 📌 B 2.6.4 (2026-08-22)

### 1. Boardest Teacher 앱 로그인 리다이렉션 & 루프백 수신 감지 완결
- **OAuth 포털(`boardest-teacher-oauth`)의 Web 타겟 직접 리다이렉션 완결**:
  - `clientTarget === 'web'` 시 불필요하게 로컬 루프백(`127.0.0.1:1217`) fetch를 시도하여 브라우저 리다이렉션이 차단되던 결함을 제거하고, 즉시 `https://boardest-teacher.web.app?${params}`로 안전하게 이동하도록 수정.
- **Web URL 쿼리 스트링 & Fragment 파라미터 이중 파싱 및 즉시 로그인 진입**:
  - Flutter Web 라우터 특성에 따라 URL 쿼리 파라미터가 `queryParameters` 또는 `fragment`(`/#/?auth=success...`) 어디에 위치하든 100% 누락 없이 전수 추출.
  - OAuth 포털에서 전달된 교사 프로필(`schoolName`, `teacherName`, `grade`, `classNum`, `token`)을 바탕으로 추가 Firestore 지연 없이 `AppSettings` 즉시 생성 및 `TeacherView` 메인 화면으로 다이렉트 전환.
- **앱 시작 시 Loopback HTTP Server 즉시 자동 가동**:
  - `main.dart` 최상단 초기화 과정에서 `CloudDriveService.instance.init()`을 자동 호출하여 Windows 데스크톱(`127.0.0.1:1217`) 루프백 서버 및 세션 저장소가 부팅 즉시 100% 대기하도록 개선.

### 2. Boardest Teacher Lite 모바일 UI 구성요소 전면 동기화 & 고도화
- **Teacher 앱과 100% 일치하는 5대 핵심 탭 컴포넌트 탑재**:
  - `0: 시간표`: 실시간 현재 교시 표시, 컴시간 실시간 연동, 주간 시간표 격자 모달, 요일별 시간표.
  - `1: Cloud OTP`: Google Drive 연동 상태, 대형 6자리 실시간 TOTP 핀코드, 남은 시간 게이지 프로그레스 바, 신뢰 기기/수업 자동 전환 토글.
  - `2: 수업 도구`: 1·3·5·10분 원클릭 수업 타이머/스톱워치, 발표자 학생 번호 랜덤 추첨기(1~30번) & 히스토리.
  - `3: 급식 & 쪽지`: 오늘/내일 NEIS 급식 식단표, 학급별(1~8반) 원클릭 급식 호출, 교내 긴급 쪽지 실시간 Firestore 발송.
  - `4: 설정`: 교사/학교 정보, 프로필 수정(/edit) 포털 링크, 로그아웃 기능.
- **모바일 최적화 & 반응형 레이아웃**:
  - 큰 터치 영역과 스크롤 뷰, 하단 `BottomNavigationBar` 적용으로 모바일 한 손 조작성 극대화.
- **Web & Hosting 배포 완료**:
  - `https://boardest-teacher-lite.web.app`
  - `https://boardest-teacher.web.app`
  - `https://boardest-teacher-oauth.web.app`

---

## 📌 B 2.6.3 (2026-08-22)

### 1. Boardest Teacher Lite (`boardest-teacher-lite.web.app`) 권한 가드 & 급식 비로그인 허용
- **비로그인 급식 지도(`/eat`) 전면 허용**:
  - 급식 지도 탭 및 `/eat` 경로는 복잡한 구글 로그인 없이도 성함 입력만으로 즉시 급식 호출 및 실시간 급식 메뉴 조회가 가능하도록 비로그인 접근 전면 개방.
- **선생님 전용 탭(시간표, Cloud OTP, 쪽지 발송) 인증 가드 적용**:
  - 미로그인 상태에서 시간표, OTP 핀코드, 쪽지 발송 탭 진입 시 임의의 OTP가 노출되지 않도록 전면 차단하고, 깔끔한 안내 카드 및 `[Google 교사 로그인]` 버튼을 제공하는 보안 가드 UI(`_buildLoginRequiredView`) 탑재.
  - AppBar에 로그인/로그아웃 상태 표시 및 원클릭 로그아웃 다이얼로그 추가.

### 2. Google Drive API 스코프 개인정보 보호 강화 (`drive.file` 단독 스코프)
- **전체 드라이브 열람(`drive.readonly`) 권한 제거**:
  - 기존 `drive.readonly` + `drive.file` 조합에서 불필요한 전체 드라이브 읽기 권한을 완전히 제거하고, Boardest 앱이 직접 생성하거나 연 파일만 다루는 `https://www.googleapis.com/auth/drive.file` 단독 스코프로 최소 권한화.
  - 교사의 개인 구글 드라이브 파일 열람을 원천 방지하여 개인정보 보호 극대화.

### 3. Teacher OAuth 포털 클라이언트 구분 (`?web` vs `?web-lite`) & 타이틀 통일
- **`?web` vs `?web-lite` 쿼리 라우팅 완결**:
  - `?web`: Boardest Teacher (웹 `boardest-teacher.web.app` / 데스크톱 `127.0.0.1:1217`) 연동 모드
  - `?web-lite`: Boardest Teacher Lite (`boardest-teacher-lite.web.app`) 전용 리디렉션 모드
- **Teacher 사이트 타이틀 통일**:
  - `boardest_teacher_lite` 등 레거시 표기를 모두 `Boardest Teacher`로 통일.

### 4. Cloudflare Worker 기반 Zero-Trust Google OAuth & OTP 토큰 프록시 배포
- **Worker 배포 완료**: `https://boardest-cloud-token.jiwho.workers.dev`
- **Cloudflare KV 저장소 바인딩**: `TEACHER_SECRETS_KV` (`id = e74963c3a60b4651b7bc790be31cc97f`) 연동.
- **기능**:
  - `/api/auth/token/exchange`: 교사 로그인 시 구글 Refresh Token 안전 획득 및 KV 저장
  - `/api/auth/verify-otp`: 전자칠판 OTP 검증 및 1회용 short-lived Access Token 발급
  - `/api/auth/revoke`: 교사 계정 연동 해제 및 데이터 파기
  - 무료 플랜(100,000 req/day)으로 신용카드 결제 없이 영구 무료 운영 가능.

---

## 📌 B 2.6.2 (2026-08-22)

### 1. Boardest Web (`boardest.web.app`) OOBE 초기 설정 마법사 스크롤 지원
- **OOBE 각 단계 `SingleChildScrollView` 전면 적용**:
  - Step 1 (학교 ID 및 학년/반/특별실 선택), Step 2 (전용 계정 자동 생성), Step 3 (가이드) 화면을 모두 세로 스크롤 가능하도록 개선하여 웹 브라우저 창 크기가 작거나 모바일 화면에서도 콘텐츠 잘림 및 오버플로우 없이 원활하게 스크롤 및 입력 가능.
  - 학급 번호 그리드 뷰 `shrinkWrap` 및 스크롤 비활성화 적용으로 부모 뷰와 부드러운 일체형 스크롤 제공.

### 2. Android 환경 80% (0.8x) 화면 배율 기본 적용
- **안드로이드 고DPI 환경 보정 스케일링**:
  - 안드로이드 기기의 높은 기본 화면 DPI 특성을 보완하기 위해 `AppPaths.adaptiveUiScale`, `MaterialApp.builder` 전역 `textScaler` 및 `SetupWizardView`에 `0.8x` 스케일 팩터를 기본 적용하여 시각적 균형과 쾌적한 화면 구성 확보.

### 3. 교수학습실 및 기타 특수실 운영 정책 최적화
- **교수학습실 (정규 수업 없음 / 교실명 입력 / 쪽지 수신 / BST 도구 전용)**:
  - 교수학습실 선택 시 학년/과목 대신 교실명(예: 교수학습지원실, 제1교무실)을 자유롭게 입력하도록 개선.
  - 대시보드 오늘의 시간표 영역에 교수학습실 전용 안내 카드 및 '쪽지 수신 가능', 'BST 도구 사용 가능' 상태 뱃지 제공.
- **특수실 급식 쪽지 미지원 & 일반 쪽지 수신 무결화**:
  - 교수학습실 및 기타 특수실(과학실, 음악실 등)은 급식 호출/알림(`eat_calls`)을 수신하지 않도록 필터링하고, Firestore 상에 고유 특수실 ID(`{schoolId}_special_{room}`)로 연결하여 교내 일반 쪽지 및 학생 호출은 정상 수신되도록 `MealCallService` 로직 고도화.

---

## 📌 B 2.6.1 (2026-08-22)

### 1. 교사 인증 & 클라우드 토큰 동기화 전면 무결화 (OAuth / Lite / Desktop / Board)
- **Web OAuth 포털(`boardest-teacher-oauth`) `teacher_cloud_tokens` 동기화 탑재**:
  - `saveProfileAndUnlockApp()` 실행 시 `teacher_profiles`뿐만 아니라 `teacher_cloud_tokens` 컬렉션에도 RFC 4648 Base32 `totpSecret` 및 토큰 페이로드를 즉시 동시 기록하여, 웹에서 가입/등록한 교사가 전자칠판에서 즉시 검색 및 캐스팅 가능하도록 완벽 연동.
  - 이메일 기반 docId 키 정규화(`replace(/[.@+]/g, '_')`) 적용.
- **RFC 6238 TOTP 6자리 PIN 코드 엔진 전 플랫폼 단일 표준화**:
  - `boardest_teacher_lite` 및 `boardest_teacher` 내 레거시 임의 SHA-256 문자열 해시 방식을 완전 폐기하고, 전자칠판(`boardest`) 검증 엔진과 100% 호환되는 RFC 6238 HMAC-SHA1 Base32 `TotpService`로 전면 교체.
  - 교사용 웹 Lite 앱에서도 생성된 OTP 핀코드가 전자칠판 원격 인증에 완벽 호환.

### 2. 교사용 데스크톱 DriveCast 연동 서비스 완성
- **`BstCloudService` 내 DriveCast 원격 승인 및 교실 조회 메서드 구현**:
  - `getOnlineClassrooms()` 및 `approveConnectionRequest()` 구현으로 데스크톱 교사용 앱에서 특정 교실 전자칠판으로 1시간/지정 시간 단위 수업자료 DriveCast 즉시 송출 정상화.

### 3. 전자칠판 dHash 엔진 및 판서 스트로크 좌표계 호환성 보강
- **dHash 해시 거리 분기 로직 정상화 (`_onNewHash`)**:
  - 해시 거리 ≤ 64비트(동일 페이지 렌더링/해상도 미세 변화)일 때 불필요하게 페이지 전환 이벤트가 발생하던 버그를 해결하여 페이지 판서 깜빡임 방지.
- **판서 스트로크 좌표계(`dx/dy` & `x/y`) 양방향 방어적 직렬화**:
  - `AnnotationStroke.fromJson` 및 `AnnotationStorageService`에서 `{'dx', 'dy'}`와 `{'x', 'y'}` 키를 모두 안전하게 파싱하도록 개선하여 판서 로드 시 null 캐스팅 에러 원천 차단.
- **임시 TBP 압축 해제 캐시 자동 정리 (`cleanupOldExtractCache`)**:
  - `%TEMP%/bstTBP_*` 내 24시간 이상 경과한 임시 압축 해제 폴더 자동 정리 루틴 추가.

### 4. 전사 15개 공통/플러그인 패키지 테스트 인프라 및 빌드 안정화
- `bst_auth`, `bst_core`, `bst_cloud`, `bst_pen`, `bst_tbp` 등 공통 패키지 단위 테스트 전원 통과 및 의존성 최신화.

---

## 📌 B 2.6.0 (2026-08-20)

### 1. OAuth 포털 Cloud 연동 유도 UI 및 원클릭 권한 승인 배너
- **Cloud 연동 체크박스 기본 활성화 & 손실 회피 안내**:
  - 체크 해제 시 실시간 수업자료 동기화, 전자칠판 원격 PT, 1분 OTP 연결 기능 중단 경고 다이얼로그 노출.
- **Cloud 미연동 감지 상단 고정 배너 & 로그아웃 없는 원클릭 승인**:
  - Cloud 권한이 없을 경우 상단에 안내 배너 노출 및 `[📁 원클릭 권한 연결하기]` 클릭 시 로그아웃 없이 구글 Drive 권한만 즉시 추가 승인.

### 2. Boardest Teacher Web (`boardest-teacher-lite.web.app`) 대개편 & 모바일 반응형
- **루프백/웹 콜백 URL 쿼리스트링 자동 정리**:
  - 로그인 완료 후 주소창의 쿼리스트링을 `replaceState`로 즉시 깔끔하게 정리.
- **웹 버전 최적화 (신호등 및 USB 완전 제거, 순수 Cloud 중심 전환)**:
  - 데스크톱 전용 윈도우 신호등 및 불필요한 USB 탐색기/연결 상태를 웹에서 완전히 제거하고, **Boardest Cloud (Google Drive)**로 100% 통합.
- **반 매핑 자리에 Boardest Cloud 전용 패널 배치**:
  - Google Drive 연동 상태, **1분 주기 OTP 6자리 실시간 핀코드**, **자동 수업 PT 실행 옵션 스위치** 및 수업자료함 배치.
- **웹 환경 시간표 로드 크래시 해결 (`_Namespace` 오류 제거)**:
  - `StorageService` 내 웹 비호환 네이티브 `File`/`Platform` 코드 가드 적용으로 시간표 정상 로드.
- **모바일 뷰포트 반응형 UI 탑재**:
  - 화면 너비 768px 미만 및 모바일 기기 접속 시 하단 네비게이션 바(시간표, Cloud, 수업도구, 급식/쪽지, 설정) 기반 전용 모바일 UI 제공.

---

## 📌 B 2.5.9 (2026-08-20)

### 1. Boardest 교사 전용 인증 허브 & 포털 대개편 (`boardest-teacher-oauth`)
- **신규 회원/미등록 교사 전용 랜딩 카드**:
  - Google 로그인 성공 후 Firestore 프로필이 미등록된 경우, 중앙에 `⚠️ 등록이 필요합니다` 카드와 함께 `[✏️ 교사 정보 등록하기 (/edit) ➔]` 대형 CTA 버튼을 제공하여 혼선 방지.
- **교사용 계정 속성 정규화 (교실 종속 필드 제거)**:
  - 교사용 계정 목적에 맞지 않던 **교실 유형 (일반학급/특별실)** 및 **급식실(cafeteriaNum)** 선택 항목을 마법사, 요약 카드, 데이터베이스 저장소에서 완전히 제거.
- **학교 ID (Boardest Control 등록 ID, 예: YDM) 입력 & 실시간 자동 검증**:
  - Boardest Control에 등록된 영문/숫자 **학교 ID (예: YDM, ydm)**를 입력받아 Firestore `control_configs` 및 컴시간 API와 연동하여 학교명(양동중학교)과 교사 목록을 실시간 로드.
- **실시간 한 글자(oninput) 컴시간 ID 자동 매칭 및 담임 학급(학년/반) 자동 전환**:
  - 교사 성함을 한 글자씩 입력하거나 컴시간 교사 칩을 클릭할 때마다 컴시간 시간표 원본 데이터(`담임`)를 실시간 분석하여, 해당 교사의 **담임 학급(학년 및 반)을 자동으로 감지하여 드롭다운 및 상태 뱃지에 즉시 동기화** (비담임 교사 선택 시 비담임으로 자동 전환).
- **진짜 회원 탈퇴 (Google OAuth 토큰 영구 Revoke + Firestore 완전 삭제)**:
  - **[🚪 로그아웃]**: 세션 토큰만 정리하고 Firestore 프로필을 유지하여 재로그인 지원.
  - **[🗑️ 회원 탈퇴]**: 경고 확인 팝업 후 **Google OAuth 엔드포인트(`https://oauth2.googleapis.com/revoke`)를 직접 호출하여 구글 연동 권한을 영구 취소(Revoke)**하고, Firestore `teacher_profiles`, `teacher_cloud_tokens` 및 로컬 데이터를 100% 영구 삭제한 뒤 초기 로그인 화면으로 완전 초기화.
- **라우팅 정규화 (`/` & `/edit`)**:
  - `?mode=edit`는 무효화하고 오직 `/edit` 경로만 유효하도록 정규화.
  - 비로그인 상태로 `/edit` 진입 시 루트(`/`)로 강제 이동하여 로그인 완료 후 다시 `/edit`로 자동 복귀하도록 인텐트 보존.

### 2. Firebase Auth 완전 배제 및 순수 Direct Google OAuth 2.0 전환
- `firebase-auth-compat.js` 의존성을 완전 제거하고, 순수 **Google OAuth 2.0 공식 엔드포인트 (`https://accounts.google.com/o/oauth2/v2/auth`)** 직접 호출 방식으로 전환.
- 로그인 클릭 시 `boardest-teacher-oauth.web.app` ➔ `accounts.google.com` ➔ `boardest-teacher-oauth.web.app/#access_token=...`로 다이렉트 복귀.
- 단일 통합 Client ID `287519871774-tccqiqt3em43311vlsb79jg222sqi8qo.apps.googleusercontent.com` 전체 통일.
- Drive 연동 선택 체크박스에 따른 스코프(`drive.file`, `drive.readonly`) 동적 분기.

### 3. Boardest Cloud & TOTP / OTP 연동 엔진 전면 점검 및 보강
- `BstCloudTeacher.fromFirestore`: `name`과 `teacherName` 필드를 모두 안전하게 지원하도록 보강.
- `CloudDriveService` (교사용 데스크톱 앱)와 `BstCloudService` (전자칠판 앱) 간 RFC 6238 TOTP 6자리 1회용 PIN 생성/검증 및 Firestore `teacher_cloud_tokens` 토큰 동기화 엔진 무결성 검증 완료.

---

## 📌 B 2.5.8 (2026-08-13)

### 1. 교사 정보 등록 5단계 프로세스 개편 및 앱 자물쇠(인증 게이트)
- **Step 1 (구글 계정 인증 필수)**: Canva API 항목 완전 영구 제거. 구글 OAuth 로그인 토큰이 수신되어야만 다음 단계 진행 허용.
- **Step 2 (학교 ID & 교사 성함)**: 중앙제어 학교 ID 및 교사 성함 입력 시 컴시간 교사 목록 자동 로드.
- **Step 3 (컴시간 교사 ID 선택)**: 교사 성함 기반 기본 필터링 + "전체 교사 ID 보기" 토글 지원.
- **Step 4 (담임 추측 및 미선택)**: 선택한 컴시간 교사 ID와 시간표 데이터 비교하여 담임 학급(N학년 N반) 자동 추측. 직접 수정 및 "담임 미선택" 옵션 제공.
- **Step 5 (저장 & 교사용 앱 시작)**: 프로필 요약 확인 후 저장. 재접속 시 언제든 재설정 및 덮어쓰기 지원.

### 2. 급식 지도 서비스 (`eat_calls`) Firestore REST 400 / 401 오류 해결
- Realtime Database DELETE 401 Unauthorized 호출을 Firestore REST API `DELETE` URL (`firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?key=$API_KEY`)로 전면 개편.
- Firestore `PATCH` 요청 시 `updateMask.fieldPaths` 파라미터 누락으로 인한 Status 400 오류 해소.

### 3. Boardest 데스크톱 앱 디버그 콘솔 및 파일 확장자 지원 확대
- `apps/boardest/windows/runner/main.cpp`: 디버거 연결 여부와 상관없이 앱 실행 시 콘솔 창 자동 팝업 (`CreateAndAttachConsole()`).
- 교과서 뷰어 및 파일 선택기 지원 확장자에 `.bsttbp`, `.bstTBP`, `.tbp`, `.TBP` 전면 추가 및 시계 영역 가로 폭 슬림화 (폰트 90 ➔ 58).

### 4. `boardest.web.app` 웹 환경 시간표 & 교과서 이미지 로딩 해결
- 웹 브라우저 환경에서 윈도우 로컬 경로 접근 시 오류가 발생하지 않도록 `buildAdaptiveImage` 렌더러 구현 (HTTP/data URL/네트워크 이미지 + 타이틀 배지 폴백).
- `selectedSchool` 객체가 웹 초기화 시 지연되더라도 `schoolId` 기반으로 컴시간 코드를 자동 조회하도록 보강.

### 5. 도메인 및 랜딩 페이지 개편
- `what-is-boardest.web.app`: Boardest 에코시스템 공식 소개 & 서비스 바로가기(전자칠판, 교사용 앱, 급식실 지도) 랜딩 사이트 개편.
- `jiwhosboardest.web.app`: 안심 404 페이지 (`404.html`) 배치.

---

## 📌 B 2.5.7 (2026-08-10)

### 1. `753210.xyz` 우회 도메인 완전 제거
- 프로젝트 내 모든 CNAME 파일(`infra/*/CNAME`) 및 우회 리다이렉트 외부 오픈 코드 완전 제거.
- Web 환경에서 별도 우회 사이트 이동 없이 전자칠판 보드 앱(`boardest`), 교사용 앱(`boardest_teacher`)의 모든 UI 및 교과서(`TBP`) 뷰어가 단일 애플리케이션 내에서 바로 구동되도록 개선.

### 2. Cloudflare Worker 프록시 연동 (`https://comcigan.jiwho.workers.dev`)
- **Flutter Web (`kIsWeb`)**: `ComciganService` 내부에서 Worker `/api/comcigan/search` 및 `/api/comcigan/lookup` API를 직접 호출하도록 구현 (Mixed Content / CORS 완전 차단 해소).
- **Flutter Desktop & Mobile (Windows / Android)**: 기존 컴시간 서버 직접 연동 방식 유지로 네이티브 성능 극대화.
- **HTML/PWA 마이크로 서비스 일괄 전환**: `teacher_timetable_web`, `school_set_web`, `boardest_control_web`, `boardest_web` 등 모든 HTML 서비스의 컴시간 데이터 요청을 Worker 프록시 API로 전환.

### 3. `comcigan_proxy.md` 가이드 문서 작성
- Cloudflare Worker 기반 100% 동적 CP949 인코더 및 Raw TCP 소켓(`cloudflare:sockets`) 아키텍처 및 API 상세 명세서 작성.

---

## 📌 B 2.5.6 (2026-08-08)

### 1. Windows 데스크톱 앱 2종 (보드용 & 교사용) 릴리즈 빌드 완료
- `apps/boardest`: C++ Win32 FFI 의존성 및 UTF-16 pointer 수술 완료 ➔ `build\windows\x64\runner\Release\boardest.exe` 릴리즈 빌드 완료.
- `apps/boardest_teacher`: `build\windows\x64\runner\Release\boardest_teacher.exe` 릴리즈 빌드 완료.
- 모노레포 패키지 상대 경로 (`../../packages/common/` & `../../packages/plugins/`) 완전 보정.

### 2. Cloudflare Worker 마이크로 서비스 연동
- `comcigan.jiwho.workers.dev`: 컴시간 학교 이름 검색 & 5자리 코드 즉시 추출 및 실시간 시간표 파싱 API 연동.

### 3. Boardest Control 관리자 포털 (`boardest-control.web.app`) 구축
- `apps/boardest_control/build/web/index.html`: Google OAuth, 신규 관리자 1회용 인증키 발급, 학교 ID 및 일과 시간표 동기화, 전교 공지/배너 게시판 포털 구축.

---

## 📌 B 2.5.5 (2026-08-07)

### 1. 전자칠판 OOBE 온보딩 특별실(과학실/음악실 등) 운영 조건 설정
- 학교 ID 입력 후 **[ 🏫 일반 학급 ]** vs **[ 🔬 특별실 모드 ]** 토글 선택 기능 추가.
- 특별실 모드 선택 시:
  - 특별실 고유 식별 ID 기입 (`music2`, `art1`, `science1` — 학교 내 중복 불허).
  - 특별실 운영 필터링 조건 설정:
    - **조건 1 (담당 선생님 지정)**: 예: `"강진"` 선생님 담당 수업 전체 타임표 자동 합성.
    - **조건 2 (학년 & 과목 지정)**: 예: `2학년 미술` 과목 타임표 자동 합성.

### 2. 특별실 (과학실/교수학습실/미술실) 예약 시스템 아키텍처 및 설계서 작성
- `special_room_reservation_plan.md` 아티팩트 작성:
  - Firestore `/control_configs/{schoolId}/special_rooms/{roomId}` 스키마 설계.
  - 주간 교사 수업 예약 및 방과후 동아리/스터디 예약 워크플로우 & 중복 검증 시퀀스 다이어그램 명세.

### 1. 전자칠판 보드용 이메일 계정 체계 최적화 (`{classID}@{schoolID}.boardest.local`)
- **교사용 앱**: 기존 이메일/소셜 인증 구조 유지 ("교사용 앱은 그대로").
- **보드용(전자칠판) 앱**: 이메일 주소 생성 형식을 `{classID}@{schoolID}.boardest.local`로 개편.
  - 일반 학급 예시 (2학년 1반, 학교ID: `ydm`): `201@ydm.boardest.local`
  - 특별실 예시 (음악2실, 학교ID: `ydm`): `music2@ydm.boardest.local`
- **계정 내 환경 설정(AppSettings) 클라우드 동기화**:
  - Firestore `users/{email}` 문서의 `settingsJson` 필드에 시정표, 런처 슬롯, 시간표 설정 등 모든 환경 설정을 자동 백업 및 로그인 시 복원.

### 1. 조/종례 기능 제거
- 사용자 요청에 따라 조/종례사항 관리 기능을 관리자 포털 및 기기에서 깔끔하게 제거.

### 2. 광고 배너 전체 공개 등록 & 멀티 배너 롤링 로직 (8초 자동 전환)
- 일반 사용자/교사도 사이트에서 자유롭게 배너 등록 가능.
- 전자칠판에 복수의 배너 등록 시 **8초 주기 자동 롤링 캐러셀** 탑재 (상단/하단 인디케이터 표기, 미등록 시 `"📢 등록된 안내/광고가 없습니다"` 렌더링).

### 3. 교사용 앱 3종 서비스통합 OAuth 서버 (`http://127.0.0.1:1217`)
- `Boardest` 필수 연동 + `bst-cld` (Google Drive) + `Canva` (Canva OAuth) 3종 서비스를 127.0.0.1:1217 크롬 브라우저에서 일괄 인증 및 연동 처리.
- 미로그인 시 교사용 앱 메인 진입을 안전하게 차단하는 계정 게이트 탑재.

### 4. 전자칠판 실시간 Firebase Auth 익명 `.nopw.bst` 계정 자동 가입
- 전자칠판 OOBE에서 School ID (예: `ydm`) + 학년 + 반 지정 시 `Class.101@ydm.nopw.bst` 형태의 실제 Firebase Auth 인증 계정이 생성 및 로그인되어 실시간 데이터 수신.

### 1. Comcigan 독립 CLI 스크립트 작성 (`Node.js` & `Python`)
- `scripts/lookup_comcigan.js` 및 `scripts/lookup_comcigan.py` 제작 ➔ CLI 터미널에서 학교명 입력 시 5자리 컴시간 학교 코드 즉시 출력.

### 2. 전자칠판 로그인 미요구 (School ID pure config mode)
- `Boardest-board`는 복잡한 구글 로그인이나 인증키 입력 없이 **School ID (예: `ydm`) + 학년 + 반**만 지정하면 일과 시간, 컴시간 시간표, 교과서, 조/종례사항 등이 일원화 자동 연동.

### 3. 관리자 포털 전교 조회/종례 전달사항 & 관리자 권한 취소 기능
- 포털에서 **아침 조회사항** 및 **하교 종례사항** 입력/게시 기능 탑재.
- **관리자 권한 취소/제거**: 등록된 관리자 목록에서 `[❌ 권한 취소]` 버튼을 통해 인가 권한 즉시 박탈 가능.

### 4. 교사 앱/웹 광고 배너 게시판 & 전자칠판 실시간 롤링 탑재
- 관리자 포털 및 교사 앱에서 **배너 제목, 사진 URL, 게시 시작/종료일**을 지정하여 광고 게시.
- 전자칠판(기존 급식 표시 구역)에 게시된 배너가 실시간 롤링되며, 미게시 시 `"📢 등록된 안내/광고가 없습니다"` 렌더링.

### 5. 학교별 교사 가입용 재사용 비밀번호 (만료기한 & 횟수 제한) 시스템
- 관리자가 특정 학교 ID(`ydm`)에 대해 **교사 가입 전용 비밀번호**, **만료일자**, **최대 사용 횟수**를 지정/발급 가능.

### 1. 관리자 포털 Firestore 권한 오류 해결
- `firestore.rules` 보안 규칙 업데이트 (`control_configs`, `admins`, `adminRegistrationKeys`, `devices`, `registrationKeys` 권한 부여) ➔ Firestore 권한 거부 오류 완벽 해소.

### 2. `bst-cld` Google Drive OAuth 스코프 추가
- Google Drive API 접근을 위한 `drive.file`, `drive.readonly`, `drive` OAuth scope 탑재 ➔ `bst-cld` 드라이브 연동 활성화.

### 3. 교사용 앱 OOBE 1단계 인증키 입력란 전면 제거
- OOBE Step 1에서 불필요했던 가입 인증키 카드 전면 제거 ➔ 오직 **구글 계정 로그인 및 3수 연동**만 깔끔하게 표시되도록 교정.

### 1. 버전 체계 B 2.5.X 전면 승격
- 프롬프트 요청 시마다 하위 버전을 자동 카운팅(B 2.5.0, B 2.5.1...)하는 버전 관리 규칙을 적용.

### 2. 가입 인증키 역할 명확화 & 기존 마스터키 철회
- **마스터키 철회**: 기존 `BST-MASTER-2026-KEY` 철회 완료.
- **인증키 사용 용도 분리**: 가입 인증키(`Registration Key`)는 **오직 관리자 포털(`boardest-control.web.app`) 신규 가입 시에만 요구**되며, 교사용 및 전자칠판 일반 사용자는 인증키 없이 자율 가입/로그인 가능.
- **인증키 미입력 가입 차단**: 관리자 포털 가입 시 발급된 인증키 미입력 시 관리자 권한 부여 거부/탈퇴 처리 (단, Boardest 전체 계정 삭제는 하지 않음).

### 3. 학교 식별 ID (`School ID` — 예: `ydm`) 통합 중앙 제어 체계
- 관리자 포털 및 모든 앱에 **School ID (예: `ydm`)** 필드 추가.
- `ydm` 식별자를 기준으로 Firestore `/control_configs/{schoolId}`에 급식실, 문자 알림, 강제 앱 배포, 학교 일과 시각, 학년별 교과서 등이 일원화되어 실시간 동기화.

### 4. 관리자 포털 학년별 교과서 ZIP 패키지 분리 관리
- `1학년 교과서 ZIP URL`, `2학년 교과서 ZIP URL`, `3학년 교과서 ZIP URL`을 학년별로 독립 관리 및 실시간 배포.

### 1. 교사용 시간표 컴시간 ID 기반 매칭 수정
- `selectedTeacherName` (3글자 풀네임) 대신 `selectedTeacherId` (2글자 컴시간 ID)를 기준으로 comcigan API 응답과 시간표 데이터를 정확히 비교/연동하도록 수정하여 시간표 로드 실패 버그 완벽 해소.

### 2. OOBE (첫 경험 온보딩) 4단계 개편 & 1회용 마스터 인증키 소멸 시스템
- **1회용 마스터 인증키 (`BST-MASTER-2026-KEY`)**: 최초 1회 입력 및 검증 성공 시 마스터 인증키가 자동 소멸/소모 처리되어 재사용이 금지됩니다. (재사용 시 제어 포털에서 발급받도록 안내)
- **Step 1 (로그인 & 3수 연동 & 인증키 검증)**: 가입/연동 필수 인증키(`Registration Key`) 검증 추가. `[✓] Boardest 로그인`, `[ ] Boardest Cloud (bst-cld)`, `[ ] Canva` 3수 체크박스 탑재.
- **Step 2 (학교명 기입)**: 컴시간 API 기반 학교명 검색 및 선택.
- **Step 3 (교사 ID & 교사명 기입)**: 컴시간 약칭(`selectedTeacherId`) 및 원본 풀네임(`selectedTeacherName`) 독립 기입/저장.
- **Step 4 (간단 설명 & 원격 제어 포털 가이드)**: 플랫폼 기능 안내 및 `boardest-control.web.app` 동기화 가이드.

### 3. boardest-control.web.app 중앙 원격 기기 제어 웹 서비스 라이브 배포 완료
- **라이브 도메인**: [https://boardest-control.web.app](https://boardest-control.web.app)
- **Firebase Google OAuth & API Key 복구**: Firebase Web API Key 적용 및 Google OAuth 로그인 게이트 완벽 구동.
- **목업 데이터 제거 & Firestore 실시간 동기화**: 더미 하드코딩 데이터를 제거하고 `registrationKeys` 및 `devices` 컬렉션 기반 동적 UI 적용.
- **과목 통합 교과서 ZIP 패키지 배포**: 교과서 이미지를 개별 수동 등록할 필요 없이 단 하나의 `.zip` 파일 공유 URL 설정 ➔ 전자칠판이 다운로드 후 과목명 자동 매칭.

### 4. 교사용 앱 (`Boardest-Teacher`) 다음 이동 교실 자동 연동
- 교사 시간표 데이터(`selectedTeacherId` / `selectedTeacherName`) 및 컴시간 API 응답을 기반으로 다음 교시 이동 교실(`grade학년 classNum반`) 및 수업 과목을 자동 추출하여 메인 카드에 실시간 표기.

### 2. TBP dHash 시각적 캡처 엔진 전면 개편 (`html2canvas`)
- 기존 텍스트/DOM 기반 해시 방식을 **시각적 캡처 기반 퍼셉추얼 해시**로 전면 전환.
- `html2canvas` 캡처 ➔ 중앙 1:1 크롭 ➔ 17×16 리사이즈 ➔ 256-bit dHash 추출을 통해 해상도나 화면 비율(16:9 ↔ 4:3)이 달라져도 동일한 페이지로 완벽 인식.

### 3. PDF 뷰어 확대/축소 & 폭 맞추기 다이내믹 독 바 탑재
- PDF 뷰어 하단 독 바에 `[ 🔍- ]`, `[ 100% ]`, `[ 🔍+ ]`, `[ ↔ 폭 맞추기 ]` 및 모드 토글 버튼 추가.
- `TransformationController` 기반으로 0.5x ~ 6.0x 실시간 줌, 100% 리셋 및 뷰어 폭 자동 맞춤 지원 (교사용 및 전자칠판 동시 적용).

### 4. 비디오 순수 Dart 다운로드 및 가상 컷편집 JSON 동기화
- Windows native/Win32/COM 의존성 없이 순수 Dart `http` 패키지로 임시 MP4 스트림 청크 다운로드 및 진행률(`0% -> 100%`) 표시 구현.
- `project.bstsave` 내 `maskedRegions` JSON 파싱 시 널-세이프 캐스팅을 보장하여 컷편집 영역 보존 및 재생 스킵 복구.
- `dispose()` 시 비디오 컨트롤러 정지 순서를 안전하게 정리하여 `MyPlayer() destroyed` 경고 해소.

### 5. Google Drive bst-cld 403 핸들링 & Canva OAuth 5대 버그 수리
- Google Drive API 401/403 발생 시 최대 3회 재시도 및 실패 시 재로그인 다이얼로그 표시. `bst-cld`와 웹 `boardest-cloud-connect` 폴더 경로 호환성 확보.
- Canva OAuth 버그 전수 수리:
  - 토큰 엔드포인트 URL 교정 (`/v1/oauth/token`)
  - Basic Auth (`Authorization: Basic base64(client_id:client_secret)`) 헤더 추가
  - `CanvaOAuthService.init()` 실행 및 4시간 만료 토큰 자동 갱신(`refreshCanvaToken`) 구현
  - 거짓 성공 리다이렉트 방지 및 목업 데이터 제거 (메뉴 명칭 `Canva`로 통일)

---

## 📌 B 2.4.0 (2026-08-05)

### 1. 단일화 판서 오버레이 모듈 (`UnifiedPenOverlay`) 신규 구축
- **판서 엔진 통일**: PDF, PPT, TBP, Web, Canva 등 모든 뷰어 모듈에 100% 동일한 펜, 형광펜, 레이저 포인터, 지우개 및 색상 패치 판서 레이어를 탑재.
- **사용자 경험 단일화**: 파일 형식에 따른 판서 도구 차이 및 파편화를 근본적으로 해소함.

### 2. Canva 실시간 API 연동 & 보관함/저장 흐름 개편
- **실시간 API 연동**: `CanvaOAuthService`를 통하여 교사의 Canva 디자인 목록(`GET https://api.canva.com/v1/designs`)을 실시간 조회.
- **UI 이관**: 독립 상단 버튼 제거 후 기존 `titleBarTools` (BST 도구함 모음) 내부로 깔끔하게 이관.
- **저장 흐름**: Canva 디자인 실행 시 `%APPDATA%` 임시 보관 ➔ 웹뷰 + 판서 ➔ 닫을 때 다이얼로그를 통해 **[로컬 PC / USB Pro / Boardest Cloud]** 지정 위치로 `.bstcanva` 내보내기 제공.

### 3. DriveCast 교사 주도 선택 송출 방식으로 전환
- **역방향 설계**: 전자칠판의 접속 대기 요청을 교사가 기다리는 대신, 교사 앱에서 현재 온라인 상태인 교실(전자칠판) 목록을 감지하여 원하는 칠판으로 즉시 1초 송출하도록 전면 개편.

### 4. Google Drive 토큰 무한 새로고침 루프 방지 가드 도입
- 토큰 갱신 시도 시 `_hasAttemptedRefresh` 가드를 추가하여 세션 내 무한 401/403 새로고침 시도 및 콘솔 도배 현상을 근본 방지.

### 5. `boardest-board` (전자칠판 앱) 동시 적용
- 교사용 앱에서 적용된 단일화 뷰어 및 판서 모듈을 전자칠판 앱 환경에도 100% 동기화 적용.

---

### 1. bst-cld 로컬 루프백 OAuth 로그인 아키텍처 전면 재설계
- **핵심**: 기존 Firebase Hosting OAuth 헬퍼 사이트(`boadest-teacher-desktop-app-oauth-login-helper-with-boadest-cld.firebaseapp.com`) 제거.
- **새 아키텍처**: 앱의 `127.0.0.1:1217` 로컬 서버가 로그인 HTML 직접 서빙 + Google Auth Code Flow(`access_type=offline`) + Canva OAuth를 모두 자체 처리.
- **Refresh Token 획득 성공**: `access_type=offline` 파라미터 적용으로 Google Refresh Token 확실 획득. 기존 Firebase SDK `signInWithPopup()`의 Access Token만 반환하는 한계를 근본적으로 해결.
- **`_PendingLoginSession` 도입**: Boardest/Drive/Canva 로그인 상태를 메모리에서 안전하게 관리.
- **라우팅 엔드포인트**: `/login-helper`, `/boardest-login-done`, `/login-status`, `/start-cloud-oauth`, `/cloud-oauth-callback`, `/start-canva-oauth`, `/canva-oauth-callback`, `/login-complete` 모두 구현.

### 2. OOBE 및 설정 UI 통합 연동 패널
- OOBE 위사드 Step 1과 설정 다이얼로그를 **3수 체크박스 연동 UI**로 교체.
  - `[✓] Boardest 로그인` (OOBE에서 필수)
  - `[ ] Boardest Cloud (Drive) 연동`
  - `[ ] Canva 연동`

### 3. what-is-boardest.web.app 안내 랜딩 페이지 신규 생성
- 로그인 완료 후 브라우저가 리다이렉트되는 `what-is-boardest.web.app` 안내 페이지 생성.
- 기존 `oauth_helper_web` 도메인 페이지를 새 주소로 리다이렉트하는 안내 페이지로 교체.

### 4. TBP 명칭 전면 정리
- 앱 전체에서 'Boardbook' 명칭 제거, `.bstTBP` 확장자로 완전 통일.
- UI 문구: '기존 TextBook Pro 교과서 가져오기', '.bstTBP 생성하기' 등으로 정리.

---

## 📌 B 2.2.3 (2026-08-04)

### 1. bst-cld Google Drive API OAuth 권한 스코프 보강 및 401 연동 문제 근본적 해결
- **원인 분석**: OAuth 로그인 도메인(`oauth_helper_web`)에서 2단계 Google Drive 권한 요청 시 제한적인 `drive.file` 스코프만 요청하고 전체 드라이브 액세스 및 사용자 프로필 스코프(`drive`, `drive.appdata`, `userinfo.profile`, `userinfo.email`)가 누락되어 구글 드라이브 API v3 호출 시 401 Unauthorized 오류가 무조건 반환되던 연동 결함 발견.
- **해결 내역**:
  - `oauth_helper_web/index.html`: `https://www.googleapis.com/auth/drive`, `drive.file`, `drive.appdata`, `userinfo.profile`, `userinfo.email` 전 권한 스코프를 추가하여 구글 인증 토큰이 100% 정상 작동하도록 수정.
  - `CloudDriveService`: 토큰 갱신 미지원/만료 시에도 사용자 세션 및 계정 정보를 항상 안전하게 보존하도록 세션 유지 보강.

---

## 📌 B 2.2.2 (2026-08-04)

### 1. bst-cld 자동 로그아웃 해제 및 TBP 컴파일 에러 보완
- `CloudDriveService` 내 401 수신 시 자동 `logout()` 처리 제거.
- TBP 스마트 판서 및 디바운스 dHash 추출 구문 교정.

---

## 📌 B 2.2.1 (2026-08-04)

### 1. bst-cld / CloudDriveService 401 수신 시 자동 로그아웃 전면 제거 & 로그인 세션 보존
- **원인**: 401 Unauthorized 수신 또는 갱신 토큰 비활성화 시 내부적으로 `logout()`이 자동 호출되어 사용자가 매번 자동 로그아웃되는 현상이 발생함.
- **해결**: 모든 자동 `logout()` 호출을 전면 제거. 토큰 갱신 실패/미존재 시에도 사용자 성함 및 기본 로그인 세션을 안전 보존하며, 사용자가 직접 로그아웃 버튼을 누르기 전까지는 세션 상태를 지속 유지.

### 2. Canva 교사용 전용 웹 로그인 헬퍼 연동
- Canva 전용 OAuth 로그인 도메인 연동 및 교사용 앱 내 Canva 계정 연결 뷰어 보강.

### 3. 교사 성함 (급식/문자 전용) vs 교사 ID (컴시간 전용) 용도 완벽 스코핑
- 급식 알림(`meal_call_service.dart`), 문자/메시지 발송, UI 헤더 등 선생님 이름 표시 기능에서는 **`selectedTeacherName`** (3자 원본 이름, e.g. `홍길동`)을 사용하도록 보장.
- 컴시간 시간표 서비스에서는 **`selectedTeacherId`** (가린 이름, e.g. `홍길`)만 사용하도록 분리.

### 4. TextbookPro (TBP) dHash 동적 트리거, 좌클릭 핫스팟, 스마트 점 판서 & 다운로드 하이제킹
- **dHash 자동 추출 트리거**: (1) 5초 주기 자동 타이머, (2) 이전/다음 페이지 버튼 클릭 직후, (3) 화면 터치/클릭 발생 1초 후 dHash 재추출 및 판서/핫스팟 즉시 연동.
- **핫스팟 좌클릭 지원**: 핫스팟 핀 터치/좌클릭 시에도 즉시 팝업/뷰어가 열리도록 보강.
- **스마트 모드 점 판서 인식**: 길게 누르지 않고 짧게 누른 점(dot)도 캔버스 스트로크로 정상 보존.
- **TBP 웹뷰 다운로드 하이제킹**: `.mp4`, `.hwp`, `.hwpx`, `.ppt`, `.pptx`, `.pdf` 등 지원 확장자 링크 클릭 시 자동으로 로컬 전용 뷰어/다운로더로 캡처 연동.

---

## 📌 B 2.2.0 (2026-08-03)

### 1. 교사명 & 교사 ID 완전 분리 표준화
- **OOBE 온보딩 & 설정 다이얼로그**: `교사 ID` (컴시간 약칭/가린 이름 e.g. `홍길`)와 `교사명` (3글자 구글/선생님 원본 성함 e.g. `홍길동`) 필드를 완전히 독립된 입력/저장 구조로 분리.
- `SharedPreferences`: `selected_teacher_id` 및 `selected_teacher_name` 각각 개별 저장.

### 2. TBP dHash 256-bit 파일명 길이 초과 (OS Error 123) 긴급 수정
- **원인**: TBP 판서 수화 중 256글자 256-bit dHash 스트링이 그대로 `.bstpen` 파일명에 포함되어 Windows MAX_PATH (260자) 규격을 초과해 `errno = 123` 발생.
- **해결**: `dHash` 256-bit 문자열을 안전한 64글자 16진수 hex 해시로 인코딩 변환하여 `.bstpen` 파일 저장 경로로 사용. `errno = 123` 오류 완벽 방지.
- **핫스팟 우클릭 & 클릭 이벤트 격리**: 핫스팟 우클릭 생성 및 아이콘 클릭 시 하위 캔버스/웹뷰로 포인터 클릭 이벤트가 전달되지 않도록 이벤트 전파 차단.

### 3. YouTube Direct Stream Downloader 보강
- `YouTubeEmbedService`: YouTube 스트림 플레이어 및 우회 다운로드 실패 시 `yt-dlp` 및 폴백 알고리즘을 강화하여 Direct Stream 복구.

### 4. CloudDriveService 403/401 토큰 자동 갱신 및 Bst-cld 호환성 복구
- API 응답이 HTTP 403 Forbidden 또는 401 Unauthorized 일 때 자동 `refreshAccessToken()`을 재시도하도록 갱신 루틴 보강.

### 5. Canva 교사용 앱 구글 로그인 라이브러리 불러오기
- `CanvaBoardView`: Canva OAuth 2.0 및 구글 로그인을 통한 사용자 디자인 라이브러리 목록 불러오기 모듈 연동.

---

> **이건 B 2.2.0 버전입니다**
