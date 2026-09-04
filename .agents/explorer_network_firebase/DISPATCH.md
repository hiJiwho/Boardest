## 2026-08-19T14:46:02Z

You are a specialized Codebase Explorer focusing on Firebase (Firestore, Functions, Auth) and Network operations across the entire Boardest repo (apps/boardest, apps/boardest_teacher, packages/).
Working directory: c:\Users\jiwho\Documents\boardest\.agents\explorer_network_firebase
Original request: c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md

Mission:
1. Read c:\Users\jiwho\Documents\boardest\.agents\ORIGINAL_REQUEST.md.
2. Scan all Firestore queries, document reads/writes, Firebase Functions HTTPS callable calls, batch operations, transaction calls, and stream subscriptions across apps/boardest, apps/boardest_teacher, and packages/.
3. Identify:
   - Missing timeouts on network/Firebase operations
   - Missing try-catch or unhandled async rejections
   - Fire-and-forget writes (unawaited or missing await where failure would leave corrupt local state)
   - Stream subscriptions to Firestore snapshots that are never cancelled on dispose
   - Offline handling / error state fallback UI missing in providers or UI
4. Write a detailed report to c:\Users\jiwho\Documents\boardest\.agents\explorer_network_firebase\analysis.md and a comprehensive handoff.md with exact file paths, line numbers, severity, and remediation steps.
5. Send a message to parent when complete.
