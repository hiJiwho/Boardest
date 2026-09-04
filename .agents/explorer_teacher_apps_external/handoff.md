# Handoff Report: Teacher Apps & External Integrations Investigation

**Date**: 2026-08-21  
**Agent**: explorer_teacher_apps_external  
**Handoff Type**: Hard (Task Complete)

---

## 1. Observation

### 1.1 OTP 알고리즘 불일치 (Critical Defect)
- **파일 1**: `apps/boardest_teacher/lib/views/teacher_view.dart` (라인 249-266)
  ```dart
  final secret = _settings.selectedTeacher.isNotEmpty ? _settings.selectedTeacher : 'boardest_teacher_secret';
  final epoch = DateTime.now().millisecondsSinceEpoch ~/ 60000;
  final key = utf8.encode(secret);
  final bytes = utf8.encode(epoch.toString());
  final hmacSha256 = Hmac(sha256, key);
  final digest = hmacSha256.convert(bytes);
  ```
- **파일 2**: `apps/boardest_teacher_lite/lib/main.dart` (라인 253-268)
  ```dart
  final secret = _googleEmail.isNotEmpty ? _googleEmail : 'boardest_teacher_lite_secret';
  final epoch = DateTime.now().millisecondsSinceEpoch ~/ 60000;
  final key = utf8.encode(secret);
  final bytes = utf8.encode(epoch.toString());
  final hmacSha256 = Hmac(sha256, key);
  ```
- **파일 3**: `apps/boardest/lib/services/totp_service.dart` (라인 56-74) & `bst_cloud_service.dart` (라인 690)
  ```dart
  // 전자칠판은 Base32 시크릿 키와 RFC 6238 HMAC-SHA1 카운터 방식으로 검증:
  final key = _base32Decode(secret);
  final hmac = Hmac(sha1, key);
  ```
  - **관찰 결과**: 전자칠판의 검증 알고리즘(RFC 6238 Base32 HMAC-SHA1)과 교사용 앱/Lite의 생성 알고리즘(문자열 HMAC-SHA256)이 완전히 달라 연동 시 무조건 불일치 에러가 발생함.

### 1.2 Universal IO 가드 누락 및 Web 런타임 크래시
- **파일 1**: `apps/boardest_teacher/lib/services/storage_service.dart`
  - 라인 196: `final exeDir = File(Platform.resolvedExecutable).parent.path;` (`saveSyncConfigs` 내부)
  - 라인 205: `final exeDir = File(Platform.resolvedExecutable).parent.path;` (`getSyncConfigs` 내부)
  - `!kIsWeb` 가드 없이 `Platform.resolvedExecutable`에 접근하여 Web에서 `UnsupportedError: Platform._operatingSystem` 발생.
- **파일 2**: `apps/boardest_teacher/lib/views/meal_view.dart`
  - 라인 109: `_reloadWebview()` 내 `if (Platform.isWindows)` (`kIsWeb` 검사 누락)
  - 라인 247, 306: `_buildUpdateRequiredWidget()` 내 `Platform.isWindows` 삼항 연산자 (`kIsWeb` 검사 누락)
- **파일 3**: `apps/boardest_teacher/lib/views/browser_board_view.dart`
  - 라인 40: `initState()` 내 `if (Platform.isWindows)` (`kIsWeb` 검사 누락으로 Web 진입 즉시 크래시)
- **파일 4**: `apps/boardest_teacher/lib/views/web_hwp_ppt_view.dart`
  - 라인 45: `_initWebview()` 내 `if (Platform.isWindows)` (`kIsWeb` 검사 누락)
- **파일 5**: `apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart`
  - 라인 97, 109, 319, 372: `Platform.isWindows`에 `kIsWeb` 검사 누락.

### 1.3 Teacher Lite 데이터 영속화 및 더미 데이터 바인딩 결함
- **파일**: `apps/boardest_teacher_lite/lib/main.dart`
  - 라인 124-154: `_initFromUrlAndStorage()`에서 URL 쿼리 파라미터(`email`, `token`, `teacherName`, `schoolId`)를 수신했을 때 `prefs.setString` 저장이 누락되어 새로고침 시 초기화됨.
  - 라인 126-127: `query['schoolCode']`가 없을 때 `query['schoolId']`로의 폴백이 없어 `_schoolCode`가 기본값 `'48588'`로 고정됨.
  - 라인 277-285, 644-648: 컴시간 Worker를 호출하지만 응답을 저장하지 않고 `_getDefaultSubject()` 더미 배열을 렌더링함.
  - 라인 291: NEIS 급식 호출 URL에 양동중학교 코드 `ATPT_OFCDC_SC_CODE=B10&SD_SCHUL_CODE=7010260`가 하드코딩됨.

### 1.4 `packages/common/bst_timetable` 불완전 및 미사용
- **파일**: `packages/common/bst_timetable/lib/src/services/comcigan_service.dart` (라인 55)
  - `fetchTimetableRaw`에서 `if (kIsWeb) { ... } throw Exception('Unsupported platform');`로 비-Web 플랫폼 지원 차단.
  - 반면 `apps/boardest_teacher/lib/services/comcigan_service.dart`에는 665줄 분량의 완전한 컴시간 TCP/HTTP 파서, CP949 디코더, 교사 약칭 매칭 로직이 별도 중복 구현되어 있음.

### 1.5 깨진 테스트 스위트
- `apps/boardest_teacher_lite/test/widget_test.dart`: 미정의된 `MyApp` 인스턴스화로 컴파일 에러.
- `packages/common/bst_timetable/test/bst_timetable_test.dart`: 미정의된 `Calculator` 참조로 컴파일 에러.
- `packages/common/bst_messaging/test/bst_messaging_test.dart`: 미정의된 `Calculator` 참조로 컴파일 에러.
- `packages/common/bst_auth/test/bst_auth_test.dart`: 미정의된 `Calculator` 참조로 컴파일 에러.

---

## 2. Logic Chain

1. **OTP 인증 실패 메커니즘**:
   - [Observation 1.1]에서 전자칠판(`boardest`)은 `TotpService.verifyOtp`를 사용하여 Firestore의 `teacher_cloud_tokens.totpSecret`(Base32)을 HMAC-SHA1 8바이트 카운터로 검증함.
   - [Observation 1.1]에서 `TeacherView`와 `Teacher Lite`는 임의의 문자열과 `epoch.toString()`을 HMAC-SHA256으로 해싱하여 화면에 표시함.
   - ➔ 결과적으로 교사가 앱 화면의 OTP를 전자칠판에 입력하면 해시 알고리즘 불일치로 인해 100% 검증에 실패함.
   - ➔ `TotpService.generateCurrentOtp(secret)`로 통일해야 함.

2. **Web 플랫폼 크래시 메커니즘**:
   - [Observation 1.2]에서 Web 플랫폼 빌드 시 `Platform.isWindows`나 `Platform.resolvedExecutable`에 접근하면 `UnsupportedError` 예외가 발생함.
   - 여러 뷰(`browser_board_view`, `meal_view`, `storage_service`)에서 `!kIsWeb` 가드 없이 해당 프로퍼티에 접근함.
   - ➔ Web 브라우저에서 보드 뷰나 동기화 설정 로드 시 앱이 비정상 종료됨.
   - ➔ 모든 `Platform` 접근부를 `if (!kIsWeb && Platform.isWindows)` 또는 `if (kIsWeb || !Platform.isWindows) return;`으로 수정해야 함.

3. **Lite 앱 데이터 유실 및 더미 출력 메커니즘**:
   - [Observation 1.3]에서 `_initFromUrlAndStorage()`가 URL 파라미터를 메모리 변수에만 대입하고 `SharedPreferences` 저장을 누락함.
   - 또한 컴시간 Worker 응답 파싱 상태가 누락되어 `_getDefaultSubject` 더미 교과목이 고정 출력되고, 급식 API도 특정 학교 코드로 고정됨.
   - ➔ 모바일 웹 사용자가 로그인 상태를 유지하지 못하고 실제 시간표/급식을 조회할 수 없음.
   - ➔ SharedPreferences 저장 로직 추가 및 컴시간 파서 바인딩, 동적 학교 코드 전달이 필요함.

4. **패키지 아키텍처 및 테스트 실패 메커니즘**:
   - [Observation 1.4, 1.5]에서 공통 패키지 `bst_timetable`의 미완성 상태로 인해 앱 레벨 중복 코드가 발생하고, 기본 템플릿 테스트 파일들이 방치되어 전체 CI/테스트 파이프라인 빌드가 실패함.
   - ➔ 패키지 코드 승격 및 올바른 테스트 작성 필요.

---

## 3. Caveats

- **Network Worker 의존성**: 컴시간 시간표 Cloudflare Worker(`https://comcigan.jiwho.workers.dev`)는 외부 엣지 서버이므로, 네트워크 단절 시 오프라인 캐시(로컬 저장된 마지막 시간표 데이터)로 폴백하는 로직의 신뢰성 검증이 추가로 필요합니다.
- **NEIS API 호출 한도**: NEIS Open API 일일 호출량 제한을 고려하여 학교 코드 및 급식 데이터의 인메모리 캐싱 유효기간(TTL) 정책을 점검해야 합니다.

---

## 4. Conclusion

- `boardest_teacher`와 `boardest_teacher_lite`는 풍부한 기능(18개 수업 도구, 플로팅 타이머/계산기/추첨기, 급식 지도, 학급 쪽지, 컴시간/NEIS 연동)을 갖추고 있으나, **(1) OTP 알고리즘 불일치**, **(2) Web 환경 IO 가드 누락**, **(3) Lite 앱 세션 영속화 및 더미 데이터 출력**, **(4) 테스트 스위트 컴파일 오류**로 인해 즉각적인 수정이 필요합니다.
- 세부적인 원인 규명 및 수정 지침은 `.agents/explorer_teacher_apps_external/analysis.md`에 상세히 명시되었습니다.

---

## 5. Verification Method

### 5.1 테스트 검증 명령어
```powershell
# 1. 패키지 단위 테스트 검증
cd packages/common/bst_timetable; flutter test
cd ../bst_messaging; flutter test
cd ../bst_auth; flutter test

# 2. 교사용 앱 단위 테스트 검증
cd ../../../apps/boardest_teacher; flutter test
cd ../boardest_teacher_lite; flutter test

# 3. 정적 분석 경고 검증
flutter analyze
```

### 5.2 검사 대상 파일 목록
- `apps/boardest_teacher/lib/views/teacher_view.dart`
- `apps/boardest_teacher/lib/services/storage_service.dart`
- `apps/boardest_teacher/lib/views/meal_view.dart`
- `apps/boardest_teacher/lib/views/browser_board_view.dart`
- `apps/boardest_teacher/lib/views/web_hwp_ppt_view.dart`
- `apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart`
- `apps/boardest_teacher_lite/lib/main.dart`
- `packages/common/bst_timetable/lib/src/services/comcigan_service.dart`

### 5.3 무효화 조건 (Invalidation Conditions)
- 전자칠판(`boardest`)의 `TotpService.verifyOtp`가 통과되지 않고 OTP 불일치 오류가 지속되는 경우.
- Flutter Web 환경(`flutter run -d chrome`)에서 보드 도구(브라우저, 급식, 뷰어) 실행 시 `Platform._operatingSystem` 콘솔 에러가 발생하는 경우.
- Teacher Lite 새로고침 시 로그인 프로필이 초기화되는 경우.
