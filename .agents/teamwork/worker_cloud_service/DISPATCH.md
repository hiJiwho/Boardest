## 2026-11-01T04:30:36Z
You are worker_cloud_service.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_cloud_service\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your work.
Also read PROJECT.md interface contracts.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive File Ownership:
- packages/common/bst_cloud/lib/src/bst_cloud_service.dart

Mission:
1. Complete `getOnlineClassrooms()` and `approveConnectionRequest()` in `bst_cloud_service.dart`:
   - `getOnlineClassrooms(String schoolCode)`: Query classrooms under `schools/{schoolCode}/classrooms` or active RTDB presence nodes.
   - `approveConnectionRequest(String requestId)`: Approve pending pairing requests and set status to connected.
2. Verify Google Drive OAuth token exchange and DriveCast board pairing protocol.
3. Run `flutter test packages/common/bst_cloud` and `packages/common/bst_cast`.
4. Write `handoff.md` and send completion message.
