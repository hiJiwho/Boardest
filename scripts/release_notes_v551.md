# 🚀 Boardest v5.5.1 Official Release (버전 정합성 & 정예 에셋 배포)

보데스트(Boardest) 생태계의 교사용 앱 버전 동기화 개선 및 정예 에셋 배포 릴리즈 **v5.5.1 (`5.5.1+5510`)**가 공식 배포되었습니다.

---

### 1. 🎓 Boardest Teacher 버전 인식 및 최신 릴리즈 동기화 완전 정상화
- **Win32 독립 실행 환경 버전 오인식 수정**: MSIX 패키지 외 일반 Windows 경로(`%LOCALAPPDATA%` / `Program Files`) 설치 환경에서 실행 시 `5.4.3` 구버전으로 인식되던 문제를 `apps/boardest_teacher/lib/main.dart` 내 `UpdateService.initVersion()` 즉시 호출 및 기본 버전 정합(`5.5.1+5510`)으로 완벽히 해결.
- **TbpHotspotOverlay 컴파일 오류 수정 및 최신 바이너리 재빌드**: 캔버스 보드 내 핫스팟 핀 매개변수(`onHotspotTap`) 일치화 및 Windows Release 공식 바이너리 정합.

### 2. ⚡ 통합 온라인 설치 마법사 (`boardest-windows-installer.web.app`) 최신 버전 자동 감지 및 구버전 선택 옵션
- **구버전 인스톨러 내장 버전 자동 감지**: 과거에 배포되었거나 보관 중이던 구버전 설치 관리자(v5.4.3 등)를 실행했을 때 웹 마법사(WV)가 이를 즉시 감지하여 경고 배너를 표출합니다.
  - **안내 문구**: `이 인스톨러는 이전 버전의 설치로 제작 되었습니다.`
  - **사용자 선택 옵션**:
    - `[이 인스톨러에 저장된 안전하지 않은 버전 사용]`: 과거 바이너리를 그대로 설치하고자 하는 경우 선택
    - `[새 버전 사용 (추천)]`: 최신 보안 패치 및 안정성이 반영된 최신 v5.5.1을 즉시 다운로드하여 설치 (기본 권장)

### 3. 📦 정예 15종 공식 배포 에셋
- **온라인 설치기 (5종)**: `boardest-installer.exe` (통합), `boardest-class.exe`, `boardest-teacher.exe`, `boardest-class-lite.exe`, `boardest-cloud.exe`
- **교사용 정식 압축 패키지 (1종)**: `bst-teacher-windows.zip`
- **Windows 현대 패키지 MSIX (4종)**: `boardest.msix`, `boardest-class.msix`, `boardest-cloud.msix`, `boardest-class-lite.msix`
- **Android 모바일 APK (4종)**: `boardest.apk`, `boardest-cloud.apk`, `boardest-class-lite.apk`, `boardest-teacher-lite.apk` (Teacher는 Lite 버전)
- **보안 서명 인증서 (1종)**: `BoardestCert.cer`
