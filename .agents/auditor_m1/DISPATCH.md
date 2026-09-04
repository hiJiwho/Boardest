# Dispatch: Auditor — Milestone 1 (Shared Packages Integrity Audit)

## Mission
Perform comprehensive forensic integrity audit on all changes committed in Milestone 1 (`packages/common/**`, `packages/plugins/**`).
Audit Checklist:
1. Static analysis: inspect all modified files to ensure genuine logic implementations and no hardcoded test outputs or dummy return values.
2. Verify all test files in all 15 packages test real behavior rather than asserting trivial `expect(true, true)` or dummy constants.
3. Verify no cheating, mock facades in production code, or bypassed validations.
4. Execute test commands and static analysis to verify actual pass results.

## Required Outputs
Write forensic audit report in `.agents/auditor_m1/audit.md` and standard `handoff.md` with explicit CLEAN or INTEGRITY VIOLATION verdict.
Report back when finished.
