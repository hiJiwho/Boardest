## 2026-11-01T09:14:46Z
You are worker_qr_cloud, an implementation worker subagent.
Your identity: teamwork_worker
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_qr_cloud\
Original request path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md first.
Also read the detailed exploration findings in:
c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_qr_cloud\handoff.md

Your mission:
Implement the complete fix for Requirement 1: Class 앱 QR Cloud 접속 실패 문제 해결.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

You EXCLUSIVELY OWN the following files (no other worker will touch them):
1. `database.rules.json`: Add `cloud_pair_sessions` security rules (`.read`: true, `.write`: true).
2. `apps/boardest_teacher_oauth/index.html`:
   - In `detectRouteState`, support parsing `bst_pair` from inside `return_url` if present.
   - In `initApp`, activate auto `proceedToClient()` when `hasReturnUrl` is true.
   - In `completeReversePairing`, write authentication payload directly to RTDB `cloud_pair_sessions/${secret}.json` via `fetch` PATCH.
3. `firebase.json`:
   - In the `boardest-teacher-oauth` target, add `headers` (Cache-Control no-cache, CORS *) and `rewrites` (`source: "**"`, `destination: "/index.html"`).
4. `infra/cloud_connect_web/index.html`:
   - Add `/edit` route redirect guard to `boardest-teacher-oauth.web.app/edit`.
   - Parse `teacherName`, `accessToken`, `refreshToken`, `email`, `folderId`, `totpSecret`.
   - In Passkey mode, if no teacher token exists on the phone, display a 1-click OAuth login button.
   - In Passkey mode approval payload to RTDB, include `refreshToken`, `email`, `schoolId`, `schoolName`.
5. `apps/boardest/lib/services/bst_cloud_service.dart`:
   - In `waitForReversePairAuth`, add Firestore fallback polling so that if RTDB is delayed or blocked, it checks Firestore `cloud_pair_sessions/$secret`.
6. `apps/boardest_teacher_lite/lib/main.dart`:
   - Fix Line 3010 URL to point to `https://boardest-teacher-oauth.web.app/edit?...`.

Verification:
- Deploy Firebase RTDB rules using `firebase.cmd deploy --only database` (or `firebase deploy --only database`) and run `powershell -Command "Invoke-RestMethod -Uri 'https://jiwhosboardest-default-rtdb.firebaseio.com/cloud_pair_sessions/test.json' -Method Get"` to verify it returns `null` (HTTP 200 OK), NOT Permission Denied.
- Run `flutter test test/e2e/all_e2e_test.dart` to verify no regressions.

Document your work and write your handoff report to:
c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_qr_cloud\handoff.md
Send message to orchestrator when completed.
