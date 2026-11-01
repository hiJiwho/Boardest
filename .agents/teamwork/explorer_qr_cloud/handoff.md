# Handoff Report: Requirement 1 — Class 앱 QR Cloud 접속 실패 문제 해결 분석

- **Agent**: `explorer_qr_cloud` (Teamwork Explorer)
- **Target**: Orchestrator (`2ce30758-d6dd-41a8-b112-4ee17b3271df`) & Implementer
- **Mission**: Investigate Requirement 1: Class 앱 QR Cloud 접속 실패 문제 해결 (QR 대상 URL 및 라우팅 파라미터, Cloud 웹/앱 리디렉션 정합성 검증)
- **Status**: Completed

---

## 1. Observation (직접 관찰된 코드 증거 및 검증 결과)

### 1.1 Firebase Realtime Database (RTDB) 보안 규칙 누락 및 라이브 401 오류 검증
- **File**: `c:\Users\jiwho\Documents\boardest\database.rules.json` (Lines 1-68)
  - 규칙 파일 내 허용된 노드 목록: `eat_calls`, `demo_active_devices`, `meal_votes`, `passkey`, `passkey_pairs`, `passkey_vaults`, `assessments`, `school_notices`.
  - `cloud_pair_sessions` 노드가 **전혀 선언되어 있지 않음**.
- **라이브 검증 명령 및 결과**:
  - 실행 명령:
    ```powershell
    Invoke-RestMethod -Uri 'https://jiwhosboardest-default-rtdb.firebaseio.com/cloud_pair_sessions/test.json' -Method Get
    ```
  - 결과 출력:
    ```json
    Invoke-RestMethod : {
      "error" : "Permission denied"
    }
    ```
  - 동일한 엔드포인트에서 선언된 `passkey/sessions/test.json`은 정상적으로 `200 OK` (`null`)을 반환하는 반면, `cloud_pair_sessions`는 즉시 **`HTTP 401 Permission denied`** 로 거부됨을 100% 실시간 확인.

### 1.2 Class 앱 내 QR 코드 생성 및 페어링 대기 로직
- **File A**: `c:\Users\jiwho\Documents\boardest\apps\boardest\lib\services\bst_cloud_service.dart`
  - Line 1754:
    ```dart
    final qrUrl = 'https://boardest-cloud-connect.web.app/?bst_pair=${Uri.encodeComponent(mangled)}';
    ```
  - Lines 1757-1774:
    ```dart
    const rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com';
    final rtdbUrl = '$rtdbBase/cloud_pair_sessions/$secret.json';
    await http.put(
      Uri.parse(rtdbUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'pending',
        'secret': secret,
        'mangled': mangled,
        ...
      }),
    ).timeout(const Duration(seconds: 4));
    ```
  - Lines 1801-1808:
    ```dart
    final rtdbUrl = '$rtdbBase/cloud_pair_sessions/$secret.json';
    final res = await http.get(Uri.parse(rtdbUrl)).timeout(const Duration(seconds: 3));
    if (res.statusCode == 200 && res.body != 'null' && res.body.isNotEmpty) {
      final data = jsonDecode(res.body);
      if (data is Map) {
        final status = data['status']?.toString() ?? '';
        if (status == 'authenticated') { ... }
    ```
  - **관찰**:
    1. `createReversePairSession` 시 RTDB `cloud_pair_sessions/$secret.json`에 `PUT` 시도 시 상기 1.1의 "Permission denied"로 인해 세션 생성이 차단됨.
    2. `waitForReversePairAuth`가 RTDB만 단독 폴링하며, Firestore `cloud_pair_sessions`에 대한 Fallback이 전혀 없음.

- **File B**: `c:\Users\jiwho\Documents\boardest\apps\boardest\lib\services\passkey_service.dart`
  - Lines 73-77:
    ```dart
    var qrPayload = 'https://boardest-cloud-connect.web.app/?key=$sessionId&c=$challenge&school=${Uri.encodeComponent(schoolName)}&device=${Uri.encodeComponent(roomName)}&t=$now';
    if (schoolId != null && schoolId.isNotEmpty) {
      qrPayload += '&schoolId=${Uri.encodeComponent(schoolId)}';
    }
    ```
  - Lines 182-191 (`listenForApproval`):
    ```dart
    yield (
      approved: true,
      accessToken: accessToken,
      refreshToken: data['refreshToken'] as String?,
      teacherName: (data['teacherName'] ?? data['teacher']) as String?,
      email: data['email'] as String?,
      schoolId: teacherSchoolId.isNotEmpty ? teacherSchoolId : null,
      schoolName: approvedSchoolName.isNotEmpty ? approvedSchoolName : null,
      errorMessage: null,
    );
    ```

### 1.3 `boardest-teacher-oauth` SPA 라우팅 및 RTDB 누락
- **File**: `c:\Users\jiwho\Documents\boardest\apps\boardest_teacher_oauth\index.html`
  - Lines 880-889 (`detectRouteState`):
    ```javascript
    const bstPairParam = params.get('bst_pair') || params.get('pair');
    if (bstPairParam) {
      const decoded = unmanglePairSecret(bstPairParam);
      if (decoded) {
        pairSecret = decoded;
        sessionStorage.setItem('boardest_pair_secret', decoded);
      }
    } else {
      pairSecret = sessionStorage.getItem('boardest_pair_secret') || null;
    }
    ```
    - **관찰**: 스마트폰에서 `boardest-cloud-connect.web.app`의 로그인 유도 링크(`?return_url=https://boardest-cloud-connect.web.app/?bst_pair=...`)를 타고 들어올 경우, `bst_pair`가 `return_url` 내부에 인코딩되어 있으므로 최상위 `params.get('bst_pair')`는 `null`이 됨. `return_url` 내부의 파라미터를 파싱하는 로직이 없음.
  - Lines 2456-2515 (`completeReversePairing`):
    ```javascript
    await db.collection('cloud_pair_sessions').doc(secret).set(payload, { merge: true });
    ```
    - **관찰**: 교사가 Google 로그인을 성공적으로 마쳐도 **Firestore `cloud_pair_sessions`에만 쓰기를 수행**하고, **RTDB `cloud_pair_sessions/${secret}.json`에는 일체 쓰기를 하지 않음**. Class 앱은 RTDB만 폴링하고 있으므로 인증 완료 신호를 영원히 수신하지 못함.
  - Lines 1682-1686 (`initApp` 로그인 완료 후 리디렉션 처리):
    ```javascript
    const hasReturnUrl = Boolean(sessionStorage.getItem('boardest_return_url'));
    if (targetMode !== 'edit' && !window.location.pathname.startsWith('/edit') && (clientTarget === 'win' || clientTarget === 'web' || clientTarget === 'web-lite' || window.location.search.includes('win'))) {
      setTimeout(() => proceedToClient(), 500);
    }
    ```
    - **관찰**: `hasReturnUrl` 변수를 선언만 해두고 `if` 조건문에서 누락함. `clientTarget`이 `'none'`(cloud-connect에서 유입 시)이면 자동 리디렉션이 차단되어 프로필 관리 화면에 멈춰버림.

### 1.4 `firebase.json` 내 `boardest-teacher-oauth` rewrites 누락
- **File**: `c:\Users\jiwho\Documents\boardest\firebase.json` (Lines 862-879)
  ```json
  {
    "target": "boardest-teacher-oauth",
    "public": "apps/boardest_teacher_oauth",
    "ignore": [ ... ],
    "cleanUrls": true
  }
  ```
  - **File**: `c:\Users\jiwho\Documents\boardest\apps\boardest_teacher_oauth\404.html` (Lines 6-8):
    ```javascript
    window.location.href = "/";
    ```
  - **관찰**: `firebase.json`의 다른 모든 SPA 타깃(11개)과 달리 `boardest-teacher-oauth` 타깃에만 `"rewrites": [{"source": "**", "destination": "/index.html"}]`가 누락됨. 교사용 앱이나 Lite에서 `https://boardest-teacher-oauth.web.app/edit?...` 또는 `/demo`로 접근 시 Firebase가 404로 응답하여 `404.html`이 실행되고, `404.html`의 스크립트가 쿼리 파라미터를 모두 증발시키며 `/`로 리디렉션해 버림.

### 1.5 `infra/cloud_connect_web/index.html` 파라미터 및 승인 페이로드 불일치
- **File**: `c:\Users\jiwho\Documents\boardest\infra\cloud_connect_web\index.html`
  - Lines 199-204:
    ```javascript
    const teacherName = params.get('teacher') || savedTeacherName || '선생님';
    let incomingToken = params.get('token') || savedToken || '';
    ```
    - **관찰**: `boardest-teacher-oauth`는 리디렉션 시 `teacherName`, `accessToken`, `refreshToken`, `email`, `folderId`, `totpSecret`을 전달하나, `cloud_connect_web`은 `params.get('teacher')`만 찾고 있어 `teacherName`이 `'선생님'`으로 누락됨. `email`, `refreshToken`, `folderId`는 URL 파라미터에서 아예 읽지 않음.
  - Lines 485-487 (Passkey 모드 토큰 미존재 시):
    ```javascript
    if (!tokenToSend) {
      throw new Error("등록된 교사 인증 토큰이 없습니다. 먼저 교사용 앱의 [패스키 등록] QR을 이 스마트폰으로 1회 스캔해주세요.");
    }
    ```
    - **관찰**: Passkey QR 스캔 시 폰에 토큰이 없으면 즉시 에러만 띄우고 OAuth 로그인 링크를 제공하지 않아 사용자가 진행할 수 없음 (역방향 페어링 모드는 line 583에 로그인 링크가 제공되는 것과 대조적).
  - Lines 492-500 (Passkey 승인 시 RTDB 전달 페이로드):
    ```javascript
    const payload = {
      status: "approved",
      teacher: teacherName,
      teacherName: teacherName,
      accessToken: tokenToSend,
      token: tokenToSend,
      proof: proof,
      timestamp: Date.now()
    };
    ```
    - **관찰**: `refreshToken`, `email`, `schoolId`, `schoolName`을 페이로드에 포함하지 않아 Class 앱 수신부(`PasskeyService.listenForApproval`)에서 `refreshToken`과 `email`이 `null`로 처리되어 이후 1시간 만료 시 토큰 갱신이 불가능해짐.

### 1.6 `apps/boardest_teacher_lite` 내 잘못된 도메인 URL 호출
- **File**: `c:\Users\jiwho\Documents\boardest\apps\boardest_teacher_lite\lib\main.dart`
  - Line 3010:
    ```dart
    onPressed: () => launchUrl(Uri.parse('https://boardest-cloud-connect.web.app/edit?web-lite&return_url=https://boardest-teacher.web.app/lite/'), webOnlyWindowName: '_self'),
    ```
  - **관찰**: 프로필 수정 마법사가 존재하는 곳은 `boardest-teacher-oauth.web.app/edit`인데, `boardest-cloud-connect.web.app/edit`으로 잘못 링크되어 있음.

---

## 2. Logic Chain (추론 단계)

1. **[인과관계 1: RTDB 보안 규칙 차단]**
   - Class 앱(`BstCloudService`)은 QR 생성 시 `PUT https://jiwhosboardest-default-rtdb.firebaseio.com/cloud_pair_sessions/$secret.json`을 호출하고, 대기 시 동일 URL로 `GET` 폴링을 수행함 (Observation 1.2).
   - 그러나 `database.rules.json`에 `cloud_pair_sessions`가 미선언되어 있어 모든 REST 호출이 401 Permission Denied로 거부됨 (Observation 1.1에서 실측 확인).
   - 따라서 Class 앱은 세션을 RTDB에 생성하지 못하고, 상태 변경도 읽어오지 못해 5분 타임아웃 오류를 발생시킴.

2. **[인과관계 2: 데이터베이스 채널 단절 (Firestore vs RTDB)]**
   - 교사가 스마트폰으로 `boardest-teacher-oauth`에서 Google 로그인을 마치면 `completeReversePairing`이 실행됨.
   - 그러나 이 함수는 Firestore `cloud_pair_sessions` 컬렉션에만 승인 데이터를 기록하고, RTDB에는 기록하지 않음 (Observation 1.3).
   - Class 앱은 Firestore를 보지 않고 RTDB만 폴링하므로, 교사가 웹에서 승인해도 칠판은 영원히 대기 상태에 머무름.

3. **[인과관계 3: 리디렉션 파라미터 파실 및 자동 복귀 실패]**
   - `cloud_connect_web`에서 로그인이 필요하여 `boardest-teacher-oauth`로 이동할 때 `return_url` 내부에 `bst_pair`가 인코딩되어 전달됨.
   - `boardest-teacher-oauth`가 `return_url` 내부의 `bst_pair`를 추출하지 못해 `pairSecret`이 null이 되고 (Observation 1.3), `hasReturnUrl` 조건문 누락으로 자동 복귀도 수행되지 않음.
   - 복귀하더라도 파라미터 키 이름 불일치(`teacher` vs `teacherName`) 및 `refreshToken`/`email` 파싱 누락으로 불완전한 세션이 생성됨 (Observation 1.5).

4. **[인과관계 4: Hosting SPA Rewrite 부재로 인한 404 파라미터 증발]**
   - `firebase.json`에서 `boardest-teacher-oauth`의 rewrite 규칙이 누락되어, `/edit` 경로 접근 시 `404.html`로 폴백됨 (Observation 1.4).
   - `404.html`은 `window.location.href = "/"`로 강제 이동시켜 모든 쿼리 파라미터를 소실시킴.

---

## 3. Caveats (제약 및 고려사항)

1. **Zero-Persistence 원칙 준수**:
   - 상위 오케스트레이터 및 사용자 합의 지침에 따라 스마트폰 및 `cloud-connect` 웹 로컬 스토리지에 영구 토큰을 저장하지 않고, 1회성 핸드셰이크 토큰만 RTDB/Firestore를 거쳐 전자칠판 RAM으로 안전하게 전달하고 즉시 폐기해야 합니다.
2. **이중 채널(Dual-Channel) 안정성**:
   - 네트워크 방화벽 환경에 따라 특정 학교망에서 Firebase RTDB(Websocket/REST) 또는 Firestore가 차단될 수 있으므로, Class 앱의 `waitForReversePairAuth`는 RTDB 1차 조회 후 Firestore 2차 Fallback 조회를 병행하는 것이 가장 안전합니다.
3. **CORS 및 캐시 방지**:
   - `firebase.json`의 `boardest-teacher-oauth` 타깃에 `Cache-Control: no-cache, no-store, must-revalidate` 및 `Access-Control-Allow-Origin: *` 헤더를 반드시 설정해야 브라우저 구버전 캐싱 문제를 방지할 수 있습니다.

---

## 4. Conclusion (결론 및 세부 수정 계획)

QR Cloud 접속 실패의 근본 원인은 **1) RTDB `cloud_pair_sessions` 보안 규칙 누락 (401 Permission Denied)**, **2) `boardest-teacher-oauth`의 RTDB 업데이트 누락 및 리디렉션 정합성 결여**, **3) `firebase.json` 내 OAuth 타깃 rewrite 누락**, **4) `cloud_connect_web`의 파라미터 파싱 및 Passkey 모드 로그인 링크 누락**으로 확정되었습니다.

### 구체적 수정 대상 파일 및 변경 사항 (File-by-File Fix Plan)

#### 1) `database.rules.json`
- **위치**: `c:\Users\jiwho\Documents\boardest\database.rules.json` (line 46 부근)
- **변경 내용**: `cloud_pair_sessions` 노드 추가
```json
    "cloud_pair_sessions": {
      "$session_id": {
        ".read": true,
        ".write": true
      }
    },
```

#### 2) `apps/boardest_teacher_oauth/index.html`
- **위치**: `c:\Users\jiwho\Documents\boardest\apps\boardest_teacher_oauth\index.html`
- **변경 내용 A (Lines 880-889)**: `return_url` 내부에 포함된 `bst_pair` 자동 추출 지원
```javascript
      let bstPairParam = params.get('bst_pair') || params.get('pair');
      if (!bstPairParam && rawReturn) {
        try {
          const retUrl = new URL(rawReturn, window.location.origin);
          bstPairParam = retUrl.searchParams.get('bst_pair') || retUrl.searchParams.get('pair');
        } catch (_) {}
      }
```
- **변경 내용 B (Lines 1682-1686)**: `hasReturnUrl` 존재 시 `proceedToClient()` 자동 호출 활성화
```javascript
      const hasReturnUrl = Boolean(sessionStorage.getItem('boardest_return_url'));
      if (targetMode !== 'edit' && !window.location.pathname.startsWith('/edit') && (hasReturnUrl || clientTarget === 'win' || clientTarget === 'web' || clientTarget === 'web-lite' || window.location.search.includes('win'))) {
        setTimeout(() => proceedToClient(), 500);
      }
```
- **변경 내용 C (Lines 2480-2515)**: `completeReversePairing` 내 RTDB `cloud_pair_sessions/${secret}.json` 즉시 동시 기록
```javascript
      // RTDB에 즉시 1회성 인증 완료 기록 (전자칠판 즉시 수신)
      const rtdbPayload = {
        status: 'authenticated',
        teacherName: profileData.teacherName || user.displayName || '선생님',
        email: user.email || '',
        accessToken: token,
        refreshToken: refreshToken,
        folderId: bstCloudFolderId,
        bstCloudFolderId: bstCloudFolderId,
        totpSecret: totpSecret,
        authenticatedAt: Date.now()
      };
      await fetch(`https://jiwhosboardest-default-rtdb.firebaseio.com/cloud_pair_sessions/${secret}.json`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(rtdbPayload)
      }).catch(err => console.warn('RTDB pair session write error:', err));
```

#### 3) `firebase.json`
- **위치**: `c:\Users\jiwho\Documents\boardest\firebase.json` (Lines 862-879)
- **변경 내용**: `boardest-teacher-oauth` 타깃에 `headers` 및 `rewrites` 추가
```json
    {
      "target": "boardest-teacher-oauth",
      "public": "apps/boardest_teacher_oauth",
      "ignore": [
        "firebase.json",
        "**/.*",
        "**/node_modules/**",
        "**/*.apk",
        "**/*.exe",
        "**/*.msi",
        "**/*.appx",
        "**/*.msix",
        "**/*.bat",
        "**/*.cmd"
      ],
      "headers": [
        {
          "source": "**",
          "headers": [
            {
              "key": "Cache-Control",
              "value": "no-cache, no-store, must-revalidate, max-age=0"
            },
            {
              "key": "Access-Control-Allow-Origin",
              "value": "*"
            }
          ]
        }
      ],
      "cleanUrls": true,
      "rewrites": [
        {
          "source": "**",
          "destination": "/index.html"
        }
      ]
    },
```

#### 4) `infra/cloud_connect_web/index.html`
- **위치**: `c:\Users\jiwho\Documents\boardest\infra\cloud_connect_web\index.html`
- **변경 내용 A**: 스크립트 시작부에 `/edit` 경로 리디렉션 가드 추가
```javascript
    if (window.location.pathname.startsWith('/edit')) {
      window.location.replace(`https://boardest-teacher-oauth.web.app/edit${window.location.search}`);
      return;
    }
```
- **변경 내용 B (Lines 199-204)**: 파라미터 파싱 보강 (`teacherName`, `accessToken`, `email`, `refreshToken` 등 수용)
```javascript
    const teacherName = params.get('teacherName') || params.get('teacher') || savedTeacherName || '선생님';
    let incomingToken = params.get('token') || params.get('accessToken') || savedToken || '';
    const incomingEmail = params.get('email') || '';
    const incomingRefreshToken = params.get('refreshToken') || '';
    const incomingFolderId = params.get('folderId') || params.get('bstCloudFolderId') || '';
    const incomingTotpSecret = params.get('totpSecret') || params.get('totp') || '';
```
- **변경 내용 C (Line 486 부근)**: Passkey 모드에서 토큰 부재 시 OAuth 로그인 링크 제공
```javascript
    if (!tokenToSend) {
      status.innerHTML = `등록된 교사 토큰이 없습니다.<br><a href="https://boardest-teacher-oauth.web.app?return_url=${encodeURIComponent(window.location.href)}" class="btn btn-purple" style="margin-top:12px;padding:12px 18px;text-decoration:none;display:inline-block;">🔑 교사 계정 1초 로그인 후 전자칠판 승인</a>`;
      btn.disabled = false;
      return;
    }
```
- **변경 내용 D (Lines 492-500)**: Passkey RTDB 승인 페이로드에 `refreshToken`, `email` 등 필수 필드 포함
```javascript
    const payload = {
      status: "approved",
      teacher: teacherName,
      teacherName: teacherName,
      accessToken: tokenToSend,
      token: tokenToSend,
      refreshToken: incomingRefreshToken || '',
      email: incomingEmail || '',
      schoolId: params.get('schoolId') || '',
      schoolName: school || '',
      proof: proof,
      timestamp: Date.now()
    };
```

#### 5) `apps/boardest/lib/services/bst_cloud_service.dart`
- **위치**: `c:\Users\jiwho\Documents\boardest\apps\boardest\lib\services\bst_cloud_service.dart` (Lines 1800-1845)
- **변경 내용**: `waitForReversePairAuth`에 Firestore Fallback 폴링 추가 (RTDB 1차 + Firestore 2차)
```dart
        // RTDB 1차 확인 후, 없으면 Firestore 2차 Fallback 확인
        if (status != 'authenticated') {
          final fsUrl = '$_firestoreBase/cloud_pair_sessions/$secret?key=$_apiKey';
          final fsRes = await http.get(Uri.parse(fsUrl)).timeout(const Duration(seconds: 3));
          if (fsRes.statusCode == 200) {
            final fsData = jsonDecode(fsRes.body);
            final fsFields = fsData['fields'] as Map<String, dynamic>?;
            final fsStatus = (fsFields?['status'] as Map?)?['stringValue'] as String? ?? '';
            if (fsStatus == 'authenticated') {
              final token = (fsFields?['accessToken'] as Map?)?['stringValue'] as String?;
              final refreshTok = (fsFields?['refreshToken'] as Map?)?['stringValue'] as String?;
              final tName = (fsFields?['teacherName'] as Map?)?['stringValue'] as String? ?? '선생님';
              final ownerEmail = (fsFields?['email'] as Map?)?['stringValue'] as String? ?? '';
              final totpSec = (fsFields?['totpSecret'] as Map?)?['stringValue'] as String?;
              final folderId = (fsFields?['folderId'] as Map?)?['stringValue'] as String? ?? '';
              final bstCloudFolderId = (fsFields?['bstCloudFolderId'] as Map?)?['stringValue'] as String? ?? folderId;
              if (token != null && token.isNotEmpty) {
                activeToken = token;
                activeRefreshToken = refreshTok;
                activeTeacherName = tName;
                activeOwnerEmail = ownerEmail;
                activeTotpSecret = totpSec;
                activeFolderId = bstCloudFolderId.isNotEmpty ? bstCloudFolderId : folderId;
                return (success: true, teacherName: tName, email: ownerEmail, errorMessage: null);
              }
            }
          }
        }
```

#### 6) `apps/boardest_teacher_lite/lib/main.dart`
- **위치**: `c:\Users\jiwho\Documents\boardest\apps\boardest_teacher_lite\lib\main.dart` (Line 3010)
- **변경 내용**: 도메인 교정
```dart
onPressed: () => launchUrl(Uri.parse('https://boardest-teacher-oauth.web.app/edit?web-lite&return_url=https://boardest-teacher.web.app/lite/'), webOnlyWindowName: '_self'),
```

---

## 5. Verification Method (독립 검증 절차)

1. **RTDB 권한 검증**:
   - `firebase.cmd deploy --only database` 배포 후:
     ```powershell
     powershell -Command "Invoke-RestMethod -Uri 'https://jiwhosboardest-default-rtdb.firebaseio.com/cloud_pair_sessions/test.json' -Method Get"
     ```
   - 정상 기대값: `null` (HTTP 200 OK, `Permission denied` 에러가 사라져야 함).
2. **Firebase Rewrite 검증**:
   - `curl -I https://boardest-teacher-oauth.web.app/edit`
   - 정상 기대값: `HTTP/2 200` (404.html로 리디렉션되지 않고 index.html이 200 OK로 서빙되어야 함).
3. **단위 테스트 실행**:
   - `flutter test apps/boardest/test/passkey_school_validation_test.dart`
   - 정상 기대값: `All tests passed!`.
4. **무효화 조건 (Invalidation Conditions)**:
   - `cloud_pair_sessions`에 대한 REST PUT/GET 시 여전히 `Permission denied`가 반환되는 경우.
   - `boardest-teacher-oauth.web.app/edit`에 접속했을 때 여전히 루트 `/`로 이동하고 파라미터가 유실되는 경우.
