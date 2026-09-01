# 🏫 Boardest (보디스트) - Smart Teacher & Classroom Platform

> **스마트 교육을 위한 차세대 교사 데스크톱 & 전자칠판 통합 에듀테크 플랫폼**  
> **현재 버전**: `v2.9.8.1`

---

## 🌟 Overview (개요)

**Boardest**는 초·중·고등학교 선생님들과 학생들을 위한 최첨단 학교 전용 스마트 플랫폼입니다.  
수업 자료 준비, 실시간 컴시간 시간표 동기화, 급식실 학급 호출, TBP 교안 패키징, 전자칠판 판서 및 문서 뷰어, 클라우드 연동까지 학교 현장에 필요한 모든 솔루션을 단 하나의 생태계로 제공합니다.

---

## 🚀 Key Platforms & Download (플랫폼별 설치 및 이용)

### 💻 1. Windows 설치 (AppInstaller 기반 1클릭 무인 자동 업데이트)
Windows 10 / 11 환경에서는 **AppInstaller**를 통해 최초 1회 설치 후, 새로운 릴리즈가 출시되면 **앱 실행 시 백그라운드에서 자동으로 최신 버전으로 업데이트**됩니다.

#### 📌 최초 설치 방법
1. **GitHub Releases 최신 릴리즈** 페이지로 이동:  
   👉 [Boardest 최신 릴리즈 다운로드 (GitHub)](https://github.com/hiJiwho/Boardest/releases/latest)
2. **`install_certificate.bat`** 다운로드 및 실행:
   - 공개 서명 인증서가 내장되어 있어 우클릭 '관리자 권한으로 실행' 한 번으로 인증서가 자동 등록됩니다.
3. 원하는 앱의 **`.appinstaller`**를 다운로드하여 더블클릭:
   - **전자칠판 본체**: `boardest.appinstaller`
   - **교사용 리모컨**: `bst-teacher.appinstaller`
   - **판서 확장 도구**: `bst-overlay-panser.appinstaller` (앱 실행 시 자동 설치 지원)

---

### 📱 2. Android 전자칠판 / 스마트 TV / 태블릿 (APK)
- **다운로드**: [boardest.apk 다운로드](https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.apk)
- **자동 업데이트**: 앱 내에서 최신 버전을 감지하면 원클릭으로 덮어쓰기 업데이트가 즉시 진행됩니다.
- **최신 기기 지원**: Pixel 8 (Tensor 64비트 전용), Galaxy S22~S24, 전용 안드로이드 전자칠판 등 완벽 호환.

---

### 🌐 3. Web 버전 (클라우드 라이브)
브라우저만 있으면 별도의 설치 없이 즉시 실행할 수 있습니다:
- 🖥️ **전자칠판 Web**: [https://boardest.web.app](https://boardest.web.app)
- 👩‍🏫 **교사용 앱 Web**: [https://boardest-teacher.web.app](https://boardest-teacher.web.app)

---

## 🛠️ Developer Guide (개발 및 빌드)

### 프로젝트 클론 및 개발 시작
본 리포지토리는 보안을 위해 비공개 키(`.pfx`)를 제외한 전체 소스 코드가 포함되어 있습니다.
```bash
git clone https://github.com/hiJiwho/Boardest.git
cd Boardest
```
1. `certs/` 디렉토리에 서명 인증서(`BoardestCert.pfx`, 비밀번호: `Boardest2026!`)를 배치합니다.
2. 모든 플랫폼 원클릭 빌드 및 패키징:
   - **Windows AppX & AppInstaller**: `powershell scripts/build_all_appx.ps1`
   - **Android APK**: `cd apps/boardest && flutter build apk --release`
   - **Firebase Web Deploy**: `firebase deploy --only hosting:boardest-main,hosting:boardest-teacher`

---

## 🛡️ Security Architecture (보안 아키텍처)

1. **Windows AppContainer 샌드박스 & 디지털 서명**:
   - 모든 `.appx` 패키지는 신뢰된 코드 서명(`CN=jiwho`)으로 검증되며 무단 변조 시 실행 및 배포가 원천 차단됩니다.
2. **Android APK 패키지 무결성 보호**:
   - Android OS 레벨의 Keystore 서명 검증(`INSTALL_FAILED_UPDATE_INCOMPATIBLE`)으로 공식 서명과 일치하지 않는 위변조 APK 업데이트를 시스템 수준에서 차단합니다.
3. **Google Drive 보안 연동**:
   - `drive.file` 최소 권한 스코프만을 요청하여 교사의 개인정보 및 문서를 안전하게 격리 보관합니다.
