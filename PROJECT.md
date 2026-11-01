# Project: Boardest Ecosystem Full Inspection, Testing, and Hardening

## Architecture
- **Monorepo Structure**:
  - `apps/boardest`: Electronic blackboard application (Flutter Desktop Windows / Web / Android). Features: 3-mode canvas (pen, smart, touch), Store Level 0 TBP packaging, dHash visual page matching, `.bstpen` / `[교실ID]dhash.pen` persistent annotation, PPT/HWP overlay, cloud pairing with teacher tokens.
  - `apps/boardest_teacher`: Teacher desktop companion application (Flutter Desktop Windows / Web). Features: 18 lesson tools, Comsigan timetable, NEIS school meal viewer, DriveCast board pairing, assessment real-time sync, lesson management.
  - `apps/boardest_teacher_lite`: Lightweight teacher web/mobile companion (Flutter Web). Features: remote OTP display, timetable viewer, meal lookup.
  - `apps/boardest_class_lite`: Lightweight class web companion.
  - `boardest-teacher-oauth`: Web OAuth onboarding portal (Vanilla JS / Firebase Firestore / Google OAuth 2.0).
  - `packages/common/`: `bst_core`, `bst_auth`, `bst_cloud`, `bst_cast`, `bst_timetable`, `bst_messaging`, `bst_ui`, `bst_control`, `bst_ad`.
  - `packages/plugins/`: `bst_canva`, `bst_native`, `bst_pdf`, `bst_pen`, `bst_tbp`, `bst_video`.
  - `tools/installer/`: C# .NET unified installers and uninstallers (`BoardestInstaller.cs`, `BoardestTeacherInstaller.cs`, `BoardestTeacherUninstaller.cs`).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | 1536px Native ZoomFactor Integration | Eliminate CSS `transform: scale()` raster blur; set WebView2 native `setZoomFactor(W / 1536.0)` with 16:9 container auto-sync while protecting Canva layout | M1 | survey |
| 2 | Board Writing `[교실ID]dhash.pen` File Naming | Standardize pen files to `[교실ID]dhash.pen` (e.g. `기본_dhash.pen`, `[1반]dhash.pen`) across TBP and Canva viewers | M1 | survey |
| 3 | In-Memory 0ms Instant Restoration Cache | Implement `_pageStrokesMemory` state cache to ensure 0ms immediate board restoration upon page turn and eliminate disk I/O race conditions | M1 | survey |
| 4 | WebView2 Capture-Phase Navigation Key Guard | Block native browser key event propagation via capture listener (`preventDefault()`, `stopImmediatePropagation()`) to eliminate 2-page double-trigger | M1 | survey |
| 5 | 50ms Ultra-Fast Page Detection Trigger | Implement 50ms fast page check trigger and 350ms navigation cooldown throttle for precise 1-key 1-page movement | M1 | survey |
| 6 | Canva DOM Slide Counter Regex & Aria Parser | Extract slide numbers via DOM text regex `/\b(\d+)\s*\/\s*(\d+)\b/` and aria attributes, eliminating hardcoded `hash__1` freeze | M1 | survey |
| 7 | TBP Multi-Publisher DOM & iframe Detection | Support publisher page attributes (`[data-page]`, `[data-page-no]`, `.cur_page`, iframe URL regex, global JS objects) for reliable dHash extraction | M1 | survey |
| 8 | StorageService `hash__1` Redirection Removal | Remove forced redirect from `hash__1`/`ui_home` to `default.json` preventing cross-page stroke contamination | M1 | survey |
| 9 | Electronic Board 3-Mode Canvas & Pointer Resolution | Verify Pen, Smart, and Touch canvas modes and pointer coordinate resolution in class app | M2 | user_request |
| 10 | Teacher 18 Lesson Tools Suite | Verify and ensure stability of Timer, Dice, Random Pick, Spotlight, Magnifier, and Split Screen tools | M2 | user_request |
| 11 | Touch Click-Through & Desktop Overlay Mode | Verify Windows touch click-through and desktop transparency handling | M2 | user_request |
| 12 | NEIS School Timetable & Meal Lookup Dynamic Sync | Ensure dynamic NEIS parsing, meal caching, and offline error handling | M2 | user_request |
| 13 | Comcigan Timetable Parsing & Fallback | Verify Comcigan timetable integration and schedule synchronization | M2 | user_request |
| 14 | School Calendar & Academic Schedule Sync | Verify academic schedule parsing and UI presentation | M2 | user_request |
| 15 | Real-Time Assessment SSE / WebPush Listener | Implement fast RTDB SSE stream listener in class app eliminating 30-second polling delay (0.1s responsiveness) | M3 | survey |
| 16 | Installed Classes Fallback Protection | Fix teacher assessment lockout bug by providing a 1~12 class fallback when RTDB `/eat_calls` is empty or delayed | M3 | survey |
| 17 | Per-Class Notice Isolation & Realtime State Rendering | Ensure notices and assessments are strictly partitioned by classroom ID | M3 | survey |
| 18 | DriveCast Board Service Connection Completion | Verify `getOnlineClassrooms` and `approveConnectionRequest` in `bst_cloud_service.dart` | M3 | survey |
| 19 | Google Drive Token & TOTP Exchange | Validate RFC 6238 HMAC-SHA1 Base32 TOTP engine and Google Drive OAuth token exchange | M3 | survey |
| 20 | Boardest Teacher Lite Cloud Session Persistence | Persist query parameters and authentication state in SharedPreferences | M3 | survey |
| 21 | COM Rejection Auto-Retry Filter | Update `OleMessageFilter.RetryRejectedCall` to retry both `SERVERCALL_REJECTED` (`dwRejectType == 1`) and `SERVERCALL_RETRYLATER` (`dwRejectType == 2`) for 10s | M4 | survey |
| 22 | 100% Full-Screen InkCanvas Layer & Floating Dock | Remove Grid row partitioning so `_inkCanvas` covers 100% of the screen without bottom 80-100px masking; convert toolbar to floating dock | M4 | survey |
| 23 | PPT / HWP Slide Navigation Sync & Stroke Persistence | Verify slide change tracking, slide-bound annotation saving, and standalone fallback resilience | M4 | user_request |
| 24 | Class App Auto-Update MSIX Explicit Priority | Match `.msix` explicitly in `UpdateService` to prevent incorrect `.appx` selection and file extension mismatches | M5 | survey |
| 25 | Teacher App Unified Installer Start Menu Shortcut | Add root Start Menu shortcut creation (`Programs`, `CommonPrograms`) and `SHChangeNotify(0x08000000)` shell cache flush to `BoardestTeacherInstaller.cs` | M5 | survey |
| 26 | Teacher App Uninstaller Root Shortcut Cleanup | Clean up root `Boardest Teacher.lnk` and align version in `BoardestTeacherUninstaller.cs` | M5 | survey |
| 27 | Desktop Analyzer Conditional Web Import Guards | Add conditional compilation / stub guards for `dart:js_util` to achieve zero static analyzer compile-time errors on Windows | M6 | survey |
| 28 | Monorepo 22 Packages Unit & Widget Test Suite | Ensure 100% pass across all unit and widget tests in `packages/**` and `apps/**` | M6 | survey |
| 29 | Monorepo Full Build & Release Notes (`Ver.md`) | Verify `flutter build windows` and `flutter build web` success and update `Ver.md` release notes | M6 | survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | TBP 스마트교과서 및 캔바 뷰어 완성도 | `apps/boardest`, `apps/boardest_teacher`, `packages/plugins/bst_tbp`, `packages/plugins/bst_canva` | none | PASSED |
| M2 | 교실/교사 메인 기능 & 수업 도구 총점검 | `apps/boardest`, `apps/boardest_teacher`, `packages/common/bst_timetable`, `packages/plugins/bst_pen` | none | PASSED |
| M3 | 수행평가 실시간 동기화 & 클라우드/드라이브캐스트 연동 | `apps/boardest`, `apps/boardest_teacher`, `packages/common/bst_cloud`, `packages/common/bst_auth` | none | PASSED |
| M4 | PPT / HWP 오버레이 판서 & COM 자동 재시도 | `apps/boardest/boardest_ppt_overlay.cs`, `packages/plugins/bst_native` | none | PASSED |
| M5 | 배포 패키징, MSIX 자동 업데이트 & 인스톨러/언인스톨러 | `apps/boardest/lib/services/update_service.dart`, `tools/installer/**`, `scripts/build_all_appx.ps1` | none | PASSED |
| M6 | 모노레포 전체 빌드, 린트 제로 에러 & 100% E2E 검증 | All apps and packages | M1, M2, M3, M4, M5 | PASSED |

## Interface Contracts
### Pen Annotation Storage Contract
- File Name Format:
  - If classId is empty or '기본': `기본_[dHash].pen`
  - If classId has brackets: `[classId][dHash].pen` (e.g. `[1반]dhash.pen`)
  - If classId lacks brackets: `[${classId}][dHash].pen`
- Storage Folders (multi-path lookup):
  1. `${tbpFolderPath}/PEN/${fileName}`
  2. `${tbpFolderPath}/${fileName}`
  3. `${tbpFolderPath}/PEN/${safeClass}_${safeHash}.pen`
  4. Legacy `${tbpFolderPath}/BBPen/${safeClass}/${safeHash}.svg`
  5. Legacy `${tbpFolderPath}/PEN/${safeHash}.bstpen`
- Memory Cache Contract:
  - State cache key: `${classId}::${dHash}`
  - Page navigation restores from memory in 0ms synchronously before asynchronous disk flush.

### COM OleMessageFilter Contract
- Interface: `IOleMessageFilter`
- `RetryRejectedCall(IntPtr hTaskCallee, int dwTickCount, int dwRejectType)`:
  - If `dwTickCount < 10000` (10 seconds), return `150` (retry after 150ms) for both `SERVERCALL_REJECTED` (`dwRejectType == 1`) and `SERVERCALL_RETRYLATER` (`dwRejectType == 2`).
  - If `dwTickCount >= 10000`, return `-1` to cancel call.

### TOTP Authentication Contract
- Secret Format: Base32 encoded string (e.g. `JBSWY3DPEHPK3PXP`)
- Hash Algorithm: RFC 6238 HMAC-SHA1
- Time Step: 60 seconds (1 minute epoch counter)
- Code Length: 6 digits (`000000` - `999999`)
- Verification: `TotpService.verifyOtp(secret, otp)` returns true if OTP matches within +/- 1 step window.

### Firestore Schema Contract
- Collection `teacher_profiles`: `{ uid, email, teacherName, schoolId, schoolName, updatedAt }`
- Collection `teacher_cloud_tokens`: `{ uid, email, teacherName, schoolId, googleDriveToken, totpSecret, updatedAt }`
- Doc ID standard: `email.replaceAll('.', '_').replaceAll('@', '_')`

## Code Layout
- `apps/boardest/`: Electronic blackboard application
- `apps/boardest_teacher/`: Teacher desktop app
- `apps/boardest_teacher_lite/`: Teacher web/mobile lite app
- `apps/boardest_class_lite/`: Class web companion
- `boardest-teacher-oauth/`: Teacher OAuth web portal
- `packages/common/`: Shared common domain packages
- `packages/plugins/`: Shared UI / canvas / media / viewer plugin packages
- `tools/installer/`: C# installer and uninstaller sources
- `scripts/`: Packaging and verification scripts
- `Ver.md`: Global version release notes and changelog


## Component Verification Matrix (25 Ecosystem Components)
| # | Component | Target App / Module | Scope & Core Responsibility | Status |
|---|-----------|---------------------|-----------------------------|--------|
| C01 | TBP E-Textbook Viewer | `apps/boardest`, `apps/boardest_teacher`, `bst_tbp` | Store Level 0 TBP packaging, 1536px native zoom, 1-page step | PASSED |
| C02 | Canva Presentation Viewer | `apps/boardest`, `apps/boardest_teacher`, `bst_canva` | HTML iframe viewer, slide counter regex, responsive layout | PASSED |
| C03 | Electronic Blackboard Canvas | `apps/boardest`, `bst_pen` | 3-mode canvas (Pen, Smart, Touch), pointer coordinate resolution | PASSED |
| C04 | Annotation Floating Dock | `apps/boardest`, `apps/boardest_teacher` | Pen width, color palette, eraser, undo/redo, dock positioning | PASSED |
| C05 | Timer & Stopwatch Tool | `apps/boardest_teacher` | Lesson countdown timer, alarm sound, persistent overlay | PASSED |
| C06 | Dice & Random Student Picker | `apps/boardest_teacher` | 3D physics dice roll, random student drawing, fair shuffle | PASSED |
| C07 | Spotlight & Magnifier Tool | `apps/boardest_teacher` | Screen darkening with circular focus spotlight and magnification | PASSED |
| C08 | Split Screen Dual Board | `apps/boardest_teacher`, `apps/boardest`, `bst_pen` | 2-way and 4-way vertical/horizontal canvas partitioning, resize handles, 1:1 reset, coordinate bleed isolation | PASSED |
| C09 | Assessment Notice Isolation | `apps/boardest_teacher`, `apps/boardest` | Per-classroom notice targeting, student assessment secrecy | PASSED |
| C10 | Assessment Real-Time Sync | `apps/boardest_teacher`, `apps/boardest` | 1~12 class real-time sync, uninstalled class fallback protection | PASSED |
| C11 | NEIS School Timetable Sync | `apps/boardest_teacher`, `boardest_teacher_lite` | Dynamic NEIS API parsing, offline cache, teacher schedule view | PASSED |
| C12 | NEIS School Meals Viewer | `apps/boardest_teacher`, `boardest_teacher_lite` | Monthly meal calendar, allergy code indicators, nutritional info | PASSED |
| C13 | Comcigan Timetable Engine | `apps/boardest_teacher`, `bst_timetable` | Comcigan Worker integration, school code lookup, auto-refresh | PASSED |
| C14 | School Calendar & Events | `apps/boardest_teacher` | Academic milestone display, exam schedules, vacation lookup | PASSED |
| C15 | PPT Overlay COM Controller | `apps/boardest/boardest_ppt_overlay.cs` | 10s auto-retry on rejection, slide tracking, full-screen canvas | PASSED |
| C16 | HWP Document Overlay | `packages/plugins/bst_native` | Windows HWP document detection and transparent ink overlay | PASSED |
| C17 | Screen Recorder & Smart Capture | `packages/plugins/bst_video`, `bst_native` | Area screenshot, full screen recording, instant clipboard paste | PASSED |
| C18 | Cloud Drive & Lesson Asset Sync | `packages/common/bst_cloud`, `boardest-teacher-oauth` | Google Drive OAuth token exchange, lesson asset sync | PASSED |
| C19 | DriveCast & Remote Pairing | `packages/common/bst_cast`, `apps/boardest` | QR code / OTP board pairing, remote screen cast protocol | PASSED |
| C20 | Boardest Class Lite | `apps/boardest_class_lite` | Lightweight web blackboard for browser-only environments | PASSED |
| C21 | Boardest Teacher Lite | `apps/boardest_teacher_lite` | Web/mobile companion for timetable, meal, and remote OTP view | PASSED |
| C22 | MSIX Class Auto-Updater | `apps/boardest/lib/services/update_service.dart` | GitHub Release `.msix` priority matching, background download | PASSED |
| C23 | Unified Online Installer | `tools/installer/BoardestInstaller.cs` | WebView2 runtime bootstrapper, MSIX side-loader, registry setup | PASSED |
| C24 | Teacher Uninstaller & Shortcuts | `tools/installer/BoardestTeacherUninstaller.cs` | Root Start Menu shortcut removal, SHChangeNotify cache flush | PASSED |
| C25 | TOTP Security & Passkey Engine | `packages/common/bst_auth`, `bst_core` | RFC 6238 HMAC-SHA1 Base32 verification, school ID validation | PASSED |
