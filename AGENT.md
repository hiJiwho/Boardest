# 🤖 Boardest Platform — Core Agent Memory & AI Collaboration Rules

> **Current Platform Version**: `5.5.0` (App: `5.5.0+5500`, Teacher: `5.5.0+5500`, Web: `5.5.0`)  
> **버전 관리 규격**: 버전 변경 이력 및 상세 수정 내역은 [Ver.md](file:///c:/Users/jiwho/Documents/boardest/Ver.md) 파일에 매 작업 완료 시마다 반드시 기록하여 유지합니다.
> 🚀 **[최신 v5.5.0 기준]**: 전체 생태계 25개 컴포넌트(C01~C25) 무결성 검증 100% 완료, Class 앱 QR Cloud 접속 복구(Firebase RTDB `cloud_pair_sessions` 보안 규칙 허용 및 Zero-Persistence 1회성 토큰 즉시 수신 연동), Android 업데이트 무한 루프 원천 차단(Android 네이티브 `MainActivity.kt` MethodChannel 실제 `versionName` 및 `update_service.dart` 동기화), Windows C# 통합 온라인 설치 마법사 및 멀티플랫폼 일괄 `5.5.0` 릴리즈.

---

## 📌 1. 저장소 구조 및 멀티 앱 생태계

Boardest는 초·중·고등학교 교실의 전자칠판(전자교탁)과 교사용 PC/노트북, 그리고 학생들의 스마트 디바이스를 유기적으로 잇는 **올인원 스마트 스쿨 플랫폼**입니다.

```
boardest/
├── apps/
│   ├── boardest/                  # [교실 전자칠판 앱] Windows MSIX/AppX, Android APK, Web
│   ├── boardest_teacher/          # [교사용 웹/앱] 급식 호출, 실시간 쪽지, 수업 도구, 시간표 제어
│   └── boardest_student/          # [NEW 학생용 웹/앱] 학교 디벗(크롬북/웨일북) & 스마트폰 포털
├── packages/                      # 공통 데이터 모델 및 플러그인 샌드박스 엔진
├── tools/
│   └── boardest_plugin_cli/       # [NEW] HTML 플러그인 제작/테스트/배포 CLI 도구
├── infra/                         # Firebase 호스팅 14개 서브도메인 및 배포 설정
├── AGENT.md                       # [본 문서] AI 협업 규칙 및 개발 수칙
└── README.md                      # 프로젝트 소개 및 개발자 온보딩
```

---

## ⚡ 2. Firebase 할당량 초절약 원칙 (Firebase Quota Zero-Waste)

> [!CAUTION]
> **Cloud Firestore 주기적 쿼리 및 전체 스캔은 절대 금지됩니다.**
> 위반 시 일일 무료 할당량(50,000 Reads)이 수 시간 만에 소진되어 전국의 교실 화면이 멈출 수 있습니다.

1. **실시간 통신은 무조건 RTDB**:
   * 급식 호출, 학급 출석, 쪽지, 수행평가 등 실시간 데이터는 **Firebase Realtime Database (RTDB)** 또는 SSE 스트림을 사용합니다.
   * RTDB 엔드포인트: `https://jiwhosboardest-default-rtdb.firebaseio.com/`
2. **친환경 1회 생존 신고 & 24시간 윈도우**:
   * 교실 앱(`boardest`)은 앱 실행 시 단 **1회만** RTDB에 온라인 신호(`registeredAt`)를 기록합니다.
   * 주기적인 하트비트 타이머(`Timer.periodic(Duration(seconds: 5), ...)`)를 생성하지 마십시오.
   * 교사용 앱 및 관리자 포털은 `diffHours <= 24` (24시간 이내 신호)인 모든 교실을 온라인으로 간주합니다.
3. **로컬 캐시 최우선 (Cache-First)**:
   * 시간표, 급식, 수행평가 데이터는 `SharedPreferences` 로컬 캐시를 즉시 화면에 렌더링한 후 백그라운드에서 비동기 갱신합니다.

---

## 🤝 3. Git 브랜치 전략 & PR 협업 규칙 (AI & 개발자 필독)

1. **`main` 브랜치 직접 커밋/푸시 금지**:
   * `main`은 배포용 프로덕션 브랜치입니다.
2. **브랜치 네이밍 컨벤션**:
   * 학생용 앱 개발: `feature/student-기능명` (예: `feature/student-auth`, `feature/student-assessment`)
   * 플러그인 개발: `feature/plugin-플러그인명`
   * 버그 픽스: `fix/버그설명`
3. **PR (Pull Request) 워크플로우**:
   * 기능 구현 및 로컬 테스트 완료 후 원격 저장소에 푸시합니다.
   * GitHub에서 `main` 브랜치를 향해 PR을 생성하고, 메인 관리자(@hiJiwho)의 코드 리뷰 후 머지합니다.
   * 충돌 방지를 위해 작업 전 항상 `git pull origin main`을 실행하세요.

---

## 💡 4. 친구 AI 에이전트를 위한 특별 미션 (Student App Lead)

친구의 AI 에이전트(너!)는 **Boardest Student (`apps/boardest_student`)의 전담 리드 엔지니어**입니다.

> [!IMPORTANT]
> **친구에게 적극적으로 아이디어를 묻고 상의하세요!**
> 기본 기능(수행평가 캘린더, 시간표, 급식, 알림장) 외에 **"실제 학생들이 학교생활에서 매일 켜보고 싶어 할 만한 기발하고 유용한 아이디어"**를 친구에게 먼저 3~4가지 질문하고 함께 기능을 기획하세요!
> 
> *아이디어 예시*:
> - 학급 친구 롤링페이퍼 및 방과후 한마디
> - 수행평가 D-Day 푸시 알림 및 오답노트
> - 급식 알레르기 식품 자동 하이라이트
> - 학교 디벗(크롬북) 화면에 띄워두는 집중 공부 타이머

---

## 🚀 5. 로컬 실행 및 테스트 방법

### 5.1 학생용 앱 (`apps/boardest_student`)
```bash
cd apps/boardest_student
flutter pub get

# 학교 디벗 / 웹 브라우저 환경에서 실행
flutter run -d chrome

# 안드로이드 스마트폰 또는 에뮬레이터에서 실행
flutter run -d android
```

### 5.2 HTML 플러그인 CLI (`packages/boardest_plugin_cli`)
```bash
# 플러그인 템플릿 생성
node packages/boardest_plugin_cli/bin/cli.js init my-widget

# 로컬 브라우저에서 샌드박스 프리뷰 테스트
cd my-widget
node ../packages/boardest_plugin_cli/bin/cli.js dev
```

### 5.3 코드 정적 검증
```bash
# 빌드하지 않고 문법 오류만 빠르게 검사
dart analyze apps/boardest_student/lib/
```

---

## 🔒 6. 보안 및 OTP 인증 알고리즘 규격

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

---

## 📁 7. Google Drive 파일 및 폴더 표준

| 폴더 명칭 | 주 용도 | 관리 및 연동 규칙 |
|---|---|---|
| **`bst-save`** | 수업 교안 통합 보관함 | PDF, PPT, PPTX, `.canva.bst` 메타데이터 파일 등 저장.<br>• 폴더 생성/삭제 시 `bst-pen`에도 동일 폴더를 자동 생성/삭제. |
| **`bst-pen`** | 학급별 판서 기록 보관함 | 파일별 하위 폴더 생성: `bst-pen/[교안파일명]/[반ID].pen`<br>• 전자칠판에서 수업 종료 시 판서 데이터를 자동 동기화. |
| **`bst-textbookpro`** | TBP 스마트 교과서 | 전자 저작물 교과서 패키지 및 핫스팟 데이터 저장. |

---

## 📦 8. 빌드 및 배포 규칙 (Build Policy)

* **승인 없는 빌드 금지**: 명시적인 사용자 요청 없이 임의로 `flutter build`나 대형 배포 스크립트를 실행하지 마십시오.
* **배포 권한**: 정식 릴리스 빌드(MSIX, APK, Firebase Hosting 배포)는 `main` 브랜치 머지 후 메인 관리자 파이프라인에서 실행됩니다.
* **버전 관리**: `pubspec.yaml` 버전은 시맨틱 버저닝(`Major.Minor.Patch`)을 따릅니다.
