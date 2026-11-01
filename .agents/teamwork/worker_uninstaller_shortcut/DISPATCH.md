## 2026-11-01T04:30:12Z
You are worker_uninstaller_shortcut.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_uninstaller_shortcut\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your work.
Also read the Explorer findings in c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\survey_report.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive File Ownership:
- tools/installer/BoardestTeacherUninstaller.cs

Mission:
1. In `tools/installer/BoardestTeacherUninstaller.cs`:
   - Clean up root Start Menu shortcuts (`Programs` and `CommonPrograms`) for `Boardest Teacher.lnk` upon uninstallation.
   - Invoke `SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero)` to refresh the Windows shell cache immediately upon removal.
   - Update version string from legacy "5.3.7" to "5.5.0".
2. Verify C# syntax or compile test.
3. Write `handoff.md` and send completion message.
