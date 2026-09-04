# BRIEFING — 2026-08-21T22:16:30+09:00

## Mission
Orchestrate comprehensive inspection, testing, bug fixes, and verification across the Boardest ecosystem (OAuth portal `boardest-teacher-oauth`, desktop/web apps `boardest_teacher` & `boardest_teacher_lite`, board app `boardest`, shared packages `bst_auth`, `bst_cloud`, `bst_timetable`, `bst_ui`, etc.).

## 🔒 My Identity
- Archetype: orchestrator
- Roles: orchestrator, user_liaison, human_reporter, successor
- Working directory: c:\Users\jiwho\Documents\boardest\.agents\orchestrator
- Original parent: parent
- Original parent conversation ID: 282fb07c-e81a-4c62-aafe-c27843cf28e7

## 🔒 My Workflow
- **Pattern**: Project Pattern
- **Scope document**: c:\Users\jiwho\Documents\boardest\PROJECT.md
1. **Decompose**: Survey codebase across apps/boardest, apps/boardest_teacher, boardest-teacher-oauth, packages/. Identify modules, bugs, risks, network/async safety gaps, and milestones.
2. **Dispatch & Execute**:
   - **Direct (iteration loop)**: Survey with parallel Explorers -> Merge feature inventory & milestones in PROJECT.md -> Dispatch milestone workers (Explorer -> Worker -> Reviewer -> Challenger -> Auditor).
3. **On failure**:
   - Retry -> Replace -> Skip -> Redistribute -> Redesign
4. **Succession**: Self-succeed at 16 spawns.
- **Work items**:
  1. Survey & Initial Audit Scan [in-progress]
  2. Milestone 1: OAuth portal & Auth / Cloud Token sync / OTP pairing (`boardest-teacher-oauth`, `bst_auth`, `bst_cloud`) [pending]
  3. Milestone 2: Teacher Desktop/Web apps & External integrations (`boardest_teacher`, `boardest_teacher_lite`, `bst_timetable`, NEIS, universal IO guards) [pending]
  4. Milestone 3: Electronic Board app (`boardest`, TBP engine, dHash page matching, .bstpen persistence, 3-mode canvas) [pending]
  5. Milestone 4: Test suites hardening, static analysis resolution, Ver.md changelog update [pending]
- **Current phase**: 0 (Survey)
- **Current focus**: Survey codebase via parallel specialists

## 🔒 Key Constraints
- Never write, modify, or create source code directly; delegate all implementation and commands to subagents.
- Never run build/test commands directly.
- Full integrity enforcement: no cheating, no dummy facades.
- Never reuse subagents after handoff.
- Pass flutter analyze without warnings/errors and pass test suites across all packages and apps.

## Current Parent
- Conversation ID: 282fb07c-e81a-4c62-aafe-c27843cf28e7
- Updated: 2026-08-21T22:16:30+09:00

## Key Decisions Made
- Initiating Project Pattern with Survey phase across 5 domain areas using parallel Explorers.

## Team Roster
| Agent | Type | Work Item | Status | Conv ID |
|-------|------|-----------|--------|---------|
| explorer_auth_oauth_cloud | teamwork_preview_explorer | Survey Auth, OAuth & Cloud Sync | completed | 998c007b-74c4-4cba-8401-d167f0500a3b |
| explorer_teacher_apps_external | teamwork_preview_explorer | Survey Teacher Apps & APIs | completed | 98118479-1a3c-4c17-b7e0-ebc05f28d51f |
| explorer_board_tbp_engine | teamwork_preview_explorer | Survey Board TBP & Canvas | completed | a3d4094c-d18b-43f6-941e-b4bd13d8cefa |
| explorer_shared_packages | teamwork_preview_explorer | Survey Shared Packages | completed | c3c80724-fea2-4e9b-a2dc-da84596c9a1d |
| worker_m1_packages | teamwork_preview_worker | Implement M1 Shared Packages & Tests | completed | 042510e6-269d-4cd4-ad20-7db4884e0277 |
| reviewer_m1_1 | teamwork_preview_reviewer | Review 1 for Milestone 1 | in-progress | 04d427a4-438e-4d6a-9655-df6f9321bf5f |
| reviewer_m1_2 | teamwork_preview_reviewer | Review 2 for Milestone 1 | in-progress | e354da51-bc5e-42bf-b11e-7a53efe4e40d |
| challenger_m1_1 | teamwork_preview_challenger | Stress Test 1 for Milestone 1 | in-progress | 42ac2ca2-11db-4b99-b1e4-510bd9852d75 |
| challenger_m1_2 | teamwork_preview_challenger | Concurrency Test 2 for Milestone 1 | in-progress | ceb00284-4377-45e9-a2dc-da84596c9a1d |
| auditor_m1 | teamwork_preview_auditor | Forensic Integrity Audit for Milestone 1 | in-progress | 8c2a2e73-d018-4802-be9c-922c89d50c2d |

## Succession Status
- Succession required: no
- Spawn count: 11 / 16
- Pending subagents: 04d427a4-438e-4d6a-9655-df6f9321bf5f, e354da51-bc5e-42bf-b11e-7a53efe4e40d, 42ac2ca2-11db-4b99-b1e4-510bd9852d75, ceb00284-4377-45e9-a2dc-da84596c9a1d, 8c2a2e73-d018-4802-be9c-922c89d50c2d
- Predecessor: none
- Successor: not yet spawned

## Active Timers
- Heartbeat cron: 5b553c4b-47d7-462b-ae55-1cabb38236d4/task-47
- Safety timer: none

## Artifact Index
- c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md — Original User Request
- c:\Users\jiwho\Documents\boardest\.agents\orchestrator\DISPATCH.md — Dispatch instructions
- c:\Users\jiwho\Documents\boardest\.agents\orchestrator\BRIEFING.md — Situational memory
- c:\Users\jiwho\Documents\boardest\.agents\orchestrator\progress.md — Liveness & progress tracking
- c:\Users\jiwho\Documents\boardest\PROJECT.md — Master project architecture & milestones

