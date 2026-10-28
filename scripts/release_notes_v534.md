# Boardest v5.3.4 Official Release

## 🚀 주요 변경사항 및 개선 (What's New in v5.3.4)

### 1. 교실 앱 급식 & 수행평가 5:5 완벽 분할 UI 탑재
- **1일 급식 카드 (50%)**:
  - 상단 날짜 탐색(`[ < ] [ 🍱 오늘 점심 (토글) ] [ > ]`, 당월 벗어날 시 안내 메시지) 제공.
  - 넓어진 공간을 활용하여 메뉴명 옆에 알레르기 태그(`[난류]`, `[우유]`, `[대두]` 등)를 시원하게 표시.
  - 급식 투표 안내 및 불필요 문구 완전 제거.
- **수행평가 공지 카드 (50%)**:
  - 마감 임박 순 4개 리스트(`[과목] [제목] [실시 날짜/교시] [D-Day 뱃지]`).
  - 터치 시 수행 범위, 세부 내용, 주의사항, 배점을 확인하고 수정/삭제 가능한 상세 모달 연동.
  - 상단 `[전체/달력]` 버튼 & 하단 `[➕ 수행평가 등록]` 버튼 탑재.

### 2. 교사용 앱 (`boardest_teacher`) 스마트 수행평가 다중 공지 & 인쇄 3종
- 사이드바 네비게이션에 `[📝 수행평가]` 전용 탭 신설 및 대시보드 연동.
- **동료 교사 시간표 연동 (피드백 반영)**: 동료 교사명 입력 시 두 교사의 시간표를 합산 분석하여 전 학급 수업이 가장 몰린 일정을 자동 계산 및 추천 배너 표출.
- **주간 달력 시각화 (Weekly Grid)**: 월~금 1~6교시 주간 시간표 테이블에 학급별 수업 배치 시각화 및 `[⏩ 다음 주로 미루기]` 버튼 제공.
- **3-Way 인쇄 / 내보내기**:
  1. **표준 학사 일정표 (Excel / CSV)**: 한글 깨짐 없는 UTF-8 BOM CSV 클립보드 복사
  2. **A4 1장 전 학급 요약본**: 교무실 게시판용 정돈된 요약 서식
  3. **반별 안내장**: 학생 배부 및 가정통신 첨부용 알림 서식
- **업데이트 알람**: 사이드바에 `[🚀 업데이트]` 항목 신설 및 새 버전 감지 시 네온 민트 'NEW' 펄스 뱃지 표시.

### 3. Windows Class Pro 업데이트 버그 수정
- `UpdateService`에서 `explorer.exe` 호출로 인해 문서(Documents) 폴더가 열리던 문제를 `Start-Process -FilePath '$escapedPath'`로 네이티브 App Installer GUI 직접 실행으로 수정.

### 4. Class Cloud (`bcld`) Windows 창틀 복원
- `TitleBarStyle.normal`, 창틀 및 최소화/최대화/닫기 버튼 복원.

### 5. Cloud 401 세션 만료 및 bst-save 로딩 멈춤 방지
- Google Drive 401 발생 시 `activeToken = null` 즉시 초기화를 방지하고 Firestore 최신 교사 토큰 자동 갱신 파이프라인(`_attemptTokenRefresh`) 적용.

---

## 📦 다운로드 에셋 안내 (Release Assets)
- **`boardest-class.appx`** / **`boardest.appx`**: 교실 전자칠판 Windows 정식 패키지 (`v5.3.4.0`)
- **`boardest-class.apk`** / **`boardest.apk`**: 교실 전자칠판 Android 정식 패키지 (`v5.3.4`)
- **`boardest-cloud.appx`**: 교실 클라우드 칠판(Cloud) Windows 네이티브 패키지 (`v5.3.4.0`)
- **`boardest-cloud.apk`**: 교실 클라우드 칠판(Cloud) Android 네이티브 패키지 (`v5.3.4`)
- **`bst-teacher.msi`**: 교사용 PC 데스크톱 PRO Windows 설치 프로그램 (`v5.3.4`)
- **`bst-teacher.apk`**: 교사용 모바일/태블릿 Android 패키지 (`v5.3.4`)
- **`BoardestCert.cer`**: Windows 패키지 서명 루트 인증서
