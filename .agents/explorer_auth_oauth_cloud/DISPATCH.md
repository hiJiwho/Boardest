# Dispatch: Explorer Auth, OAuth & Cloud Token Sync

## Mission
Investigate Teacher OAuth, account linking, Google Drive cloud token sync, OTP/pin remote pairing, and casting.

## Scope
- `boardest-teacher-oauth` web portal (Direct Google OAuth 2.0, School ID verification, Comsigan teacher auto-matching, profile registration/edit/revoke).
- `packages/bst_auth`, `packages/bst_cloud`, `apps/boardest_teacher`, `apps/boardest`.
- Google Drive cloud tokens (`teacher_cloud_tokens`), OTP 6-digit pin authentication, real-time lesson material casting.
- Locate all bugs, exceptions, missing error handling, type mismatches, race conditions.

## Required Outputs
Write comprehensive findings in `.agents/explorer_auth_oauth_cloud/analysis.md` and standard 5-component `handoff.md`.
Report back when finished.
