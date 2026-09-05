# 🤖 Boardest Platform — Core Agent Memory & Complete System Knowledge Base

> **버전 관리 규격**: 버전 변경 이력 및 상세 수정 내역은 [Ver.md](file:///c:/Users/jiwho/Documents/boardest/Ver.md) 파일에 매 작업 완료 시마다 반드시 기록하여 유지합니다.
> ⚠️ **[중요] Beta 버전 관리 철칙**: Beta 테스트가 공식 종료되기 전까지는 모든 앱과 패키지의 버전을 **반드시 `2.9.9.X`** 형식(예: `2.9.9.1`, `2.9.9.2`, `2.9.9.5`, `2.9.9.6` 등)으로 유지해야 합니다 (절대로 `3.0.0` 등으로 앞자리를 올리지 말 것).

---

## 📌 1. 플랫폼 개요 및 시스템 철학

**Boardest(보디스트)**는 초·중·고등학교 교실의 전자칠판(전자교탁)과 교사용 PC/노트북 간의 유기적인 수업 진행, 판서 기록, 클라우드 교안 관리, 실시간 급식 지도 및 학내 메시징을 지원하는 **올인원 스마트 스쿨 플랫폼**입니다.

### 핵심 시스템 원칙
1. **숄더 서핑(Shoulder Surfing) 원천 차단**: 교실에서 학생들이 교사의 입력을 훔쳐보더라도 비밀번호가 노출되지 않도록 **6자리 동적 자릿수 셔플(Steganography) OTP**를 적용합니다.
2. **크로스플랫폼 (Universal IO / FFI Stub)**: Windows 데스크톱, Web 브라우저, Android APK 환경에서 단일 메인 소스코드가 예외 없이 구동되도록 C++ FFI 및 Win32 의존성을 추상화합니다.
3. **모달 닫기 시 세션 유지**: 전자칠판 클라우드 팝업창을 닫아도 토큰이 유지되며, 명시적인 [로그아웃] 버튼이나 수업 종료 3분 타이머 만료 시에만 세션이 안전하게 종료됩니다.
4. **Google Drive 차분 동기화 & 드라이브 구조 일원화**: 모든 수업 교안은 `bst-save`, 학급별 판서 기록은 `bst-pen` 폴더로 1:1 대칭 관리됩니다.

---

## 🏗️ 2. 멀티 앱 아키텍처 및 생태계 구성

```
                                  ┌───────────────────────────────────────────┐
                                  │   Cloudflare Worker & Google Drive v3 API │
                                  └─────────────────────┬─────────────────────┘
                                                        │
              ┌─────────────────────────────────────────┼─────────────────────────────────────────┐
              ▼                                         ▼                                         ▼
┌──────────────────────────┐               ┌──────────────────────────┐               ┌──────────────────────────┐
│  전자칠판 메인 앱 (Web/Win)│               │    교사용 앱 (Web/Win)    │               │  교사용 라이트 (모바일 PWA)│
│  (apps/boardest)         │               │  (apps/boardest_teacher) │               │ (apps/boardest_teacher_lite│
├──────────────────────────┤               ├──────────────────────────┤               ├──────────────────────────┤
│ - 급식 분리, 7:4 시간표  │              │ - 24:76 초슬림도구:탐색기│             │ - 급식 호출 원격 제어    │
│ - PPT/HWP 외부 헬퍼 구동 │              │ - 대형 와이드 Drive 탐색 │             │ - 6자리 OTP & 클라우드   │
│ - PDF, Canva 내장 판서   │               │ - 4버튼 콤팩트 액션 툴바 │             │ - 스마트폰 홈 화면 추가 PWA│
│ - 시크릿 QR 기기 자동등록│               │ - 교과/반별 폴더 맵핑    │             │ - 가볍고 즉각적인 모바일 UI│
└──────────────────────────┘               └──────────────────────────┘               └──────────────────────────┘
              │                                         │                                         │
              └─────────────────────────────────────────┼─────────────────────────────────────────┘
                                                        ▼
                                ┌──────────────────────────────────────────┐
                                │   교사 계정 & 시크릿 허브 (Web)          │
                                │   (apps/boardest_teacher_oauth)          │
                                ├──────────────────────────────────────────┤
                                │ - Google OAuth 2.0 PKCE 인증             │
                                │ - 토큰 만료 검증 & Refresh 자동 갱신     │
                                │ - 전자칠판 QR 연동용 시크릿 허브         │
                                └──────────────────────────────────────────┘
```

### 1) `apps/boardest` (전자칠판 메인 앱)
- **주요 기능**: 전자칠판 메인 뷰어, 화이트보드, PDF 보드(`pdfrx`), PPT 오버레이, Canva 뷰어, TBP 교과서 런처, 실시간 급식 호출 수신.
- **레이아웃**: 급식 요소를 메인에서 완전 분리하여 '지금 시간표'를 63.6%(flex: 7)로 확대하고, 디지털 시계(flex: 5)와 광고판(flex: 4)을 안정적으로 배치.
- **파일 실행 엄격 분리**: PPT/PPTX 및 HWP/HWPX 파일은 웹 뷰어 대신 네이티브 C#/WPF 오버레이 또는 OS 기본 프로그램(`launchUrl(Uri.file)`)으로 실행(웹 환경은 Drive 뷰어 직결). PDF/TBP/Canva는 Boardest 내장 전용 뷰어로 구동.
- **시크릿 QR 자동 등록 & 401 자가 치유**: 8자리 텍스트 코드 대신 즉각적인 시크릿 QR 코드를 스캔하여 자동 로그인 기기 등록을 수행하며, Google Access Token 만료(401 Unauthorized) 시 Refresh Token을 통한 자가 치유(Self-healing) 재발급 지원.
- **웹 초기화 필수 사항**: `main.dart`의 `main()`에서 `WidgetsFlutterBinding.ensureInitialized()` 직후 `pdfrxFlutterInitialize()` 호출 필수.

### 2) `apps/boardest_teacher` (교사용 메인 앱)
- **주요 기능**: 주간 시간표, 교실 쪽지 전송, 24:76 초슬림 OTP/Drive 제어 도구 & 초대형 클라우드 파일 탐색기.
- **하단 도구 통합 및 와이드 탐색기**: 좌측 제어 영역을 `flex: 24`로 슬림화하고 [업로드 / Canva / 새 폴더 / 동기화] 4버튼 액션 툴바를 배치하여, 우측 Google Drive `bst-save` 파일 탐색기를 `flex: 76`으로 전폭 확장.
- **Web PDF 에러 원천 해결**: `kIsWeb` 조건에서 `localF.existsSync()`를 우회하고 `CloudDriveService.webMemoryFiles` 바이트를 직접 `PdfBoardView`로 바인딩하여 브라우저에서도 PDF 즉시 로드.
- **배포 타겟**: `boardest-teacher` (Firebase Hosting) 및 Windows 데스크톱 EXE/AppX.

### 3) `apps/boardest_teacher_lite` (교사용 모바일 라이트 PWA — `boardest-teacher-lite.web.app`)
- **주요 기능**: 스마트폰 최적화 무설치 모바일 웹앱. 원격 급식 호출 및 취소, 6자리 Stegano OTP 생성 및 연동, Google Drive 수업 자료 전송.
- **특징**: 스마트폰 브라우저에서 '홈 화면에 추가' 시 전체 화면 PWA 네이티브 경험 제공.

### 4) `apps/boardest_teacher_oauth` (교사 계정 설정 및 시크릿 관리 허브 — `boardest-teacher-oauth.web.app`)
- **주요 기능**: Google OAuth 2.0 PKCE 인증, 교사 프로필 등록, **보안 시크릿 키 관리/생성/저장 전용 허브** (보안을 위해 1회용 OTP 번호는 본 사이트에 직접 노출하지 않음).

### 5) `infra/welcome_web` & `download-boardest` (설치 & 다운로드 허브)
- **`welcome-to-boardest.web.app`**: 접속 기기(User-Agent) 자동 감지 맞춤형 온보딩 포털 및 핵심 기능 소개 쇼케이스.
- **`download-boardest.web.app`**: 설치 명령어 및 브라우저 다운로드 출처 URL 지원 서버 (`/win-cer.ps1`, `/bst.apk`, `/boardest.appinstaller`, `/bst-teacher.appinstaller`, 루트 접속 시 welcome으로 302 리다이렉트).

### 6) `infra/boardest_auth_worker` (Cloudflare Worker 인증 프록시)
- **주요 기능**: Zero-Trust Google OAuth 토큰 교환, 6자리 Steganography OTP 검증, 8자리 전자칠판 자동 페어링 관리, 접속 감사 로그(Audit Log) 및 폴더 맵핑 저장.

---

## 🌐 3. 배포 호스팅 및 라우팅 테이블

| 호스팅 플랫폼 | 타겟 명 / 도메인 | 실제 접속 URL | 설명 및 용도 |
|---|---|---|---|
| **Firebase Hosting** | `welcome-to-boardest` | `https://welcome-to-boardest.web.app` | 공식 사용자 안내 및 온보딩 포털 (UA 자동 감지 & 기능 소개) |
| **Firebase Hosting** | `download-boardest` | `https://download-boardest.web.app` | 원클릭 스크립트(`win-cer.ps1`) 및 최신 릴리즈 직접 다운로드 출처 허브 |
| **Firebase Hosting** | `boardest-main` | `https://boardest.web.app` | Boardest 메인 전자칠판 앱 (웹 버전) |
| **Firebase Hosting** | `boardest-teacher` | `https://boardest-teacher.web.app` | 교사용 데스크톱 & 웹 통합 앱 (38:62 2분할 레이아웃) |
| **Firebase Hosting** | `boardest-teacher-lite` | `https://boardest-teacher-lite.web.app` | 교사용 라이트 모바일 웹앱 (급식 호출 & OTP) |
| **Firebase Hosting** | `boardest-teacher-oauth` | `https://boardest-teacher-oauth.web.app` | Google OAuth 및 보안 시크릿 키 관리/생성/저장 허브 |
| **Cloudflare Worker** | `boardest-cloud-token` | `https://boardest-cloud-token.jiwho.workers.dev` | 인증/토큰 교환/OTP 검증/기기 관리 API |
| **Cloudflare Worker** | `comcigan` | `https://comcigan.jiwho.workers.dev` | 컴시간 시간표 초고속 TCP 프록시 |

---

## 🔒 4. 보안 및 OTP 인증 알고리즘 규격

### 1) 6자리 동적 자릿수 셔플 (Steganography) OTP
교사가 학생들 앞에서 직접 칠판에 입력하는 6자리 1회용 코드입니다.
- **구성 요소**: 2자리 Cloud ID ($Y_1 Y_2$, 00~99) + 4자리 RFC 6238 TOTP ($X_1 X_2 X_3 X_4$, 60초 주기).
- **셔플 인덱스 매핑** ($m = \text{현재 시각 분(Minute)} \pmod 5$):

| $m$ ($분 \pmod 5$) | 1번째 ($index 0$) | 2번째 ($index 1$) | 3번째 ($index 2$) | 4번째 ($index 3$) | 5번째 ($index 4$) | 6번째 ($index 5$) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **0** | $Y_1$ | $X_1$ | $X_2$ | $Y_2$ | $X_3$ | $X_4$ |
| **1** | $X_1$ | $Y_1$ | $X_2$ | $X_3$ | $Y_2$ | $X_4$ |
| **2** | $X_1$ | $X_2$ | $Y_1$ | $X_3$ | $X_4$ | $Y_2$ |
| **3** | $Y_1$ | $X_1$ | $X_2$ | $X_3$ | $Y_2$ | $X_4$ |
| **4** | $X_1$ | $Y_1$ | $X_2$ | $X_3$ | $X_4$ | $Y_2$ |

- **검증 절차**:
  1. 전자칠판에서 6자리 코드 입력.
  2. 서버(Worker)에서 현재 분($m$)의 역연산으로 2자리 Cloud ID와 4자리 TOTP를 분리.
  3. 교사의 `totpSecret`으로 $\pm 1$ 윈도우(총 3분 오차 허용) 내 유효성 검증.
  4. 검증 성공 시 1시간 유효 단기 Google Drive `access_token` 발급 및 감사 로그 기록.

### 2) 8자리 전자칠판 자동 OTP & 기기 페어링
전자칠판을 선생님 계정에 영구/신뢰 기기로 등록하여 자동 로그인할 때 사용합니다.
- **코드 규격**: 8자리 난수 (예: `4829 1042`), 유효 시간 180초(3분).
- **프로세스**:
  1. 전자칠판 [자동 기기 등록] 클릭 $\rightarrow$ Worker `/api/auth/device/pair-request` 호출하여 8자리 코드 발급 및 화면 표시.
  2. 교사가 교사용 앱 [인증 & 기기 관리]에서 8자리 코드 입력 $\rightarrow$ Worker `/api/auth/device/pair-confirm` 승인.
  3. 전자칠판의 Device ID가 교사의 계정에 신뢰할 수 있는 기기로 등록되어 이후 자동 인증 가능.

---

## 📁 5. Google Drive 파일 및 폴더 표준

| 폴더 명칭 | 주 용도 | 관리 및 연동 규칙 |
|---|---|---|
| **`bst-save`** | 수업 교안 통합 보관함 | PDF, PPT, PPTX, `.canva.bst` 메타데이터 파일 등 저장.<br>• 폴더 생성/삭제 시 `bst-pen`에도 동일 폴더를 자동 생성/삭제. |
| **`bst-pen`** | 학급별 판서 기록 보관함 | 파일별 하위 폴더 생성: `bst-pen/[교안파일명]/[반ID].pen`<br>• 전자칠판에서 수업 종료 시 판서 데이터를 자동 동기화. |
| **`bst-textbookpro`** | TBP 스마트 교과서 | 전자 저작물 교과서 패키지 및 핫스팟 데이터 저장. |

> **통합 주의사항**:
> - 구 `bst-sync` 및 `bst-canva` 폴더는 폐기되었으며, 모든 교안 및 Canva 링크(`.canva.bst` JSON)는 `bst-save`에 통합 저장됩니다.

---

## 🍱 6. 실시간 급식 지도 & 반별 호출 규격

### 1) 데이터베이스 스키마 (`Firestore: eat_calls/{docId}`)
- `docId` 포맷: `{schoolCode}_{cafeteriaNum}_{grade}_{classNum}` (예: `ydm_1_2_8`)
- 필드 구성:
  - `called`: `boolean` (호출 여부)
  - `grade`: `integer` (학년)
  - `classNum`: `integer` (반)
  - `cafeteriaNum`: `string` ("1" ~ "9")
  - `lastActive`: `timestamp` (전자칠판 온라인 하트비트 시간)
  - `lastCalledAt`: `string` (호출 발송 일시)

### 2) 학급 필터링 및 중복 병합 규칙
1. **일반 학급 전용**: `grade > 0 && classNum > 0` 인 정규 학급만 급식실 목록에 노출 (`music2`, `교수학습실1` 등 특별실 완전 제외).
2. **온라인 기준**: `DateTime.now() - lastActive <= 5분` 인 온라인 교실만 실시간 목록에 표시.
3. **동일 학급 단일 병합**: 동일한 학급(예: 2학년 8반)이 2개 이상 조회될 경우, 가장 최근 `lastActive`를 가진 단일 엔트리로 병합.
4. **전자칠판 수신 폴링**: 전자칠판 `MealCallService`는 4초 간격 경량 폴링 및 2분 주기 `lastActive` 하트비트를 유지하여 호출 신호 즉시 수신.

---

## 📄 7. PDF 렌더링 및 Universal Pen 표준

1. **`pdfrx` 웹 초기화**:
   `apps/boardest/lib/main.dart`의 `main()` 최상단에서 `WidgetsFlutterBinding.ensureInitialized()` 직후 `pdfrxFlutterInitialize()` 호출 필수.
2. **Cloud Drive Web PDF 로딩 (Namespace 에러 방지)**:
   - 웹 브라우저 환경에서는 `dart:io` `File.existsSync()` 호출 시 `Unsupported operation: _Namespace` 예외가 발생합니다.
   - 따라서 `kIsWeb` 조건에서는 로컬 파일 존재 검사를 원천 생략하고, `CloudDriveService.webMemoryFiles`에 캐시된 메모리 바이트(`Uint8List`)를 직접 추출하여 `PdfBoardView(initialFilePath: name, pdfData: bytes)`로 전달합니다.

---

## 🎨 8. 디자인 시스템 및 공통 UI 사양

- **테마 컬러 팔레트**:
  - Main Background: Deep Obsidian Slate (`#0B0C10`, `#0F172A`, `#16161A`)
  - Surface Card: `#14161F` ~ `#1E293B` (Border: `rgba(255, 255, 255, 0.08)`)
  - Primary Accent: Mint Emerald (`#00F5D4`, `#2EC4B6`)
  - Secondary Accent: Indigo Violet (`#6366F1`, `#7F5AF0`)
  - Warning/Action: Warm Amber (`#FACC15`, `#FF8906`)
  - Danger: Neon Coral (`#EF4565`, `#F87171`)
- **터치 키패드**:
  - 전자칠판 3×4 숫자 키패드 (`1~9`, `C`, `0`, `⌫`).
- **Cloud 파일 탐색기**:
  - Breadcrumb (`내 드라이브 > bst-save`), 실시간 검색창, 카테고리 칩 (`[전체]`, `[📄 PDF]`, `[🎨 Canva]`, `[📊 PPT]`, `[📝 판서]`).

---

## 🛠️ 9. 빌드 및 배포 명령어 모음

### 1) Flutter Web 빌드
```powershell
# 1. 전자칠판 메인
cd apps/boardest; cmd.exe /c flutter build web --release --no-tree-shake-icons

# 2. 교사용 웹 앱
cd apps/boardest_teacher; cmd.exe /c flutter build web --release --no-tree-shake-icons

# 3. 교사용 라이트 앱
cd apps/boardest_teacher_lite; cmd.exe /c flutter build web --release --no-tree-shake-icons
```

### 2) Firebase Hosting 전체 배포
```powershell
cmd.exe /c firebase deploy --only hosting:welcome-to-boardest,hosting:download-boardest,hosting:boardest-eat,hosting:boardest-main,hosting:boardest-teacher,hosting:boardest-teacher-lite,hosting:boardest-teacher-oauth
```

### 3) Cloudflare Worker 배포
```powershell
cd infra/boardest_auth_worker; cmd.exe /c npx wrangler deploy
```

---

## 🖥️ 10. 최신 화면 레이아웃 규격

### 1) Boardest 메인 전자칠판 대시보드 (7:4 시간표 최적화 레이아웃)
- **최좌측 (flex: 18)**: 오늘의 시간표 세로 패널 (`_buildTodayTimetablePanel`).
- **메인 영역 (flex: 82)**:
  - **상단 섹션 (flex: 5)**: 확대된 디지털 시계 카드 (`_buildPptClockCard`) & 런처 상단 3행.
  - **하단 섹션 (flex: 8)**: **7:4 = [지금 시간표 (flex: 7, 63.6%)] : [광고판 / Cloud / USB (flex: 4, 36.4%)]**
    - **급식 요소 완전 분리**: 급식 기능은 독립 웹앱(`boardest-eat.web.app`)으로 단일화하고, 메인 대시보드에서는 급식 선택 버튼을 제거하여 시간표와 시계에 화면 공간 집중.
    - **세션 영구 보존**: 클라우드 패널을 닫아도 `activeToken = null`이 아닌 `_hideCloudPanel = true`를 적용하여 교사 세션이 풀리지 않고 유지됨. 광고판 하단의 `[☁️ 클라우드 다시 열기]` 버튼으로 언제든 즉시 재전개.
  - **우측 런처 열 구성**:
    - **1열**: 1행 날씨, 2행 학사달력, 3행 앱서랍, 4~7행 광고판/컨텍스트 영역.
    - **2열**: 고정 수업 도구 7행 (판서하기, 교과서, Canva, Cloud, 플러그인, 학생연결, 설정).
    - **3열 (Windows 데스크톱/Android 전용)**: 사용자 등록 시스템 앱 7행. (Web 환경에서는 `!kIsWeb` 조건으로 자동 제외).

### 2) Boardest Teacher 하단 2분할 통합 패널 (24:76 와이드 레이아웃)
- **상단 (flex: 4)**: 교사 주간 시간표 + 담임 학급 주간 시간표 (담임인 경우 1:1 배치).
- **우측 (flex: 3)**: 3열 × 6행 수업 도구 패널.
- **하단 (flex: 6, [24% 통합 제어 도구] : [76% 클라우드 와이드 탐색기] 2분할 구조)**:
  - **좌측 (flex: 24) — 초슬림 OTP & 빠른 도구 & 교과 맵핑 패널**:
    - **6자리 Stegano OTP 대형 카드**: 잔여 시간 프로그레스 바, 원클릭 복사, Auto-PT 스위치.
    - **콤팩트 4-Action 툴바**: [업로드 / Canva / 새 폴더 / 동기화] 1열 가로 툴바 배치 (`_buildSlimActionBtn`).
    - **인증 기기 관리 & 교과/반별 폴더 매핑**: 기기 차단/승인 모달 연동 및 `bst-save` 폴더 맵핑 리스트.
  - **우측 (flex: 76) — 초대형 와이드 클라우드 파일 탐색기 (`_buildDriveFilesPanel`)**:
    - 화면의 대부분을 차지하는 압도적인 와이드 탐색 환경.
    - Google Drive `bst-save` 보관함 폴더 내비게이션, 파일 검색 및 카테고리 필터링.
    - 상단 경로 표시줄 및 액션 아이콘 툴바 내장.

---

## ⚙️ 11. 자동 업데이트, 인증서 및 원클릭 설치 규격

1. **`download-boardest.web.app/win-cer.ps1` 인증서 전용 설치 스크립트**:
   ```powershell
   irm https://download-boardest.web.app/win-cer.ps1 | iex
   ```
   - 앱 설치와 별개로 **보안 인증서만 단독으로 설치**하는 경량 전용 스크립트.
   - ExecutionPolicy 제한을 우회하여 관리자 권한 자동 승격 후 `BoardestCert.cer`를 로컬 머신 루트 및 신뢰할 수 있는 사용자 저장소에 등록 완료 후 즉시 종료.
   - 앱 설치는 이후 웹사이트 다운로드 또는 `Add-AppxPackage`를 통해 사용자가 별도로 진행.
2. **다운로드 출처 직접 연결 (GitHub latest 302 리다이렉트)**:
   - APK: `https://download-boardest.web.app/bst.apk`
   - AppInstaller: `https://download-boardest.web.app/bst.appinstaller`
   - AppX: `https://download-boardest.web.app/bst.appx`, `/bst-teacher.appx`
   - 인증서: `https://download-boardest.web.app/bst.cer`
3. **영구 자체 서명 인증서**:
   - `BoardestCert.cer` (발행: `CN=jiwho`, 만료일: **2999년 12월 31일**).
   - 로컬 머신 루트 인증 기관(`Cert:\LocalMachine\Root`) 및 신뢰할 수 있는 사용자(`Cert:\LocalMachine\TrustedPeople`)에 동시 등록되어 `0x800B0109` 신뢰 오류 원천 차단.
4. **AppInstaller vs .appx 안내**:
   - 일반 환경: 자동 백그라운드 업데이트가 지원되는 **AppInstaller** 적극 권장.
   - 교내 보안망/폐쇄망 환경: 인터넷이 차단된 PC를 위한 수동 **.appx** 오프라인 설치 제공.

---

> **에이전트 준수 사항**: 향후 어떤 새 대화나 세션에서도 이 문서(`AGENT.md`)에 정의된 아키텍처, 6자리 Steganography 수식, 3:2 대시보드 레이아웃, Teacher 38:62 2분할 패널, OAuth 시크릿 허브, 독립 급식 웹앱 규격 및 `download-boardest` 다운로드 프로토콜을 최우선 기준으로 준수하여 개발하십시오.

