# Handoff Report: Timetable Engine Inspection, Edge Case Hardening & Offline Caching Verification

## 1. Observation

1. **Source Implementations**:
   - `packages/common/bst_timetable/lib/src/services/comcigan_service.dart`:
     - Line 132: `for (int w = 1; w < classList.length && w <= 5; w++)` restricted parsing to Monday–Friday only, discarding weekend schedules (Saturday w=6, Sunday w=7).
     - Lines 91-95: `for (int g = 1; g <= 3; g++)` hardcoded grade count to 3, failing to parse elementary schools with 6 grades.
     - Line 137: `final cellVal = (dayList[p] as num?)?.toInt() ?? 0;` failed to parse Comcigan string cells (e.g. `">101"` or `"101"`), resulting in 0 and discarding changed classes.
     - Line 155: `teacherName` when 0 or unassigned remained empty without homeroom fallback for self-study / homeroom slots.
     - Caching: No local caching mechanism existed in `ComciganService`.
   - `packages/common/bst_timetable/lib/src/services/neis_service.dart`:
     - NEIS timetable API endpoints (`hisTimetable`, `misTimetable`, `elsTimetable`, `spsTimetable`) were completely missing; only schedule and meal diet info were present.
     - Flutter linter reported 12 issues for `use_null_aware_elements`.
   - `apps/boardest_teacher/lib/services/comcigan_service.dart`:
     - Line 650: `for (int weekday = 1; weekday <= 5; weekday++)` ignored weekend classes.
     - Line 561: `getTimetable` did not have an offline persistent cache fallback, returning empty or failing when network was disconnected.
   - `apps/boardest_teacher/lib/services/storage_service.dart`:
     - Lacked timetable cache persistence methods (`saveCachedTimetable` / `getCachedTimetable`).
   - `apps/boardest_teacher/lib/views/teacher_timetable_popup_dialog.dart`:
     - Lines 63-66: If `selectedSchool` was null or fetch threw an exception, `_timetableResult` remained null, resulting in an empty grid. The grid only supported weekdays 1..5.

2. **Verification & Test Execution Outputs**:
   - `flutter analyze packages/common/bst_timetable/`:
     ```
     Analyzing bst_timetable...
     No issues found! (ran in 3.8s)
     ```
   - `flutter test packages/common/bst_timetable/`:
     ```
     00:01 +15: All tests passed!
     ```
   - `powershell -Command "cd apps\boardest_teacher; flutter test test/comcigan_service_test.dart"`:
     ```
     00:00 +6: All tests passed!
     ```

## 2. Logic Chain

1. **Weekend & Multi-Grade Handling**:
   - From Observation 1 (`w <= 5` and `g <= 3`), Comcigan and Korean schools often schedule weekend extracurriculars (Saturday w=6, Sunday w=7) and elementary schools have 6 grades.
   - Expanding the day loop to `w <= 7` and dynamic grade loop `g < classCountsRaw.length` enables seamless parsing of weekend schedules and elementary grades without list index out-of-bounds errors, since all indexing is guarded by `length` bounds.

2. **Cell Value & Teacher Edge Cases**:
   - Comcigan transmits changed timetable cells prefixed with `>` (e.g., `">101"`).
   - Parsing both `num` and `String` while setting `isChanged: true` when `>` is detected correctly captures changed subjects and preserves timetable integrity.
   - For missing teacher indices, falling back to homeroom teachers (`homeroomTeachers[g][c]`) during self-study / homeroom slots resolves unassigned slots while leaving unassigned subject classes safely unassigned without crashing.

3. **Offline Caching Architecture**:
   - In `packages/common/bst_timetable`, an in-memory cache (`_cache`) stores normalized school timetables upon successful retrieval. When network requests fail (offline or worker timeout), it checks `_cache[schoolCode]` before falling back to minimal placeholder structures.
   - In `apps/boardest_teacher`, dual-tier caching was implemented: in-memory `_inMemoryTimetableCache` + persistent `StorageService.saveCachedTimetable` / `getCachedTimetable` (SharedPreferences + `%LOCALAPPDATA%\...LocalState\bst-save\config\timetable_cache_<code\>.json`).
   - When offline teachers open `TeacherTimetablePopupDialog` or when `getTimetable` is called without network, it automatically recovers previous schedules from the local cache. If no previous schedule exists, it generates a conflict-free demo timetable (`generateDemo`), preventing any blank screens or application crashes.

4. **NEIS Timetable Engine**:
   - `NeisService` was augmented with `fetchTimetable` and `parseNeisTimetable`, supporting `els`, `mis`, `his`, and `sps` school levels and mapping JSON rows to `Lesson` objects.

## 3. Caveats

- NEIS Open API timetable data generally does not disclose individual teacher names due to Korean Ministry of Education privacy guidelines (teacher field is left empty in NEIS timetable entries, unlike Comcigan which includes teacher abbreviations).
- If an offline user runs the app for the very first time on a fresh install without any previous online sync and without internet connection, the system gracefully falls back to the conflict-free demo timetable.

## 4. Conclusion

All timetable engine components across `packages/common/bst_timetable` and `apps/boardest_teacher` have been inspected, hardened against edge cases (grade/class out of range, missing teachers, weekend schedules), and equipped with resilient local caching. All 15 tests in `bst_timetable` and 6 tests in `boardest_teacher` pass with 0 lint warnings.

## 5. Verification Method

To independently verify:
1. Run timetable package unit tests:
   ```powershell
   flutter test packages/common/bst_timetable/
   ```
   *Expected outcome*: 15 passed tests, exit code 0.
2. Run timetable package static analysis:
   ```powershell
   flutter analyze packages/common/bst_timetable/
   ```
   *Expected outcome*: "No issues found!".
3. Run teacher app timetable tests:
   ```powershell
   cd apps/boardest_teacher
   flutter test test/comcigan_service_test.dart
   ```
   *Expected outcome*: 6 passed tests, exit code 0.
4. Verify files modified:
   - `packages/common/bst_timetable/lib/bst_timetable.dart`
   - `packages/common/bst_timetable/lib/src/services/comcigan_service.dart`
   - `packages/common/bst_timetable/lib/src/services/neis_service.dart`
   - `packages/common/bst_timetable/test/bst_timetable_test.dart`
   - `packages/common/bst_timetable/test/adversarial_challenge_test.dart`
   - `apps/boardest_teacher/lib/services/storage_service.dart`
   - `apps/boardest_teacher/lib/services/comcigan_service.dart`
   - `apps/boardest_teacher/lib/views/teacher_timetable_popup_dialog.dart`
   - `apps/boardest_teacher/test/comcigan_service_test.dart`
