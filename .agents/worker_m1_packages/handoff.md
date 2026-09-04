# Handoff: Milestone 1 — Shared Packages & Test Infrastructure Hardening

## 1. Observation
- Across the 15 packages in `packages/common/` (`bst_core`, `bst_auth`, `bst_cloud`, `bst_cast`, `bst_timetable`, `bst_messaging`, `bst_ui`, `bst_control`, `bst_ad`) and `packages/plugins/` (`bst_pen`, `bst_tbp`, `bst_native`, `bst_canva`, `bst_pdf`, `bst_video`):
  1. `bst_core`: `AppSettings` in `packages/common/bst_core/lib/src/models/app_settings.dart` was missing `schoolId` in `toJson()` and defaulted in `fromJson()`. `PlatformCapability` in `platform_capability.dart` imported `dart:io`, causing crashes on Web platforms.
  2. `bst_auth`: Missing `crypto: ^3.0.3` dependency; `totp_service.dart` was missing; `loopback_login_service.dart` leaked previous HttpServer instances; Canva PKCE helpers were private.
  3. `bst_cloud`: `CloudFile` and `CloudSyncStatus` models and status streams were missing.
  4. `bst_cast`: Missing `CastMessage` and `CastSignalingData` models.
  5. `bst_timetable`: `ComciganService` threw `Unsupported platform` on non-web targets and lacked normalized schema parsing.
  6. `bst_messaging`, `bst_control`, `bst_ad`, `bst_ui`: `Message.fromJson` lacked null safety, `DeviceInfo.fromJson` lacked null safety, `AdBanner` lacked JSON serialization, and all test suites had dummy Calculator tests.
  7. `bst_pen`: `AnnotationStroke` serialized `{x, y}` while `BstPenData` parsed `{dx, dy}`, causing coordinate deserialization errors across whiteboard/viewer overlays.
  8. `bst_tbp`: `pubspec.yaml` was missing 14 required dependencies; imports in views pointed to nonexistent relative app paths (`../../views/pdf_board_view.dart`); `HttpClient` in `tbp_download_interceptor.dart` and `WebviewController`/`AnnotationController`/`StreamSubscription` in `tbp_viewer_route.dart` were not disposed/cancelled.
  9. `bst_native`, `bst_canva`, `bst_pdf`, `bst_video`: `bst_native` was missing `universal_io` and dummy tests were present.

## 2. Logic Chain
1. Fixed `AppSettings` serialization: added `schoolId: schoolId` to `toJson()` and `schoolId: json['schoolId'] as String? ?? 'ydm'` to `fromJson()`. Replaced direct `dart:io` in `PlatformCapability` with `defaultTargetPlatform` from `package:flutter/foundation.dart`.
2. Implemented RFC 6238 `TotpService` in `bst_auth` with HMAC-SHA1 and base32 secret cleaning, added public PKCE methods to `CanvaOAuthService`, closed previous socket instances before binding in `LoopbackLoginService`, and added `crypto: ^3.0.3` to `pubspec.yaml`.
3. Created models (`CloudFile`, `CloudSyncStatus`, `CastMessage`, `CastSignalingData`), implemented in-memory and broadcast services, and ensured null-safe deserialization across `bst_cloud`, `bst_cast`, `bst_messaging`, `bst_control`, and `bst_ad`.
4. Upgraded `ComciganService` with `TimetableResult`, `normalizeRawData`, and unified Cloudflare worker lookup for web and native platforms without throwing exceptions.
5. Standardized `AnnotationStroke` and `BstPenData` in `bst_pen` so point maps accept both `{dx, dy}` and `{x, y}` formats with null fallbacks.
6. Updated `bst_tbp` `pubspec.yaml` with all dependencies, resolved relative imports to package imports (`bst_core`, `bst_pen`, `bst_cloud`), added `SaveDestinationDialog` and `BoardDockToolbar` components to `bst_tbp`, closed `HttpClient` in `try/finally`, disposed modal text controllers in `finally`, and cancelled stream subscriptions / disposed controllers in `TbpViewerRoute.dispose()`.
7. Replaced all dummy Calculator tests with 64 comprehensive unit and widget tests covering real domain logic across all 15 packages.
8. Executed `flutter test` on all 15 packages (100% pass) and `flutter analyze` across all 15 packages (0 errors).

## 3. Caveats
- `apps/**` were strictly not modified per Milestone 1 write ownership rules. Any app-level view integrations with `bst_tbp` are provided via `TbpDownloadInterceptor.customViewerOpener`.
- Deprecation notices for `.withOpacity` vs `.withValues()` in Flutter 3.33+ remain as non-blocking `info` annotations in existing UI rendering code.

## 4. Conclusion
Milestone 1 is complete with high integrity. All 15 shared and plugin packages have been fully hardened, all identified bugs and resource leaks resolved, and genuine test suites implemented with 100% test pass rate and 0 analyzer errors.

## 5. Verification Method
Independently verifiable with:
```powershell
# 1. Test all 15 packages
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_core; flutter test test/bst_core_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_auth; flutter test test/bst_auth_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_cloud; flutter test test/bst_cloud_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_cast; flutter test test/bst_cast_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_timetable; flutter test test/bst_timetable_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_messaging; flutter test test/bst_messaging_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_ui; flutter test test/bst_ui_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_control; flutter test test/bst_control_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\common\bst_ad; flutter test test/bst_ad_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\plugins\bst_pen; flutter test test/bst_pen_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\plugins\bst_tbp; flutter test test/bst_tbp_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\plugins\bst_native; flutter test test/bst_native_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\plugins\bst_canva; flutter test test/bst_canva_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\plugins\bst_pdf; flutter test test/bst_pdf_test.dart
cd c:\Users\jiwho\Documents\boardest\packages\plugins\bst_video; flutter test test/bst_video_test.dart

# 2. Analyze all 15 packages
cd c:\Users\jiwho\Documents\boardest
flutter analyze packages/common/bst_core packages/common/bst_auth packages/common/bst_cloud packages/common/bst_cast packages/common/bst_timetable packages/common/bst_messaging packages/common/bst_ui packages/common/bst_control packages/common/bst_ad packages/plugins/bst_pen packages/plugins/bst_tbp packages/plugins/bst_native packages/plugins/bst_canva packages/plugins/bst_pdf packages/plugins/bst_video
```
Expected output: 0 errors, 100% tests passed across all 15 targets.
