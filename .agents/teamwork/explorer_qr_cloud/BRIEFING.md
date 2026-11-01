# BRIEFING — 2026-11-01T09:12:45Z

## Mission
Investigate Requirement 1: Class app QR Cloud connection failure (QR target URL, routing parameters, Cloud web/app redirection consistency).

## 🔒 My Identity
- Archetype: explorer
- Roles: teamwork_explorer
- Working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_qr_cloud\
- Original parent: 2ce30758-d6dd-41a8-b112-4ee17b3271df
- Milestone: Investigation & Root Cause Analysis

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Thorough code-level verification with exact file paths, line numbers, and changes needed
- Self-contained handoff.md report

## Current Parent
- Conversation ID: 2ce30758-d6dd-41a8-b112-4ee17b3271df
- Updated: 2026-11-01T09:12:45Z

## Investigation State
- **Explored paths**:
  - `database.rules.json`: Confirmed `cloud_pair_sessions` missing, verified live 401 Permission Denied via `Invoke-RestMethod`.
  - `apps/boardest/lib/services/bst_cloud_service.dart`: `createReversePairSession` and `waitForReversePairAuth`.
  - `apps/boardest/lib/services/passkey_service.dart`: `createChallengeSession` and `listenForApproval`.
  - `apps/boardest/lib/views/boardest_cloud_view.dart`, `bst_cloud_modal.dart`, `dashboard_view.dart`, `bst_cloud_passkey_modal.dart`, `bst_cloud_auth_modal.dart`.
  - `infra/cloud_connect_web/index.html`: QR scan handler, reverse pair & passkey approval flows.
  - `apps/boardest_teacher_oauth/index.html`: OAuth callback, route detection, `completeReversePairing`.
  - `firebase.json`: Hosting targets, rewrites, redirects, missing rewrites on `boardest-teacher-oauth`.
  - `apps/boardest_teacher_lite/lib/main.dart`: Bad URL `boardest-cloud-connect.web.app/edit`.
- **Key findings**:
  1. `database.rules.json` does not declare `cloud_pair_sessions`, causing all RTDB calls to return 401 Permission Denied.
  2. `apps/boardest_teacher_oauth/index.html` writes ONLY to Firestore and never writes to RTDB in `completeReversePairing`, while Class app only polls RTDB.
  3. `boardest-teacher-oauth` is missing `rewrites` in `firebase.json`, causing `/edit` and other routes to return `404.html` and clear all query parameters.
  4. Parameter name mismatch (`teacher` vs `teacherName`, missing `email`/`refreshToken` extraction).
  5. Missing Google login fallback in `cloud_connect_web/index.html` for Passkey QR.
  6. Bad domain `boardest-cloud-connect.web.app/edit` in `boardest_teacher_lite`.
- **Unexplored areas**: None.

## Key Decisions Made
- Fully documented root causes and formulated precise file-by-file patch strategy.

## Artifact Index
- DISPATCH.md — Dispatch log
- progress.md — Liveness & progress tracking
- BRIEFING.md — Situational memory
- handoff.md — Complete investigation report
