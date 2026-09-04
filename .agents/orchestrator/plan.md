# Plan: Boardest Platform Codebase Audit and Proactive Bug-Fixing Sweep

## Objectives
1. Perform exhaustive audit and bug fixing across `apps/boardest`, `apps/boardest_teacher`, and `packages/`.
2. Secure network & async operations (Firebase Firestore/Functions, Comcigan, Canva, YouTube) with proper timeouts, try-catch, fallbacks, and eliminate unawaited/fire-and-forget calls.
3. Refactor fragile/brittle code patterns while preserving core business logic.
4. Ensure `flutter analyze` passes cleanly across all packages/apps with zero new warnings/errors.
5. Ensure `flutter build web` succeeds for both `boardest` and `boardest_teacher`.
6. Ensure core functionalities (OAuth, Boardest Eat, Comcigan timetable, bst_cast) remain fully intact.

## Workflow Phases
- **Phase 0: Survey & Scope Mapping**
  - Dispatch 3 parallel Explorers:
    - Explorer 1: `packages/` audit (shared libraries, models, network clients, helpers, bst_cast).
    - Explorer 2: `apps/boardest/` audit (student app, widgets, providers/blocs, network calls, OAuth, Boardest Eat, timetable).
    - Explorer 3: `apps/boardest_teacher/` audit (teacher app, screens, services, Firebase/Firestore interactions, auth).
- **Phase 1: Feature Inventory & Milestones in PROJECT.md**
  - Synthesize reports into categorized bug lists & safety improvements.
- **Phase 2: Milestone Implementation Loop**
  - Dispatch Workers for packages and apps.
  - Review with Reviewers & Challengers.
  - Audit with Forensic Auditor.
- **Phase 3: Verification & Build Web Validation**
  - Run flutter analyze & flutter build web.
  - Validate core workflows.
- **Phase 4: Synthesis & Final Reporting**
