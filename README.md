# 🏫 Boardest (보디스트) — All-in-One Smart School Platform

[![Release](https://img.shields.io/github/v/release/hiJiwho/Boardest?color=00F5D4&label=Latest%20Release)](https://github.com/hiJiwho/Boardest/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20Web%20%7C%20WhaleOS-7F5AF0)](https://welcome-to-boardest.web.app)
[![License](https://img.shields.io/badge/License-Proprietary-FACC15)](#)
[![AI Rules](https://img.shields.io/badge/AI_Rules-AGENT.md-00F5D4)](AGENT.md)

> **초·중·고 교실 전자칠판(교탁 PC), 교사용 디바이스, 학생 스마트 디벗을 잇는 차세대 올인원 스마트 교육 플랫폼**  
> **현재 시스템 버전**: `v5.5.0`  
> 🤖 **AI 에이전트 및 친구 개발자 협업 수칙**: 프로젝트 작업 전 반드시 [AGENT.md](AGENT.md)의 **Firebase 쿼터 제로 원칙** 및 **Git PR 가이드**를 준수해야 합니다.

---

## 🌟 Overview (개요)

**Boardest(보디스트)**는 수업 준비부터 교안 판서, 실시간 시간표 연동, Google Drive 클라우드 보관함, 학내 급식 지도 및 수행평가 관리까지 학교 현장의 모든 상호작용을 하나로 융합한 **스마트 스쿨 통합 솔루션**입니다.

- 🖥️ **전자칠판 메인 (`apps/boardest`)**: 교과서 좌측 밀착, 상시 전고 롱-사이즈 수업도구 독, 전용교실 교과/반 대형 강조, PDF/PPT/Canva 실시간 판서, TBP 디지털 교과서 런처, 실시간 수행평가 캘린더 연동.
- 👩‍🏫 **교사용 통합 앱 (`apps/boardest_teacher`)**: 초대형 카드 그리드 & 리스트 토글 탐색기, 확장자별 원클릭 필터, 실시간 급식 호출 및 쪽지 전송.
- 🎒 **학생용 포털 (`apps/boardest_student`)**: 학교 디벗(크롬북/웨일북/태블릿) 및 스마트폰 최적화, 수행평가 D-Day 캘린더, 시간표, 급식표, 우리 반 알림장 열람.
- 🧩 **인앱 HTML 플러그인 생태계 (`packages/boardest_plugin_cli`)**: HTML/CSS/JS 기반의 미니앱을 제작하고 교실 도구함(시스템 앱)에 바로 추가할 수 있는 플러그인 스토어 엔진.
- 🔐 **초호환 3원화 인증**: Web QR 모바일 1초 승인(기본) + 6자리 Stegano OTP 가상 키패드 + `boardest-cloud.web.app` Passkey 생체인증.
- ⚡ **영구 인증서 & 원클릭 설치**: 2999년까지 유효한 자체 코드 서명 인증서와 PowerShell 원클릭 설치 지원.

---

## 🤝 AI 에이전트 및 친구 협업 가이드 ([AGENT.md](AGENT.md))

AI 코딩 어시스턴트(Antigravity, Cursor, Claude Code, GitHub Copilot 등)를 활용하여 프로젝트를 개발하거나 친구와 함께 작업할 때는 [AGENT.md](AGENT.md)에 기술된 규칙을 따릅니다:

1. **🔥 Firebase 할당량 초절약 (Zero-Waste)**:
   * Firestore 주기적 쿼리 및 전체 스캔 절대 금지!
   * 실시간 통신(급식 호출, 출석, 수행평가)은 무조건 RTDB(`jiwhosboardest-default-rtdb.firebaseio.com`) 사용.
   * 교실 출석은 앱 시작 시 **1회만** 기록하며, 교사는 **24시간 이내** 신호를 온라인으로 인식합니다.
2. **🌿 Git 브랜치 전략**:
   * `main` 브랜치 직접 푸시 금지. `feature/student-*` 브랜치 작업 후 GitHub PR로 머지합니다.
3. **💡 학생용 앱 전담 미션**:
   * 친구의 AI는 친구에게 학교생활에 필요한 창의적인 아이디어(익명 건의함, 롤링페이퍼 등)를 먼저 묻고 함께 기능을 발전시킵니다.

---

## 🚀 Quick Start & Installation (빠른 설치 및 이용)

### 🪟 Windows 설치 가이드 (2단계 분리 설치)

#### 1단계: 영구 서명 인증서 설치 (최초 1회 필수)
PowerShell을 열고 아래 명령어를 입력하여 2999년 영구 보안 서명 인증서를 등록합니다:
```powershell
irm https://download-boardest.web.app/win-cer.ps1 | iex
```

#### 2단계: 원하는 AppX 설치
인증서 등록 후, 웹사이트([welcome-to-boardest.web.app](https://welcome-to-boardest.web.app))에서 다운로드하거나 PowerShell에서 설치합니다:
```powershell
# 전자칠판 메인 (Boardest) 설치
Add-AppxPackage -Path .\boardest.appx

# 또는 교사용 (Boardest Teacher) 설치
Add-AppxPackage -Path .\bst-teacher.appx
```

---

## 📱 학생용 앱 (`apps/boardest_student`) 로컬 개발
```bash
cd apps/boardest_student
flutter pub get
flutter run -d chrome  # 디벗/웹 브라우저 테스트
```

## 🧩 플러그인 제작 CLI (`packages/boardest_plugin_cli`)
```bash
node packages/boardest_plugin_cli/bin/cli.js init my-plugin
cd my-plugin
node ../packages/boardest_plugin_cli/bin/cli.js dev
```

---

## 🌐 Live Web Ecosystem (웹 서비스 전체 안내)

| 서비스 명칭 | 공식 접속 URL | 주요 기능 |
|---|---|---|
| **🌐 공식 온보딩 포털** | [welcome-to-boardest.web.app](https://welcome-to-boardest.web.app) | 접속 기기(OS) 자동 감지 맞춤형 설치 안내 & 제품 기능 소개 |
| **🖥️ 전자칠판 Web** | [boardest.web.app](https://boardest.web.app) | 3:2 대시보드, PDF/판서 뷰어, 클라우드 탐색기 |
| **👩‍🏫 교사용 통합 Web** | [boardest-teacher.web.app](https://boardest-teacher.web.app) | 38:62 2분할 통합 도구 & Google Drive 파일 관리 |
| **📱 교사용 라이트 (PWA)** | [boardest-teacher-lite.web.app](https://boardest-teacher-lite.web.app) | 스마트폰/태블릿 최적화 모바일 웹앱 (급식 호출 & OTP & 클라우드) |
| **🔐 교사 계정 & 시크릿 허브** | [boardest-teacher-oauth.web.app](https://boardest-teacher-oauth.web.app) | Google OAuth 2.0 PKCE 인증 및 보안 시크릿 키 관리 |

---

## 📄 License & System Knowledge

- 자세한 개발 규칙 및 세부 아키텍처는 [AGENT.md](AGENT.md)를 참조하십시오.
- 버전별 상세 변경 내역은 [Ver.md](Ver.md)에서 확인하실 수 있습니다.
- Copyright © 2026 **hiJiwho / Boardest Platform**. All rights reserved.
