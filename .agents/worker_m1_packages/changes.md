# Milestone 1: Shared Packages & Test Infrastructure Hardening — Changes Report

## Overview
Milestone 1 implemented fixes across all 15 shared and plugin packages under `packages/common/` and `packages/plugins/`. All dummy test suites have been completely replaced with genuine, behavior-based unit and widget tests. Zero test failures, zero compilation errors, and 100% passing tests across all 15 packages.

---

## Detailed Summary of Changes by Package

### 1. `bst_core` (`packages/common/bst_core/`)
- **Fixes**:
  - In `lib/src/models/app_settings.dart`: Fixed critical bug where `schoolId` was omitted in `toJson()` and defaulted in `fromJson()`. Added `schoolId: schoolId` serialization and deserialization with `'ydm'` fallback.
  - In `lib/src/platform_capability.dart`: Replaced `dart:io` `Platform` usage with `defaultTargetPlatform` from `package:flutter/foundation.dart` for universal web compatibility without crashing.
- **Tests**: Created `test/bst_core_test.dart` with 9 passing tests covering `AppSettings`, `TimeSettings`, `DDayEvent`, `School`, `Lesson`, `TbpMetadata`, and `PlatformCapability`.

### 2. `bst_auth` (`packages/common/bst_auth/`)
- **Fixes**:
  - In `pubspec.yaml`: Added `crypto: ^3.0.3` dependency.
  - In `lib/src/services/totp_service.dart`: Created RFC 6238 TOTP computation engine supporting secret cleaning, custom step intervals, and HMAC-SHA1 one-time code generation.
  - In `lib/bst_auth.dart`: Exported `totp_service.dart`.
  - In `lib/src/services/canva_oauth_service.dart`: Exposed public PKCE helper methods (`generateRandomString`, `generateCodeChallenge`, `buildAuthUrl`) for robust OAuth flow validation.
  - In `lib/src/services/loopback_login_service.dart`: Fixed server socket leak by closing previous server before binding and exposed `isRunning`.
- **Tests**: Replaced `test/bst_auth_test.dart` with 14 passing unit tests.

### 3. `bst_cloud` (`packages/common/bst_cloud/`)
- **Fixes**:
  - In `lib/src/models/cloud_file.dart`: Created `CloudFile` and `CloudSyncStatus` models with `toJson()` and `fromJson()`.
  - In `lib/src/services/cloud_drive_service.dart`: Added status streams, singleton `instance`, file cache management, and `uploadFileToDrive()`.
  - In `lib/bst_cloud.dart`: Exported `cloud_file.dart`.
- **Tests**: Replaced `test/bst_cloud_test.dart` with 4 passing unit tests.

### 4. `bst_cast` (`packages/common/bst_cast/`)
- **Fixes**:
  - In `lib/src/models/cast_message.dart`: Created `CastMessage` and `CastSignalingData` models with JSON serialization.
  - In `lib/src/services/cast_service.dart`: Implemented room-based cast dispatch and stream broadcast listening.
  - In `lib/bst_cast.dart`: Exported `cast_message.dart`.
- **Tests**: Replaced `test/bst_cast_test.dart` with 3 passing unit tests.

### 5. `bst_timetable` (`packages/common/bst_timetable/`)
- **Fixes**:
  - In `lib/src/services/comcigan_service.dart`: Removed `throw Exception('Unsupported platform')` on non-web platforms. Implemented unified `TimetableResult`, raw data normalization (`normalizeRawData`), and response parsing (`parseTimetableData`).
  - In `lib/bst_timetable.dart`: Exported `comcigan_service.dart`.
- **Tests**: Replaced `test/bst_timetable_test.dart` with 4 passing unit tests.

### 6. `bst_messaging` (`packages/common/bst_messaging/`)
- **Fixes**:
  - In `lib/src/models/message.dart`: Added null safety and fallback parsing to `Message.fromJson`.
  - In `lib/src/services/messaging_service.dart`: Created `InMemoryMessagingService` for testable decoupled messaging.
- **Tests**: Replaced `test/bst_messaging_test.dart` with 3 passing unit tests.

### 7. `bst_ui` (`packages/common/bst_ui/`)
- **Tests**: Created comprehensive unit & widget test suite in `test/bst_ui_test.dart` covering `AppTheme.darkTheme`, `PrimaryButton`, `SecondaryButton`, `AppCard`, and `AppDialog` (5 passing tests).

### 8. `bst_control` (`packages/common/bst_control/`)
- **Fixes**:
  - In `lib/src/models/device_info.dart`: Added null safety and `toString()` implementation.
  - In `lib/src/services/device_control_service.dart`: Made validation delay configurable (`validationDelay`) for fast test execution.
- **Tests**: Replaced `test/bst_control_test.dart` with 4 passing unit tests.

### 9. `bst_ad` (`packages/common/bst_ad/`)
- **Fixes**:
  - In `lib/src/models/ad_banner.dart`: Implemented complete `toJson()` and `fromJson()` serialization.
- **Tests**: Replaced `test/bst_ad_test.dart` with 4 passing unit & widget tests covering serialization, sorting, and empty state rendering.

### 10. `bst_pen` (`packages/plugins/bst_pen/`)
- **Fixes**:
  - In `lib/src/annotation_canvas.dart` & `lib/src/bst_pen_data.dart`: Standardized coordinate serialization and deserialization to seamlessly handle both `{dx, dy}` and `{x, y}` keys with null fallbacks.
  - In `lib/src/unified_pen_overlay.dart`: Removed unused `dart:io` import.
- **Tests**: Replaced `test/bst_pen_test.dart` with 5 passing unit tests.

### 11. `bst_tbp` (`packages/plugins/bst_tbp/`)
- **Fixes**:
  - In `pubspec.yaml`: Added all required dependencies (`archive`, `path_provider`, `path`, `url_launcher`, `google_fonts`, `file_picker`, `webview_windows`, `webview_flutter`, `universal_io`, `crypto`, `bst_core`, `bst_pen`, `bst_cloud`).
  - In `lib/src/services/tbp_storage_service.dart`: Fixed relative imports to use `package:bst_core/bst_core.dart` and `package:bst_pen/bst_pen.dart`. Added `Directory.systemTemp` fallback if `getTemporaryDirectory()` throws in test environments.
  - In `lib/src/services/tbp_download_interceptor.dart`: Removed nonexistent app-level view imports; added `customViewerOpener` callback; wrapped `HttpClient` in `try/finally` with `client.close()`.
  - In `lib/src/views/tbp_creator_dialog.dart`: Fixed imports and replaced app `BstSaveService` reference with `getApplicationDocumentsDirectory()`.
  - In `lib/src/views/tbp_hotspot_overlay.dart`: Fixed imports and added `finally` block to dispose modal `TextEditingController`s.
  - In `lib/src/views/tbp_viewer_route.dart`: Fixed imports; stored `_webMessageSub` stream subscription and cancelled in `dispose()`; disposed `_annotationController` and `_winWebview`.
  - In `lib/src/widgets/save_destination_dialog.dart` & `lib/src/widgets/board_toolbar.dart`: Created self-contained widgets within `bst_tbp`.
- **Tests**: Created `test/bst_tbp_test.dart` with 3 passing tests for ZIP packaging/extraction roundtrip, hotspot persistence, and dHash message processing.

### 12. `bst_native` (`packages/plugins/bst_native/`)
- **Fixes**: Added `universal_io: ^2.2.2` to `pubspec.yaml`.
- **Tests**: Replaced `test/bst_native_test.dart` with 2 passing unit tests for `HwpHelper` and `PptHelper`.

### 13. `bst_canva` (`packages/plugins/bst_canva/`)
- **Tests**: Replaced `test/bst_canva_test.dart` with 2 passing unit tests for `CanvaBoardView` and `CanvaLibraryView`.

### 14. `bst_pdf` (`packages/plugins/bst_pdf/`)
- **Tests**: Replaced `test/bst_pdf_test.dart` with 2 passing unit & widget tests for `PdfBoardView`.

### 15. `bst_video` (`packages/plugins/bst_video/`)
- **Fixes**: Cleaned up `avoid_print` lints with `debugPrint` and removed redundant library name.
- **Tests**: Replaced `test/bst_video_test.dart` with 3 passing unit tests for `VideoStudioService`, `VideoEditorRenderer`, and `YouTubeStreamExtractor`.

---

## Verification Summary Table

| Package | Test Count | Test Status | Analyzer Status |
|---|---|---|---|
| `bst_core` | 9 | PASS | 0 Errors |
| `bst_auth` | 14 | PASS | 0 Errors |
| `bst_cloud` | 4 | PASS | 0 Errors |
| `bst_cast` | 3 | PASS | 0 Errors |
| `bst_timetable` | 4 | PASS | 0 Errors |
| `bst_messaging` | 3 | PASS | 0 Errors |
| `bst_ui` | 5 | PASS | 0 Errors |
| `bst_control` | 4 | PASS | 0 Errors |
| `bst_ad` | 4 | PASS | 0 Errors |
| `bst_pen` | 5 | PASS | 0 Errors |
| `bst_tbp` | 3 | PASS | 0 Errors |
| `bst_native` | 2 | PASS | 0 Errors |
| `bst_canva` | 2 | PASS | 0 Errors |
| `bst_pdf` | 2 | PASS | 0 Errors |
| `bst_video` | 3 | PASS | 0 Errors |
| **Total** | **64** | **100% PASS** | **0 Errors** |
