# 🏫 Boardest (보디스트) - Smart Teacher & Classroom Platform

> **스마트 교육을 위한 차세대 교사 데스크톱 & 전자칠판 통합 에듀테크 플랫폼**  
> **현재 버전**: `B 2.1.1`

---

## 🌟 Overview (개요)

**Boardest**는 초·중·고등학교 선생님들을 위한 최첨단 교사 전용 스마트 플랫폼입니다.  
수업 자료 준비, 실시간 컴시간 시간표 동기화, 급식실 학급 호출, TBP 교안 패키징, 전자칠판(Boardest Board) 미러링까지 학교 현장에 필요한 모든 솔루션을 단 하나의 앱으로 통합 제공합니다.

---

## 🚀 Key Features (주요 기능)

### 💻 1. Boardest Teacher (PC 교사용 앱)
- ⏰ **컴시간 실시간 시간표 Sync**: 학급/교과 시간표 및 실시간 교시(수업/쉬는시간/점심시간) 자동 계산.
- 🍱 **급식실 호출 & 모니터링**: 급식실 학급별 순서 호출 및 실시간 상태 동기화.
- 📁 **TBP 교안 패키저 (ZIP 0초 로딩)**: PPT, HWP, PDF, 동영상, Canva 자료를 단 하나의 `.tbp` 파일로 묶어 전자칠판으로 즉시 전송.
- 📺 **DriveCast 미러링**: 구글 드라이브 수업 자료를 전자칠판에 보안 연결하여 1초 만에 캐스팅.
- 🎥 **Video Studio & Canva Studio**: 동영상 구간 편집 및 Canva 100% 무인증 풀스크린 프레젠테이션.

### 🖥️ 2. Boardest Board (전자칠판 전용 앱)
- 🎨 **스마트 판서 & 8가지 핫스팟 오버레이**: 터치/펜/손가락 자동 감지 및 수업 도구 모음.
- ⚡ **0초 초고속 압축 해제**: TBP 대용량 수업 자료를 메모리 스트리밍 방식으로 딜레이 없이 즉시 오픈.
- 🌐 **Cross-Platform 지원**: Windows 및 Android(APK) 전자칠판 완벽 지원.

### ☁️ 3. Boardest Cloud (`bst-cld.web.app`)
- 🔒 **Google Drive Sync**: 선생님의 개인 Google Drive(`drive.file` 권한)와 연동하여 수업 자료 자동 백업.
- 🛡️ **User-Agent & HMAC 보안 연동**: 크롬 브라우저 남용 차단 및 앱 전용 WebView 위변조 방지.

---

## 🏗️ System Architecture (시스템 아키텍처)

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Boardest Ecosystem                              │
├──────────────────┬───────────────────┬─────────────────────────────────┤
│  Boardest Teacher│   Boardest Board  │       Boardest Web Cloud        │
│    (Windows)     │ (Windows / Android)│   (boadest / bst-cld / oauth)   │
└────────┬─────────┴─────────┬─────────┴────────────────┬────────────────┘
         │                   │                          │
         ▼                   ▼                          ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     Security & Update Infrastructure                   │
│  - GitHub Releases ECDSA/SHA-256 Code Signing                          │
│  - Update Validation Server (https://boardest-update-work.firebaseapp.com)│
│  - Single-Use Hash Fragment & Auto-Purge Session Store                 │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🛡️ Security & Privacy (보안 및 개인정보 보호)

1. **Hash Fragment & URL Address Bar Auto-Purge**:
   - OAuth 인증 시 주소창 쿼리 스트링(`?token=...`) 유출을 방지하기 위해 `#` Hash Fragment 사용.
   - 인증 완료 후 주소창 자동 클린화 및 `localStorage` 세션 즉시 완전 삭제(Auto-Purge).
2. **User-Agent Custom Signature**:
   - 앱 내부 WebView 접근 시 `User-Agent: Boardest-Teacher/1.0.0 (X-BST-SIG: ...)` 메타데이터를 검증하여 토큰 남용 차단.
3. **Electronic Signature Auto Update**:
   - `sign/` 폴더 내 개발자 개인키로 서명된 패키지(`release.sig`)만 업데이트 승인.
   - `boardest-update-work.firebaseapp.com` 루트 접근 시 **403 Forbidden** 방어.

---

## 💻 Console Verification (개발자 콘솔 버전 확인)

모든 웹 플랫폼(`boadest.web.app`, `bst-cld.web.app`, `oauth-helper`)의 Chrome DevTools 콘솔에서 아래 명령어를 실행하면 현재 버전을 확인할 수 있습니다:

```javascript
bst.ver()
// Output: "B 2.1.1"
```

---

© 2026 Boardest. All rights reserved.
