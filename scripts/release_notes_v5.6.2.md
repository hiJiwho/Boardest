# 🚀 Boardest v5.6.2 Official Release [Must update]

보데스트(Boardest) 생태계의 교사용 Google OAuth2 인증 완벽 복구, 전 플랫폼 안정성 강화 및 40종 정식 배포 에셋 릴리즈 **v5.6.2 (`5.6.2+5620`, Package `5.6.2.0`)**가 공식 배포되었습니다.

---

### 1. 🎓 Boardest Teacher 교사용 구글 로그인 창 미오픈 버그 완벽 해결
- **Google OAuth2 루프백 서버 및 시스템 브라우저 연동 정상화**:
  - Windows 데스크톱 환경에서 Google OAuth2 인증 시 로컬 루프백 HTTP 서버(`127.0.0.1`) 포트 바인딩 및 IPv6/localhost 주소 해석 충돌 방지.
  - 시스템 기본 웹 브라우저(`url_launcher` / `Process.start`) 프로세스 핸들러를 안전하게 호출하여 인증 창이 열리지 않던 결함을 완벽히 해결.
  - OAuth2 콜백 리다이렉션 수신 후 인증 토큰 안전 교환 및 로컬 캐싱 복구.
- **초기 설정 마법사(Setup Wizard) UI 로딩 멈춤(Freeze) 해소**:
  - 교사용 앱 최초 구동 마법사(`TeacherSetupWizardView`)에서 비동기 인증 진행 상태(`isLoading`)가 멈추지 않고 적절한 타임아웃 및 예외 처리를 통해 즉시 해제되도록 안전성 확보.
- **교사용 메인 화면(TeacherView) 피드백 및 포커스 복원**:
  - Google 로그인 시도 중 시각적 피드백 제공 및 인증 완료 후 앱 창이 백그라운드로 밀려나지 않도록 Windows 포그라운드 포커스 복원 지원.

### 2. 📱 학생용 앱(Boardest Student) 정합성 및 테스트 완벽화
- **위젯 테스트 복구**:
  - `BoardestStudentApp`의 메인 위젯 테스트 규격을 일치화하여 CI/CD 회귀 검증 통과.
- **수행평가(Assessment) RTDB 실시간 정합성 동기화**:
  - 학교 코드 및 세션 키 정규화(`school_key_normalization`) 스트레스 테스트 통과 및 Realtime Database 실시간 데이터 구조 정합성 검증 완료.

### 3. ⚡ 시스템 성능 및 UI 반응성 최적화
- **Windows 시스템 테마 악센트 컬러 조회 최적화**:
  - 레지스트리 쿼리(`reg query`) 및 DWM 컬러 팔레트 조회 빈도를 캐싱하여 반복적인 쉘 프로세스 호출 오버헤드 제거 및 UI 렌더링 지연 방지.

### 4. 📦 전 플랫폼 빌드 및 40종 공식 릴리즈 에셋 배포
- **Windows 데스크톱 패키지**:
  - Modern MSIX 4종 (`boardest.msix`, `boardest-cloud.msix`, `boardest-class-lite.msix`, `bst-overlay-panser.msix`)
  - WiX v3.11 Enterprise MSI 2종 (`boardest-teacher.msi`, `bst-teacher.msi`)
  - Standalone Portable ZIP 3종 (`boardest-windows.zip`, `boardest-teacher-windows.zip`, `bst-teacher-windows.zip`)
  - C# WebView2 통합 온라인 인스톨러 및 13종 앱 설치 도구 (`boardest-installer.exe`, `installer.exe`, `uninstall.exe` 등)
- **Android 모바일 APK 6종**:
  - `boardest.apk` (Class Pro)
  - `boardest-cloud.apk` (Class Cloud)
  - `boardest-teacher.apk` & `boardest-teacher-lite.apk` (Teacher Pro & Lite)
  - `boardest-class-lite.apk` (Classroom Launcher & BoardCast)
  - `boardest-student.apk` (Student Portal)
- **보안 서명 인증서**:
  - 모든 Windows 실행 파일, MSI, MSIX 및 Android APK에 SHA256 공식 인증서 및 릴리즈 키스토어 디지털 서명 완료.
