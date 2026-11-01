# Handoff Report — NEIS School Meal Service & Allergy Synchronization (worker_meal_service)

## 1. Observation
1. **`apps/boardest_teacher/lib/models/meal_models.dart`**:
   - `_allergyCodeMap` had incomplete and duplicated entries (e.g. `8: '갑각'`, `9: '갑각'`) instead of standard NEIS 1~19 specifications (`8: '게'`, `9: '새우'`, `13: '아황산류'`, `18: '조개류'`).
   - `MealDishItem` lacked `allergyCodes` (`List<int>`) and `matchesAllergy(dynamic filter)`.
   - `MealDayInfo` lacked `hasAllergy(dynamic filter)`.
2. **`apps/boardest_teacher/lib/services/neis_service.dart`**:
   - `fetchMonthMeals` had no persistent offline caching mechanism: on network failure or offline mode, it simply caught the exception and returned `{}`.
   - `fetchTodayMeal` stripped allergy information with `_cleanMealMenu` before returning.
3. **`apps/boardest_teacher/lib/views/monthly_meal_calendar_dialog.dart`**:
   - `_allergyLabels` only had 8 items with erroneous index mapping (e.g., `9: '9.토마토'` instead of `새우`, missing 11 of the 19 standard allergens).
   - Filter matching was evaluated as `dish.allergies.any((a) => a.contains('$_selectedAllergyFilter'))`, comparing a Korean string name against an integer filter string `'1'`, failing to match properly.
4. **`apps/boardest_teacher/lib/views/meal_view.dart`**:
   - Rendered dishes as plain unparsed strings in chips without distinct visual badge separation for allergens.
5. **`apps/boardest_teacher/lib/services/tbp/tbp_storage_service.dart`**:
   - Contained a duplicate variable declaration `final rootPenFile` at line 971 colliding with line 925, causing compilation failure during `flutter test`.
6. **`apps/boardest_teacher_lite/lib/main.dart`**:
   - `_fetchNeisMeal()` hardcoded `ATPT_OFCDC_SC_CODE=B10&SD_SCHUL_CODE=7010260`, completely stripped allergy numbers with `raw.replaceAll(RegExp(r'\([0-9\.\*]+\)'), '')`, and lacked monthly meal fetching, offline caching, and allergy badges.

## 2. Logic Chain
1. Standard NEIS school meal API specifies 19 allergy categories (1.난류, 2.우유, 3.메밀, 4.땅콩, 5.대두, 6.밀, 7.고등어, 8.게, 9.새우, 10.돼지고기, 11.복숭아, 12.토마토, 13.아황산류, 14.호두, 15.닭고기, 16.쇠고기, 17.오징어, 18.조개류, 19.잣).
2. By implementing `allergyCodes` list and `matchesAllergy` on `MealDishItem` alongside `hasAllergy` on `MealDayInfo`, allergy filtering reliably matches both numeric codes (1..19) and Korean textual representations (e.g., '게', '새우', '닭고기', '소고기').
3. By introducing `saveOfflineMonthCache` and `loadOfflineMonthCache` using `SharedPreferences` in `NeisService` and `LiteNeisMealService`, monthly meal plans fetched online are cached locally to disk (`bst_month_meals_$cacheKey` and `bst_lite_month_$cacheKey`). When a teacher opens the calendar offline, the app restores and displays the month's meal data and allergy warnings without network access.
4. Upgraded `MonthlyMealCalendarDialog` in `boardest_teacher` with all 19 allergy filter chips, cell warning indicators (`⚠️`), and colored badge chips in the day detail bottom sheet.
5. Resolved `rootPenFile` duplicate variable declaration in `apps/boardest_teacher/lib/services/tbp/tbp_storage_service.dart` to `legacyRootPenFile`.
6. Designed and created `apps/boardest_teacher_lite/lib/models/meal_models.dart`, `services/neis_meal_service.dart`, and `views/monthly_meal_calendar_dialog.dart`, integrating school code resolution, 1~19 allergy parsing with badges, monthly calendar dialog, and offline caching into `boardest_teacher_lite`.
7. Created and executed targeted unit tests in `apps/boardest_teacher/test/meal_service_test.dart` and `apps/boardest_teacher_lite/test/meal_service_test.dart`, verifying complete 1~19 allergy parsing and offline cache recovery.

## 3. Caveats
- NEIS Open API rate limits or network timeout policies may vary on live networks; however, offline persistent caching guarantees previously loaded month data is displayed seamlessly regardless of connectivity status.
- When no cached data exists and device is completely offline on initial first run, the service falls back gracefully with a clear informative status message rather than crashing.

## 4. Conclusion
NEIS School Meal Service in both `apps/boardest_teacher` and `apps/boardest_teacher_lite` has been verified, enhanced, and validated.
- All 19 standard NEIS allergy categories (1~19) parse correctly from raw `DDISH_NM` with both numeric and keyword matching.
- Allergy badges and warning indicators are displayed in both daily views and monthly meal calendar dialogs.
- Persistent monthly meal caching via `SharedPreferences` is fully active and validated for offline display.
- All 30 tests in `apps/boardest_teacher` and all 4 tests in `apps/boardest_teacher_lite` pass with 0 errors.

## 5. Verification Method
1. Run `apps/boardest_teacher` meal service unit test suite:
   ```powershell
   cd apps/boardest_teacher
   flutter test test/meal_service_test.dart
   ```
   *Expected outcome*: All 4 test cases pass (1~19 allergy parsing, edge case regex, JSON roundtrip, offline monthly cache).
2. Run `apps/boardest_teacher_lite` meal service unit test suite:
   ```powershell
   cd apps/boardest_teacher_lite
   flutter test test/meal_service_test.dart
   ```
   *Expected outcome*: All 3 test cases pass (Lite 1~19 allergy parsing, JSON roundtrip, offline today & month cache).
3. Run full test suites:
   ```powershell
   cd apps/boardest_teacher; flutter test
   cd apps/boardest_teacher_lite; flutter test
   ```
   *Expected outcome*: All tests pass (30/30 in teacher, 4/4 in teacher lite).
4. Code analysis:
   ```powershell
   cd apps/boardest_teacher; dart analyze lib/models/meal_models.dart lib/services/neis_service.dart
   cd apps/boardest_teacher_lite; dart analyze lib/models/meal_models.dart lib/services/neis_meal_service.dart
   ```
   *Expected outcome*: `No issues found!`.
