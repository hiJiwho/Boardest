# BRIEFING — 2026-11-01T04:18:00Z

## Mission
Investigate and analyze Issue Group 2 (전체적 기능 완성도 총점검: 수행평가 1~12반 실시간 동기화/미설치 반 비활성화, PPT 오버레이 COM 재시도/주 모니터 하단 독 표시, Class 자동 업데이트 .msix 매칭 및 Teacher 언인스톨러/시작 메뉴 등록)

## 🔒 My Identity
- Archetype: explorer
- Roles: Teamwork explorer (read-only investigation, code survey, architectural analysis)
- Working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2
- Original parent: 5f2157b5-ad8b-4304-bdf1-235163c68948
- Milestone: Issue Group 2 Survey & Proposal

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Do NOT modify source code files
- Output survey_report.md and handoff.md in working directory
- Return completion via send_message to 5f2157b5-ad8b-4304-bdf1-235163c68948

## Current Parent
- Conversation ID: 5f2157b5-ad8b-4304-bdf1-235163c68948
- Updated: 2026-11-01T04:18:00Z

## Investigation State
- **Explored paths**:
  - `apps/boardest_teacher/lib/services/assessment_service.dart`
  - `apps/boardest_teacher/lib/views/teacher_assessment_view.dart`
  - `apps/boardest/lib/services/assessment_service.dart`
  - `apps/boardest/lib/views/components/assessment_dialog.dart`
  - `apps/boardest/lib/views/components/bst_class_main_layout.dart`
  - `apps/boardest/lib/services/meal_call_service.dart`
  - `apps/boardest/boardest_ppt_overlay.cs`
  - `apps/boardest/lib/views/ppt_overlay_view.dart`
  - `apps/boardest/lib/services/update_service.dart`
  - `tools/installer/BoardestInstaller.cs`
  - `tools/installer/BoardestTeacherInstaller.cs`
  - `tools/installer/BoardestTeacherUninstaller.cs`
  - `tools/installer/build_installer.ps1`
  - `scripts/build_all_appx.ps1`
  - `scripts/publish_release_v543.js`
- **Key findings**:
  1. 수행평가: 교실의 30초 지연 폴링, RTDB `/eat_calls` 빈 결과 반환 시 1~12반이 전면 비활성화되어 교사의 공지 등록이 차단되는 심각한 Lockout 결함 발견.
  2. PPT 오버레이: `OleMessageFilter.RetryRejectedCall`이 `dwRejectType == 1`일 때 -1을 반환하여 `RPC_E_CALL_REJECTED` 유발 및 Standalone 모드 격하 발생. Grid Row 분할로 인해 InkCanvas가 화면 하단 80~100px를 가리지 못하는 판서 불가 버그 확인.
  3. Class 업데이트 & Teacher 시작메뉴: `UpdateService`가 에셋 순서에 따라 `.appx`를 매칭하여 `.msix`로 잘못 저장하는 결함 발견. `BoardestTeacherInstaller.cs` 및 `BoardestTeacherUninstaller.cs`가 `BoardestInstaller.cs`의 시작 메뉴 루트 등록 및 `SHChangeNotify` 로직과 불일치하는 상태 확인.
- **Unexplored areas**: None for Issue Group 2.

## Key Decisions Made
- Completed thorough analysis across all 3 sub-issues with line numbers and before/after code proposals.
- Documented all details in `survey_report.md` and `handoff.md`.

## Artifact Index
- DISPATCH.md — Dispatch log
- BRIEFING.md — Working memory
- progress.md — Heartbeat & status
- survey_report.md — Detailed survey & proposal report
- handoff.md — 5-component handoff report
