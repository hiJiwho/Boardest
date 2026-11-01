# Progress Tracker - worker_update_loop

Last visited: 2026-11-01T09:16:30Z

- [x] Read DISPATCH.md and ORIGINAL_REQUEST.md
- [x] Read explorer_update_loop handoff report
- [ ] Inspect target files before editing:
  - [ ] `apps/boardest/android/app/src/main/kotlin/.../MainActivity.kt`
  - [ ] `apps/boardest/pubspec.yaml`
  - [ ] `apps/boardest_teacher/pubspec.yaml`
  - [ ] `apps/boardest/assets/version.json`
  - [ ] `apps/boardest/lib/services/update_service.dart`
  - [ ] `apps/boardest_teacher/lib/services/update_service.dart`
  - [ ] `apps/boardest/test/update_service_test.dart`
- [ ] Execute edits:
  - [ ] 1. Update `MainActivity.kt` with MethodChannel `boardest/version`
  - [ ] 2. Update `apps/boardest/pubspec.yaml` (`package_info_plus: ^9.0.0` and assets)
  - [ ] 3. Update `apps/boardest_teacher/pubspec.yaml` (`package_info_plus: ^9.0.0`)
  - [ ] 4. Create/update `apps/boardest/assets/version.json`
  - [ ] 5. Implement fixes in `apps/boardest/lib/services/update_service.dart`
  - [ ] 6. Implement fixes in `apps/boardest_teacher/lib/services/update_service.dart`
  - [ ] 7. Update/add unit tests in `apps/boardest/test/update_service_test.dart`
- [ ] Run `flutter test test/update_service_test.dart` in `apps/boardest`
- [ ] Run `flutter analyze lib/services/update_service.dart` in `apps/boardest` and `apps/boardest_teacher`
- [ ] Write handoff report and notify parent
