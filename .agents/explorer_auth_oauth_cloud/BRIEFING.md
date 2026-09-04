# BRIEFING — 2026-08-21T13:22:30Z

## Mission
Thoroughly explore, analyze, and diagnose:
1. `boardest-teacher-oauth` (Direct Google OAuth 2.0 flow, School ID verification, Comsigan teacher auto-matching, profile registration/edit/revoke).
2. `packages/bst_auth` and `packages/bst_cloud`.
3. Teacher cloud token sync (`teacher_cloud_tokens`), OTP 6-digit pin authentication, real-time lesson material casting.
4. Error handling, token expiration/refresh, Firestore schema and permission assumptions, race conditions, edge cases.

## 🔒 My Identity
- Archetype: teamwork_preview_explorer
- Roles: explorer_auth_oauth_cloud
- Working directory: c:/Users/jiwho/Documents/boardest/.agents/explorer_auth_oauth_cloud
- Original parent: 5b553c4b-47d7-462b-ae55-1cabb38236d4
- Milestone: Investigation & Diagnosis

## 🔒 Key Constraints
- Read-only investigation — do NOT implement code changes in the main project (only write reports/handoffs in .agents/explorer_auth_oauth_cloud)
- Report findings via analysis.md and handoff.md
- Send message to parent upon completion

## Current Parent
- Conversation ID: 5b553c4b-47d7-462b-ae55-1cabb38236d4
- Updated: 2026-08-21T13:22:30Z

## Investigation State
- **Explored paths**:
  - `apps/boardest_teacher_oauth/index.html`
  - `infra/school_set_web/boardest-teacher-oauth/index.html`
  - `packages/common/bst_auth/`
  - `packages/common/bst_cloud/`
  - `packages/common/bst_cast/`
  - `apps/boardest_teacher/lib/services/` (`cloud_drive_service.dart`, `totp_service.dart`, `canva_oauth_service.dart`, `bst_cloud_service.dart`)
  - `apps/boardest_teacher/lib/views/` (`drivecast_board_view.dart`, `google_login_webview.dart`, `canva_login_webview.dart`)
  - `apps/boardest_teacher_lite/lib/main.dart`
  - `apps/boardest/lib/services/` (`bst_cloud_service.dart`, `totp_service.dart`)
  - `apps/boardest/lib/widgets/bst_cloud_modal.dart`
  - `firebase/firestore.rules`
  - `firebase.json`
- **Key findings**:
  1. `boardest-teacher-oauth`: Saves only to `teacher_profiles`, omitting `teacher_cloud_tokens`. Uses implicit grant (no refresh token). DocId sanitization handles `+` differently from Flutter apps.
  2. `boardest_teacher_lite`: OTP calculated via non-standard HMAC-SHA256 over email string instead of RFC 6238 TOTP, causing 100% auth failure on electronic board.
  3. `DriveCastBoardView`: Calls missing methods `getOnlineClassrooms` and `approveConnectionRequest` on `BstCloudService` in `boardest_teacher`.
  4. `bst_auth`, `bst_cloud`, `bst_cast`: Missing `crypto` dependency in `bst_auth/pubspec.yaml`; broken `Calculator` unit tests across all three packages.
- **Unexplored areas**: None within auth/cloud scope.

## Key Decisions Made
- Structured complete diagnosis into `analysis.md` and 5-component `handoff.md`.

## Artifact Index
- `.agents/explorer_auth_oauth_cloud/analysis.md` — Comprehensive analysis report
- `.agents/explorer_auth_oauth_cloud/handoff.md` — 5-component handoff report
- `.agents/explorer_auth_oauth_cloud/progress.md` — Heartbeat and task progress
