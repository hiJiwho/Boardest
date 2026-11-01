## 2026-11-01T04:29:57Z
You are worker_assessment_class.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_assessment_class\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your work.
Also read the Explorer findings in c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\survey_report.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive File Ownership:
- apps/boardest/lib/views/components/bst_class_main_layout.dart

Mission:
1. In `bst_class_main_layout.dart`:
   - Replace the 30-second slow polling delay with fast synchronization (e.g. 1~2s poll or immediate SSE stream listener / push trigger for notices and assessments).
   - Ensure notices and assessments are strictly filtered and isolated by the current classroom ID.
   - Ensure instantaneous display update when a new assessment or notice is received.
2. Run `flutter analyze apps/boardest` to verify no errors.
3. Write `handoff.md` and send completion message.
