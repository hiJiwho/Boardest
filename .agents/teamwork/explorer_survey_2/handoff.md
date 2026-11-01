# Handoff Report — Issue Group 2 (전체적 기능 완성도 총점검)

**Agent**: `teamwork_explorer_survey_2`  
**Date**: 2026-11-01  
**Working Directory**: `c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\`  
**Target Milestone**: Issue Group 2 Survey & Architecture Assessment

---

## 1. Observation

### 1) 수행평가 (1~12반 실시간 동기화 및 미설치 반 비활성화)
- `apps/boardest/lib/views/components/bst_class_main_layout.dart` Lines 427~434:
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
  교실 화면은 30초 주기로만 폴링하고 있으며, 실시간 소켓/SSE 수신기가 없음.
- `apps/boardest_teacher/lib/services/assessment_service.dart` Lines 46~102:
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
  ```
  타임아웃이나 빈 결과 발생 시 `{1: {}, 2: {}, 3: {}}`를 반환.
- `apps/boardest_teacher/lib/views/teacher_assessment_view.dart` Lines 884~920:
  ```dart
  for (int c = 1; c <= 12; c++)
    Builder(
      builder: (_) {
        final isInstalled = installedForGrade.contains(c);
        final isSel = isInstalled && selectedClasses.contains(c);
        return Opacity(
          opacity: isInstalled ? 1.0 : 0.38,
          child: FilterChip(
            label: Text(isInstalled ? '$c반' : '$c반(미설치)'),
            ...
            onSelected: isInstalled ? (val) { ... } : null,
          ),
        );
      }
    )
  ```
  Line 857: `ActionChip` 또한 `onPressed: installedForGrade.isEmpty ? null : ...`로 비활성화됨.
  Line 1050: `if (selectedClasses.isEmpty) { SnackBar('공지할 학급을 1개 이상 선택해주세요.'); return; }`
  따라서 설치된 기기가 RTDB `/eat_calls`에 아직 등록되지 않았거나 네트워크 지연 발생 시, 선생님이 공지를 전면 등록할 수 없는 치명적인 차단 현상이 발생함.

### 2) PPT 오버레이 (COM 자동 재시도 및 주 모니터 하단 독 표시)
- `apps/boardest/boardest_ppt_overlay.cs` Lines 49~53:
  ```csharp
  public int RetryRejectedCall(IntPtr hTaskCallee, int dwTickCount, int dwRejectType)
  {
      if (dwRejectType == 2) return 150;
      return -1;
  }
  ```
  `dwRejectType == 1` (`SERVERCALL_REJECTED`) 발생 시 `-1`을 반환하여 COM이 `0x80010001 (RPC_E_CALL_REJECTED)` 오류를 즉시 발생시킴.
- `apps/boardest/boardest_ppt_overlay.cs` Lines 208~248:
  ```csharp
  _mainGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
  _mainGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
  ...
  _mainGrid.Children.Add(_inkCanvas); // Row 0에만 배치됨
  Grid.SetRow(toolBorder, 1);
  ```
  `toolBorder`가 Row 1에 배치되어 있고 `_inkCanvas`에 RowSpan이 설정되지 않아, 화면 하단 80~100px 영역에 판서가 마스킹되어 그려지지 않음.

### 3) Class 자동 업데이트 (.msix 매칭) 및 Teacher 언인스톨러/시작 메뉴 등록
- `apps/boardest/lib/services/update_service.dart` Lines 260~267:
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
  GitHub Release 에셋 순서에 따라 `.appx`가 먼저 오면 `appxDownloadUrl`에 `.appx`가 바인딩됨.
  Line 324: `final ext = isWindows ? 'msix' : 'apk';` 로 무조건 `.msix`로 저장되어 확장자 불일치 발생.
- `tools/installer/BoardestTeacherInstaller.cs` Lines 1660~1687:
  `BoardestInstaller.cs`에 적용된 시작 메뉴 루트(`CommonPrograms`, `Programs`) 바로가기 생성 및 `SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero)` 호출이 누락되어 있음.
- `tools/installer/BoardestTeacherUninstaller.cs` Lines 208~216:
  `...\Programs\Boardest` 하위 폴더만 삭제하고 시작 메뉴 루트의 `Boardest Teacher.lnk`는 삭제하지 않음. 버전도 `"5.3.7"`로 구버전 고정됨.

---

## 2. Logic Chain

1. **수행평가 동기화**:
   - `bst_class_main_layout.dart:427` -> 30초마다 폴링 -> 실시간성 결여 확인.
   - `assessment_service.dart:46` -> `_eatCallsUrl` 4초 타임아웃 또는 미등록 시 빈 맵 반환 -> `teacher_assessment_view.dart:884`에서 1~12반이 모두 미설치로 판정되어 `onSelected: null` -> `teacher_assessment_view.dart:1050`에서 빈 선택으로 등록 불가 확인.
2. **PPT 오버레이**:
   - `boardest_ppt_overlay.cs:49` -> `dwRejectType == 1`일 때 `-1` 리턴 -> COM `RPC_E_CALL_REJECTED` 유발 -> `PollTimer_Tick:1308`에서 Standalone 모드로 즉시 격하되어 슬라이드 연동 중단 확인.
   - `boardest_ppt_overlay.cs:208` -> Grid 분할로 인해 `_inkCanvas`가 Row 0에 갇히고 Row 1(하단 툴바) 영역에 판서 불가 확인.
3. **Class 자동 업데이트 & Teacher 시작메뉴**:
   - `update_service.dart:265` -> `(name.endsWith('.msix') || name.endsWith('.appx'))`에서 `??=` 연산자로 인해 에셋 순서에 따라 `.appx`가 선택될 수 있음 -> Line 324에서 파일명을 `.msix`로 강제 저장하여 패키지 무결성 결함 가능성 확인.
   - `BoardestTeacherInstaller.cs:1660` 및 `BoardestTeacherUninstaller.cs:208` -> 루트 바로가기 및 `SHChangeNotify` 동기화 누락 확인.

---

## 3. Caveats

1. Firebase RTDB는 본 리포지토리의 설정 파일(`database.rules.json`) 및 소스 코드 기준으로 조사되었으며, 실 서버의 활성 세션 상태는 런타임 네트워크 연결에 따라 달라집니다.
2. PowerPoint COM 연동은 Windows OS 환경에서 Microsoft PowerPoint 정품이 설치되어 있는 환경을 전제로 합니다.
3. Windows 11 시작 메뉴의 경우 `SHChangeNotify` 호출 후 셸 캐시가 갱신되는 데 약 0.5~1초의 지연이 발생할 수 있습니다.

---

## 4. Conclusion

1. **수행평가**:
   - 감지 실패 시에도 1~12반 전체를 선택 가능하도록 폴백(Fallback) 안전장치를 즉시 추가해야 합니다.
   - RTDB SSE 스트림 리스너를 도입하여 교사-교실 간 0.1초 실시간 동기화를 달성해야 합니다.
2. **PPT 오버레이**:
   - `OleMessageFilter.RetryRejectedCall`에서 `dwRejectType` 1과 2 모두 10초간 자동 재시도하도록 수정해야 합니다.
   - `_inkCanvas`가 화면 전체(100%)를 덮고, 툴바가 캔버스 상단에 플로팅되는 레이아웃으로 변경해야 합니다.
3. **업데이트 & 인스톨러**:
   - `UpdateService`에서 `boardest-class.msix` 및 `.msix` 확장자를 최우선으로 매칭하고 파일 확장자를 동적으로 일치시켜야 합니다.
   - `BoardestTeacherInstaller.cs` 및 `BoardestTeacherUninstaller.cs`를 `BoardestInstaller.cs`의 시작 메뉴 루트 등록 및 `SHChangeNotify` 로직과 완전 동기화해야 합니다.

---

## 5. Verification Method

1. **코드 및 정적 분석 검증**:
   - `apps/boardest_teacher/lib/services/assessment_service.dart`의 `fetchInstalledClasses`와 `teacher_assessment_view.dart`의 칩 렌더링 로직 확인.
   - `apps/boardest/boardest_ppt_overlay.cs`의 `RetryRejectedCall` 및 `InitUI` Grid/InkCanvas 레이아웃 검사.
   - `apps/boardest/lib/services/update_service.dart`의 `appxDownloadUrl` 추출 루프 검사.
2. **빌드 검증**:
   - PowerShell: `pwsh apps/boardest/build_all.ps1` 또는 `flutter analyze` 명령 실행.
   - C# 컴파일: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`를 통한 `boardest_ppt_overlay.cs` 빌드 확인.
