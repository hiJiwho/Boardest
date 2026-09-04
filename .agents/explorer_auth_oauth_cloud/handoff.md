# Handoff Report: Auth, OAuth & Cloud Token Sync Investigation

**Agent**: `explorer_auth_oauth_cloud`  
**Working Directory**: `c:/Users/jiwho/Documents/boardest/.agents/explorer_auth_oauth_cloud`  
**Target Milestone**: Investigation & System Diagnosis (R1 & Common Auth/Cloud Packages)

---

## 1. Observation

1. **`boardest-teacher-oauth` Portal (`apps/boardest_teacher_oauth/index.html`)**:
   - Lines 1403-1422: `saveProfileAndUnlockApp()` writes profile data to `db.collection('teacher_profiles').doc(docId).set(payload, { merge: true })` but never creates or updates `teacher_cloud_tokens`.
   - Line 1405: `const docId = currentUser?.email ? currentUser.email.replace(/[.@+]/g, '_') : ...` replaces `+` with `_`, whereas `apps/boardest_teacher/lib/services/cloud_drive_service.dart` line 753 and `apps/boardest/lib/services/bst_cloud_service.dart` line 710 use `replaceAll('.', '_').replaceAll('@', '_')` (retaining `+`).
   - Lines 901-914: Uses Google OAuth Implicit Grant (`response_type=token id_token`) without obtaining a refresh token.
   - Lines 1484-1546: `deleteAccountProfile()` implements a 3-step confirmation (`[1/3]`, `[2/3]`, `[3/3]`), deletes Firestore records from both `teacher_profiles` and `teacher_cloud_tokens`, sends a revocation POST to `https://oauth2.googleapis.com/revoke?token=...` with `no-cors`, and purges storage.

2. **`boardest_teacher_lite` OTP Incompatibility (`apps/boardest_teacher_lite/lib/main.dart`)**:
   - Lines 252-275:
     ```dart
     final secret = _googleEmail.isNotEmpty ? _googleEmail : 'boardest_teacher_lite_secret';
     final epoch = DateTime.now().millisecondsSinceEpoch ~/ 60000;
     final key = utf8.encode(secret);
     final bytes = utf8.encode(epoch.toString());
     final hmacSha256 = Hmac(sha256, key);
     final digest = hmacSha256.convert(bytes);
     ```
   - In contrast, `apps/boardest/lib/services/totp_service.dart` and `apps/boardest_teacher/lib/services/totp_service.dart` implement RFC 6238 TOTP using Base32 decoded secrets and HMAC-SHA1 over 8-byte big-endian counters.

3. **`DriveCastBoardView` Missing Method Crash (`apps/boardest_teacher/lib/views/drivecast_board_view.dart`)**:
   - Line 40: `final classrooms = await BstCloudService.instance.getOnlineClassrooms();`
   - Line 92: `final success = await BstCloudService.instance.approveConnectionRequest(...)`
   - `apps/boardest_teacher/lib/services/bst_cloud_service.dart` (lines 1-28) only defines `saveSyncState()` and `listenSyncState()`. `getOnlineClassrooms()` and `approveConnectionRequest()` do not exist.

4. **Static Analysis & Test Failures (`packages/common/bst_auth`, `bst_cloud`, `bst_cast`)**:
   - `packages/common/bst_auth/lib/src/services/canva_oauth_service.dart:3:8`: `Target of URI doesn't exist: 'package:crypto/crypto.dart'` (missing dependency in `pubspec.yaml`).
   - `packages/common/bst_auth/test/bst_auth_test.dart:7:24`: `Method not found: 'Calculator'`.
   - `packages/common/bst_cloud/test/bst_cloud_test.dart:7:24`: `Method not found: 'Calculator'`.
   - `packages/common/bst_cast/test/bst_cast_test.dart:7:24`: `Method not found: 'Calculator'`.
   - Running `flutter test packages/common/bst_auth/test packages/common/bst_cloud/test packages/common/bst_cast/test` exits with code 1 and compilation failure.

---

## 2. Logic Chain

1. **Step 1 (Web Portal -> Board Visibility)**:
   - Observation 1 shows `saveProfileAndUnlockApp()` writes solely to `teacher_profiles`.
   - Observation in `apps/boardest/lib/services/bst_cloud_service.dart:107` shows `getCloudTeachers()` queries `teacher_cloud_tokens`.
   - *Inference*: A teacher registering only via the Web OAuth portal is never added to `teacher_cloud_tokens`, making them completely invisible to electronic blackboards attempting cloud connection.

2. **Step 2 (Teacher Lite -> Board OTP Verification)**:
   - Observation 2 shows `boardest_teacher_lite` generates OTP using `Hmac(sha256, utf8.encode(email))` with stringified epoch minute.
   - Observation in `boardest` (`bst_cloud_service.dart:676`) shows `verifyAndAuthenticateWithTotp()` evaluates `TotpService.verifyOtp()` against Base32 `totpSecret` stored in `teacher_cloud_tokens`.
   - *Inference*: Because the hashing algorithm (SHA256 vs SHA1), secret type (raw email string vs Base32 secret), input counter (ASCII string vs binary 8-byte uint64), and Firestore storage are mismatched, OTP validation from Teacher Lite fails 100% of the time.

3. **Step 3 (DriveCast Runtime Crash)**:
   - Observation 3 shows `DriveCastBoardView` calls `getOnlineClassrooms()` and `approveConnectionRequest()` on `BstCloudService.instance`.
   - `BstCloudService` in `boardest_teacher` lacks these methods.
   - *Inference*: Opening the DriveCast dialog on desktop results in an unhandled `NoSuchMethodError` exception at runtime.

4. **Step 4 (Package Integrity & Build/Test Stability)**:
   - Observation 4 shows missing dependencies and broken `Calculator` boilerplate across `bst_auth`, `bst_cloud`, and `bst_cast`.
   - *Inference*: Automated test runners (`flutter test` / `melos run test`) will fail immediately until dependencies and unit tests are corrected.

---

## 3. Caveats

1. **Network Availability for Google Endpoints**: During local offline development, direct Google OAuth endpoints (`accounts.google.com`, `oauth2.googleapis.com`, `googleapis.com/drive/v3`) require external internet connectivity. Loopback servers on `127.0.0.1:1217` function locally but depend on browser redirection.
2. **Cloudflare Worker Availability**: Comcigan timetable and school search rely on `https://comcigan.jiwho.workers.dev`. The web portal and desktop app contain fallback routines for school `YDM` and direct numeric code search, but full dynamic resolution depends on worker uptime.

---

## 4. Conclusion

The core authentication architecture (Desktop Loopback + RFC 6238 TOTP + Google Drive API v3) is sound and feature-rich on Windows Desktop. However, four critical defects must be addressed by implementation agents:
1. **Teacher Lite OTP Engine Alignment**: Refactor `boardest_teacher_lite` to use RFC 6238 TOTP and sync `teacher_cloud_tokens`.
2. **DriveCast Service Method Completion**: Implement `getOnlineClassrooms()` and `approveConnectionRequest()` in `apps/boardest_teacher/lib/services/bst_cloud_service.dart`.
3. **Web Portal Cloud Token Sync**: Update `boardest-teacher-oauth/index.html` to write to `teacher_cloud_tokens` and unify document ID keying.
4. **Common Package Cleanup**: Add `crypto` to `bst_auth/pubspec.yaml` and update unit tests across `bst_auth`, `bst_cloud`, and `bst_cast`.

---

## 5. Verification Method

### Automated Commands
1. **Static Analysis**:
   ```powershell
   flutter analyze packages/common/bst_auth packages/common/bst_cloud packages/common/bst_cast apps/boardest_teacher apps/boardest_teacher_lite apps/boardest
   ```
   *Expected outcome after fix*: 0 errors in auth and cloud modules.

2. **Unit Test Execution**:
   ```powershell
   flutter test packages/common/bst_auth/test packages/common/bst_cloud/test packages/common/bst_cast/test
   ```
   *Expected outcome after fix*: All unit tests pass with exit code 0.

### Code & Runtime Inspection
- Verify `apps/boardest_teacher_lite/lib/main.dart` OTP generation produces the same 6 digits as `TotpService.generateCurrentOtp()`.
- Verify `apps/boardest_teacher/lib/views/drivecast_board_view.dart` opens without `NoSuchMethodError`.
- Verify `apps/boardest_teacher_oauth/index.html` writes documents to both `teacher_profiles` and `teacher_cloud_tokens`.
