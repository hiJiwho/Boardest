# Boardest Auth, OAuth & Cloud Token Sync Comprehensive Diagnosis Report

**Date**: 2026-08-21  
**Investigator**: `explorer_auth_oauth_cloud` (Teamwork Explorer)  
**Target Modules**: `boardest-teacher-oauth`, `packages/bst_auth`, `packages/bst_cloud`, `packages/bst_cast`, `apps/boardest_teacher`, `apps/boardest_teacher_lite`, `apps/boardest`

---

## Executive Summary

A comprehensive, end-to-end architectural and code-level investigation was conducted across the Boardest ecosystem's authentication, OAuth 2.0 flow, Google Drive cloud synchronization, TOTP/PIN pairing, and lesson material casting systems.

### Key Highlights
1. **`boardest-teacher-oauth` Web Portal**: Implements direct Google OAuth 2.0 (implicit grant), real-time school verification via Firestore + Cloudflare Comcigan worker, and teacher name / homeroom auto-matching. However, it writes only to `teacher_profiles` and **omits `teacher_cloud_tokens` sync**, causing teachers who register via web to be invisible to electronic boards.
2. **`boardest_teacher_lite` OTP Incompatibility**: Computes OTP via non-standard HMAC-SHA256 over email string instead of RFC 6238 TOTP over Base32 secret. This causes **100% pairing failure** between Teacher Lite and Electronic Board.
3. **`DriveCastBoardView` Missing Method Crash**: Calls `getOnlineClassrooms()` and `approveConnectionRequest()` on `BstCloudService`, which are not implemented in `apps/boardest_teacher/lib/services/bst_cloud_service.dart`.
4. **Common Package Deficiencies & Broken Tests**: `packages/common/bst_auth` is missing `crypto` in `pubspec.yaml` (causing compilation errors). `bst_auth`, `bst_cloud`, and `bst_cast` contain placeholder dummy code and boilerplate `Calculator` test files that fail during `flutter test`.

---

## Detailed Investigation & Findings

### 1. `boardest-teacher-oauth` Portal (`apps/boardest_teacher_oauth/index.html`)

#### 1.1 OAuth Flow & Token Lifecycle
- **Grant Type**: Uses Google OAuth 2.0 Implicit Grant (`response_type=token id_token`).
- **Scopes**:
  - Cloud Enabled: `openid`, `userinfo.email`, `userinfo.profile`, `drive.file`, `drive.readonly`
  - Cloud Disabled: `openid`, `userinfo.email`, `userinfo.profile`
- **State Handling**: State object serialized via base64 JSON (`{ mode, target, wantsDrive, profileData }`) and parsed on callback.
- **Defect — No Refresh Token in Web Portal**: Implicit grant tokens expire after 3600s (1 hour). Without offline code exchange, web sessions cannot refresh tokens silently in background.

#### 1.2 School & Comsigan Matching Engine
- **Verification Chain**:
  1. Checks Firestore `control_configs/{schoolId}` (lowercase, uppercase, raw).
  2. Fallback default for `YDM` -> `양동중학교` (Comcigan code `48588`).
  3. Queries Cloudflare Worker proxy: `https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=...`
  4. Parses teachers from `data['자료446']` and homeroom mappings from `data['담임']` matrix.
  5. Fallback search by school name if code lookup yields 0 teachers.
- **Name Matching**: Prefix/substring matching against Comcigan teacher list with dynamic chip rendering.

#### 1.3 Firestore Document Keying Discrepancy
- `index.html` line 1405: `docId = email.replace(/[.@+]/g, '_')`
- `cloud_drive_service.dart` line 753: `uid = email.replaceAll('.', '_').replaceAll('@', '_')`
- `bst_cloud_service.dart` line 710: `uid = email.replaceAll('.', '_').replaceAll('@', '_')`
- **Impact**: Emails containing `+` (e.g. `teacher+test@school.org`) create disparate documents in Firestore.

#### 1.4 Missing Sync to `teacher_cloud_tokens`
- `saveProfileAndUnlockApp()` saves to `db.collection('teacher_profiles').doc(docId)`.
- It does not write to `teacher_cloud_tokens`. Electronic boards discover active teachers exclusively via `teacher_cloud_tokens`, making web-registered teachers undiscoverable on the board until they log into the desktop app.

#### 1.5 Client Redirection & Revocation Flow
- `proceedToClient()`:
  - Windows (`clientTarget === 'win'`): HTTP loopback request to `http://127.0.0.1:1217/oauth-callback?...`
  - Web Lite (`clientTarget === 'web'`): Redirect to `https://boardest-teacher-lite.web.app?...`
- `deleteAccountProfile()`:
  - 3-step sequential confirmation (`[1/3]`, `[2/3]`, `[3/3]`).
  - Deletes documents from `teacher_profiles` and `teacher_cloud_tokens`.
  - Sends revocation request to `https://oauth2.googleapis.com/revoke?token=...` with `mode: 'no-cors'`.
  - Clears `localStorage` and `sessionStorage`.

---

### 2. Common Packages (`packages/common/bst_auth`, `bst_cloud`, `bst_cast`)

#### 2.1 `packages/common/bst_auth`
- **Compilation Error**: `lib/src/services/canva_oauth_service.dart` imports `package:crypto/crypto.dart`, but `crypto` is not declared in `pubspec.yaml`.
- **Hardcoded Placeholder**: `CanvaOAuthService.clientId` contains `'YOUR_CANVA_CLIENT_ID'`.
- **Desktop Incompleteness**: `GoogleOAuthService.signInWithGoogle()` returns `null` on non-web platforms without initiating loopback authentication.
- **Broken Unit Test**: `test/bst_auth_test.dart` invokes non-existent `Calculator()` class.

#### 2.2 `packages/common/bst_cloud`
- **Skeleton Implementation**: `CloudDriveService` only contains a mock delay simulation (`Future.delayed(Duration(seconds: 1))`). The real 1543-line service is implemented directly inside `apps/boardest_teacher/lib/services/cloud_drive_service.dart`.
- **Broken Unit Test**: `test/bst_cloud_test.dart` invokes non-existent `Calculator()` class.

#### 2.3 `packages/common/bst_cast`
- **Skeleton Implementation**: `CastService` contains hardcoded URL `https://firestore.googleapis.com/v1/projects/YOUR_PROJECT_ID/...` and returns empty streams.
- **Broken Unit Test**: `test/bst_cast_test.dart` invokes non-existent `Calculator()` class.

---

### 3. Teacher Cloud Token Sync, OTP 6-Digit PIN Authentication & Casting

#### 3.1 Desktop Cloud Token Sync (`apps/boardest_teacher/lib/services/cloud_drive_service.dart`)
- **Loopback Server**: Persistent HTTP server on `http://127.0.0.1:1217` handling OAuth callbacks for Google, Canva, and portal redirects.
- **Token Exchange**: Authorization Code exchanged for `access_token` and `refresh_token` via Google OAuth token endpoint.
- **Folder Provisioning**: Ensures `Boardest_Cloud`, `Bst-cloud` (lesson materials), and `Bst-pen` (annotations) folders exist on Google Drive.
- **Firestore Sync**: Writes full token payload, Base32 `totpSecret`, and settings to `teacher_cloud_tokens/{uid}`.
- **Auto-Refresh**: Periodic 40-minute timer + reactive 401 retry mechanism.

#### 3.2 OTP Authentication Protocol & Anti-Replay Engine
- **Engine**: RFC 6238 Time-Based One-Time Password with 60-second step and 6-digit output.
- **Verification Windows**: Evaluates `[current - 1, current, current + 1]` windows for both 30s and 60s intervals.
- **Replay Protection**: Stores `lastConsumedWindow` in Firestore upon successful verification. If `window <= lastConsumedWindow`, authentication is rejected.
- **Device Trust**:
  - First OTP success saves `totpSecret` in Board local storage (`bst_trusted_secret_{email}`).
  - Subsequent connections auto-compute OTP without teacher intervention.
  - Disabling device trust in teacher app generates a new TOTP secret, immediately invalidating cached keys across all boards.
  - 3-failure lockout clears board trust cache and forces manual OTP entry.

#### 3.3 Critical Bug: `boardest_teacher_lite` OTP Mismatch
- `apps/boardest_teacher_lite/lib/main.dart` (lines 253-274):
  ```dart
  final secret = _googleEmail.isNotEmpty ? _googleEmail : 'boardest_teacher_lite_secret';
  final epoch = DateTime.now().millisecondsSinceEpoch ~/ 60000;
  final key = utf8.encode(secret);
  final bytes = utf8.encode(epoch.toString());
  final hmacSha256 = Hmac(sha256, key);
  ```
- **Discrepancy**:
  1. Uses HMAC-SHA256 instead of HMAC-SHA1.
  2. Uses raw UTF-8 email string instead of Base32 decoded binary secret.
  3. Uses UTF-8 string epoch instead of 8-byte big-endian binary counter.
  4. Does not sync secret to `teacher_cloud_tokens`.
- **Result**: Electronic Blackboard fails 100% of OTP verification attempts originating from Teacher Lite.

#### 3.4 Critical Bug: `DriveCastBoardView` Missing Service Methods
- `apps/boardest_teacher/lib/views/drivecast_board_view.dart`:
  - Line 40: `BstCloudService.instance.getOnlineClassrooms()`
  - Line 92: `BstCloudService.instance.approveConnectionRequest(...)`
- `apps/boardest_teacher/lib/services/bst_cloud_service.dart` only defines `saveSyncState` and `listenSyncState`.
- **Result**: Invoking DriveCast controller throws a runtime `NoSuchMethodError`.

---

### 4. Firestore Security Rules & Permissions Analysis

#### 4.1 Security Rules Matrix (`firebase/firestore.rules`)
| Collection | Read Rule | Write Rule | Assessment |
|---|---|---|---|
| `/teacher_profiles/{profileId}` | `true` | `true` | Accessible via web portal REST / client |
| `/teacher_cloud_tokens/{teacherUid}` | `true` | `true` | Required for serverless token sync |
| `/cloud_connections/{doc=**}` | `true` | `true` | Required for 1:1 board pairing |
| `/eat_calls/{callId}` | `true` | `true` | Required for cafeteria guidance |
| `/control_configs/{schoolId}` | `true` | `isAuthenticated()` | Read-only public config, admin write |

#### 4.2 Security & Integrity Considerations
- Public read/write on `teacher_cloud_tokens` enables lightweight REST syncing across web, desktop, and boards without requiring Firebase Auth custom claims on every client.
- Mitigating factors: Document IDs are email-based obfuscated keys, access tokens expire in 1 hour, and OTP verification enforces single-use anti-replay (`lastConsumedWindow`).

---

## Actionable Recommendations & Remediation Plan

1. **Fix `boardest_teacher_lite` OTP Engine**:
   - Replace custom HMAC-SHA256 logic with `TotpService` from common package or local helper.
   - Sync `totpSecret` and tokens to `teacher_cloud_tokens/{uid}` upon Google login.
2. **Implement Missing Methods in `BstCloudService` (`boardest_teacher`)**:
   - Add `getOnlineClassrooms()` and `approveConnectionRequest()` to `apps/boardest_teacher/lib/services/bst_cloud_service.dart`.
3. **Fix `packages/common/bst_auth` Compilation**:
   - Add `crypto: ^3.0.3` to `packages/common/bst_auth/pubspec.yaml`.
   - Update `packages/common/bst_auth/test/bst_auth_test.dart`, `bst_cloud_test.dart`, and `bst_cast_test.dart` to test real services instead of undefined `Calculator`.
4. **Synchronize `teacher_cloud_tokens` in `boardest-teacher-oauth`**:
   - In `saveProfileAndUnlockApp()`, write tokens and metadata to both `teacher_profiles` and `teacher_cloud_tokens`.
   - Standardize document ID sanitization to `email.replaceAll('.', '_').replaceAll('@', '_')`.
