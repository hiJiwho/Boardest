# Handoff: Shared Packages Architecture & Diagnostics

**Agent**: `explorer_shared_packages`  
**Handoff Type**: Hard (Investigation Complete)  
**Artifacts Generated**:
- `c:/Users/jiwho/Documents/boardest/.agents/explorer_shared_packages/analysis.md`
- `c:/Users/jiwho/Documents/boardest/.agents/explorer_shared_packages/handoff.md`

---

## 1. Observation

Direct observations from source code inspection and tool outputs:

1. **Test Suite Failures**:
   - `flutter analyze packages/` produced 282 errors/warnings.
   - Command output sample:
     ```
     error - The function 'Calculator' isn't defined - packages\common\bst_ad\test\bst_ad_test.dart:7:24
     error - The function 'Calculator' isn't defined - packages\common\bst_auth\test\bst_auth_test.dart:7:24
     error - The function 'Calculator' isn't defined - packages\plugins\bst_tbp\test\bst_tbp_test.dart:7:24
     ```
   - Observed across all 14 package test files: `bst_ad_test.dart`, `bst_auth_test.dart`, `bst_cast_test.dart`, `bst_cloud_test.dart`, `bst_control_test.dart`, `bst_messaging_test.dart`, `bst_timetable_test.dart`, `bst_ui_test.dart`, `bst_canva_test.dart`, `bst_native_test.dart`, `bst_pdf_test.dart`, `bst_pen_test.dart`, `bst_tbp_test.dart`, `bst_video_test.dart`.
   - `packages/common/bst_core` does not contain a `test/` directory.

2. **Serialization Inconsistencies**:
   - `packages/common/bst_core/lib/src/models/app_settings.dart`:
     - Line 194: `final String schoolId;`
     - Lines 376-405 (`toJson()`): `'schoolId'` is completely omitted.
     - Lines 407-514 (`fromJson()`): `schoolId` is not read from `json`.
   - `packages/plugins/bst_pen/lib/src/bst_pen_data.dart`:
     - Line 21: `'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList()`
     - Line 46: `Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble())`
   - `packages/plugins/bst_pen/lib/src/annotation_canvas.dart`:
     - Line 19: `'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList()`
     - Line 27: `Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())`
   - `packages/common/bst_ad/lib/src/models/ad_banner.dart`:
     - Lines 1-14: No `toJson()` or `fromJson()` methods implemented.

3. **Platform Abstraction Defects**:
   - `packages/common/bst_timetable/lib/src/services/comcigan_service.dart`:
     - Lines 28-56: `fetchTimetableRaw` has `if (kIsWeb) { ... } throw Exception('Unsupported platform');`. Non-web desktop/mobile callers immediately throw.
   - `packages/plugins/bst_native/pubspec.yaml` vs `hwp_helper.dart` (line 2), `ppt_helper.dart` (line 2):
     - `import 'package:universal_io/io.dart';` used without `universal_io` in `pubspec.yaml`.

4. **Resource Management & Leaks**:
   - `packages/plugins/bst_tbp/lib/src/views/tbp_viewer_route.dart`:
     - Line 127: `_winWebview.webMessage.listen(...)` created without storing or cancelling subscription.
     - Lines 39, 56: `AnnotationController _annotationController` and `WebviewController _winWebview` are never disposed in `dispose()` (lines 255-259).
   - `packages/plugins/bst_tbp/lib/src/services/tbp_download_interceptor.dart`:
     - Lines 41-50: `HttpClient()` instantiated and executed without `client.close()`.
   - `packages/plugins/bst_tbp/lib/src/views/tbp_hotspot_overlay.dart`:
     - Lines 38-39: `titleCtrl` and `valCtrl` are created in static `showAddHotspotModal` but never disposed.

5. **Package Decoupling & Import Pathology in `bst_tbp`**:
   - `packages/plugins/bst_tbp/lib/src/services/tbp_storage_service.dart`:
     - Line 9: `import '../../models/tbp_metadata.dart';` (File does not exist at path)
     - Line 10: `import '../../widgets/annotation_canvas.dart';` (File does not exist at path)
   - `packages/plugins/bst_tbp/lib/src/services/tbp_download_interceptor.dart`:
     - Lines 7-9: `import '../../views/pdf_board_view.dart';`, `ppt_overlay_view.dart`, `hwp_overlay_view.dart` (Files do not exist at path)
   - `packages/plugins/bst_tbp/lib/src/views/tbp_viewer_route.dart`:
     - Lines 10-18: 8 broken relative imports referencing non-existent parent directory paths.

---

## 2. Logic Chain

1. **Step 1 (Test Suite Failure)**:
   - Observations show all 14 package test files instantiate `Calculator()`, which is undefined in all packages.
   - Therefore, running `flutter test` or `melos run test` fails immediately on every single package.
   - Conclusion: All package unit test suites are non-functional templates requiring complete replacement with valid unit tests.

2. **Step 2 (Data Loss & Crash on Deserialization)**:
   - Observation: `AppSettings.schoolId` is omitted in `toJson` and `fromJson`.
   - Inference: When a user selects or configures a school and the app persists settings to `SharedPreferences` or cloud, re-reading the settings will silently discard `schoolId` and reset it to default `'ydm'`.
   - Observation: `BstPenData` writes `'dx'`/`'dy'` while `AnnotationStroke` reads `'x'`/`'y'`.
   - Inference: Exchanging pen stroke data across these two classes within `bst_pen` throws a `TypeError` due to null values passed to `num`.

3. **Step 3 (Platform Runtime Crash on Timetable Fetch)**:
   - Observation: `fetchTimetableRaw` in `bst_timetable` unconditionally throws `Exception('Unsupported platform')` when `kIsWeb == false`.
   - Inference: Any Windows, Android, macOS, or Linux client calling `fetchTimetableRaw` will encounter an unhandled exception.
   - Observation: The full native Comcigan crawler (610 lines) resides in `apps/boardest/lib/services/comcigan_service.dart` but was never ported into the shared package `bst_timetable`.

4. **Step 4 (Compilation Failures in `bst_tbp`)**:
   - Observation: `bst_tbp` uses relative path imports (`../../models/...`, `../../views/...`) that do not exist within `packages/plugins/bst_tbp/`.
   - Inference: `bst_tbp` cannot be built or imported as an isolated package until imports are re-pointed to `package:bst_core`, `package:bst_pen`, `package:bst_cloud`, and missing pubspec dependencies are added.

5. **Step 5 (Memory & Socket Leaks)**:
   - Observation: Streams, HttpClients, and Controllers in `bst_tbp` are unclosed.
   - Inference: Repeatedly opening and closing TBP textbooks in `boardest` or `boardest_teacher` will leak Webview event listeners, file download sockets, and ChangeNotifier controllers into memory.

---

## 3. Caveats

1. **App-Level Decoupling State**:
   - `apps/boardest` and `apps/boardest_teacher` still contain local duplicate copies of models (`models/app_settings.dart`) and services (`services/comcigan_service.dart`). Fixing `packages/` is the first prerequisite step; subsequently, the apps need to be migrated to import from `package:bst_core`, `package:bst_timetable`, etc.
2. **Cloudflare Worker Availability**:
   - `ComciganService` uses `https://comcigan.jiwho.workers.dev/api/comcigan/lookup`. The web path relies on the availability of this external proxy. On desktop, native fallback must always be supported.
3. **No Code Modification Performed**:
   - In accordance with read-only investigator constraints, no source files were modified. All defects are documented with line numbers and exact remediation recipes in `analysis.md`.

---

## 4. Conclusion

The 15 shared packages in `packages/` have well-defined domain boundaries, but the monorepo migration was left incomplete:
1. **Critical functional blockers**: `AppSettings.schoolId` serialization drop, `bst_timetable` desktop crash, `bst_pen` coordinate key mismatch.
2. **Package compilation blockers**: `bst_tbp` broken relative imports and missing `pubspec.yaml` dependencies; `bst_native` missing `universal_io`.
3. **Quality/CI blockers**: 14 broken test files using dummy `Calculator` and 1 missing test suite in `bst_core`.
4. **Resource management**: 4 specific memory/socket leaks in `bst_tbp` and `bst_auth`.

All issues are precisely located and diagnosed with concrete remedies in `analysis.md`.

---

## 5. Verification Method

To independently verify all findings:

1. **Verify Static Analysis Errors**:
   ```powershell
   flutter analyze packages/
   ```
   *Expected result*: 282 issues (undefined identifiers in `bst_tbp`, missing `Calculator` in tests, deprecated member uses).

2. **Verify Test Suite Failures**:
   ```powershell
   flutter test packages/common/bst_core
   flutter test packages/common/bst_auth
   flutter test packages/common/bst_timetable
   flutter test packages/plugins/bst_tbp
   ```
   *Expected result*: `bst_core` has no tests; `bst_auth`, `bst_timetable`, `bst_tbp` fail with `Undefined name 'Calculator'`.

3. **Verify File & Line Observations**:
   - Inspect `packages/common/bst_core/lib/src/models/app_settings.dart:376-405` (Check omission of `schoolId`).
   - Inspect `packages/common/bst_timetable/lib/src/services/comcigan_service.dart:55` (Check `Exception('Unsupported platform')`).
   - Inspect `packages/plugins/bst_pen/lib/src/bst_pen_data.dart:21` vs `annotation_canvas.dart:19` (Check `'dx'` vs `'x'`).
   - Inspect `packages/plugins/bst_tbp/lib/src/services/tbp_storage_service.dart:9-10` (Check broken `../../models` imports).
