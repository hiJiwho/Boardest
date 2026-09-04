# Shared Packages Deep-Dive Analysis & Diagnostics

**Target Scope**: All packages in `packages/` (`packages/common/**` and `packages/plugins/**`)  
**Investigator**: `explorer_shared_packages`  
**Date**: 2026-08-21  

---

## 1. Executive Summary

A comprehensive investigation was conducted across all 15 shared packages (9 common modules and 6 plugin modules) in the Boardest monorepo. 

Key Findings Summary:
1. **Broken Tests Across All Packages**: Every single package with a test suite (14 packages) contains boilerplate dummy tests (`Calculator().addOne(...)`) referencing a nonexistent class, causing immediate test compilation failure (`flutter test` fails across the workspace). `bst_core` has no test directory at all.
2. **Critical Serialization Inconsistency**:
   - `AppSettings` in `bst_core`: `schoolId` (line 194) is completely missing from both `toJson()` and `fromJson()`, causing school ID to default to `'ydm'` upon loading from persistence.
   - `BstPenData` vs `AnnotationStroke` in `bst_pen`: `BstPenData` serializes points with `'dx'`/`'dy'` while `AnnotationStroke` expects `'x'`/`'y'`, breaking stroke serialization/deserialization compatibility.
   - `AdBanner` in `bst_ad`: Missing `toJson()` and `fromJson()` entirely.
3. **Broken Relative Imports & Missing Dependencies in `bst_tbp`**:
   - `bst_tbp` files contain multiple invalid relative import paths pointing to `../../models/`, `../../views/`, `../../widgets/`, and `../../services/` that exist in app directories rather than package structure.
   - `bst_tbp/pubspec.yaml` lacks critical dependencies (`archive`, `path_provider`, `webview_windows`, `webview_flutter`, `google_fonts`, `file_picker`, `bst_core`, `bst_pen`, `bst_cloud`, `url_launcher`, `path`).
4. **Platform Abstraction & Runtime Fallback Defects**:
   - `ComciganService` in `bst_timetable`: `fetchTimetableRaw` throws `Exception('Unsupported platform')` on all non-web platforms (Windows/Android/Desktop), breaking timetable fetching on desktop.
   - `HwpHelper` / `PptHelper` in `bst_native`: Imports `package:universal_io/io.dart` but `universal_io` is missing from `bst_native/pubspec.yaml`.
   - Direct un-abstracted `dart:io` imports exist in `bst_core`, `bst_auth`, `bst_pen`, and `bst_tbp`.
5. **Resource Leaks**:
   - `bst_tbp`: `_winWebview.webMessage.listen` subscription is unmanaged/never cancelled; `AnnotationController` and `WebviewController` are never disposed in `_TbpViewerRouteState`; `HttpClient` in `TbpDownloadInterceptor` is never closed; `TextEditingController` instances in `TbpHotspotOverlay.showAddHotspotModal` are never disposed.
   - `bst_auth`: `LoopbackLoginService.startServer` can overwrite running server instances and lacks port collision recovery.

---

## 2. Comprehensive Package Inventory & Health Matrix

| # | Package Name | Directory | Type | Dependencies Defined in pubspec.yaml | Status / Diagnostic Summary |
|---|---|---|---|---|---|
| 1 | `bst_core` | `packages/common/bst_core` | Core Models & Utils | `flutter`, `shared_preferences`, `path_provider` | **Defect**: `AppSettings` omits `schoolId` in `toJson`/`fromJson`; direct `dart:io` in `platform_capability.dart`; missing `test/` dir. |
| 2 | `bst_ui` | `packages/common/bst_ui` | Common Themes & Widgets | `flutter`, `google_fonts` | **Defect**: SDK constraint `^3.12.2` overly rigid; dummy `Calculator` test. |
| 3 | `bst_auth` | `packages/common/bst_auth` | Authentication & OAuth | `firebase_auth`, `flutter`, `url_launcher` | **Defect**: Missing `crypto` dependency in pubspec; direct `dart:io` in `loopback_login_service.dart`; dummy `Calculator` test. |
| 4 | `bst_cast` | `packages/common/bst_cast` | Classroom Casting | `flutter` | **Defect**: Hardcoded `YOUR_PROJECT_ID` placeholder; returns `const Stream.empty()`; dummy `Calculator` test. |
| 5 | `bst_cloud` | `packages/common/bst_cloud` | Cloud Drive Integration | `flutter` | **Defect**: Stub mock implementation; lacks `uploadFileToDrive`; dummy `Calculator` test. |
| 6 | `bst_control` | `packages/common/bst_control` | Device & License Control | `flutter` | **Defect**: Unsafe `DateTime.parse` without null/format guard; dummy `Calculator` test. |
| 7 | `bst_messaging`| `packages/common/bst_messaging`| Inter-app Messaging | `flutter` | **Defect**: Abstract interface only; unsafe `DateTime.parse`; dummy `Calculator` test. |
| 8 | `bst_timetable`| `packages/common/bst_timetable`| Timetable & NEIS API | `bst_core`, `flutter`, `http` | **Critical Defect**: `fetchTimetableRaw` throws on non-web; missing full parsing logic & `TimetableResult`; missing `cp949_codec`; dummy `Calculator` test. |
| 9 | `bst_ad` | `packages/common/bst_ad` | Banner Ads & Carousel | `flutter` | **Defect**: `AdBanner` lacks `toJson`/`fromJson`; dummy `Calculator` test. |
| 10 | `bst_canva` | `packages/plugins/bst_canva` | Canva Web Integration | `flutter`, `webview_flutter` | **Defect**: Lacks Windows desktop webview adapter; dummy `Calculator` test. |
| 11 | `bst_native` | `packages/plugins/bst_native` | Native Process Helpers | `flutter` | **Defect**: Missing `universal_io` in pubspec; dummy `Calculator` test. |
| 12 | `bst_pdf` | `packages/plugins/bst_pdf` | PDF Board Viewer | `flutter`, `pdfrx` | **Defect**: Dummy `Calculator` test. |
| 13 | `bst_pen` | `packages/plugins/bst_pen` | Pen Engine & Canvas | `flutter`, `google_fonts` | **Defect**: Schema mismatch (`'dx'`/`'dy'` vs `'x'`/`'y'`); unused `dart:io` import in `unified_pen_overlay.dart`; dummy `Calculator` test. |
| 14 | `bst_tbp` | `packages/plugins/bst_tbp` | TextBook Plus Engine | `flutter`, `image` | **Critical Defect**: Missing 11 dependencies; broken relative imports across views/services; 4 resource leaks; dummy `Calculator` test. |
| 15 | `bst_video` | `packages/plugins/bst_video` | Video Studio / YouTube | `flutter`, `video_player`, `youtube_explode_dart` | **Defect**: Stub renderer; dummy `Calculator` test. |

---

## 3. Detailed Technical Diagnosis by Domain

### 3.1 Data Model Contracts & Serialization Integrity

#### Bug M1: `AppSettings.schoolId` dropped during serialization
- **Location**: `packages/common/bst_core/lib/src/models/app_settings.dart` (lines 194, 376-405, 407-514)
- **Observation**:
  `schoolId` is defined on line 194 (`final String schoolId;`), but in `toJson()` (lines 376-405), `'schoolId'` is not included in the returned map. In `fromJson()` (lines 407-514), `schoolId` is never extracted from `json` and falls back to the default parameter value `'ydm'`.
- **Impact**: Any custom school ID configured by a teacher is lost whenever settings are persisted and reloaded.
- **Evidence**:
  ```dart
  // app_settings.dart line 376:
  Map<String, dynamic> toJson() {
    return {
      'selectedSchool': selectedSchool?.toJson(),
      'selectedGrade': selectedGrade,
      'selectedClass': selectedClass,
      'timeSettings': timeSettings.toJson(),
      // 'schoolId' is missing!
  ```
- **Remediation**: Add `'schoolId': schoolId` to `toJson()`, and `schoolId: json['schoolId'] as String? ?? (json['connectionName'] as String? ?? 'ydm')` to `fromJson()`.

#### Bug M2: `BstPenData` vs `AnnotationStroke` JSON point coordinate key mismatch
- **Location**:
  - `packages/plugins/bst_pen/lib/src/bst_pen_data.dart` (lines 21, 46)
  - `packages/plugins/bst_pen/lib/src/annotation_canvas.dart` (lines 19, 27)
- **Observation**:
  - In `bst_pen_data.dart`:
    ```dart
    // line 21:
    'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList(),
    // line 46:
    .map<Offset>((p) => Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble()))
    ```
  - In `annotation_canvas.dart`:
    ```dart
    // line 19:
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    // line 27:
    .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
    ```
- **Impact**: Passing JSON data generated by `AnnotationStroke.toJson()` into `BstPenData.fromJson()` (or vice-versa) results in `null` coordinate lookups and runtime crash (`type 'Null' is not a subtype of type 'num' in type cast`).
- **Remediation**: Standardize coordinate keys to support both or unify to `dx`/`dy` with backwards compatibility:
  `final x = (p['dx'] ?? p['x'] ?? 0.0) as num; final y = (p['dy'] ?? p['y'] ?? 0.0) as num;`

#### Bug M3: Missing serialization in `AdBanner`
- **Location**: `packages/common/bst_ad/lib/src/models/ad_banner.dart` (lines 1-14)
- **Observation**: `AdBanner` contains four fields (`id`, `imageUrl`, `clickUrl`, `remainingSeconds`) but does not implement `toJson()` or `fromJson()`.
- **Impact**: Cannot persist or transmit banner data via Firestore or REST APIs.
- **Remediation**: Implement `toJson()` and `factory AdBanner.fromJson(Map<String, dynamic> json)`.

---

### 3.2 Platform Abstraction & Universal IO Safety

#### Bug P1: `ComciganService` rejects non-web platforms
- **Location**: `packages/common/bst_timetable/lib/src/services/comcigan_service.dart` (lines 28-56)
- **Observation**:
  ```dart
  Future<Map<String, dynamic>> fetchTimetableRaw(int schoolCode, {int weekOffset = 0}) async {
    if (kIsWeb) {
      final workerUrl = Uri.parse('https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=$schoolCode');
      ...
      return normalized;
    }
    throw Exception('Unsupported platform');
  }
  ```
- **Impact**: Windows, macOS, Linux, and Android clients calling `fetchTimetableRaw` receive an immediate exception.
- **Remediation**: Integrate the comprehensive desktop crawler from `apps/boardest/lib/services/comcigan_service.dart` (which supports CP949 decoding, HTTP landing page frame extraction, and Cloudflare Worker fallback).

#### Bug P2: Missing `universal_io` dependency in `bst_native`
- **Location**: `packages/plugins/bst_native/pubspec.yaml` and `lib/src/helpers/hwp_helper.dart` (line 2), `ppt_helper.dart` (line 2)
- **Observation**: `bst_native` imports `package:universal_io/io.dart`, but `universal_io` is not declared under `dependencies` in `bst_native/pubspec.yaml`.
- **Impact**: Package fails static analysis and cannot be compiled independently.
- **Remediation**: Add `universal_io: ^2.2.2` to `packages/plugins/bst_native/pubspec.yaml`.

#### Bug P3: Direct `dart:io` imports without universal IO abstraction
- **Location**:
  - `packages/common/bst_core/lib/src/platform_capability.dart` (line 1: `import 'dart:io' show Platform;`)
  - `packages/common/bst_auth/lib/src/services/loopback_login_service.dart` (line 1: `import 'dart:io';`)
  - `packages/plugins/bst_pen/lib/src/unified_pen_overlay.dart` (line 1: `import 'dart:io';` - unused)
- **Impact**: Risk of web compilation errors when packages are imported in web applications (`boardest_teacher_lite`).
- **Remediation**: Remove unused `dart:io` in `unified_pen_overlay.dart`. Use `package:universal_io/io.dart` or conditional exports for `loopback_login_service.dart`.

---

### 3.3 Resource Management & Leak Analysis

#### Leak R1: Uncancelled `StreamSubscription` and un-disposed controllers in `TbpViewerRoute`
- **Location**: `packages/plugins/bst_tbp/lib/src/views/tbp_viewer_route.dart` (lines 39, 56, 127, 255-259)
- **Observation**:
  - Line 127: `_winWebview.webMessage.listen(...)` creates a `StreamSubscription` that is never stored in a variable and never cancelled.
  - Line 39: `final AnnotationController _annotationController = AnnotationController();` is never disposed in `dispose()`.
  - Line 56: `final WebviewController _winWebview = WebviewController();` is never disposed in `dispose()`.
- **Impact**: Memory leaks on every TBP book open/close cycle, duplicate message listeners triggering multiple times.
- **Remediation**:
  Store `StreamSubscription? _webMessageSub;` and cancel it in `dispose()`. Call `_annotationController.dispose()` and `_winWebview.dispose()`.

#### Leak R2: Unclosed `HttpClient` in `TbpDownloadInterceptor`
- **Location**: `packages/plugins/bst_tbp/lib/src/services/tbp_download_interceptor.dart` (lines 41-50)
- **Observation**:
  ```dart
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(downloadUrl));
  final res = await req.close();
  // client is never closed!
  ```
- **Impact**: Open sockets and uncollected HTTP client instances on downloaded files.
- **Remediation**: Wrap in `try/finally` and call `client.close()`.

#### Leak R3: Undisposed `TextEditingController`s in `TbpHotspotOverlay`
- **Location**: `packages/plugins/bst_tbp/lib/src/views/tbp_hotspot_overlay.dart` (lines 38-39, 178)
- **Observation**: `titleCtrl` and `valCtrl` are created in static `showAddHotspotModal` but never disposed after `showDialog` returns.
- **Remediation**: Call `titleCtrl.dispose()` and `valCtrl.dispose()` after dialog completion.

#### Leak R4: Unhandled server lifecycle in `LoopbackLoginService`
- **Location**: `packages/common/bst_auth/lib/src/services/loopback_login_service.dart` (lines 9-47)
- **Observation**: Re-invoking `startServer` without calling `stopServer` drops the reference to the running `_server` without closing it, causing the previous socket to hang and new binds to fail with port collision on port `1217`.
- **Remediation**: Call `stopServer()` at the beginning of `startServer()`.

---

### 3.4 Package Decoupling & Import Pathology in `bst_tbp`

#### Issue D1: Broken Cross-Directory Relative Imports
- **Location**: `packages/plugins/bst_tbp/lib/src/`
- **Observation**: Files in `bst_tbp` contain paths expecting an app directory layout instead of package dependencies:
  - `tbp_storage_service.dart`:
    - Line 9: `import '../../models/tbp_metadata.dart';` ➔ Should be `import 'package:bst_core/bst_core.dart';`
    - Line 10: `import '../../widgets/annotation_canvas.dart';` ➔ Should be `import 'package:bst_pen/bst_pen.dart';`
  - `tbp_download_interceptor.dart`:
    - Line 7: `import '../../views/pdf_board_view.dart';` ➔ Nonexistent in package
    - Line 8: `import '../../views/ppt_overlay_view.dart';` ➔ Nonexistent in package
    - Line 9: `import '../../views/hwp_overlay_view.dart';` ➔ Nonexistent in package
  - `tbp_creator_dialog.dart`:
    - Line 8: `import '../../services/tbp/tbp_storage_service.dart';` ➔ Should be `import '../services/tbp_storage_service.dart';`
    - Line 9: `import '../../services/bst_save_service.dart';` ➔ Nonexistent in package
  - `tbp_hotspot_overlay.dart`:
    - Line 7: `import '../../services/tbp/tbp_download_interceptor.dart';` ➔ Should be `import '../services/tbp_download_interceptor.dart';`
    - Line 8: `import '../../services/tbp/tbp_storage_service.dart';` ➔ Should be `import '../services/tbp_storage_service.dart';`
  - `tbp_viewer_route.dart`:
    - Lines 10-18: Multiple invalid relative imports (`../../models/board_tools.dart`, `../../models/tbp_metadata.dart`, `../../services/cloud_drive_service.dart`, `../../widgets/annotation_canvas.dart`, etc.)

#### Issue D2: Missing `pubspec.yaml` Dependencies in `bst_tbp`
`bst_tbp/pubspec.yaml` is missing:
- `archive: ^4.0.9`
- `path_provider: ^2.1.5`
- `path: ^1.9.1`
- `url_launcher: ^6.3.2`
- `google_fonts: ^8.2.1`
- `file_picker: ^11.0.2`
- `webview_windows: ^0.4.0`
- `webview_flutter: ^4.10.0`
- `bst_core: path: ../../common/bst_core`
- `bst_pen: path: ../bst_pen`
- `bst_cloud: path: ../../common/bst_cloud`

---

## 4. Test Suite Diagnostic

| Package | Test File | Current Status | Cause of Failure |
|---|---|---|---|
| `bst_core` | *(None)* | Missing | No `test/` directory |
| `bst_ad` | `bst_ad_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_auth` | `bst_auth_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_cast` | `bst_cast_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_cloud` | `bst_cloud_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_control` | `bst_control_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_messaging` | `bst_messaging_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_timetable` | `bst_timetable_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_ui` | `bst_ui_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_canva` | `bst_canva_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_native` | `bst_native_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_pdf` | `bst_pdf_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_pen` | `bst_pen_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_tbp` | `bst_tbp_test.dart` | Fails Compilation | References undefined `Calculator()` |
| `bst_video` | `bst_video_test.dart` | Fails Compilation | References undefined `Calculator()` |

---

## 5. Architectural Monorepo Convergence & Duplication Analysis

During inspection, extensive duplication was identified between `apps/` and `packages/`:
1. `AppSettings` is duplicated between `apps/boardest/lib/models/app_settings.dart`, `apps/boardest_teacher/lib/models/app_settings.dart`, and `packages/common/bst_core/lib/src/models/app_settings.dart`. The `apps/` copy has full serialization including `schoolId`, while `bst_core` has an outdated version.
2. `ComciganService` in `apps/boardest/lib/services/comcigan_service.dart` is the complete 610-line engine with CP949 decoding, frame parsing, and teacher mapping, while `packages/common/bst_timetable/lib/src/services/comcigan_service.dart` is an incomplete 58-line stub.
3. `TbpStorageService` and `UnifiedPenOverlay` exist both inside apps and inside `packages/plugins/`.

**Recommended Convergence Strategy**:
- Upgrade `packages/common/bst_core` models to match the canonical complete models.
- Port the full `ComciganService` and `TimetableResult` into `packages/common/bst_timetable`.
- Fix `bst_tbp` dependencies and imports so apps consume `package:bst_tbp` instead of local copy.
- Fix all 15 package test files with proper unit tests covering models and services.
