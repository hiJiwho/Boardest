## 2026-11-01T04:30:08Z
[Message] timestamp=2026-11-01T04:30:08Z sender=5f2157b5-ad8b-4304-bdf1-235163c68948 priority=MESSAGE_PRIORITY_HIGH content=You are worker_online_installer.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_online_installer\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your work.
Also read the Explorer findings in c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\survey_report.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive File Ownership:
- tools/installer/BoardestTeacherInstaller.cs

Mission:
1. In `tools/installer/BoardestTeacherInstaller.cs`:
   - Synchronize with `BoardestInstaller.cs` to add root Start Menu shortcut creation (`Environment.SpecialFolder.Programs` and `CommonPrograms`) for "Boardest Teacher.lnk".
   - Invoke `SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero)` (SHCNE_ASSOCCHANGED) to immediately flush Windows 10/11 Shell shortcut caches so the icon appears instantly in the Start Menu.
   - Update installer product version constant to "5.5.0".
2. Verify C# syntax or compile test.
3. Write `handoff.md` and send completion message.
