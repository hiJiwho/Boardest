# Boardest v5.3.5 Official Release

차세대 스마트 교실 및 교사용 올인원 플랫폼 **Boardest v5.3.5** 정식 릴리즈입니다.

### 🌟 주요 업데이트 내역

1. **교사용 기능 공식 런칭 & 파일명 공식 통일**
   - 교사용 Windows 설치 파일: `boardest-teacher.msi`
   - 교사용 Android Lite 설치 파일: `boardest-teacher-lite.apk` (수업 현장 이동성 최적화)
   - 교사용 Android Pro 설치 파일: `boardest-teacher.apk`
   - 이전 파일명(`bst-teacher.msi`, `bst-teacher.apk`, `bst-teacher-lite.apk`)과의 100% 하위 호환 유지

2. **수행평가 다중 등록 및 실시간 알람 시스템 고도화**
   - **반별 다중 일괄 등록**: 1반부터 8반까지의 수행평가 일정을 한 번에 공지 배포
   - **동료 교사 시간표 병합 & 주간 달력 히트맵**: 타 교과 수행평가 집중도를 분석하여 학생 부담이 적은 최적 일정 추천
   - **교실 전자칠판 실시간 알람 연동**: 급식 식단표 옆 수행평가 공지 카드에 `[오늘 수행!]`, `[내일 수행!]` 실시간 펄스 알람 뱃지 작동
   - 수행평가 포맷 정렬: `[과목] [제목] [실시 날짜/교시] [D-Day 뱃지]` 순서 표준화

3. **교실 클라우드 (BCLD) 교실 전용 보호 모드 & 창틀 탑재**
   - **교실 열람 전용 모드 (Read Only)**: 전자칠판에서 학생들의 임의 조작/삭제 방지를 위해 업로드 버튼을 제거하고 안전한 열람 및 판서 전용으로 전환
   - **창틀 유지**: Windows Class Cloud 앱에서 닫기/최소화/이동이 가능한 표준 창틀 지원
   - **TBP / PDF / Pen 완벽 지원**: 스마트 디지털 교과서(TBP / HTMLP), PDF 학습지, 수업 판서(형광펜, 지우개, 도형) 원터치 구동

4. **웹 포털 전면 리뉴얼 및 통합 안내/가이드 제공**
   - `boardest.web.app` 모던 글래스모피즘 디자인 전면 개편
   - `download-boardest` 다운로드 센터를 `boardest.web.app` 안내 페이지로 통합
   - 처음 사용하는 선생님을 위한 친절하고 상세한 6단계 교사 완벽 활용 가이드 수록
   - Windows 원클릭 파워쉘 설치기 (`bst-ins` / `bst-installer.web.app`) 완벽 유지
   - 베타 릴리즈 정리 및 정식 안정화 버전 단일화

---
### 📦 다운로드 및 설치 안내
- **교사용 Windows PC**: `boardest-teacher.msi`
- **교사용 모바일/태블릿**: `boardest-teacher-lite.apk`
- **교실 전자칠판 Windows**: `boardest.appx` (또는 PowerShell: `irm https://bst-ins.web.app/bst.ps1 | iex`)
- **교실 전자칠판 Android**: `boardest.apk`
- **교실 클라우드 전용(BCLD)**: `boardest-cloud.appx` / `boardest-cloud.apk`
