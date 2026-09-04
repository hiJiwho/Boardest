# Original User Request

## 2026-08-21T13:15:24Z

Boardest 에코시스템 전반(교사 OAuth 포털, 교사용 데스크톱/웹 앱, 전자칠판 앱, 중앙제어 시스템)의 모든 기능을 정밀 검토하고, 교사 로그인/계정 연동, Google Drive Cloud 동기화, 시간표, 판서, 급식 호출 등 핵심 연동을 철저히 테스트 및 완벽 개선합니다.

Working directory: c:/Users/jiwho/Documents/boardest
Integrity mode: development

## Requirements

### R1. 교사 인증 & 계정 연동 전면 점검 및 완벽화 (OAuth / Web / Desktop / Board)
- `boardest-teacher-oauth` 웹 포털의 Direct Google OAuth 2.0 흐름, 학교 ID 실시간 검증, 컴시간 교사 자동 매칭, 프로필 등록/수정/탈퇴(Revoke) 흐름의 무결성을 검증하고 연동 결함을 해결합니다.
- 교사용 앱(`boardest_teacher`, `boardest_teacher_lite`)과 전자칠판(`boardest`) 간의 구글 드라이브 토큰(`teacher_cloud_tokens`), OTP 6자리 핀코드 인증, 실시간 수업 자료 캐스팅 연동의 신뢰성을 검증하고 예외 처리를 보강합니다.

### R2. 교사용 데스크톱 & 웹(Lite) 전 기능 동작 및 예외 처리 개선
- 컴시간 실시간 시간표 연동(Cloudflare Worker 프록시 및 네이티브), NEIS 급식 호출 연동, 교내 메시징, 수업 도구 패널의 동작을 검증하고 플랫폼별 호환성을 보장합니다.
- Web/Desktop/Mobile 반응형 UI 및 비호환 네이티브 API 예외 처리(Universal IO 가드) 완결성을 확보합니다.

### R3. 전자칠판(Boardest Board) 판서 & 교안(TBP) 뷰어 엔진 점검
- Store Level 0 TBP 패키지 로딩, dHash 기반 페이지 매칭 및 `.bstpen` 판서 데이터 자동 저장/복원 로직을 검증합니다.
- 3모드 캔버스(마우스, 스마트, 주석) 터치/이벤트 통과 및 멀티 플랫폼(Web, Windows, Android) 구동 안정성을 검증합니다.

### R4. 전사 테스트 스위트 보강 및 자동화 검증
- 각 앱 및 공통 패키지(`bst_auth`, `bst_cloud`, `bst_timetable`, `bst_ui` 등)의 테스트 스위트를 검증 및 보강하고 전체 정적 분석 경고를 해결합니다.
- 작업 완료 후 시스템 변경 내역을 `Ver.md`에 최신 버전 명세로 상세히 기록합니다.

## Acceptance Criteria

### 인증 & 클라우드 연동
- [ ] Google OAuth 2.0 로그인 및 토큰 전달, Firestore 연동 과정에서 콘솔 에러 없이 정상 완료
- [ ] TOTP / 6자리 OTP 기반 전자칠판 원격 연동 로직 정상 통과 및 동기화 무결성 확보

### 시간표 & 데이터 연동
- [ ] 컴시간 및 NEIS 급식 API 데이터 파싱 및 시간표 계산 정상 동작
- [ ] Web 및 데스크톱 환경 모두에서 플랫폼 종속적 충돌 없이 실행

### 품질 & 안정성
- [ ] 주요 앱 및 패키지의 유닛/통합 테스트 스위트 통과
- [ ] `Ver.md`에 최신 변경 내역 및 버전 업데이트 명세 기록
