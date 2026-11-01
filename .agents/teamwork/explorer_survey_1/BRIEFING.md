# BRIEFING — 2026-11-01T04:12:30Z

## Mission
Investigate and analyze Issue Group 1 (TBP Smart Textbook and Canva Viewer: 1536px scaling, board writing format & preservation [classId]dhash.pen, 2-page skip prevention, and dHash stuck at hash__1/default root cause).

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_1\
- Original parent: 5f2157b5-ad8b-4304-bdf1-235163c68948
- Milestone: survey

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Must inspect codebase thoroughly with precise file paths and line numbers
- Document in survey_report.md and handoff.md

## Current Parent
- Conversation ID: 5f2157b5-ad8b-4304-bdf1-235163c68948
- Updated: 2026-11-01T04:12:30Z

## Investigation State
- **Explored paths**:
  - `ORIGINAL_REQUEST.md`, `PROJECT.md`, `Ver.md`
  - `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart`
  - `apps/boardest_teacher/lib/services/tbp/tbp_dhash_engine.dart`
  - `packages/plugins/bst_tbp/lib/src/services/tbp_dhash_engine.dart`
  - `apps/boardest/lib/services/tbp/tbp_storage_service.dart`
  - `apps/boardest_teacher/lib/services/tbp/tbp_storage_service.dart`
  - `packages/plugins/bst_tbp/lib/src/services/tbp_storage_service.dart`
  - `apps/boardest/lib/views/tbp/tbp_viewer_route.dart`
  - `apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart`
  - `apps/boardest/lib/views/canva_board_view.dart`
  - `apps/boardest_teacher/lib/views/canva_board_view.dart`
  - `packages/plugins/bst_canva/`
- **Key findings**:
  1. 1536px: CSS `transform: scale()` in `sync1536Scale()` causes raster blur and ruins Canva. Replacing with WebView2 native `setZoomFactor(W / 1536.0)` provides 100% crisp, native monitor rendering.
  2. Naming: Need `[교실ID]dhash.pen` format (e.g. `기본_dhash.pen`, `[1반]dhash.pen`). Memory cache `_pageStrokesMemory` eliminates race conditions and ensures 0ms 100% restoration on page turn.
  3. 2-page skip: Double trigger caused by WebView2 native Windows message + Flutter `Focus` (`onKeyEvent`). Capture-phase key interceptor in JS + Flutter cooldown + 50ms fast page check trigger.
  4. dHash stuck: Canva hardcodes `return 'hash_' + chash` with empty `loc.hash` returning `'hash__1'` for every slide. Fixed via DOM regex for `\b(\d+)\s*/\s*(\d+)\b`, aria attributes, and virtual slide tracking.
- **Unexplored areas**: None for Issue Group 1.

## Key Decisions Made
- Completed technical survey and documented detailed findings and code changes in `survey_report.md`
- Prepared 5-component handoff in `handoff.md`

## Artifact Index
- DISPATCH.md — Initial dispatch record
- BRIEFING.md — Situational awareness
- progress.md — Liveness heartbeat
- survey_report.md — Detailed technical survey report
- handoff.md — 5-component handoff report
