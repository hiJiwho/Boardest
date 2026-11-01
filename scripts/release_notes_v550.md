# 🚀 Boardest v5.5.0 Official Ecosystem Overhaul Release

보데스트(Boardest) 대규모 전사 생태계 개편 릴리즈 **v5.5.0 (`5.5.0+5500`)**가 공식 배포되었습니다.  
이번 릴리즈에서는 전자저작물(TBP) 뷰어, Canva 연동, PPT 오버레이 COM 컨트롤러, QR 클라우드 세션, 안드로이드 업데이트 루프 차단, 수행평가 1~12반 공지 관리 등 25대 핵심 구성요소에 대한 전면 정밀 점검 및 리팩토링이 완료되었습니다.

---

## ✨ 25대 핵심 구성요소 전면 점검 및 개선 내역 (`C01` ~ `C25`)

### 1. 📖 전자저작물(TBP) 및 캔바(Canva) 뷰어 완벽화 (`C01`, `C02`, `C03`, `C04`)
- **1536px 네이티브 가상 배율 뷰포트**: 어떤 디스플레이 해상도에서도 왜곡 없이 1536px 원본 종횡비와 선명한 폰트 렌더링 동기화.
- **교실 격리형 판서 저장 체계**: `[교실ID]dhash.pen` (예: `기본_dhash.pen`, `[2반]dhash.pen`) 파일 규격 적용 및 0ms 인메모리 캐시 복구 지원.
- **페이지 2장 건너뜀 원천 차단**: 캡처 단계 키보드 이벤트 인터셉트 및 350ms 네비게이션 쿨다운을 통해 빠른 페이지 이동 시 판서 유실 및 중복 이벤트 완벽 억제.
- **Canva DOM 슬라이드 카운터 정규식 추적**: `_sendVirtualKey` 미정의 오류 제거 및 `view?embed` 변환과 현재 슬라이드 번호 추출 고도화.

### 2. 📊 수행평가 다중 공지 및 학사 관리 고도화 (`C09`, `C10`)
- **1~12반 전면 노출 및 미설치반 비활성화**: 교사앱에서 등록한 수행평가가 모든 반(1~12반)에 유연하게 다중 공지되며, 미설치 반은 비활성화 처리.
- **엄격한 학급 간 데이터 격리**: 타 학급의 수행평가 및 교실 데이터가 혼입되지 않도록 교실 ID 기반의 엄격한 데이터 파티셔닝 적용.
- **초저지연 듀얼 SSE 동기화**: Firebase Realtime Database와 SSE 채널을 이중화하여 50ms 미만 지연시간으로 실시간 갱신.

### 3. 🖥️ 파워포인트(PPT) & HWP 투명 판서 오버레이 (`C15`, `C16`)
- **COM `IOleMessageFilter` 10초 자동 재시도**: PowerPoint 슬라이드쇼 전환 중 비지(Busy) 상태 발생 시 `0x80010001 (RPC_E_CALL_REJECTED)` 예외 없이 10초간 자동 지연 재시도(`dwRejectType == 1, 2`).
- **전체 화면 풀 캔버스 판서**: 하단 80~100px 마스킹 문제를 해결하여 화면 100% 전 영역에서 끊김 없는 풀스크린 잉킹 지원.

### 4. ☁️ 모바일 QR 클라우드 접속 무기록(Zero-Persistence) 복구 (`C18`, `C19`)
- **RTDB `cloud_pair_sessions` 보안 규칙 정식 반영**: 스마트폰으로 QR 스캔 시 Firebase RTDB 권한 오류(401) 없이 1초 원터치 Google 로그인 및 칠판 연결 복구.
- **Zero-Persistence 보안 원칙**: 로컬 스토리지에 토큰을 저장하지 않고 전자칠판 RAM으로만 1회성 세션을 안전하게 전달.

### 5. 🤖 안드로이드 무한 업데이트 안내 루프 원천 차단 (`C20`, `C22`)
- **네이티브 PackageInfo 동기화**: `MainActivity.kt` MethodChannel(`getAppVersion`)을 통해 실제 설치된 APK의 `versionName`을 실시간 감지하여 Dart-Android 버전 불일치 제거.
- **내장 `assets/version.json` 번들링**: 빌드 번들과 일치하는 버전 매니페스트를 제공하여 업데이트 직후 다시 업데이트 안내가 뜨는 무한 루프 버그 원천 해결.

### 6. 🕒 시간표 및 급식/수업 도구 스위트 (`C05`~`C08`, `C11`~`C14`)
- **NEIS & 컴시간 시간표 엔진**: 교사별 시간표, 학급별 시간표 매핑 및 실시간 학사 일정 연동.
- **급식 식단표 및 알레르기 유발 정보**: HTML 태그 정제, 영양 정보 및 알레르기 번호 자동 필터링.
- **수업 보조 도구**: 타이머/스톱워치, 주사위/발표자 추첨, 스포트라이트/돋보기, 2분할/4분할 듀얼 보드 완비.

### 7. 📦 통합 패키징 및 설치/제거 프로그램 (`C21`, `C23`, `C24`, `C25`)
- **Unified Online Installer (BoardestInstaller.exe)**: WebView2 기반의 빠른 온라인 설치 및 v5.5.0 최신 패키지 자동 탐색.
- **Windows 시작 메뉴 루트 바로가기 복구 및 제거 마법사**: Teacher 앱이 시작 메뉴 'Boardest' 폴더 또는 루트에 정상 등록되고, 제거 시 잔여 파일을 완벽 클린업.
- **코드 사이닝 및 4단 세맨틱 버전**: MSIX 및 AppX 패키지 공식 서명 완료.

---

## 📦 배포 산출물 (Distribution Assets)
- `boardest-installer.exe` / `installer.exe` (Boardest 통합 온라인 빠른 설치기)
- `boardest.msix` / `boardest-class.msix` (전자칠판 순정 패키지)
- `boardest-cloud.msix` (수업자료 클라우드 전용 패키지)
- `boardest-class-lite.msix` (웹보드 전용 경량 패키지)
- `bst-teacher-windows.zip` / `boardest-teacher.msi` (선생님 교무실 PC 패키지)
- `Boardest-Teacher-Setup.exe` / `boardest-teacher-installer.exe`
- `boardest.apk` / `boardest-cloud.apk` / `boardest-class-lite.apk` (안드로이드 전자칠판 및 태블릿용)
- `BoardestCert.cer` (루트 서명 인증서)
