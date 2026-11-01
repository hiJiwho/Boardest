## 2026-11-01T04:29:52Z
You are worker_assessment_teacher.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_assessment_teacher\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your work.
Also read the Explorer findings in c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\survey_report.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive File Ownership:
- apps/boardest_teacher/lib/services/assessment_service.dart
- apps/boardest_teacher/lib/views/teacher_assessment_view.dart

Mission:
1. Fix the 1~12 class lockout bug in `assessment_service.dart` and `teacher_assessment_view.dart`:
   - In `fetchInstalledClasses`, when network times out, returns an empty set, or errors, provide a fallback returning all classes 1~12 as available `{1: {1,2,3,4,5,6,7,8,9,10,11,12}, ...}` or safe fallback so teachers are never locked out from selecting classes.
   - In `teacher_assessment_view.dart`, ensure that even if a class is marked '미설치', the teacher can still select it with a warning or fallback, eliminating the bug where `selectedClasses.isEmpty` blocks notice creation.
2. Ensure strict per-classroom notice isolation and verify real-time state rendering.
3. Run `flutter analyze apps/boardest_teacher` or relevant test commands.
4. Write `handoff.md` and send completion message.
