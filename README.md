# 🏫 Boardest (보디스트) — All-in-One Smart School Platform

[![Release](https://img.shields.io/github/v/release/hiJiwho/Boardest?color=00F5D4&label=Latest%20Release)](https://github.com/hiJiwho/Boardest/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20Web-7F5AF0)](https://welcome-to-boardest.web.app)
[![License](https://img.shields.io/badge/License-Proprietary-FACC15)](#)

> **초·중·고 교실 전자칠판(교탁 PC)과 교사용 디바이스를 잇는 차세대 올인원 스마트 교육 플랫폼**  
> **현재 시스템 버전**: `v2.9.9.5`

---

## 🌟 Overview (개요)

**Boardest(보디스트)**는 수업 준비부터 교안 판서, 실시간 시간표 연동, Google Drive 클라우드 보관함, 학내 급식 지도 및 쪽지 전송까지 학교 현장의 모든 상호작용을 하나로 융합한 **스마트 스쿨 통합 솔루션**입니다.

- 🖥️ **전자칠판 메인**: 3:2 비율의 시원한 시간표/교안 뷰어, PDF/PPT/Canva 실시간 판서, TBP 디지털 교과서 런처, 창을 닫아도 유지되는 안전한 교사 세션.
- 👩‍🏫 **교사용 통합 앱**: 38:62 2분할 통합 도구(시간표, 메모, QR 기기 관리, 폴더 맵핑) 및 Google Drive `bst-save` 전체 탐색기.
- 🍱 **독립 급식 지도 웹앱**: 1~9급식실 실시간 호출, 학년 일괄 호출, 웹 오디오 차임벨, 전자칠판 즉시 쪽지 전송 (`?schoolCode=ydm` 쿼리스트링 지원).
- 🔒 **Zero-Trust 보안**: 훔쳐보기(Shoulder Surfing) 원천 차단 6자리 동적 자릿수 셔플(Steganography) OTP 및 QR 무선 자동 등록.
- ⚡ **영구 인증서 & 원클릭 설치**: 2999년까지 유효한 자체 코드 서명 인증서와 PowerShell 원클릭 설치 지원.

---

## 🚀 Quick Start & Installation (빠른 설치 및 이용)

### 🪟 Windows 설치 가이드 (2단계 분리 설치)

#### 1단계: 영구 서명 인증서 설치 (최초 1회 필수)
PowerShell을 열고 아래 명령어를 입력하여 2999년 영구 보안 서명 인증서를 등록합니다. (앱 설치와 완전히 분리되어 인증서만 깔끔하게 등록됩니다)
```powershell
irm https://download-boardest.web.app/win-cer.ps1 | iex
```

#### 2단계: 원하는 앱 설치 (온라인 AppInstaller 권장 ⭐⭐⭐⭐⭐)
인증서 등록 후, 웹사이트([welcome-to-boardest.web.app](https://welcome-to-boardest.web.app))에서 다운로드하거나 PowerShell에서 설치합니다:
```powershell
# 전자칠판 메인 (Boardest) 설치
Add-AppxPackage -AppInstallerFile https://download-boardest.web.app/bst.appinstaller

# 또는 교사용 (Boardest Teacher) 설치
Add-AppxPackage -AppInstallerFile https://download-boardest.web.app/bst-teacher.appinstaller
```

> [!TIP]
> **온라인 AppInstaller vs 오프라인 .appx 안내**
> - **AppInstaller (온라인 자동 갱신 권장)**: 앱 실행 시 백그라운드에서 GitHub 최신 버전으로 자동 무인 업데이트됩니다.
> - **.appx (오프라인 패키지)**: 인터넷이 차단된 교내 보안망/폐쇄망 환경의 교실 PC를 위한 독립형 패키지입니다.

---

### 📥 공식 다운로드 직통 URL (`download-boardest.web.app`)
브라우저 주소창이나 다운로드 버튼 클릭 시 GitHub 최신 릴리즈(`latest`) 파일로 자동 연결됩니다:

| 다운로드 항목 | 직통 URL (Latest 302 리다이렉트) | 설명 |
|---|---|---|
| **🔑 영구 서명 설치 스크립트** | [`https://download-boardest.web.app/win-cer.ps1`](https://download-boardest.web.app/win-cer.ps1) | 인증서 전용 원클릭 PowerShell 스크립트 |
| **🔑 영구 보안 인증서 파일** | [`https://download-boardest.web.app/bst.cer`](https://download-boardest.web.app/bst.cer) | 2999-12-31 만료 영구 자체 서명 인증서 (.cer) |
| **🪟 전자칠판 AppInstaller** | [`https://download-boardest.web.app/bst.appinstaller`](https://download-boardest.web.app/bst.appinstaller) | Windows 자동 업데이트 온라인 설치기 |
| **👩‍🏫 교사용 AppInstaller** | [`https://download-boardest.web.app/bst-teacher.appinstaller`](https://download-boardest.web.app/bst-teacher.appinstaller) | 교사용 PC 자동 업데이트 온라인 설치기 |
| **📦 전자칠판 .appx** | [`https://download-boardest.web.app/bst.appx`](https://download-boardest.web.app/bst.appx) | 폐쇄망/오프라인 수동 설치 패키지 |
| **📦 교사용 .appx** | [`https://download-boardest.web.app/bst-teacher.appx`](https://download-boardest.web.app/bst-teacher.appx) | 폐쇄망/오프라인 수동 설치 패키지 |
| **📱 안드로이드 APK** | [`https://download-boardest.web.app/bst.apk`](https://download-boardest.web.app/bst.apk) | 전자칠판/태블릿 전용 설치 파일 |

---

## 🌐 Live Web Ecosystem (웹 서비스 전체 안내)

브라우저만 있으면 모든 플랫폼(Windows, Mac, ChromeOS, iPad, Android)에서 별도의 설치 없이 즉시 이용할 수 있습니다:

| 서비스 명칭 | 공식 접속 URL | 주요 기능 |
|---|---|---|
| **🌐 공식 온보딩 포털** | [welcome-to-boardest.web.app](https://welcome-to-boardest.web.app) | 접속 기기(OS) 자동 감지 맞춤형 설치 안내 & 제품 기능 소개 |
| **🖥️ 전자칠판 Web** | [boardest.web.app](https://boardest.web.app) | 3:2 대시보드, PDF/판서 뷰어, 클라우드 탐색기 |
| **👩‍🏫 교사용 통합 Web** | [boardest-teacher.web.app](https://boardest-teacher.web.app) | 38:62 2분할 통합 도구 & Google Drive 파일 관리 |
| **📱 교사용 라이트 (PWA)** | [boardest-teacher-lite.web.app](https://boardest-teacher-lite.web.app) | 스마트폰/태블릿 최적화 모바일 웹앱 (급식 호출 & OTP & 클라우드) |
| **🔐 교사 계정 & 시크릿 허브** | [boardest-teacher-oauth.web.app](https://boardest-teacher-oauth.web.app) | Google OAuth 2.0 PKCE 인증 및 보안 시크릿 키 관리 |

> [!NOTE]
> **배포 에러(0x80073D37) 해결 안내**
> 만약 이전에 설치된 플러그인 연결 충돌로 인해 `0x80073D37` 오류가 발생하는 경우, `irm https://download-boardest.web.app/win-cer.ps1 | iex`를 다시 실행하시거나 PowerShell에서 `Get-AppxPackage *overlaypanser* | Remove-AppxPackage`를 실행하시면 충돌이 즉시 해결됩니다.

---

## 🏗️ Architecture & Core Features (아키텍처 및 핵심 기능)

```
                                  ┌───────────────────────────────────────────┐
                                  │   Cloudflare Worker & Google Drive v3 API │
                                  └─────────────────────┬─────────────────────┘
                                                        │
              ┌─────────────────────────────────────────┼─────────────────────────────────────────┐
              ▼                                         ▼                                         ▼
┌──────────────────────────┐               ┌──────────────────────────┐               ┌──────────────────────────┐
│  전자칠판 메인 앱 (Web/Win)│               │    교사용 앱 (Web/Win)    │               │   독립 급식 지도 웹앱     │
│  (apps/boardest)         │               │  (apps/boardest_teacher) │               │ (infra/boardest_eat_web) │
├──────────────────────────┤               ├──────────────────────────┤               ├──────────────────────────┤
│ - 3:2 시간표:광고판 레이아웃│              │ - 38:62 통합도구:탐색기 분할│             │ - ?schoolCode=... 쿼리스트링│
│ - 창 닫아도 세션 영구 보존│               │ - Web PDF 바이트 직결    │               │ - 1~9 급식실 탭 & 학급 호출│
│ - PDF, PPT, Canva 판서   │               │ - QR 스캔 & 신뢰 기기 차단│              │ - 학년 일괄 호출/취소 & 쪽지│
│ - TBP 스마트 교과서      │               │ - 교과/반별 폴더 맵핑     │               │ - Web Audio 신디사이저 차임│
└──────────────────────────┘               └──────────────────────────┘               └──────────────────────────┘
```

1. **6자리 동적 자릿수 셔플 (Steganography) OTP**:
   - 2자리 Cloud ID + 4자리 RFC 6238 TOTP를 현재 시각($분 \pmod 5$)에 따라 동적으로 자릿수를 셔플하여 학생들이 보는 앞에서도 안전하게 로그인.
2. **전자칠판 3:2 황금 비율 & 세션 보존**:
   - 메인 대시보드를 **[지금 시간표 (flex: 3)] : [광고판 / Cloud / USB (flex: 2)]**로 단일화.
   - 클라우드 패널을 닫아도 `_hideCloudPanel` 플래그로 세션이 유지되어 번거로운 재인증 불필요.
3. **교사용 38:62 2분할 통합 도구 & Web PDF 완벽 지원**:
   - 좌측 38%에 시간표, 판서 메모, QR 기기 관리, 교과 폴더 맵핑을 일원화.
   - 우측 62%에 Google Drive `bst-save` 와이드 파일 브라우저 배치.
   - Web 환경에서 `kIsWeb` 메모리 바이트 직결 패턴을 적용하여 브라우저에서도 PDF 즉시 로드.
4. **독립 급식 지도 시스템 (`boardest-eat`)**:
   - URL 파라미터(`?schoolCode=ydm&cafeteria=1`)로 간편하게 북마크하고 1~9급식실을 실시간으로 관제.

---

## 🛠️ Developer Guide (개발 및 빌드)

```bash
# 1. 소스코드 복제
git clone https://github.com/hiJiwho/Boardest.git
cd Boardest

# 2. 패키지 설치
flutter pub get

# 3. Windows AppX 및 AppInstaller 패키징
powershell scripts/build_all_appx.ps1

# 4. Android APK 빌드
cd apps/boardest && flutter build apk --release

# 5. Firebase Hosting 전체 서비스 배포
firebase deploy --only hosting:welcome-to-boardest,hosting:download-boardest,hosting:boardest-eat,hosting:boardest-main,hosting:boardest-teacher,hosting:boardest-teacher-lite,hosting:boardest-teacher-oauth
```

---

## 📄 License & System Knowledge

- 자세한 시스템 아키텍처 및 세부 내부 구현 규격은 [AGENT.md](AGENT.md)를 참조하십시오.
- 버전별 상세 변경 내역은 [Ver.md](Ver.md)에서 확인하실 수 있습니다.
- Copyright © 2026 **hiJiwho / Boardest Platform**. All rights reserved.
