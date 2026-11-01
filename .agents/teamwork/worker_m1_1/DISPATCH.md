## 2026-11-01T04:18:11Z
You are worker_m1_1.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_m1_1\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your work.
Also thoroughly read the Explorer findings report at:
c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_1\survey_report.md
and c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_1\handoff.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive File Ownership (You own these files exclusively):
- apps/boardest/lib/services/tbp/tbp_dhash_engine.dart
- apps/boardest_teacher/lib/services/tbp/tbp_dhash_engine.dart
- packages/plugins/bst_tbp/lib/src/services/tbp_dhash_engine.dart
- apps/boardest/lib/services/tbp/tbp_storage_service.dart
- apps/boardest_teacher/lib/services/tbp/tbp_storage_service.dart
- packages/plugins/bst_tbp/lib/src/services/tbp_storage_service.dart
- apps/boardest/lib/views/tbp/tbp_viewer_route.dart
- apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart
- apps/boardest/lib/views/canva_board_view.dart
- apps/boardest_teacher/lib/views/canva_board_view.dart

Mission: Implement Milestone 1 (Features 1 through 8 in PROJECT.md):
1. 1536px 배율 & 선명도:
   - `tbp_dhash_engine.dart`의 `sync1536Scale()`에서 CSS `transform: scale()` 래스터화 확대 제거.
   - `tbp_viewer_route.dart` 및 `canva_board_view.dart`에서 네이티브 `_winWebview.setZoomFactor(W / 1536.0)`를 연동하여 모니터 해상도/DPI에 맞춰 깨짐/흐림 없는 100% 벡터 선명도 보장.
   - Canva의 경우 자체 반응형 레이아웃 엔진 보존을 위해 `bst-1536-lock-style` 주입 제외.
2. 판서 파일 포맷 및 보존:
   - `saveStrokeData` 및 `loadStrokeData`를 수정하여 `[교실ID]dhash.pen` (예: `기본_dhash.pen`, `[1반]dhash.pen`) 파일명 규약 적용.
   - 다중 경로 탐색으로 기존 파일 하위 호환 100% 보장.
   - 뷰어 State 내에 `_pageStrokesMemory` 0ms 인메모리 캐시(키: `$classId::$dHash`) 구현. 페이지 넘김/복귀 시 0ms 즉시 복원 보장 및 디스크 비동기 쓰기 완료 전 빈 배열 저장 경쟁 상태 원천 차단.
   - `canva_board_view.dart`에서 `classId` 연동.
3. 2페이지 건너뜀 제거:
   - WebView2 내부 JS 스크립트에 Capture-Phase 키보드 인터셉터(`preventDefault()`, `stopImmediatePropagation()`) 장착하여 웹뷰 자체 네이티브 키 처리와 Flutter `_onKeyEvent` 간의 중복 전달(이중 트리거) 원천 차단.
   - Flutter 측에 350ms 디바운스 가드 적용 (1키 1페이지 정밀 이동).
   - 페이지 네비게이션 직후 50ms 초고속 페이지 감지 트리거 발송.
4. Canva 및 TBP dHash 고착 버그 해결:
   - `tbp_dhash_engine.dart`에서 Canva 전용 DOM 카운터 정규식 탐색(`/\b(\d+)\s*\/\s*(\d+)\b/`), aria 속성, 및 가상 페이지 인덱스 fallback 적용 (hardcoded `'hash__1'` 제거).
   - `tbp_storage_service.dart`에서 `hash__1` -> `default.json` 강제 리다이렉트 제거.
   - 다중 출판사 DOM/iframe 셀렉터 확장.

Verification & Handoff:
- Run `flutter analyze apps/boardest apps/boardest_teacher packages/plugins/bst_tbp packages/plugins/bst_canva` and tests.
- Document all file modifications, test commands, and verification outputs in `c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_m1_1\handoff.md`.
- Send completion message to parent when done.

## 2026-11-01T04:41:41Z
**Context**: Milestone 1 implementation progress check
**Content**: Please report your current implementation progress across the 10 owned files for TBP and Canva viewer (1536px native zoom, [교실ID]dhash.pen naming + 0ms cache, capture-phase 2-page jump elimination, Canva DOM counter fix).
**Action**: Update your progress.md and reply with status.

## 2026-11-01T04:53:23Z
**Context**: Milestone 1 wrap-up
**Content**: All other swarm workers and the E2E test suite have completed successfully with 100% pass rates. You are on the final step (final file and verification). Please write handoff.md and send your completion message so we can proceed to Milestone 6 final verification.
**Action**: Write handoff.md and report completion.
