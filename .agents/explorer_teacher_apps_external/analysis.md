# Comprehensive Analysis & Diagnostic Report: Teacher Apps & External Integrations

**Date**: 2026-08-21  
**Investigator**: explorer_teacher_apps_external (teamwork_preview_explorer)  
**Target Subsystems**:
1. `apps/boardest_teacher` (Desktop / Web)
2. `apps/boardest_teacher_lite` (Mobile Web / PWA)
3. `packages/common/bst_timetable` (Comcigan Timetable Engine & Cloudflare Proxy)
4. NEIS School Meals & Schedule Integration
5. School Realtime Messaging (`MessageView`, `bst_messaging`, Firestore REST)
6. Lesson Tool Panels (18-slot matrix, Floating Mini Timer, Mini Calculator, Mini Picker)
7. Cross-Platform IO Guards (`universal_io`, `kIsWeb`, `Platform.isWindows`)

---

## 1. Executive Summary & Defect Classification Matrix

Boardest의 교사용 애플리케이션 에코시스템(`boardest_teacher`, `boardest_teacher_lite`)과 외부 연동 모듈(`bst_timetable`, `NEIS`, `Firestore Messaging`)을 심층 분석한 결과, 기능적 완결성을 저해하는 **핵심 결함 7가지** 및 **잠재적 플랫폼 크래시 요인들**이 식별되었습니다.

### 📊 결함 진단 요약표

| ID | 결함 항목 | 위치 | 심각도 | 영향도 및 증상 |
|---|---|---|---|---|
| **BUG-01** | **OTP 알고리즘 불일치로 인한 전자칠판 연동 불가** | `apps/boardest_teacher/lib/views/teacher_view.dart:250-270`<br>`apps/boardest_teacher_lite/lib/main.dart:253-275` | 🔴 **Critical** | 교사용 앱/Lite에서 생성한 6자리 OTP가 임의 HMAC-SHA256으로 계산되어 전자칠판(`boardest`)의 RFC 6238 Base32 HMAC-SHA1 검증기에서 100% 인증 실패 발생 |
| **BUG-02** | **Web 환경 Universal IO 가드 누락 (런타임 UnsupportedError 크래시)** | `apps/boardest_teacher/lib/services/storage_service.dart:196,205`<br>`apps/boardest_teacher/lib/views/meal_view.dart:109,247,306`<br>`apps/boardest_teacher/lib/views/browser_board_view.dart:40`<br>`apps/boardest_teacher/lib/views/web_hwp_ppt_view.dart:45`<br>`apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart:97,109` | 🔴 **Critical** | Web 빌드 실행 시 `!kIsWeb` 가드 없이 `Platform.isWindows` 또는 `Platform.resolvedExecutable`에 접근하여 `UnsupportedError: Platform._operatingSystem` 런타임 크래시 발생 |
| **BUG-03** | **Teacher Lite OAuth 로그인 상태 미영속화 (새로고침 시 세션 증발)** | `apps/boardest_teacher_lite/lib/main.dart:124-154` | 🟠 **High** | OAuth 포털에서 쿼리 스트링으로 전달받은 토큰, 교사명, 학교 정보가 `SharedPreferences`에 저장되지 않아 페이지 새로고침 시 초기화됨 |
| **BUG-04** | **Teacher Lite 시간표 및 급식 고정 더미 데이터 출력** | `apps/boardest_teacher_lite/lib/main.dart:277-285, 291, 644-648` | 🟠 **High** | 컴시간 Worker 응답을 수신만 하고 화면에 반영하지 않아 고정 더미 교과목(`_getDefaultSubject`)이 표시되며, 급식 호출 시 학교 코드가 양동중(`7010260`)으로 하드코딩됨 |
| **BUG-05** | **`bst_timetable` 패키지 구현 불완전 및 미사용 방치** | `packages/common/bst_timetable/lib/src/services/comcigan_service.dart:55` | 🟠 **High** | 공통 패키지 `bst_timetable`의 Comcigan 서비스가 Web 외 플랫폼에서 `throw Exception('Unsupported platform')`을 던지고 파싱 로직이 없어, `boardest_teacher`가 자체 서비스 코드를 중복 유지함 |
| **BUG-06** | **패키지 및 앱 테스트 스위트 컴파일 실패** | `apps/boardest_teacher_lite/test/widget_test.dart`<br>`packages/common/bst_timetable/test/bst_timetable_test.dart`<br>`packages/common/bst_messaging/test/bst_messaging_test.dart`<br>`packages/common/bst_auth/test/bst_auth_test.dart` | 🟡 **Medium** | 존재하지 않는 `MyApp` 또는 템플릿 `Calculator` 클래스를 참조하여 `flutter test` 실행 시 컴파일 에러 발생 |
| **BUG-07** | **타이머 미해제 및 메모리 누수 위험** | `apps/boardest_teacher/lib/views/teacher_view.dart:2897-2910` | 🟢 **Low** | 모바일 세로모드 리다이렉트 타이머(`_mobileRedirectTimer`)가 위젯 `dispose()` 시 해제되지 않음 |

---

## 2. `apps/boardest_teacher` (데스크톱 & 웹) 심층 분석

### 2.1 아키텍처 및 진입점 (`main.dart`)
- **CLI 인자 기반 다중 모드 라우팅**:
  - `--lite-map <folder>`: 교안 매핑 팝업 다이얼로그(`LiteMapDialog`) 모드로 가로 900x650(담임) 또는 520x600(비담임) 전용 창 구동.
  - `--view-bst <file>`: `.bsttbp`, `.bstcanva`, `.bstpen` 파일 확장자 더블클릭 시 뷰어 라우트(`BstViewerRoute`) 즉시 진입.
  - 기본 실행: 메인 교사용 대시보드(`TeacherView`) 진입.
- **플랫폼 초기화 체계**:
  - Windows: `flutter_acrylic.Window.initialize()`, `RegistryService.registerFileAssociations()`, `windowManager` 투명 타이틀바 및 시스템 트레이(`TrayService`) 초기화.
  - Web: URL 쿼리 파라미터(`?auth=success`) 자동 파싱을 통해 `StorageService` 및 `SharedPreferences`에 Google OAuth 세션 저장.

### 2.2 Universal IO 가드 위반 및 Web 런타임 크래시 분석
Dart는 Flutter Web 환경에서 `dart:io` 패키지의 임포트 자체는 허용하지만, `Platform.isWindows`, `Platform.resolvedExecutable`, `Platform.environment` 등의 런타임 프로퍼티에 접근하는 즉시 `UnsupportedError: Platform._operatingSystem`을 throw합니다.

#### 위반 코드 위치 및 원인:
1. **`lib/services/storage_service.dart` (라인 196, 205)**:
   ```dart
   // 196줄 (saveSyncConfigs)
   final exeDir = File(Platform.resolvedExecutable).parent.path; // Web에서 UnsupportedError
   // 205줄 (getSyncConfigs)
   final exeDir = File(Platform.resolvedExecutable).parent.path; // Web에서 UnsupportedError
   ```
   `saveSettings`나 `loadConfigAndSync`에는 `if (!kIsWeb)` 가드가 있으나, `saveSyncConfigs`와 `getSyncConfigs`의 상단 파일 접근 블록에는 `kIsWeb` 검사가 누락되어 있습니다.

2. **`lib/views/meal_view.dart` (라인 109, 247, 306)**:
   - `_reloadWebview()`: `if (!kIsWeb)` 없이 `Platform.isWindows` 접근.
   - `_buildUpdateRequiredWidget()`: `Platform.isWindows ? ... : ...`를 직접 호출하여 Web에서 에러 UI 렌더링 도중 2차 크래시 발생.

3. **`lib/views/browser_board_view.dart` (라인 40-44)**:
   ```dart
   if (Platform.isWindows) { // kIsWeb 검사 없음!
     _initWindowsWebview();
   } else if (Platform.isAndroid) {
     _initAndroidWebview();
   }
   ```
   `initState()` 실행 즉시 크래시가 발생하여 웹 브라우저 보드 뷰가 완전히 먹통이 됩니다.

4. **`lib/views/web_hwp_ppt_view.dart` (라인 45)**:
   ```dart
   if (Platform.isWindows) { // kIsWeb 검사 없음!
     try { _winWebviewController = WebviewController(); ... }
   ```

5. **`lib/views/tbp/tbp_viewer_route.dart` (라인 97, 109, 319, 372)**:
   - `if (Platform.isWindows)` 접근에 `!kIsWeb` 가드 누락.

6. **네이티브 서비스 레이어 (`context_menu_service.dart`, `registry_service.dart`, `tray_service.dart`, `update_service.dart`, `usb_format_service.dart`)**:
   - `if (!Platform.isWindows) return;` 형태로 작성되어 있어 Web에서 호출 시 즉시 크래시 발생.
   - 반드시 `if (kIsWeb || !Platform.isWindows) return;`으로 가드되어야 함.

---

## 3. OTP / TOTP 인증 알고리즘 불일치 심층 진단

### 3.1 문제 메커니즘
전자칠판(`boardest`)과 교사용 앱(`boardest_teacher`, `boardest_teacher_lite`) 간의 1분 연동 OTP 체계에서 상호 불일치 결함이 발견되었습니다.

```
[Firestore teacher_cloud_tokens] ──> totpSecret (RFC 4648 Base32 문자열, 예: "JBSWY3DPEHPK3PXP")
           │
           ├── [Boardest 전자칠판] ──> TotpService.verifyOtp() 
           │                             (RFC 6238 Base32 HMAC-SHA1 계산 ➔ 정상 검증 기대)
           │
           ├── [CloudDriveService] ──> TotpService.generateCurrentOtp() 
           │                             (RFC 6238 Base32 HMAC-SHA1 ➔ 정상)
           │
           ├── [TeacherView 로컬] ─❌─> _TeacherViewState._updateOtp()
           │                             (Hmac(sha256, utf8.encode(teacherName)).convert(epoch) ➔ 불일치 코드 생성!)
           │
           └── [Teacher Lite PWA] ─❌─> _LiteMainScreenState._updateOtp()
                                         (Hmac(sha256, utf8.encode(email)).convert(epoch) ➔ 불일치 코드 생성!)
```

### 3.2 코드 비교 분석

#### ❌ `TeacherView` (teacher_view.dart:249-266):
```dart
final secret = _settings.selectedTeacher.isNotEmpty ? _settings.selectedTeacher : 'boardest_teacher_secret';
final epoch = DateTime.now().millisecondsSinceEpoch ~/ 60000;
final key = utf8.encode(secret);
final bytes = utf8.encode(epoch.toString());
final hmacSha256 = Hmac(sha256, key);
final digest = hmacSha256.convert(bytes);
// ...
```

#### ❌ `Teacher Lite` (apps/boardest_teacher_lite/lib/main.dart:253-268):
```dart
final secret = _googleEmail.isNotEmpty ? _googleEmail : 'boardest_teacher_lite_secret';
final epoch = DateTime.now().millisecondsSinceEpoch ~/ 60000;
final key = utf8.encode(secret);
final bytes = utf8.encode(epoch.toString());
final hmacSha256 = Hmac(sha256, key);
// ...
```

#### ✅ 전자칠판이 요구하는 표준 `TotpService` (totp_service.dart:56-74):
```dart
final key = _base32Decode(secret); // Base32 디코딩
final msg = Uint8List(8); // 8바이트 빅엔디안 카운터
var w = window;
for (int i = 7; i >= 0; i--) {
  msg[i] = w & 0xff;
  w >>= 8;
}
final hmac = Hmac(sha1, key); // HMAC-SHA1
final hash = hmac.convert(msg).bytes;
// Dynamic truncation & Modulo 1,000,000
```

### 3.3 해결 방안
`TeacherView`와 `Teacher Lite`의 OTP 생성 로직을 `TotpService.generateCurrentOtp(secret)`를 사용하도록 통일하고, Firestore `teacher_cloud_tokens`에 동기화된 Base32 `totpSecret`을 시크릿 키로 참조하도록 변경해야 합니다.

---

## 4. `apps/boardest_teacher_lite` (모바일 PWA) 상세 분석

### 4.1 4개 핵심 탭 구조
1. **시간표 탭 (`_buildTimetableTab`)**:
   - 요일 선택 바(월~금) 및 1~7교시 시간표 카드 렌더링.
   - **결함**: 컴시간 조회 응답이 UI 상태로 바인딩되지 않고 `_getDefaultSubject()` 고정 배열로 표시됨.
2. **Cloud OTP 탭 (`_buildOtpTab`)**:
   - 전자칠판 1분 연동 6자리 OTP 표시 및 남은 시간 프로그레스 바.
   - Auto-PT(교실 진입 시 등록된 교안 자동 실행) 토글 스위치.
   - Google 계정 연동 상태 및 포털 바로가기.
3. **쪽지 발송 탭 (`_buildNoteTab`)**:
   - 수신 대상: 내 담임 반 / 특정 학급(학년-반) / 전체 학급 방송(📢).
   - 상용구 칩(6종) 지원.
   - Firestore `eat_calls/{schoolId}_{cafeteria}_{grade}_{class}`로 PATCH/POST 전송.
4. **급식 지도 탭 (`_buildMealTab`)**:
   - `/eat` 서브루트 또는 QR 진입 시 교사명 미입력 상태면 다이얼로그 팝업.
   - 학년/반 선택 후 '식사이동' / '식사완료' 상태 호출.
   - 오늘 식단(NEIS) 메뉴 칩 표시.

### 4.2 발견된 결함 및 개선점
1. **OAuth 콜백 파라미터 영속화 누락**:
   - `_initFromUrlAndStorage()`에서 URL 파라미터 수신 시 `prefs.setString('bst_google_token', ...)` 등의 저장이 누락되어 PWA를 닫고 다시 열면 로그인이 풀림.
2. **학교 코드 매핑 오류**:
   - `_schoolCode`가 기본값 `'48588'`로 남아있어, 다른 학교 교사가 로그인해도 양동중학교 시간표를 요청함 (`query['schoolCode'] ?? query['schoolId']` 폴백 필요).
3. **NEIS API 하드코딩**:
   - `https://open.neis.go.kr/hub/mealServiceDietInfo?...&ATPT_OFCDC_SC_CODE=B10&SD_SCHUL_CODE=7010260`로 양동중학교가 고정되어 타 학교 급식이 조회되지 않음.
4. **위젯 테스트 컴파일 에러**:
   - `test/widget_test.dart`가 `MyApp`을 인스턴스화하려 하여 빌드 실패 (`BoardestTeacherLiteApp`으로 수정 필요).

---

## 5. `packages/common/bst_timetable` & 컴시간/NEIS 연동 분석

### 5.1 컴시간 통신 아키텍처 (Cloudflare Worker Proxy vs Native)

```
                       ┌──────────────────────────────────────────────────────────┐
                       │                   컴시간 시간표 요청                     │
                       └────────────────────────────┬─────────────────────────────┘
                                                    │
                         ┌──────────────────────────┴──────────────────────────┐
                         │                                                     │
                   [kIsWeb == true]                                    [kIsWeb == false]
                         │                                                     │
                         ▼                                                     ▼
        ┌──────────────────────────────────┐                 ┌──────────────────────────────────┐
        │     Cloudflare Worker Proxy      │                 │         Direct Native TCP        │
        │ https://comcigan.jiwho.workers   │                 │   http://xn--s39aj90b0nb2xw6xh   │
        │             .dev                 │                 │                .kr               │
        ├──────────────────────────────────┤                 ├──────────────────────────────────┤
        │ • Raw TCP (cloudflare:sockets)   │                 │ • Landing frame src 추출         │
        │ • TextDecoder('euc-kr') 동적 매핑 │                 │ • sc_data 인자 및 school_ra 추출 │
        │ • Base64 페이로드 생성           │                 │ • cp949_codec 인코딩/디코딩      │
        │ • CORS 및 Mixed Content 완벽 회피 │                 │ • HTTP GET 직송신                │
        └─────────────────┬────────────────┘                 └─────────────────┬────────────────┘
                          │                                                    │
                          └──────────────────────────┬─────────────────────────┘
                                                     │
                                                     ▼
                                     ┌───────────────────────────────┐
                                     │   JSON 응답 표준 정규화       │
                                     │   (자료147, 자료446, 자료492, │
                                     │    자료481, 자료542, 자료245, │
                                     │    학급수, 분리, 일과시간)    │
                                     └───────────────┬───────────────┘
                                                     │
                                                     ▼
                                     ┌───────────────────────────────┐
                                     │     parseTimetable() 엔진     │
                                     │ • 교사 1~2글자 약칭 자동 매칭 │
                                     │ • 담임교사 학급 매핑          │
                                     │ • 동시수업/분리수업 그룹코드  │
                                     │ • 수업 변경점(isChanged) 감지 │
                                     └───────────────────────────────┘
```

### 5.2 패키지 구조적 결함 (Package Discrepancy)
- `packages/common/bst_timetable`의 `ComciganService`:
  - Web 외 플랫폼에서는 `throw Exception('Unsupported platform')`을 던짐.
  - 시간표 파싱(`parseTimetable`), 교사명 매핑(`matchComciganTeacherName`), 동시그룹 계산이 전혀 구현되어 있지 않음.
- `apps/boardest_teacher/lib/services/comcigan_service.dart`:
  - 665줄에 달하는 완전한 파싱/매핑 엔진이 구현되어 있으나 패키지로 추출되지 못하고 앱 내부에 갇혀 있음.
- **조치 방안**: `apps/boardest_teacher`의 완성된 `ComciganService` 파서 엔진과 `NeisService`를 `packages/common/bst_timetable`로 승격/통합하여 `boardest_teacher`, `boardest_teacher_lite`, `boardest` 전자칠판이 동일한 고품질 파서를 공유하도록 구성해야 합니다.

---

## 6. NEIS 급식/학사일정 & 실시간 메시징 시스템

### 6.1 NEIS 연동 메커니즘
- **교육청/학교 코드 자동 조회 (`_resolveSchoolCodes`)**:
  - 학교명을 입력받아 `https://open.neis.go.kr/hub/schoolInfo`를 조회하고, `ATPT_OFCDC_SC_CODE`(교육청코드)와 `SD_SCHUL_CODE`(표준학교코드)를 `_schoolCodesCache` 인메모리 캐시에 저장.
- **급식 메뉴 정제 (`_cleanMealMenu`)**:
  - `mealServiceDietInfo` 응답에서 HTML `<br/>` 태그를 줄바꿈으로 변환.
  - 알레르기 유발 정보 정규식 `RegExp(r'\([0-9. \t\n]+\)')`를 제거하여 순수 음식명만 추출.
- **학사일정 365일 조회 (`fetchSchoolSchedule`)**:
  - `SchoolSchedule` API를 통해 연간 일정을 가져오고, '토요휴업일', '일요일' 등 무의미한 항목 필터링 후 날짜순 정렬 반환.

### 6.2 실시간 학급 메시징 (`MessageView` & `bst_messaging`)
- **Firestore REST Direct 통신**:
  - 엔드포인트: `https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/{docId}?updateMask.fieldPaths=message...`
  - 문서 ID 형식: `{schoolConnName}_{cafeteriaNum}_{grade}_{class}`
  - 타깃 모드:
    1. `homeroom`: 담임 학급 1개 문서 업데이트.
    2. `specific`: 선택된 특정 학년/반 1개 문서 업데이트.
    3. `all`: 1~3학년 1~8반 총 24개 문서 병렬 업데이트.
- **예외 복구 메커니즘**:
  - PATCH 요청 실패(문서 미존재) 시 `http.post`로 신규 문서를 생성하는 fallback 완비.

---

## 7. 수업 도구 패널 & 플로팅 오버레이

### 7.1 18-슬롯 도구 매트릭스 (`_buildToolsPanel`)
`TeacherView` 우측의 3열 × 6행 패널 구조:
- **1열 (유틸리티 & 학사)**: 타이머(`timer`), 계산기(`calculator`), 발표자(`picker`), 날씨(`weather`), 학사달력(`school_calendar`), BoardBook(`boardbook`).
- **2열 (판서 & 미디어)**: 기본판서(`whiteboard`), 문서판서(`document_board`), 사이트판서(`website_board`), 웹브라우저(`browser_board`), 유튜브(`youtube_board`), 캔바(`canva_board`).
- **3열 (연동 & 관리)**: USB 탐색기(`usb_explorer`), BST Cloud(`bst_cloud`), 인증 관리(`auth_management`), 급식문자(`meal_call`), 학급쪽지(`message_box`), 설정(`settings`).

### 7.2 드래그 가능한 플로팅 미니 윈도우
1. **미니 타이머 (`_buildFloatingTimer`)**:
   - `Positioned` + `GestureDetector(onPanUpdate)`를 통해 화면 내 자유 이동.
   - 3분/5분/10분/15분/20분/30분 원터치 프리셋 버튼.
   - 시간 종료 시 사운드/시각적 강조.
2. **미니 계산기 (`_buildMiniCalculatorWindow`)**:
   - 기본 사칙연산 및 실시간 수식 평가.
3. **미니 발표자 추첨기 (`_buildMiniPickerWindow`)**:
   - 1~40번 학생 번호 랜덤 룰렛 애니메이션.

### 7.3 반응형 레이아웃 및 모바일 처리
- **화면비 기반 적응형 UI**: `AppPaths.adaptiveUiScale`을 통해 High-DPI 및 다양한 해상도에서 1.0~2.5 스케일 팩터 적용.
- **모바일 세로 모드 차단 뷰 (`_buildMobileBlockedView`)**:
  - 모바일 세로 비율(`aspect >= 1.2`) 감지 시 경고 뷰 표시 및 10초 카운트다운 후 `boardest-teacher-lite.web.app`으로 자동 리다이렉션.

---

## 8. 테스트 스위트 결함 및 패키지 정적 분석

### 8.1 깨진 테스트 목록
1. `apps/boardest_teacher_lite/test/widget_test.dart`:
   - `MyApp` 클래스 미존재로 컴파일 에러.
2. `packages/common/bst_timetable/test/bst_timetable_test.dart`:
   - `Calculator` 클래스 미존재로 컴파일 에러.
3. `packages/common/bst_messaging/test/bst_messaging_test.dart`:
   - `Calculator` 클래스 미존재로 컴파일 에러.
4. `packages/common/bst_auth/test/bst_auth_test.dart`:
   - `Calculator` 클래스 미존재로 컴파일 에러.

### 8.2 보강 권장 테스트 명세
- **`bst_timetable_test.dart`**:
  - Cloudflare Worker 및 CP949 원본 시간표 JSON 파싱 무결성 검증.
  - 교사 1~2글자 약칭 자동 매칭(`matchComciganTeacherName`) 알고리즘 테스트 (성+이름앞글자, 부분일치, 성일치).
  - NEIS 급식 알레르기 번호 제거 정규식 유닛 테스트.
- **`bst_messaging_test.dart`**:
  - `Message` 모델 JSON 직렬화/역직렬화 및 Firestore payload 구조 검증.
- **`boardest_teacher_lite/test/widget_test.dart`**:
  - `BoardestTeacherLiteApp` 4개 탭 전환 및 OTP UI 렌더링 스모크 테스트.

---

## 9. 결론 및 권장 수정 사항 (Actionable Items)

1. **OTP 계산 로직 표준화**: `TeacherView`와 `Teacher Lite`의 `_updateOtp()`를 `TotpService.generateCurrentOtp`로 교체하여 전자칠판과의 완벽한 60초 1회용 PIN 인증 호환성을 확보할 것.
2. **Universal IO 가드 전면 적용**: `storage_service.dart`, `meal_view.dart`, `browser_board_view.dart`, `web_hwp_ppt_view.dart`, `tbp_viewer_route.dart` 등 모든 `Platform` 접근에 `!kIsWeb` 가드를 적용하여 Web 환경에서의 무결성을 보장할 것.
3. **Teacher Lite 데이터 영속화 및 실데이터 바인딩**: OAuth 쿼리 수신 시 `SharedPreferences`에 저장하고, 컴시간 Worker 응답 데이터를 파싱하여 시간표 UI에 바인딩하며, NEIS 급식 호출에 교사의 실제 학교 코드를 전달하도록 개선할 것.
4. **`bst_timetable` 패키지 승격 및 테스트 스위트 수정**: `apps/boardest_teacher`의 완성된 파서 로직을 `bst_timetable` 패키지로 공통화하고 깨진 테스트들을 올바른 모델/서비스 테스트로 전면 재작성할 것.
