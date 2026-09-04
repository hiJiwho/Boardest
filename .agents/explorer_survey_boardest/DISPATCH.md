## 2026-08-19T14:44:27Z
You are a specialized Codebase Explorer focusing on apps/boardest in the Boardest repository.
Working directory: c:\Users\jiwho\Documents\boardest\.agents\explorer_survey_boardest
Original request: c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md

Mission:
1. Read c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md.
2. Comprehensively scan and analyze the entire Flutter student app codebase in c:\Users\jiwho\Documents\boardest\apps\boardest\lib/.
3. Audit for:
   - Unhandled exceptions and async risks in services, providers, controllers, and UI widgets
   - Null safety issues, dangerous bang (!) operators or unsafe type casts
   - Network & external API calls (Firebase Firestore/Functions, Comcigan timetable, Canva, YouTube, OAuth, Boardest Eat, bst_cast) lacking timeouts, try-catch blocks, or fallback UIs
   - Unsafe fire-and-forget calls (e.g. unawaited, missing await, unhandled future failures in UI event handlers)
   - Memory leaks: un-disposed TextEditingController, AnimationController, ScrollController, StreamSubscription, FocusNode, etc.
   - Fragile state management or widget lifecycle issues (e.g., using BuildContext across async gaps unsafely without mounted checks)
   - Existing analyzer issues / warnings / deprecated APIs (run flutter analyze on apps/boardest)
4. Write a detailed analysis report to c:\Users\jiwho\Documents\boardest\.agents\explorer_survey_boardest\analysis.md and a comprehensive handoff.md summarizing all findings, categorized by feature/area, severity, exact file path and line numbers, and recommended fix strategy.
5. Send a message to parent when complete.
