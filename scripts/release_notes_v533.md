# Boardest v5.3.3 Official Release

## 🚀 주요 변경사항 및 개선 (What's New in v5.3.3)

### 1. Firebase Quota (Firestore / RTDB) 실시간 할당량 초절약 최적화
- **미사용 급식 기능 네트워크 호출 완전 차단 ("급식 안쓰고")**:
  - 교사용 앱(`TeacherView`)에서 미사용 `MealView`('급식 지도 & 호출') 탭을 제거하고 '학급 쪽지'(`MessageView`)로 기본 전환했습니다.
  - 급식 호출(`eat_calls`) 및 급식 투표(`meal_votes`)의 주기적 상시 폴링/쓰기를 전면 중단하고, 100% 로컬 SharedPreferences 캐시로 전환했습니다.
- **클라우드 교사 목록 조회 캐시 강화**:
  - `BstCloudService.getCloudTeachers` 캐시 유효 시간을 30분으로 확장하고 레거시 컬렉션 스캔을 제거했습니다.
- **QR 클라우드 로그인 세션 RTDB 전환**:
  - `waitForReversePairAuth` 및 스마트폰 QR 로그인 연결을 Firestore REST 대신 RTDB 단일 경로로 처리하여 Firestore 읽기/쓰기 0회를 실현했습니다.
- **보안 감사 로그 로컬 기기 저장**:
  - `BstCloudLogger`를 SharedPreferences 기반 50개 로컬 FIFO 링버퍼로 전환하여 무의미한 Firestore `audit_logs` 쓰기를 없앴습니다.

### 2. 구버전(5.1.1) 및 신규 버전 자동 업데이트 완벽 보장
- **5.1.1 다운로드 캐시 오염 차단**:
  - 릴리즈 에셋에 `boardest-class.appx` 및 `boardest-class.apk`를 `boardest.appx` / `boardest.apk`와 동일하게 1순위로 제공하여 구버전 클라이언트의 잘못된 패키지 다운로드를 방지했습니다.
- **급식표 미사용 시에도 업데이트 상시 노출**:
  - 급식 식단표를 보지 않는 교실, Cloud 패널 활성 교실, `BoardestCloudView` 등에서도 상단 바에 다운로드 진행률 및 `[지금 즉시 업데이트 설치 (v5.3.3)]` 버튼이 항시 표시됩니다.
- **Windows 자동 무인 백그라운드 설치 복원**:
  - Windows에서 `Add-AppxPackage -ForceApplicationShutdown` 및 최신 앱 자동 재시작 스크립트를 백그라운드 실행하여 스토어 GUI 없이 즉시 업데이트가 완료됩니다.

### 3. 수업 시간 화면 시계/날짜/D-day 중복 버그 완벽 수정
- **단일 대형 시계(시:분:초) 및 단일 날짜·D-day 체제**:
  - 상단 대형 시계의 시:분:초 및 날짜, D-day만 깔끔하게 유지하고, 하단 수업 카드 내부에 중복되어 뜨던 `시:분` 시계, 중복 날짜, 중복 D-day를 완전히 제거했습니다.
  - 수업 중 과목명, 교과서 표지, 교시 뱃지 및 시간대, 학급 정보가 한눈에 들어오도록 최적화했습니다.

### 4. 웹 포털 & 가이드 리뉴얼
- `boardest.web.app` 포털, 다운로드 허브, 클래스 프로/라이트 가이드 및 원클릭 파워쉘 설치 스크립트(`bst.ps1`, `cer.ps1`, `win-cer.ps1`, `install-class-lite.ps1`)를 최신 v5.3.3 규격으로 갱신했습니다.

---

## 📦 다운로드 에셋 안내 (Release Assets)
- **`boardest-class.appx`** / **`boardest.appx`**: 교실 전자칠판 Windows 정식 패키지 (`v5.3.3.0`)
- **`boardest-class.apk`** / **`boardest.apk`**: 교실 전자칠판 Android 정식 패키지 (`v5.3.3`)
- **`boardest-cloud.appx`**: 교실 클라우드 칠판(Cloud) Windows 네이티브 패키지 (`v5.3.3.0`)
- **`boardest-cloud.apk`**: 교실 클라우드 칠판(Cloud) Android 네이티브 패키지 (`v5.3.3`)
- **`bst-teacher.msi`**: 교사용 PC 데스크톱 PRO Windows 설치 프로그램 (`v5.3.3`)
- **`bst-teacher.apk`**: 교사용 모바일/태블릿 Android 패키지 (`v5.3.3`)
- **`BoardestCert.cer`**: Windows 패키지 서명 루트 인증서
