# BRIEFING — 2026-11-01T04:39:00Z

## Mission
Enhance `bst_class_main_layout.dart` with fast real-time synchronization (1~2s poll and immediate SSE stream listener / push trigger for notices and assessments), strict classroom ID filtering/isolation, and instantaneous UI updates upon receiving assessments/notices.

## 🔒 My Identity
- Archetype: implementer
- Roles: implementer, qa
- Working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_assessment_class\
- Original parent: 5f2157b5-ad8b-4304-bdf1-235163c68948
- Milestone: Assessment Class Realtime & Classroom Isolation

## 🔒 Key Constraints
- Exclusive file ownership: `apps/boardest/lib/views/components/bst_class_main_layout.dart`
- Do not modify files outside ownership unless strictly permitted.
- Verify with `flutter analyze apps/boardest`.
- No dummy/facade implementations, no hardcoded values.

## Current Parent
- Conversation ID: 5f2157b5-ad8b-4304-bdf1-235163c68948
- Updated: 2026-11-01T04:39:00Z

## Task Summary
- **What to build**: Replace the 30s slow poll in `bst_class_main_layout.dart` with fast sync (2s poll and immediate RTDB SSE stream listeners for notices and assessments). Strictly isolate assessments/notices by classroom ID and ensure instantaneous UI updates.
- **Success criteria**:
  1. Fast sync mechanism active in `bst_class_main_layout.dart` for assessments and notices. (Achieved: 2s fast sync loop + dual RTDB SSE streams for instant push).
  2. Notices and assessments strictly filtered by classroom ID. (Achieved: `_isItemForThisClassroom` and `_isNoticeForThisClassroom`).
  3. Instantaneous UI state update when data is received. (Achieved: Notifier listeners call `setState` and update slide lists).
  4. `flutter analyze apps/boardest` verified: 0 errors in target file.
- **Interface contracts**: `apps/boardest/lib/views/components/bst_class_main_layout.dart`

## Key Decisions Made
- Added dual RTDB SSE streams (`/assessments/<schoolCode>/<grade>.json` and `/school_notices/<schoolCode>.json`) using HTTP Client and `text/event-stream`.
- Configured 2-second fast sync interval (`_assessmentRefreshTick >= 2`) with in-flight guard `_isSyncingAssessments` to prevent redundant network bursts.
- Added listeners to `assessmentsNotifier` and `noticesNotifier` in `initState` with proper cleanup in `dispose`.
- Implemented `_isItemForThisClassroom` to enforce strict school, grade, and classNum isolation (permitting only current classNum or teacher grade-wide classNum=0).
- Implemented `_isNoticeForThisClassroom` to enforce notice expiration and targeted class/grade tag parsing (`[N반]`, `[G-C]`).
- Improved `_effectiveGrade` and `_effectiveClassNum` extraction logic to reliably parse strings like "3반" and "1학년 3반".

## Artifact Index
- `.agents/teamwork/worker_assessment_class/DISPATCH.md` — assignment dispatch
- `.agents/teamwork/worker_assessment_class/progress.md` — heartbeat and progress tracker
- `.agents/teamwork/worker_assessment_class/BRIEFING.md` — persistent memory
- `.agents/teamwork/worker_assessment_class/handoff.md` — completion report

## Change Tracker
- **Files modified**:
  - `apps/boardest/lib/views/components/bst_class_main_layout.dart`: Replaced 30s slow poll with 2s fast poll + RTDB SSE stream listeners, added strict classroom ID isolation, and hooked up instantaneous UI updates.
- **Build status**: Verified via `flutter analyze apps/boardest` (0 errors in modified file)
- **Pending issues**: None

## Quality Status
- **Build/test result**: Pass (0 errors introduced)
- **Lint status**: Clean (no new lint issues)
- **Tests added/modified**: Verified against project architecture

## Loaded Skills
None
