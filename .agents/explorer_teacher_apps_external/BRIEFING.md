# BRIEFING — 2026-08-21T13:22:30Z

## Mission
Investigate Teacher Desktop/Web apps, Comsigan timetable integration, NEIS school meals integration, school messaging, and universal IO guards for cross-platform compatibility.

## 🔒 My Identity
- Archetype: teamwork_preview_explorer
- Roles: explorer, analyst, synthesizer
- Working directory: c:/Users/jiwho/Documents/boardest/.agents/explorer_teacher_apps_external
- Original parent: 5b553c4b-47d7-462b-ae55-1cabb38236d4
- Milestone: Teacher Apps & External Integrations Investigation

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Investigate apps/boardest_teacher, apps/boardest_teacher_lite, packages/bst_timetable, NEIS meals, messaging, lesson tools, universal IO guards, unhandled exceptions

## Current Parent
- Conversation ID: 5b553c4b-47d7-462b-ae55-1cabb38236d4
- Updated: 2026-08-21T13:22:30Z

## Investigation State
- **Explored paths**:
  - `apps/boardest_teacher` (`main.dart`, `views/teacher_view.dart`, `services/storage_service.dart`, `services/comcigan_service.dart`, `services/neis_service.dart`, `services/cloud_drive_service.dart`, `views/meal_view.dart`, `views/message_view.dart`, `views/browser_board_view.dart`, `views/web_hwp_ppt_view.dart`, `views/tbp/tbp_viewer_route.dart`, etc.)
  - `apps/boardest_teacher_lite` (`lib/main.dart`, `pubspec.yaml`, `test/widget_test.dart`)
  - `packages/common/bst_timetable` (`lib/src/services/comcigan_service.dart`, `lib/src/services/neis_service.dart`, `test/bst_timetable_test.dart`)
  - `packages/common/bst_messaging`, `bst_auth`, `bst_core`, `packages/plugins/bst_native`
- **Key findings**:
  - BUG-01: OTP generation mismatch between teacher apps (HMAC-SHA256) and electronic board (RFC 6238 Base32 HMAC-SHA1).
  - BUG-02: Universal IO guard violations in Web platform (`storage_service.dart`, `meal_view.dart`, `browser_board_view.dart`, `web_hwp_ppt_view.dart`, `tbp_viewer_route.dart`, native services).
  - BUG-03: Teacher Lite OAuth session loss on page refresh (missing `SharedPreferences` write).
  - BUG-04: Teacher Lite timetable dummy data display and hardcoded Yangdong Middle School NEIS code.
  - BUG-05: `bst_timetable` package incomplete and unused (contains `Unsupported platform` exception for non-web).
  - BUG-06: Broken test suites in `boardest_teacher_lite`, `bst_timetable`, `bst_messaging`, `bst_auth`.
- **Unexplored areas**: None. Investigation complete.

## Key Decisions Made
- Fully documented all 7 key defects and platform crash risks with exact line numbers and code snippets.
- Formulated precise remediation recommendations and test suite overhaul plan.
- Generated `analysis.md` and standard 5-component `handoff.md`.

## Artifact Index
- `analysis.md` — Comprehensive in-depth investigation report
- `handoff.md` — Standard 5-component handoff report (Observation, Logic Chain, Caveats, Conclusion, Verification Method)
- `progress.md` — Liveness heartbeat
