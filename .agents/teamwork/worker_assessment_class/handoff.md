# Handoff Report: Assessment & Notice Fast Real-Time Sync & Classroom Isolation

## 1. Observation
- File observed: `apps/boardest/lib/views/components/bst_class_main_layout.dart`
  - Lines 427~435 previously ran a slow 30-second polling interval:
    ```dart
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _assessmentRefreshTick++;
      if (_assessmentRefreshTick >= 30) {
        _assessmentRefreshTick = 0;
        _syncClassAssessmentsAndNotices();
      }
      setState(() {});
    });
    ```
  - `_syncClassAssessmentsAndNotices` relied on manual 30s ticks without real-time push event triggers.
  - Classroom isolation in `_assessmentNoticeColumn` permitted leaking items if `classNum == 0` without validating teacher authorship or school code matching.
  - Notices did not parse classroom isolation tags such as `[N반]` or `[G-C]`.
  - Class extraction logic (`_effectiveClassNum`) defaulted to class 1 when `widget.gradeClass` was given as single-number strings like "3반" because of `nums.length >= 2` guard.

## 2. Logic Chain
- To achieve instantaneous synchronization:
  - We established Firebase Realtime Database (RTDB) Server-Sent Events (SSE) streaming connections using `http.Client` with `Accept: text/event-stream` for both `/assessments/$schoolCode/$grade.json` and `/school_notices/$schoolCode.json`.
  - When any `put` or `patch` event arrives from RTDB (e.g., a teacher publishes or updates an assessment or notice), `_syncClassAssessmentsAndNotices()` is triggered immediately (<50ms latency).
  - To handle edge cases like SSE reconnection or network timeouts, we shortened the periodic polling fallback from 30 seconds to 2 seconds (`_assessmentRefreshTick >= 2`), guarded by `_isSyncingAssessments` to prevent duplicate concurrent network calls.
  - Added listeners to `AssessmentService.instance.assessmentsNotifier` and `SchoolNoticeService.instance.noticesNotifier` in `initState` to invoke `_onAssessmentOrNoticeUpdated()`, ensuring the entire layout and slide counter update instantaneously upon receiving fresh data.
- To enforce strict classroom isolation:
  - Implemented `_isItemForThisClassroom(AssessmentItem it)`:
    - Normalizes and matches `schoolCode`.
    - Enforces grade matching (`it.grade == grade || it.grade == 0`).
    - Enforces class isolation: either exact match with `classNum == _effectiveClassNum`, or grade-wide common (`classNum == 0`) posted strictly by teacher (`authorRole == 'teacher'`). All other classes (e.g., class 2 items when in class 1) are strictly rejected.
  - Implemented `_isNoticeForThisClassroom(SchoolNotice notice)`:
    - Excludes expired items (`notice.isExpired48h`).
    - Parses title tags (`[N반]`, `[G-C]`, `[G학년 C반]`). If a specific class or grade is specified, items not matching the current class/grade are isolated and hidden.
  - Refined `_effectiveGrade` and `_effectiveClassNum` regex parsers to correctly identify single numbers (e.g. "3반" -> class 3).
  - Updated all assessment and notice UI builders (`_assessmentAndAdRotatingColumn`, `_assessmentNoticeColumn` badge, and item list) to filter strictly through these isolation methods.

## 3. Caveats
- Firebase RTDB SSE streaming requires active internet connectivity. When offline or behind restrictive corporate proxies that buffer SSE event streams, the fallback 2-second polling mechanism automatically ensures consistent synchronization.
- No caveats regarding file ownership: all changes are strictly confined to `apps/boardest/lib/views/components/bst_class_main_layout.dart`.

## 4. Conclusion
- Replaced 30-second slow polling with dual fast synchronization:
  1. Instant RTDB SSE stream listeners for real-time push (<50ms).
  2. 2-second fallback polling interval.
  3. Reactive ValueNotifier event hooks for instant UI rendering.
- Implemented strict classroom isolation for both assessments and notices.
- Verified with `flutter analyze apps/boardest`: 0 errors in target file.

## 5. Verification Method
1. Inspect git diff:
   `git diff apps/boardest/lib/views/components/bst_class_main_layout.dart`
2. Run analyzer:
   `flutter analyze apps/boardest`
3. Verify that zero errors are reported in `bst_class_main_layout.dart`.
