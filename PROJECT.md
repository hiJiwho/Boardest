# Project: Boardest Ecosystem Full Inspection, Testing, and Hardening

## Architecture
- **Monorepo Structure**:
  - `apps/boardest`: Electronic blackboard application (Flutter Desktop Windows / Web / Android). Features: 3-mode canvas (pen, smart, touch), Store Level 0 TBP packaging, dHash visual page matching, `.bstpen` persistent annotation, cloud pairing with teacher tokens.
  - `apps/boardest_teacher`: Teacher desktop companion application (Flutter Desktop Windows / Web). Features: 18 lesson tools, Comsigan timetable, NEIS school meal viewer, DriveCast board pairing, lesson management.
  - `apps/boardest_teacher_lite`: Lightweight teacher web/mobile companion (Flutter Web). Features: remote OTP display, timetable viewer, meal lookup.
  - `apps/boardest_teacher_oauth` / `boardest-teacher-oauth`: Web OAuth onboarding portal (Vanilla JS / Firebase Firestore / Google OAuth 2.0). Features: Direct Google OAuth, School ID lookup, teacher profile registration/revocation.
  - `packages/common/`: `bst_core`, `bst_auth`, `bst_cloud`, `bst_cast`, `bst_timetable`, `bst_messaging`, `bst_ui`, `bst_control`, `bst_ad`.
  - `packages/plugins/`: `bst_canva`, `bst_native`, `bst_pdf`, `bst_pen`, `bst_tbp`, `bst_video`.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Shared Core Models & Settings | Fix `AppSettings.schoolId` serialization, resolve null safety and model contracts in `bst_core` | M1 | survey |
| 2 | Shared Packages Dependencies & Imports | Fix `pubspec.yaml` dependencies and relative import paths across all common/plugin packages | M1 | survey |
| 3 | Shared Packages Resource Safety | Fix leaks (HttpClients, StreamSubscriptions, Controllers) in `bst_tbp` and `bst_auth` | M1 | survey |
| 4 | Shared Packages Unit Test Suite | Replace dummy `Calculator` boilerplate with comprehensive unit tests across all 15 packages | M1 | survey |
| 5 | Web OAuth Portal Firestore Sync | Ensure `saveProfileAndUnlockApp()` writes to both `teacher_profiles` and `teacher_cloud_tokens` | M2 | survey |
| 6 | Firestore Document Key Normalization | Standardize docId sanitization (`replaceAll('.', '_').replaceAll('@', '_')`) across portal and apps | M2 | survey |
| 7 | DriveCast Board Service Completion | Implement missing `getOnlineClassrooms()` and `approveConnectionRequest()` in `bst_cloud_service.dart` | M2 | survey |
| 8 | RFC 6238 TOTP Engine Standardization | Replace custom HMAC-SHA256 with RFC 6238 Base32 HMAC-SHA1 in `TeacherView` and `Teacher Lite` | M3 | survey |
| 9 | Universal IO Guards for Web Stability | Guard all `Platform.*` invocations with `!kIsWeb` across teacher views and services | M3 | survey |
| 10 | Teacher Lite Session & Dynamic Data | Persist query parameters to `SharedPreferences`, parse Comsigan Worker response, dynamic NEIS query | M3 | survey |
| 11 | Teacher Apps Unit & Widget Tests | Fix broken tests in `boardest_teacher` and `boardest_teacher_lite` | M3 | survey |
| 12 | dHash Engine Offline Independence | Bundle `html2canvas.min.js` locally to eliminate external WAN CDN dependence on offline smartboards | M4 | survey |
| 13 | dHash Hash Distance Branch Logic | Fix `_onNewHash` branch logic to prevent visual variations (3-64 bits) from triggering page changes | M4 | survey |
| 14 | Stroke Coordinate Key Compatibility | Support both `{'dx', 'dy'}` and `{'x', 'y'}` in `AnnotationStroke` and `BstPenData` serialization | M4 | survey |
| 15 | TBP Unpack Cache Lifecycle | Add cleanup/eviction routine for temporary unpacked TBP folders in `%TEMP%/bstTBP_*` | M4 | survey |
| 16 | Board Canvas & Click-Through Verification | Ensure 3-mode canvas stability, touch event passing, and Windows click-through | M4 | survey |
| 17 | Board App Test Suite | Fix and enhance unit/widget tests in `apps/boardest/test/` | M4 | survey |
| 18 | Global Static Analysis Zero Warnings | Pass `flutter analyze` across all packages and apps with 0 errors and 0 warnings | M5 | survey |
| 19 | Monorepo Test Suite 100% Pass | Pass `flutter test` across all packages and apps | M5 | survey |
| 20 | Web Build Compilation | Verify `flutter build web` succeeds for `boardest`, `boardest_teacher`, and `boardest_teacher_lite` | M5 | survey |
| 21 | Version Specification & Changelog | Update `Ver.md` with complete documentation of all fixes and architecture upgrades | M5 | survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Shared Packages & Test Infrastructure | `packages/common/**`, `packages/plugins/**` | none | IN_PROGRESS |
| M2 | Teacher OAuth, Cloud Sync & DriveCast | `boardest-teacher-oauth`, `bst_auth`, `bst_cloud` | M1 | PLANNED |
| M3 | Teacher Desktop/Web Apps & Universal IO | `apps/boardest_teacher`, `apps/boardest_teacher_lite`, `bst_timetable` | M1, M2 | PLANNED |
| M4 | Electronic Board App, TBP & Canvas Engine | `apps/boardest`, `bst_tbp`, `bst_pen` | M1, M2 | PLANNED |
| M5 | Full Verification, Diagnostics & Ver.md | All apps and packages | M1, M2, M3, M4 | PLANNED |

## Interface Contracts
### TOTP Authentication Contract
- Secret Format: Base32 encoded string (e.g. `JBSWY3DPEHPK3PXP`)
- Hash Algorithm: RFC 6238 HMAC-SHA1
- Time Step: 60 seconds (1 minute epoch counter)
- Code Length: 6 digits (`000000` - `999999`)
- Verification: `TotpService.verifyOtp(secret, otp)` returns true if OTP matches within +/- 1 step window.

### Stroke Point Serialization Contract
- Point map supports both `{'dx': double, 'dy': double}` and `{'x': double, 'y': double}`.
- Parser reads `(p['dx'] ?? p['x'] as num).toDouble()` and `(p['dy'] ?? p['y'] as num).toDouble()`.

### Firestore Schema Contract
- Collection `teacher_profiles`: `{ uid, email, teacherName, schoolId, schoolName, updatedAt }`
- Collection `teacher_cloud_tokens`: `{ uid, email, teacherName, schoolId, googleDriveToken, totpSecret, updatedAt }`
- Doc ID standard: `email.replaceAll('.', '_').replaceAll('@', '_')`

## Code Layout
- `apps/boardest/`: Electronic blackboard application
- `apps/boardest_teacher/`: Teacher desktop app
- `apps/boardest_teacher_lite/`: Teacher web/mobile lite app
- `apps/boardest_teacher_oauth/` or root `boardest-teacher-oauth/`: Teacher OAuth web portal
- `packages/common/`: Shared common domain packages
- `packages/plugins/`: Shared UI / canvas / media / viewer plugin packages
- `Ver.md`: Global version release notes and changelog
