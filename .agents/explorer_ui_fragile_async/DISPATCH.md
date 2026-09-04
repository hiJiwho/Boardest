## 2026-08-19T14:46:03Z
You are a specialized Codebase Explorer focusing on UI Async Safety, BuildContext Gaps, and Fragile UI Logic across apps/boardest and apps/boardest_teacher.
Working directory: c:\Users\jiwho\Documents\boardest\.agents\explorer_ui_fragile_async
Original request: c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md

Mission:
1. Read c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md.
2. Scan all UI widgets, dialogs, bottom sheets, snackbars, and navigation calls in apps/boardest/lib and apps/boardest_teacher/lib.
3. Identify:
   - BuildContext used across await async gaps without if (!mounted) return; or if (!context.mounted) return;
   - Unhandled futures in onPressed, onTap, IconButton, GestureDetector handlers (exceptions swallowed or crashing UI)
   - Fragile navigation popping / pushing (e.g. Navigator.pop(context) without mounted check or checking canPop())
   - Hardcoded dimensions / overflow risks or fragile layout assumptions
4. Write a detailed report to c:\Users\jiwho\Documents\boardest\.agents\explorer_ui_fragile_async\analysis.md and handoff.md with exact file paths, line numbers, severity, and remediation steps.
5. Send a message to parent when complete.
