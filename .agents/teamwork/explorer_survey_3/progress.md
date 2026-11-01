# Progress — 2026-11-01T04:12:00Z
Last visited: 2026-11-01T04:12:00Z

## Status
- **Current Phase**: Surveying Monorepo Build, Test, and Dependency Status
- **Toolchain Identified**: Flutter 3.44.7 (channel stable), Dart 3.12.2, Melos 4.1.0 (22 packages detected in workspace)
- **Test Executions Completed**:
  - `apps/boardest_teacher/test/pointer_and_encryption_test.dart`: Passed (5 tests)
  - `apps/boardest_teacher/test/widget_test.dart`: Passed (1 test)
  - `apps/boardest_teacher_lite/test/widget_test.dart`: Passed (1 test)
  - `apps/boardest/test/totp_cloud_token_test.dart`: Passed (6 tests)
  - `apps/boardest/test/tbp_pointer_resolution_test.dart`: Passed (4 tests)
  - `apps/boardest/test/parser_test.dart`: Passed (1 test)
  - `apps/boardest/test/widget_test.dart`: Passed (1 test)
  - `apps/boardest/test/passkey_school_validation_test.dart`: Passed (3 tests)
  - `apps/boardest/test/pro_launcher_and_neis_test.dart`: Passed (2 tests)
  - `apps/boardest/test/school_schedule_sync_test.dart`: Passed (5 tests)
  - `packages/common/bst_core`: Passed (15 tests)
  - `packages/plugins/bst_pen`: Passed (11 tests)
  - `packages/plugins/bst_tbp`: Passed (3 tests)
- **Static Analysis Status**:
  - `bst_core`: 0 issues (clean)
  - `boardest_teacher`: 2 errors (`dart:js_util` in web capture/crx bridge on non-web compilation target), 776 warnings/infos (mostly deprecated `withOpacity` / `dart:html`)
  - `boardest`: Analysis running in background
- **E2E & Packaging Flow Identified**:
  - `scripts/build_all_appx.ps1` builds Windows MSIX/AppX using Windows Kit makeappx & signtool
  - `tools/installer/build_installer.ps1` compiles C# `BoardestInstaller.cs` (.NET Framework 4.0 + WebView2) for single unified installer & uninstaller
  - WiX template `scripts/wix_templates/bst-teacher/Product.wxs` configures Teacher MSI & start menu shortcuts
- **Next Steps**:
  - Finalize analysis of `boardest` and remaining packages
  - Document mock requirements (NEIS / Comcigan / Firebase network calls)
  - Write `survey_report.md` and `handoff.md`
