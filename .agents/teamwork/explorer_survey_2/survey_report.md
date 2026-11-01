# Issue Group 2 상세 분석 보고서 (전체적 기능 완성도 총점검)

**작성자**: `teamwork_explorer_survey_2`  
**일시**: 2026-11-01  
**조사 대상**:
1. 수행평가 (1~12반 실시간 동기화 및 미설치 반 비활성화)
2. PPT 오버레이 (COM 자동 재시도 및 주 모니터 하단 독 표시)
3. Class 자동 업데이트 (.msix 매칭) 및 Teacher 언인스톨러/시작 메뉴 등록

---

## 1. 수행평가 (1~12반 실시간 동기화 및 미설치 반 비활성화)

### 1.1 현재 아키텍처 및 구현 현황
- **관련 파일**:
  - `apps/boardest_teacher/lib/services/assessment_service.dart`: 교사용 RTDB CRUD 및 설치 학급 감지 (`fetchInstalledClasses`)
  - `apps/boardest_teacher/lib/views/teacher_assessment_view.dart`: 교사용 1~12반 필터 바 및 "스마트 다중 공지" 다이얼로그 (`_showSmartMultiNoticeDialog`)
  - `apps/boardest/lib/services/assessment_service.dart`: 교실용 RTDB 조회 및 학년/반 엄격 격리 (`_filterAndNotify`)
  - `apps/boardest/lib/views/components/bst_class_main_layout.dart`: 교실 대시보드 내 주기적 동기화 (`_syncClassAssessmentsAndNotices`)
  - `apps/boardest/lib/services/meal_call_service.dart`: 교실 출석/온라인 상태 등록 (`_registerClassroom`) -> RTDB `/eat_calls`
  - `database.rules.json`: `/assessments` 경로 규칙 (`.read: true, .write: true`)

### 1.2 문제점 분석 (Root Cause Analysis)

#### 1) 실시간 동기화 부재 (Class의 30초 지연 폴링, Teacher의 0초 동기화)
- `apps/boardest/lib/views/components/bst_class_main_layout.dart` (Lines 427~434):
  ```dart
  _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!mounted) return;
    _assessmentRefreshTick++;
    if (_assessmentRefreshTick >= 30) {
      _assessmentRefreshTick = 0;
      _syncClassAssessmentsAndNotices();
    }
    setState(() {});
  });
  ```
  교실 앱(`Boardest Class`)은 30초 주기의 `Timer.periodic` 폴링에 의존하고 있어, 선생님이 교사용 앱에서 수행평가를 등록하거나 수정해도 교실 전자칠판에는 최대 30초 동안 반영되지 않습니다.
- `apps/boardest_teacher/lib/views/teacher_assessment_view.dart`:
  교사용 앱은 아예 백그라운드 폴링이나 이벤트 리스너가 없어, 다른 동료 교사나 교실에서 등록/수정한 내용이 사용자가 직접 '새로고침' 버튼을 누르기 전까지 영구히 갱신되지 않습니다.
- 반면 `MealCallService`(`apps/boardest/lib/services/meal_call_service.dart` Lines 211~250)는 Firebase RTDB의 Server-Sent Events (SSE) `text/event-stream`을 사용하여 0.05초 만에 실시간 스트리밍 처리를 구현하고 있습니다. `AssessmentService`는 이 실시간 스트림이 누락되어 있습니다.

#### 2) 미설치 반 감지 실패 시 교사의 공지 등록 전면 차단 (Lockout 버그)
- `apps/boardest_teacher/lib/services/assessment_service.dart` (Lines 46~102):
  ```dart
  Future<Map<int, Set<int>>> fetchInstalledClasses(String schoolCode) async {
    final effectiveCode = normalizeSchoolKey(schoolCode);
    final Map<int, Set<int>> result = {
      1: <int>{},
      2: <int>{},
      3: <int>{},
    };
    try {
      final res = await http.get(Uri.parse(_eatCallsUrl)).timeout(const Duration(seconds: 4));
      ...
    } catch (e) {
      debugPrint('[Teacher AssessmentService] fetchInstalledClasses error: $e');
    }
    return result;
  }
  ```
- 문제 발생 경로:
  1. 네트워크 지연, 오프라인 모드, RTDB 타임아웃, 또는 신규 학교/데모 환경에서 아직 교실들이 `eat_calls`에 출석 등록을 하지 않은 경우, `result`는 `{ 1: {}, 2: {}, 3: {} }` (빈 집합)을 반환합니다.
  2. `teacher_assessment_view.dart` (Line 341 & Lines 884~920):
     `installedForGrade`가 비어있으면 1반부터 12반까지 모든 반이 `isInstalled = false`가 되어 불투명도 0.38로 흐려지고 클릭이 불가능해집니다 (`onSelected: null`).
  3. `_showSmartMultiNoticeDialog` (Line 857):
     `ActionChip`("설치 학급 전체 선택") 역시 `installedForGrade.isEmpty ? null : ...`로 완전 비활성화됩니다.
  4. 다이얼로그 등록 버튼 클릭 시 (Line 1050):
     `if (selectedClasses.isEmpty) { SnackBar('공지할 학급을 1개 이상 선택해주세요.'); return; }`
     선생님은 그 어떤 학급도 선택할 수 없어 수행평가 등록 기능이 완전히 먹통(Lockout)이 됩니다.

#### 3) 초·고등학교 학년 확장성 부족
- `fetchInstalledClasses`에서 학년 키를 `1, 2, 3`으로만 고정 선언하고 있어, 초등학교(1~6학년) 지원 시 4~6학년 데이터가 유실됩니다.

### 1.3 구체적 구현 개선 방안 (Implementation Proposal)

1. **설치 학급 감지 폴백(Fallback) 안전장치 추가**:
   - `fetchInstalledClasses` 결과가 비어있거나 감지된 반이 0개일 경우, 선생님이 차단되지 않도록 기본 1~12반을 모두 활성화 상태로 허용하거나, 상단에 `[모든 학급 강제 활성화]` 토글 스위치를 제공.
   - `isInstalled`가 `false`여도 `(미확인)` 뱃지만 달고 선택 자체는 가능하도록 완화하거나, `installedForGrade.isEmpty`인 경우 fallback으로 1~12반 전체를 선택 가능하도록 처리.
2. **RTDB SSE 실시간 스트림 리스너 도입**:
   - `AssessmentService`에 `startStreaming(schoolCode, grade)` 함수를 추가하여 `https://jiwhosboardest-default-rtdb.firebaseio.com/assessments/<schoolCode>/<grade>.json`에 `Accept: text/event-stream` 연결을 유지.
   - 교사가 수행평가를 등록하거나 삭제하면 모든 교실 전자칠판과 동료 교사 앱에 0.1초 내 즉시 이벤트가 수신되어 화면이 자동 갱신되도록 처리.

---

## 2. PPT 오버레이 (COM 자동 재시도 및 주 모니터 하단 독 표시)

### 2.1 현재 아키텍처 및 구현 현황
- **관련 파일**:
  - `apps/boardest/boardest_ppt_overlay.cs`: C#/WPF 기반 투명 오버레이 윈도우 및 PowerPoint COM 연동
  - `apps/boardest/boardest_ppt_helper.cs`: COM 브릿지 콘솔 헬퍼
  - `apps/boardest/lib/views/ppt_overlay_view.dart`: Flutter 실행 래퍼 (WPF 오버레이 프로세스 구동 및 표준 입출력 파이프라인 관리)
  - `packages/plugins/bst_native/lib/src/helpers/ppt_helper.dart`: 플러그인 레벨 바이너리 실행 유틸리티

### 2.2 문제점 분석 (Root Cause Analysis)

#### 1) `IOleMessageFilter` COM 자동 재시도 누락 (`RPC_E_CALL_REJECTED`)
- `apps/boardest/boardest_ppt_overlay.cs` (Lines 49~53):
  ```csharp
  public int RetryRejectedCall(IntPtr hTaskCallee, int dwTickCount, int dwRejectType)
  {
      if (dwRejectType == 2) return 150;
      return -1;
  }
  ```
  - COM 명세에서 `dwRejectType`은:
    - `1`: `SERVERCALL_REJECTED` (PowerPoint가 애니메이션 재생, 슬라이드 전환, 사용자 입력 등으로 호출을 명시적 거부)
    - `2`: `SERVERCALL_RETRYLATER` (PowerPoint가 잠시 대기 요청)
  - 현재 코드는 `dwRejectType == 2`일 때만 150ms 후 재시도하고, PowerPoint가 바쁠 때 발생하는 `dwRejectType == 1`에 대해서는 즉시 `-1`을 반환하여 COM이 `0x80010001 (RPC_E_CALL_REJECTED)` 예외를 발생시킵니다.
  - 이로 인해 `PollTimer_Tick` (Line 1308)에서 예외가 발생하여 `_isStandaloneMode = true;`로 즉시 격하(Fall-back)되고, 이후 슬라이드 쇼 페이지 동기화가 끊어지는 치명적인 버그가 발생합니다.

#### 2) 주 모니터 하단 독 표시 및 InkCanvas 하단 영역 마스킹 버그
- `apps/boardest/boardest_ppt_overlay.cs` (Lines 195~248):
  ```csharp
  this.Left = 0;
  this.Top = 0;
  this.Width = SystemParameters.PrimaryScreenWidth;
  this.Height = SystemParameters.PrimaryScreenHeight;

  _mainGrid = new Grid();
  _mainGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
  _mainGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
  ...
  _inkCanvas = new InkCanvas { ... };
  _mainGrid.Children.Add(_inkCanvas); // Row 0에 배치됨 (RowSpan 미지정)

  Grid.SetRow(toolBorder, 1);
  ```
  - `_mainGrid`를 Row 0(`1*`)과 Row 1(`Auto`)로 분할한 뒤, `_inkCanvas`를 Row 0에만 배치했습니다.
  - 이로 인해 `_inkCanvas`는 하단 툴바가 차지하는 Row 1 영역을 덮지 못하여, 화면 하단 약 80~100px 영역(PowerPoint 슬라이드의 하단 자막, 출처, 각주 영역)에는 **판서가 전혀 그려지지 않는 마스킹 현상**이 발생합니다.
  - 펜 세부 설정 카드(`_penDetailsCard`), 지우개 카드(`_eraserDetailsCard`), 페이지 점프 팝업(`_jumpBorder`) 모두 Row 0의 바닥을 기준으로 위치가 잡혀 상단으로 붕 뜨거나 툴바와 정렬이 어긋납니다.
  - 주 모니터(`SystemParameters.PrimaryScreenWidth / Height`) 해상도 기준 윈도우 크기는 올바르게 설정되어 있으나, 전체 화면 판서와 하단 플로팅 독의 계층 구조(Z-Index / Layering)가 Grid Row 분할로 인해 왜곡되어 있습니다.

### 2.3 구체적 구현 개선 방안 (Implementation Proposal)

1. **`OleMessageFilter` 재시도 필터 완벽 구현**:
   ```csharp
   public int RetryRejectedCall(IntPtr hTaskCallee, int dwTickCount, int dwRejectType)
   {
       // dwRejectType 1 (SERVERCALL_REJECTED) 및 2 (SERVERCALL_RETRYLATER) 모두 재시도
       // 최대 10초(10,000ms) 동안 150ms 간격으로 자동 재시도
       if (dwTickCount < 10000)
       {
           return 150;
       }
       return -1;
   }
   ```
2. **`PollTimer_Tick` 예외 완충 로직**:
   - 일시적인 COM 비지 상태에서 1회 오류로 즉시 `_isStandaloneMode`로 전환되지 않도록, 연속 3~5회 실패 시에만 Standalone 모드로 전환하도록 완충 카운터 추가.
3. **InkCanvas 전체 화면 100% 오버레이 및 하단 독 플로팅 구조 수정**:
   - `_mainGrid`의 RowDefinitions를 제거하거나, `Grid.SetRowSpan(_inkCanvas, 2)`를 지정하여 판서 캔버스가 화면 최하단(0 ~ PrimaryScreenHeight)까지 100% 덮도록 변경.
   - `toolBorder`를 캔버스 위에 투명 레이어로 띄우고, `VerticalAlignment = VerticalAlignment.Bottom`, `HorizontalAlignment = HorizontalAlignment.Center`, `Margin = new Thickness(0, 0, 0, 48)`으로 주 모니터 하단에 독 형태로 정렬.
   - 팝업 카드들도 독 상단에 자연스럽게 배치되도록 `Margin` 기준점 정돈.

---

## 3. Class 자동 업데이트 (.msix 매칭) 및 Teacher 언인스톨러/시작 메뉴 등록

### 3.1 현재 아키텍처 및 구현 현황
- **관련 파일**:
  - `apps/boardest/lib/services/update_service.dart`: 교실 앱 무인 백그라운드 자동 업데이트
  - `apps/boardest_teacher/lib/services/update_service.dart`: 교사 앱 업데이트 검사
  - `tools/installer/BoardestInstaller.cs`: 단일 통합 온라인 인스톨러/언인스톨러 (Class/Teacher/Cloud 통합)
  - `tools/installer/BoardestTeacherInstaller.cs`: 구형 Teacher 전용 인스톨러 (동기화 누락 상태)
  - `tools/installer/BoardestTeacherUninstaller.cs`: 구형 Teacher 전용 언인스톨러
  - `tools/installer/build_installer.ps1`: 인스톨러 빌드 및 바이너리 복제 스크립트
  - `scripts/build_all_appx.ps1`: MSIX/AppX 패키징 및 전자서명 스크립트
  - `scripts/publish_release_v543.js`: GitHub Release 에셋 배포 목록
  - `infra/windows_installer_web/index.html`: 웹 기반 인스톨러 UI 엔진

### 3.2 문제점 분석 (Root Cause Analysis)

#### 1) Class 자동 업데이트 시 `.msix` 우선 매칭 실패 및 `.appx` 혼선
- `apps/boardest/lib/services/update_service.dart` (Lines 260~267):
  ```dart
  } else if (!name.contains('teacher') &&
      !name.contains('lite') &&
      !name.contains('cloud') &&
      !name.contains('bcld') &&
      !name.contains('overlay') &&
      (name.endsWith('.msix') || name.endsWith('.appx'))) {
    appxDownloadUrl ??= url;
  }
  ```
  - GitHub Release 에셋에는 `boardest.msix`, `boardest-class.msix`, `boardest.appx`, `boardest-class.appx`가 모두 올라가 있습니다.
  - GitHub API가 반환하는 `assets` 배열에서 `.appx`가 먼저 순회되면 `appxDownloadUrl`에 `.appx` URL이 할당됩니다.
  - 이후 `_startSilentDownload` (Line 324)에서는:
    `final ext = isWindows ? 'msix' : 'apk';`
    다운로드한 원본 파일이 `.appx`임에도 확장자를 무조건 `.msix`로 저장합니다.
  - Windows의 `Add-AppxPackage`는 패키지 내부 블록 맵과 확장자 일치 여부를 엄격히 검사하므로, `.appx` 바이너리가 `.msix` 확장자로 전달될 경우 설치 오류가 발생할 수 있습니다.
- `tools/installer/BoardestInstaller.cs` (Line 1230):
  `pattern = @"https://github\.com/[^""\s]+/releases/download/[^""\s]+/(?:boardest-class|boardest|bst-class)\.(?:msix|appx)";`
  정규식 패턴에서 `(?:msix|appx)`로 묶여 있어 JSON 상에서 앞에 위치한 `.appx`가 우선 캡처될 수 있습니다.

#### 2) Teacher 시작 메뉴 루트 바로가기 등록 및 언인스톨러 파일 간 동기화 불일치
- `tools/installer/BoardestInstaller.cs` (Commit `44d0caa`에서 개선된 상태):
  - `CreateStartMenuShortcutsMultiLocations`:
    `CommonPrograms` 루트, `CommonPrograms\Boardest` 하위폴더, `Programs` 루트, `Programs\Boardest` 하위폴더 모두에 바로가기를 생성하고 `SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero)`를 호출하여 윈도우 11 시작 메뉴 "모든 앱" 목록 루트(B 섹션)에 즉시 노출되도록 구현되어 있습니다.
  - `RemoveShortcutsMultiLocations`:
    바탕화면, 시작메뉴 루트 및 하위폴더, 시작프로그램, 작업표시줄 고정 바로가기까지 모두 검색하여 일괄 영구 삭제하도록 구현되어 있습니다.
- **그러나 동기화 누락 파일들**:
  1. `tools/installer/BoardestTeacherInstaller.cs` (Lines 1660~1687):
     여전히 `...\Programs\Boardest` 하위 폴더에만 바로가기를 넣고 있어, 시작 메뉴 루트에 등록되지 않으며 `SHChangeNotify` P/Invoke도 누락되어 있습니다.
  2. `tools/installer/BoardestTeacherUninstaller.cs`:
     - Line 161: 버전이 구버전(`"5.3.7"`)으로 하드코딩되어 있습니다.
     - Lines 208~216: `RemoveShortcuts()`에서 `...\Programs\Boardest` 하위 폴더만 삭제하고, 시작 메뉴 루트(`...\Programs\Boardest Teacher.lnk`) 및 공용 바탕화면(`CommonDesktopDirectory`)에 등록된 바로가기는 삭제하지 않고 그대로 방치합니다. `SHChangeNotify` 호출도 없습니다.

### 3.3 구체적 구현 개선 방안 (Implementation Proposal)

1. **`UpdateService`의 `.msix` 우선 매칭 보장**:
   - `apps/boardest/lib/services/update_service.dart`:
     `msixDownloadUrl`과 `appxDownloadUrl`을 분리하고, `boardest-class.msix` 또는 `boardest.msix` 등 `.msix` 파일이 발견되면 최우선으로 선택. `.msix`가 전무한 경우에만 `.appx`로 폴백.
   - `_startSilentDownload`에서 대상 파일 확장자를 하드코딩하지 않고, 실제 선택된 URL의 확장자(`.msix` 또는 `.appx`)와 100% 일치하도록 저장.
2. **`BoardestInstaller.cs` 정규식 개선**:
   - `ResolveDownloadUrlAsync`에서 `.msix` 정규식 검색을 먼저 시도하고, 매칭되지 않을 때만 `.appx`를 검색하도록 2단계 순차 매칭 적용.
3. **인스톨러 / 언인스톨러 코드 일원화 및 동기화**:
   - `BoardestTeacherInstaller.cs`와 `BoardestTeacherUninstaller.cs`를 `BoardestInstaller.cs`의 검증된 로직(시작 메뉴 루트 바로가기 등록, `SHChangeNotify` 쉘 갱신, 다중 경로 바로가기 영구 소거)과 100% 동일하게 동기화.
   - `build_installer.ps1`에서 단일 소스인 `BoardestInstaller.cs`를 컴파일하여 모든 변형(`boardest-teacher-installer.exe`, `uninstall.exe` 등)을 생성하는 방식을 정식 표준으로 고정.

---

## 4. 결론 및 종합 요약

| 영역 | 핵심 문제점 | 해결 방안 |
|---|---|---|
| **1. 수행평가 (1~12반)** | 30초 지연 폴링, RTDB 실패 시 1~12반 전체 비활성화(교사 공지 불가) | RTDB SSE 실시간 스트림 연결, 감지 실패 시 1~12반 전체 선택 허용(Fallback) |
| **2. PPT 오버레이** | `IOleMessageFilter`에서 `dwRejectType==1` 거부(COM 에러), 하단 툴바가 InkCanvas를 가림 | `dwRejectType` 1·2 모두 10초간 자동 재시도, InkCanvas 전면 100% 확장 및 툴바 플로팅 독 처리 |
| **3. Class 업데이트 & Teacher 언인스톨러** | 에셋 순서에 따라 `.appx`가 매칭될 위험, 구형 인스톨러/언인스톨러의 시작 메뉴 루트 누락 | `.msix` 명시적 우선순위 바인딩, `BoardestInstaller.cs`의 루트 바로가기 및 `SHChangeNotify` 완전 동기화 |
