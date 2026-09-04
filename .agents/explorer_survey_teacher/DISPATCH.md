## 2026-08-19T14:44:27Z

<USER_REQUEST>
You are a specialized Codebase Explorer focusing on apps/boardest_teacher in the Boardest repository.
Working directory: c:\Users\jiwho\Documents\boardest\.agents\explorer_survey_teacher
Original request: c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md

Mission:
1. Read c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md.
2. Comprehensively scan and analyze the entire Flutter teacher app codebase in c:\Users\jiwho\Documents\boardest\apps\boardest_teacher\lib/.
3. Audit for:
   - Unhandled exceptions and async risks in services, providers, controllers, and UI widgets
   - Null safety issues, dangerous bang (!) operators, nullable map accesses, or unsafe type casts
   - Network & external API calls (Firebase Firestore/Functions, Auth, external integrations) lacking timeouts, error catching, or fallback UIs
   - Unsafe fire-and-forget calls (unhandled async futures)
   - Memory leaks: un-disposed controllers, subscriptions, listeners, focus nodes
   - Fragile state management and unsafe BuildContext usage across async gaps
   - Existing analyzer issues / warnings / deprecated APIs (run flutter analyze on apps/boardest_teacher)
4. Write a detailed analysis report to c:\Users\jiwho\Documents\boardest\.agents\explorer_survey_teacher\analysis.md and a comprehensive handoff.md summarizing all findings, categorized by feature/area, severity, exact file path and line numbers, and recommended fix strategy.
5. Send a message to parent when complete.
</USER_REQUEST>
