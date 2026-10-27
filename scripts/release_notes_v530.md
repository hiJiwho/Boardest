# 🚀 Boardest v5.3.0 Release Notes

보데스트(Boardest) v5.3.0 정식 릴리즈 안내입니다.

---

### 1. 🛡️ 보안 잠금 및 강화된 업데이트 정책 (Class & Teacher)
- **버전 래그(Lag) 카운팅 체계**: GitHub Releases API를 기준으로 4번째 자리 패치는 1개의 릴리즈로 합산 카운트
- **강제 실행 차단**: 메이저(Major) 버전 변경 또는 6차례 이상 릴리즈가 지연된 경우 앱 실행을 안전하게 차단
- **Cloud 기능 선별 차단**: 3차례 이상 업데이트가 지연된 경우 Cloud 기능 사용 제한 안내
- **차단 화면 4대 필수 기능 제공**:
  1. `[업데이트 다운]`: 최신 설치 패키지 자동 다운로드
  2. `[수동 설치]`: 다운로드 허브 사이트로 즉시 이동
  3. `[앱 런처]`: 앱이 차단된 상태에서도 기기에 설치된 외부 교육용 앱을 실행할 수 있는 비상 런처 모달
  4. `[앱 삭제]`: 기기에서 앱을 안전하게 삭제(Uninstall)
- **Windows 무중단 패키지 설치 관리자(App Installer) 연동**:
  - 앱을 강제 종료(`exit(0)`)하지 않고 Windows 공식 앱 설치 관리자 GUI 실행
  - 새 버전 실행 시 AppData의 구버전 설치 임시 파일 자동 소거
- **Boardest Teacher**:
  - 일반 업데이트: 방해 없는 상단 알람 제공 (누르면 다운로드 페이지 이동)
  - 긴급 차단: 20초 카운트다운 후 자동 앱 삭제 및 종료 안내

### 2. ☁️ 독립형 Boardest Class Cloud (`bcld`) 100% Native Flutter 출시
- 웹뷰(WebView) 래퍼가 아닌 **순수 Flutter 네이티브 엔진** 기반 독립 패키지
- **`bcld.apk`** (`applicationId: jiwho.boardest.cloud`): 시간표/부팅 등록 없는 교실 수업자료/QR 패스키 전용 앱
- **`bcld.appx`**: Windows 전자칠판용 독립 패키지. 로컬 PPT 연동 및 투명 슬라이드쇼 판서 오버레이 지원
- **QR 패스키 학교 ID 검증 체계 고도화**:
  - `bcld`: 학교 정보 기입 없이 즉시 접속 가능
  - `Boardest Class`: 전자칠판에 설정된 학교 ID와 교사의 학교 ID가 다를 경우 즉시 차단

### 3. 📐 TBP & HTML Present 통합 생성기 (`TbpCreatorDialog`)
- **생성 UI 통합**: 전자교과서(TBP)와 HTML Present(Canva 등) 교안을 단일 모달에서 손쉽게 생성
- **대상 학년 제거**: 불필요한 학년 선택 과정을 제거하고 제목 및 Web URL 직접 기입
- **원터치 드래그 앤 드롭 업로드**: `.tbp`, `.htmlp`, `.save`, `.bst` 파일 드롭 지원
- **32자리 고유 ID 아키텍처**:
  - 실체 프로젝트 데이터는 Google Drive `bst-tbp/{32자리 ID}`에 보관
  - 포인터 껍데기 파일(`.tbp.bst`, `.htmlp.bst`)을 `bst-save` 및 로컬에 저장하여 파일 관리에서 즉시 확인 가능

### 4. 🔑 Google Drive 토큰 안정성 및 세션 지속성 강화
- 일시적 400 에러 시 리프레시 토큰이 영구 삭제되던 결함 수정
- 전자칠판 패스키 세션 승인 직전 최신 Access Token 강제 갱신으로 401 권한 오류 원천 차단
- Web 환경 CORS 우회를 위한 Firestore `teacher_cloud_tokens` 폴백 지원

### 5. 🌐 Web 버전 안정화 및 TBP 웹 로딩 차단
- Firebase Hosting 루트 도메인(`bcld.web.app`, `boardest-class.web.app`, `boardest-teacher.web.app`)에 맞춘 Base-href(`/`) 최신화 (Service Worker 및 Manifest 404 에러 해결)
- Web 환경에서의 TBP 로딩 차단 안내 다이얼로그 적용 (보안 및 네이티브 성능 보호)
- CRX(크롬 확장 프로그램) 패키징 완전 제외 및 다운로드 허브 리뉴얼
