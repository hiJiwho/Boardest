## 2026-11-01T04:18:23Z
You are worker_m4_1.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_m4_1\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your work.
Also read the Explorer findings report at:
c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\survey_report.md
and c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\handoff.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive File Ownership:
- apps/boardest/boardest_ppt_overlay.cs

Mission: Implement Milestone 4 (Features 21, 22, 23 in PROJECT.md):
1. COM Rejection Auto-Retry:
   - In `apps/boardest/boardest_ppt_overlay.cs`, update `OleMessageFilter.RetryRejectedCall` so that it retries both `SERVERCALL_REJECTED` (`dwRejectType == 1`) and `SERVERCALL_RETRYLATER` (`dwRejectType == 2`) for up to 10 seconds (10000ms, returning 150ms retry interval).
   - This eliminates COM `0x80010001 (RPC_E_CALL_REJECTED)` and prevents the overlay from dropping to standalone mode when PowerPoint is busy.
2. 100% Full-Screen InkCanvas & Floating Bottom Dock Layout:
   - Restructure the UI Grid layout in `InitUI`: Remove the row division where `_inkCanvas` was trapped in Row 0 while `toolBorder` occupied Row 1.
   - Position `_inkCanvas` to cover 100% of the screen width and height.
   - Position `toolBorder` (toolbar dock) as a floating overlay at the bottom center of the primary monitor, allowing annotations to be drawn everywhere on the screen without masking the bottom 80~100px.
3. Verification:
   - Compile `boardest_ppt_overlay.cs` using C# compiler (e.g. `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:winexe /out:test_overlay.exe apps\boardest\boardest_ppt_overlay.cs` or test compilation).
   - Record compilation logs, verification steps, and code changes in `c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_m4_1\handoff.md`.
   - Send completion message to parent when done.
