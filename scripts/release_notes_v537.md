# 🚀 Boardest v5.3.7 Official Release

## 🌟 주요 업데이트 및 변경 사항

### 1. 🖥️ 전용 독립형 설치 마법사 3종 완전 분리 탑재
- **Boardest Class (`boardest-class-installer.exe`)**:
  - 서명된 최신 MSIX 패키지와 신뢰할 수 있는 루트 인증서(`BoardestCert.cer`)를 내장한 독립형 패키지.
  - 교실 전자칠판 환경에 최적화된 소개 UI(타이머, 식단, 판서, 시간표) 및 설치 여부 확인 후 자동 설치.
- **Boardest Class Cloud (`boardest-cloud-installer.exe`)**:
  - Cloud 전용 MSIX 패키지와 인증서를 내장하여 네트워크 제한 환경에서도 원클릭으로 설치 가능.
  - Google Drive 1초 QR 연동 및 TBP 전자교과서 원터치 뷰어 안내 소개 UI 탑재.
- **Boardest Teacher (`boardest-teacher-installer.exe`)**:
  - 교사용 PC 및 노트북 전용 초경량 온라인 설치 도구.
  - 최신 릴리즈 ZIP을 백그라운드로 자동 다운로드하여 설치하고, 전용 언인스톨러(`uninstall.exe`)를 자동 구성.

### 2. 🗑️ Teacher 전용 안전 삭제 마법사 (`uninstall.exe`) 탑재
- MSI가 아닌 독립형 설치 방식 전환에 맞춰 Windows "앱 및 기능" / "프로그램 추가/제거"에 정식 등록되는 WebView 기반 삭제 마법사를 도입했습니다.
- 실수로 인한 데이터 유실을 방지하기 위해 3단계 안전 확인 질문("진짜 지울건지 몇 번 확인") 및 수업 판서/교안 데이터 보존 옵션을 제공합니다.

### 3. ☁️ Boardest Cloud 잠금 및 폴더 검색 동기화 해결
- 버전 지연 카운터로 인해 구버전에서 Cloud 기능이 잠기던 문제를 해결하고 최신 `v5.3.7` 정합성을 확보했습니다.
- `BstCloudService`에서 `bst-tbp` 폴더 내 32자리 프로젝트 디렉터리를 정상 감지하도록 쿼리 조건을 개선했습니다.

### 4. 🌐 다운로드 페이지 단일화 & 웹 배포 정리
- 웹 다운로드 허브에서 혼란을 주던 직다운로드 버튼(`MSI 받기`, `MSIX 받기`, `원클릭 파워쉘`)을 정돈하고, 완성도 높은 전용 설치 프로그램(`.exe`) 중심으로 다운로드 환경을 간소화했습니다.
