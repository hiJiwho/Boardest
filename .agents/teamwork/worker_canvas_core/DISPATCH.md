## 2026-11-01T04:30:41Z
You are worker_canvas_core.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\worker_canvas_core\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your work.
Also read PROJECT.md interface contracts.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Mission:
1. In `packages/plugins/bst_pen/`:
   - Support both `{'dx': double, 'dy': double}` and `{'x': double, 'y': double}` in stroke point parsing (`(p['dx'] ?? p['x'] as num).toDouble()`).
   - Ensure `AnnotationStroke` and `BstPenData` serialization & deserialization are 100% bi-directional and backward compatible with existing `.bstpen` files.
2. Run `flutter test packages/plugins/bst_pen/` to verify all tests pass.
3. Write `handoff.md` and send completion message.
