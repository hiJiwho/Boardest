## 2026-11-01T09:14:59Z
You are worker_update_loop, an implementation worker subagent.
Your identity: teamwork_worker
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_update_loop\
Original request path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md first.
Also read the detailed exploration findings in:
c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_update_loop\handoff.md

Your mission:
Implement the complete fix for Requirement 2: Android 환경에서 앱 업데이트 완료 후에도 계속 '업데이트 필요' 알림/잠금이 발생하는 무한 루프 버그 수정.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

You EXCLUSIVELY OWN the following files (no other worker will touch them):
1. `apps/boardest/android/app/src/main/kotlin/.../MainActivity.kt`:
   - Implement MethodChannel (e.g. `com.example.boardest/app_version` or `boardest/version`) with methods `getAppVersion` / `getPackageInfo` returning the real installed APK's `versionName` (from `context.packageManager.getPackageInfo(context.packageName, 0).versionName`) and `versionCode`.
2. `apps/boardest/pubspec.yaml`:
   - Add `package_info_plus: ^9.0.0` under dependencies.
3. `apps/boardest_teacher/pubspec.yaml`:
   - Add `package_info_plus: ^9.0.0` under dependencies.
4. `apps/boardest/assets/version.json`:
   - Create or update to `{"app_name":"boardest","version":"5.5.0","build_number":"5500"}`.
   - Also add `assets/version.json` to Flutter assets in `apps/boardest/pubspec.yaml` if not already included.
5. `apps/boardest/lib/services/update_service.dart`:
   - In `initVersion()`:
     1) On Android, try MethodChannel first to query native package version (`versionName`).
     2) Try `PackageInfo.fromPlatform()`.
     3) Try Windows MSIX executable path regex.
     4) Try `version.json` from rootBundle.
     5) Cache in `_resolvedVersion`.
   - In `cleanupOldUpdates()`:
     Purge BOTH `getApplicationSupportDirectory() / Updates` AND `getTemporaryDirectory() / Updates` on Android/Windows so stale downloaded `.apk` / `.msix` files are completely cleaned up!
   - In `executeInstall()`:
     Reset `stateNotifier.value = UpdateState.idle` so subsequent app resumes do not continuously re-trigger `executeInstall` in an infinite loop!
   - In `normalizeVersion()`:
     Use case-insensitive `^[vV]` and strip `+` build metadata (split on `+`).
   - In `_isNewerVersion()`:
     Compare SemVer parts numerically, and only compare build numbers if both target and current provide one. Ensure `5.5.0` vs `v5.5.0` or `5.5.0` vs `5.5.0+5500` returns `false`.
6. `apps/boardest_teacher/lib/services/update_service.dart`:
   - Synchronize `initVersion()`, `cleanupOldUpdates()`, `normalizeVersion()`, and `_isNewerVersion()` with `boardest`.
7. `apps/boardest/test/update_service_test.dart`:
   - Add unit tests verifying:
     - `_isNewerVersion('v5.5.0', '5.5.0') == false`
     - `_isNewerVersion('5.5.0', '5.5.0+5500') == false`
     - `_isNewerVersion('v5.5.0+5500', '5.5.0+5500') == false`
     - `_isNewerVersion('v5.5.1', '5.5.0+5500') == true`
     - `_isNewerVersion('v5.5.0+5501', '5.5.0+5500') == true`
     - `_isNewerVersion('v5.4.3', '5.5.0') == false`

Verification:
- Run `flutter test test/update_service_test.dart` in `apps/boardest` and ensure all tests pass.
- Run `flutter analyze lib/services/update_service.dart` to verify zero static errors.

Document your work and write your handoff report to:
c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_update_loop\handoff.md
Send message to orchestrator when completed.
