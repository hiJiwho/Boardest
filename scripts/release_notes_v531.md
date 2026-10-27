# Boardest v5.3.1 Official Release

## 🚀 주요 변경사항 및 개선 (What's New in v5.3.1)

### 1. 업데이트 감지 및 패키지 분리 정규화
- **패키지 에셋 명칭 변경 (`boardest-cloud`)**: 기존 `bcld.apk` / `bcld.appx`가 알파벳 정렬 순서로 인해 일반 `boardest` 업데이트 시 오감지되던 문제를 해결하기 위해 클라우드 전용 패키지 파일명을 **`boardest-cloud.apk`** 및 **`boardest-cloud.appx`**로 변경했습니다.
- **업데이트 에셋 엄격 분리**:
  - `Boardest Class Pro` (`jiwho.boardest.bst`)는 오직 `boardest.apk` / `boardest.appx`만 다운로드합니다.
  - `Boardest Class Cloud` (`jiwho.boardest.cloud`)는 오직 `boardest-cloud.apk` / `boardest-cloud.appx`만 다운로드합니다.
- **Windows AppX 내부 버전 동기화 (`5.3.1.0`)**: Windows `AppxManifest.xml` 4자리 버전 정규화(`5.3.1.0`)를 통해 Windows 설정 및 앱 내부에서 최신 버전(`5.3.1`)으로 정확히 인식됩니다.

### 2. 강제 업데이트 및 버전 차단 정책
- **6단계 이상 지연 또는 메이저 버전 변경 시 실행 차단**:
  - **Boardest Class**: `[업데이트 필수] 이 버전은 안전하지 않습니다. 다운로드 버튼을 눌러 다운받고 새로운 버전을 다운받으세요.` 안내와 함께 **[업데이트 다운 / 수동 설치 / 앱 런처 / 앱 삭제]** 4가지 필수 버튼 및 시스템 앱 실행을 보장합니다.
  - **Boardest Teacher**: 시작 시 신규 버전 알림을 제공하며, 6단계 이상 지연 시 `[업데이트 필수] 이 버전은 안전하지 않습니다. 새 버전의 msi 를 다운받아주시기 바랍니다. [다운로드 사이트 이동]` 안내 후 20초 카운트다운 뒤 자동 제거를 수행합니다.
- **Cloud 기능 3단계 지연 차단**: 릴리즈 기준 3차례 이상 뒤처진 경우 `"Cloud 기능을 사용하시려면 업데이트를 하시기 바랍니다."` 알림과 함께 Cloud 기능을 즉시 제한합니다.
- **Windows 비종료 AppX 업데이트**: 업데이트 다운로드 후 앱을 강제 종료하지 않고 Windows 패키지 설치 관리자(`explorer.exe`)를 호출하며, 업데이트 완료 후 재실행 시 이전 `.appx` 캐시를 자동 정리합니다.

### 3. TBP & HTML Present 통합 및 포인터(`.tbp.bst` / `.htmlp.bst`) 호환성 강화
- **통합 교안 생성기 (`TbpCreatorDialog`)**: 교안 생성 시 제목과 URL 입력 또는 파일 드래그 앤 드롭을 단일 모달에서 지원하며, 로컬에는 경량 포인터 파일(`.tbp.bst`)을 저장하고 실제 데이터는 Google Drive `bst-tbp`에 동기화합니다.
- **전 뷰어 포인터 해석 지원**: `TeacherView`, `CanvaBoardView`, `DashboardView`, `BstCloudModal`, `BoardestCloudView` 어디서든 `.tbp.bst` 및 `.htmlp.bst` 포인터 파일을 열면 `bst-tbp` 내 32자리 프로젝트 폴더와 판서/핫스팟 데이터를 즉시 복원합니다.
- **웹 환경 TBP 실행 차단 및 레거시 CRX 제거**: 웹 브라우저 환경에서는 TBP 로딩을 원천 차단하고, 더 이상 사용하지 않는 CRX 확장 프로그램 브릿지를 완전히 제거했습니다.

---

## 📦 다운로드 에셋 안내 (Release Assets)
- **`boardest.appx`**: 교실 전자칠판 Windows 정식 패키지 (`v5.3.1.0`)
- **`boardest.apk`**: 교실 전자칠판 Android 정식 패키지 (`v5.3.1`)
- **`boardest-cloud.appx`**: 교실 클라우드 칠판(Cloud) Windows 네이티브 패키지 (`v5.3.1.0`)
- **`boardest-cloud.apk`**: 교실 클라우드 칠판(Cloud) Android 네이티브 패키지 (`v5.3.1`)
- **`bst-teacher.msi`**: 교사용 PC 데스크톱 PRO Windows 설치 프로그램 (`v5.3.1`)
- **`bst-teacher.apk`**: 교사용 모바일/태블릿 Android 패키지 (`v5.3.1`)
- **`BoardestCert.cer`**: Windows 패키지 서명 루트 인증서
