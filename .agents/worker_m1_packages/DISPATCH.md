# Dispatch: Worker Milestone 1 — Shared Packages & Test Infrastructure Hardening

## Mission
Implement all fixes and test suite replacements across all shared packages in `packages/common/` and `packages/plugins/`.

## Scope & Write Ownership
You have exclusive write ownership of:
- `packages/common/**`
- `packages/plugins/**`

Do NOT modify `apps/**` in this milestone.

## Required Tasks
1. **`bst_core`**: Fix `packages/common/bst_core/lib/src/models/app_settings.dart`:
   - Include `'schoolId'` in `toJson()` (serialize `schoolId: schoolId`).
   - Read `'schoolId'` in `fromJson()` (deserialize `schoolId: json['schoolId'] as String? ?? 'ydm'`).
   - Create `packages/common/bst_core/test/bst_core_test.dart` with unit tests for `AppSettings`, `Subject`, etc.
2. **`bst_auth`**:
   - Add `crypto: ^3.0.3` to `packages/common/bst_auth/pubspec.yaml`.
   - Replace `test/bst_auth_test.dart` with actual unit tests for `TotpService` and `CanvaOAuthService`.
3. **`bst_cloud`**:
   - Replace `test/bst_cloud_test.dart` with actual unit tests for cloud models and services.
4. **`bst_cast`**:
   - Replace `test/bst_cast_test.dart` with actual unit tests for cast message serialization and signaling data.
5. **`bst_timetable`**:
   - Fix `packages/common/bst_timetable/lib/src/services/comcigan_service.dart`: remove `throw Exception('Unsupported platform')` on non-web; provide unified fetching/parsing support.
   - Replace `test/bst_timetable_test.dart` with actual unit tests for Comcigan models and timetable parsing.
6. **`bst_messaging`, `bst_ui`, `bst_control`, `bst_ad`**:
   - Replace dummy `Calculator` tests with actual unit tests for each package's models, widgets, or services.
7. **`bst_pen`**:
   - Standardize point serialization in `packages/plugins/bst_pen`: ensure both `AnnotationStroke` and `BstPenData` accept both `{'dx', 'dy'}` and `{'x', 'y'}` gracefully.
   - Replace `test/bst_pen_test.dart` with unit tests for pen stroke serialization and data models.
8. **`bst_tbp`**:
   - Update `packages/plugins/bst_tbp/pubspec.yaml` to include required dependencies (`bst_core`, `bst_pen`, `bst_ui`, `archive`, `universal_io`, `google_fonts`, `crypto`, etc.).
   - Fix broken relative imports in `packages/plugins/bst_tbp/lib/src/**`.
   - Fix memory/socket leaks (dispose `AnnotationController`, `WebviewController`, close `HttpClient`, cancel subscriptions).
   - Replace `test/bst_tbp_test.dart` with unit tests for TBP metadata and storage service.
9. **`bst_native`, `bst_canva`, `bst_pdf`, `bst_video`**:
   - Add `universal_io: ^2.2.2` to `packages/plugins/bst_native/pubspec.yaml`.
   - Replace dummy `Calculator` tests with valid unit tests.
10. **Verification**:
   - Run `flutter test` across all 15 packages. Ensure all package test suites pass with 100% success (0 failures, 0 errors).
   - Run `flutter analyze packages/` and resolve all package-level analysis errors/warnings.

## MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Deliverables
Write detailed work report in `.agents/worker_m1_packages/changes.md` and 5-component `handoff.md`.
Report back when finished.

## 2026-08-21T13:45:19Z
- Parent Status Check: In progress with Milestone 1 implementation, executing test updates and leak fixes across packages.
