# 🤖 Boardest Platform — Core Agent Memory & Complete System Knowledge Base

> **버전 관리 규격**: 버전 변경 이력 및 상세 수정 내역은 [Ver.md](file:///c:/Users/jiwho/Documents/boardest/Ver.md) 파일에 매 작업 완료 시마다 반드시 기록하여 유지합니다.

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
│  전자칠판 메인 앱 (Web/Win)│               │    교사용 앱 (Web/Win)    │               │   교사용 라이트 (Web/PWA) │
│  (apps/boardest)         │               │  (apps/boardest_teacher) │               │(apps/boardest_teacher_lite)│
├──────────────────────────┤               ├──────────────────────────┤               ├──────────────────────────┤
│ - 터치 숫자 키패드 / 모달 │               │ - 파일 탐색기형 클라우드 UI│               │ - 실시간 컴시간 시간표   │
│ - PDF, PPT, Canva 판서   │               │ - 8자리 자동 OTP 기기 등록 │               │ - 6자리 Stegano OTP      │
│ - TBP 스마트 교과서      │               │ - 실시간 접속 로그 & 기기관리│              │ - 실시간 급식 지도 & 호출│
│ - 실시간 급식 호출 수신  │               │ - 교과/반별 폴더 맵핑     │               │ - Glassmorphism UI       │
└──────────────────────────┘               └──────────────────────────┘               └──────────────────────────┘
```

### 1) `apps/boardest` (전자칠판 메인 앱)
- **주요 기능**: 전자칠판 메인 뷰어, 화이트보드, PDF 보드(`pdfrx`), PPT 오버레이, Canva 뷰어, TBP 교과서 런처, 실시간 급식 호출 수신.
- **인증 방식**: 6자리 1회용 OTP 입력, 2자리 Cloud ID 자동로그인, 8자리 자동 기기 페어링.
- **웹 초기화 필수 사항**: `main.dart`의 `main()`에서 `WidgetsFlutterBinding.ensureInitialized()` 직후 `pdfrxFlutterInitialize()` 호출 필수.

### 2) `apps/boardest_teacher` (교사용 메인 앱)
- **주요 기능**: 주간 시간표, 실시간 급식 지도 & 반별 호출(`eat_calls`), 파일 탐색기형 Google Drive 보관함, 8자리 자동 OTP 기기 등록, 실시간 접속 로그, 교과/학급별 폴더 맵핑.
- **배포 타겟**: `boardest-teacher` (Firebase Hosting) 및 Windows 데스크톱 EXE.

### 3) `apps/boardest_teacher_lite` (교사용 라이트 웹/PWA)
- **주요 기능**: 컴시간 시간표, 6자리 Stegano OTP 카드(60초 자동 갱신), 급식 지도 및 1~9급식실 실시간 호출.
- **배포 타겟**: `boardest-teacher-lite` (Firebase Hosting).

### 4) `apps/boardest_teacher_oauth` (교사 계정 설정 및 OAuth 포털)
- **주요 기능**: Google OAuth 2.0 PKCE 인증, 교사 정보(학교, 성명, 컴시간 ID, 담당 학급) 등록 및 수정.

### 5) `infra/boardest_auth_worker` (Cloudflare Worker 인증 프록시)
- **주요 기능**: Zero-Trust Google OAuth 토큰 교환, 6자리 Steganography OTP 검증, 8자리 전자칠판 자동 페어링 관리, 접속 감사 로그(Audit Log) 및 폴더 맵핑 저장.

---

## 🌐 3. 배포 호스팅 및 라우팅 테이블

| 호스팅 플랫폼 | 타겟 명 / 도메인 | 실제 접속 URL | 설명 및 용도 |
|---|---|---|---|
| **Firebase Hosting** | `boardest-main` | `https://boardest.web.app` | Boardest 메인 전자칠판 앱 (웹 버전) |
| **Firebase Hosting** | `boardest-teacher` | `https://boardest-teacher.web.app` | 교사용 데스크톱 & 웹 통합 앱 |
| **Firebase Hosting** | `boardest-teacher-lite` | `https://boardest-teacher-lite.web.app` | 교사용 라이트 웹 포털 |
| **Firebase Hosting** | `boardest-teacher-oauth` | `https://boardest-teacher-oauth.web.app` | Google OAuth 및 교사 설정 포털 |
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
2. **Cloud Drive PDF 로딩**:
   웹 환경에서는 로컬 파일 경로 접근이 불가능하므로, `downloadDriveFileBytes(fileId, token)`를 통해 Drive 바이너리 바이트(`Uint8List`)를 직접 다운로드하여 `PdfBoardView(pdfData: bytes, initialFilePath: name)`로 전달.

---

## 🎨 8. 디자인 시스템 및 공통 UI 사양

- **테마 컬러 팔레트**:
  - Main Background: Deep Obsidian Slate (`#0B0F19`, `#0F172A`, `#16161A`)
  - Surface Card: `#1E293B` (Border: `rgba(255, 255, 255, 0.08)`)
  - Primary Accent: Mint Emerald (`#00F5D4`, `#2EC4B6`)
  - Secondary Accent: Indigo Violet (`#6366F1`, `#7F5AF0`)
  - Warning/Action: Warm Amber (`#FACC15`, `#FF8906`)
- **터치 키패드**:
  - 전자칠판 3×4 숫자 키패드 (`1~9`, `C`, `0`, `⌫`).
- **Cloud 파일 탐색기**:
  - Breadcrumb (`내 드라이브 > bst-save`), 실시간 검색창, 카테고리 칩 (`[전체]`, `[📄 PDF]`, `[🎨 Canva]`, `[📊 PPT]`, `[📝 판서]`).

---

## 🛠️ 9. 빌드 및 배포 명령어 모음

### 1) Flutter Web 일괄 빌드
```powershell
# 1. 전자칠판 메인
cd apps/boardest; cmd.exe /c flutter build web --release --no-tree-shake-icons

# 2. 교사용 웹 앱
cd apps/boardest_teacher; cmd.exe /c flutter build web --release --no-tree-shake-icons

# 3. 교사용 라이트 앱
cd apps/boardest_teacher_lite; cmd.exe /c flutter build web --release --no-tree-shake-icons
```

### 2) Firebase Hosting 일괄 배포
```powershell
cmd.exe /c firebase deploy --only hosting:boardest-main,hosting:boardest-teacher,hosting:boardest-teacher-lite,hosting:boardest-teacher-oauth
```

### 3) Cloudflare Worker 배포
```powershell
cd infra/boardest_auth_worker; cmd.exe /c npx wrangler deploy
```

---

## 🖥️ 10. v2.9.8.x 이후 화면 레이아웃 및 런처 규격

### 1) Boardest 메인 전자칠판 대시보드 레이아웃
- **최좌측 (flex: 18)**: 오늘의 시간표 세로 패널 (`_buildTodayTimetablePanel`).
- **메인 영역 (flex: 82)**:
  - **좌측 섹션 (flex: kIsWeb ? 56 : 48)**:
    - 상단 (flex: 43): 대형 디지털 시계 카드 (`_buildPptClockCard`).
    - 하단 (flex: 57): 지금 수업 카드 / Cloud 드라이브 패널 전면 전개 (`_buildPptSubjectCard` / `_buildFullCloudPanel`).
  - **우측 섹션 (런처 & 광고판, flex: kIsWeb ? 44 : 52)**:
    - **1열 (flex: kIsWeb ? 13 : 12)**:
      - 1행: 날씨 (`weather`)
      - 2행: 학사달력 (`school_calendar`)
      - 3행: 앱서랍 (`app_drawer`)
      - 4~7행: 광고판 (`_buildAdBannerOrContextCard` — A4 배너 / USB 탐색기 / 수업카드 / OTP 키패드). 1열 4~7행과 좌측 여백을 통합 차지하여 넓은 A4 가로폭 확보.
    - **2열 (flex: 10)**:
      - 1~7행 고정 도구: 판서하기, 교과서(TextbookPro), Canva, Cloud, 플러그인, 학생연결, 설정.
    - **3열 (flex: 10, 데스크톱/안드로이드 전용)**:
      - 1~7행 시스템 앱 자유 등록 슬롯 (슬롯 인덱스 14~20). 명확한 테두리와 `+ 앱 등록` 안내 제공.
      - **웹(Web) 버전 규격**: `if (!kIsWeb)` 조건으로 웹 브라우저 환경에서는 3열만 깔끔하게 제외됨.

### 2) Boardest Teacher 하단 3단 패널 레이아웃
- **상단 (flex: 5)**: 교사 주간 시간표 + 담임 학급 주간 시간표 (담임인 경우 1:1 배치).
- **우측 (flex: 3)**: 3열 × 6행 수업 도구 패널.
- **하단 (flex: 5, 3단 좌/우 통일 신규 구조)**:
  - **좌측 (flex: 33) — OTP & 보안 인증 관리**:
    - 상단: 6자리 Stegano OTP 대형 카드 (코드 복사, 60초 프로그레스 게이지 바, Cloud ID 배지, Auto-PT 토글 스위치).
    - 하단 서브 탭:
      - `[📡 다른 기기 OTP 주기]`: 교내 등록된 전자칠판 중 `lastActive`가 5분 이내인 **실제 온라인 기기만** 🟢 뱃지와 함께 노출, [8자리 전송] 클릭 시 Worker를 통해 해당 칠판에 직통 자동 OTP Secret 푸시.
      - `[🔐 인증 기기 & 로그]`: 계정에 등록된 신뢰 전자칠판 목록 조회 및 원격 연결 해제.
  - **중간 (flex: 37) — 파일 탐색기**:
    - Google Drive `bst-save` 보관함 브라우저.
    - 실시간 검색창 (`_cloudSearchQuery`), 카테고리 필터 칩 (`[전체]`, `[📄 PDF]`, `[🎨 Canva]`, `[📊 PPT]`, `[📝 판서]`).
    - 파일 클릭 시 바로 열기/다운로드/삭제.
  - **우측 (flex: 30) — 파일 업로드 & 폴더 맵핑**:
    - 4개 액션 버튼: [📁 파일 올리기], [🎨 Canva 등록], [📂 새 폴더], [🔄 폴더 맵핑].
    - 교과 / 반별 폴더 매핑 현황 리스트 및 클릭 시 해당 폴더 파일 필터링.

---

## ⚙️ 11. 자동 업데이트 및 시스템 정책 규격

1. **중복 다이얼로그 방지 가드**:
   - `UpdateService._isChecking` static boolean 플래그를 통해 앱 실행 중 `checkAndUpdate()`가 중복 호출되더라도 다이얼로그가 1회만 표시되도록 뮤텍스 보장.
2. **명시적 업데이트 팝업 (대놓고 업데이트)**:
   - 새 버전 감지 시 조용히 숨기지 않고, 명확한 [업데이트 알림] 다이얼로그를 띄워 신규 버전(vX.X.X.X), 릴리즈 안내 및 [업데이트 시작] 버튼 제공.
3. **Windows 무방해 업데이트**:
   - AppX 매니페스트 `UpdateBlocksActivation="false"` 적용으로 앱 시작 지연 없이 백그라운드 다운로드 진행.
4. **Android 홈 런처 및 화면 배율(DPI) 제어**:
   - `isDefaultHomeLauncher` / `openHomeLauncherSettings` MethodChannel 탑재.
   - 앱 최초 구동 시 전자칠판 전용 홈 런처로 등록할지 묻는 안내 팝업 제공.
   - 60% ~ 150% 화면 배율(DPI) 커스텀 슬라이더 다이얼로그 제공.

---

> **에이전트 준수 사항**: 향후 어떤 새 대화나 세션에서도 이 문서(`AGENT.md`)에 정의된 아키텍처, 6자리 Steganography 수식, 8자리 자동 페어링 규격, Google Drive 파일/폴더 규칙, 대시보드 3열 레이아웃, Teacher 하단 3단 패널 및 급식 호출 필터 규칙을 최우선 기준으로 준수하여 개발하십시오.
