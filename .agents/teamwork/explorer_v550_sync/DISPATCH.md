## 2026-11-01T08:59:19Z
[Message] timestamp=2026-11-01T08:59:19Z sender=2ce30758-d6dd-41a8-b112-4ee17b3271df priority=MESSAGE_PRIORITY_HIGH content=You are explorer_v550_sync, a read-only exploration subagent.
Your identity: teamwork_explorer
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_v550_sync\
Original request path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md first.

Your mission:
Investigate Requirement 3: 전체 생태계 v5.5.0 (5.5.0+5500) 버전 일괄 동기화 및 25개 컴포넌트 무결성 검증, 빌드 및 배포 완료.

Detailed tasks:
1. Search and list all `pubspec.yaml` files across the entire monorepo (`apps/boardest`, `apps/boardest_teacher`, `apps/boardest_teacher_lite`, `apps/boardest_class_lite`, `packages/common/*`, `packages/plugins/*`).
   - Check the current `version:` field in each file.
   - List which files already have `5.5.0+5500` and which ones have older versions (e.g. `5.4.0`, `1.0.0`, etc.).
2. Search and list all other version-bearing configuration and installer files:
   - `tools/installer/BoardestInstaller.cs`
   - `tools/installer/BoardestTeacherInstaller.cs`
   - `tools/installer/BoardestTeacherUninstaller.cs`
   - Windows app manifests (`Package.appxmanifest` or MSIX manifests)
   - `Ver.md`
   - `scripts/build_all_appx.ps1` or other packaging scripts.
3. Review the 25-Component Verification Matrix in `c:\Users\jiwho\Documents\boardest\PROJECT.md` (C01 through C25) and `test/e2e/all_e2e_test.dart` / `TEST_READY.md`.
   - Identify the current implementation and test status of all 25 components.
   - What build and test commands are needed to verify the entire ecosystem?
4. Formulate a comprehensive synchronization and verification plan:
   - Exhaustive list of all files that must be updated to `5.5.0+5500` / `5.5.0`.
   - Build commands for Flutter Web, Flutter Windows, Flutter Android, and C# .NET installers.
   - Verification steps to ensure zero broken references or regressions.
5. Write your complete, self-contained report to:
   c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_v550_sync\handoff.md
   Include: Full File Inventory, Current vs Target Versions, Build & Test Commands, and Step-by-Step Execution Plan.
6. When finished, use send_message to report your completion to the orchestrator.
