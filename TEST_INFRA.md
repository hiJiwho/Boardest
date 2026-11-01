# Boardest E2E Test Infrastructure Specification (`TEST_INFRA.md`)

## 1. Overview & Test Architecture

This document defines the 4-tier End-to-End (E2E) testing framework for the Boardest ecosystem. The Boardest ecosystem comprises electronic blackboard applications (`boardest`, `boardest_class_lite`, `boardest_class_cloud`), teacher applications (`boardest_teacher`, `boardest_teacher_lite`), shared packages (`bst_core`, `bst_pen`, `bst_tbp`, `bst_canva`, `bst_auth`, `bst_cloud`, `bst_timetable`, `bst_messaging`, `bst_ui`), and Windows native bridges (C# PPT/HWP overlays, COM OleMessageFilter, installer/uninstaller).

The E2E testing framework uses the Flutter test environment (`flutter test`) at the workspace root to exercise all subsystems, interface contracts, boundary constraints, cross-feature flows, and full-lesson lifecycle scenarios without facade or mock-pass anti-patterns.

---

## 2. Directory Layout & Test Suite Organization

```
boardest/
├── TEST_INFRA.md                         # This specification
├── TEST_READY.md                         # Test runner execution report and status
├── pubspec.yaml                          # Workspace test dependencies
└── test/
    └── e2e/
        ├── all_e2e_test.dart             # Master test suite running all tiers
        ├── tier1_feature_coverage_test.dart  # Tier 1: Feature coverage & equivalence classes
        ├── tier2_boundary_corner_test.dart   # Tier 2: Boundary conditions & corner stress
        ├── tier3_cross_feature_interaction_test.dart # Tier 3: Cross-feature orchestration
        ├── tier4_real_world_simulation_test.dart     # Tier 4: 45-minute real lesson simulation
        ├── component_matrix_test.dart                # Full 25-component verification (C01 - C25)
        └── helpers/
            └── e2e_test_fixtures.dart    # Fixtures, synthetic documents, mock data builders
```

---

## 3. Systematic 4-Tier Methodology

### Tier 1: Feature Coverage (Happy Path & Equivalence Classes)
Validates primary functionalities and positive execution paths across all core system modules:
1. **TBP Viewer & 1536px Native Zoom Engine**:
   - Verification of aspect ratio calculation: `zoomFactor = W / 1536.0` for target 16:9 canvas dimensions.
   - Perceptual dHash visual page matching using 256-bit binary/hex representation and Hamming distance threshold (`<= 64`).
2. **Canva Viewer & Slide Counter Parsing**:
   - URL sanitization and embed format transformation (`formatPresentUrl` for Canva, Google Slides, MiriCanvas).
   - DOM regex slide extraction `/\b(\d+)\s*\/\s*(\d+)\b/` eliminating hardcoded `hash__1` freeze.
3. **Pen Annotation File Naming & Format Standard**:
   - Standardized `[교실ID]dhash.pen` file naming:
     - Default class: `기본_[dHash].pen`
     - Bracketed class: `[1반]dhash.pen`
     - Non-bracketed class: `[${classId}][dHash].pen`
   - Store Level 0 (uncompressed ZIP) serialization of `.pen` documents with `manifest.json`, `pages/page_X.svg`, and media assets.
4. **Assessment Sync & Per-Class Partitioning**:
   - Real-time RTDB synchronization and normalization of school codes (e.g. `ydm`, `양동중학교` -> `ydm`).
   - Installed classes fallback protection: 1~12 class fallback when remote call tree is empty or delayed.
5. **PPT / HWP Overlay COM Auto-Retry Filter**:
   - COM `IOleMessageFilter.RetryRejectedCall` contract:
     - `SERVERCALL_REJECTED` (`dwRejectType == 1`) with `dwTickCount < 10000` -> returns `150` (retry after 150ms).
     - `SERVERCALL_RETRYLATER` (`dwRejectType == 2`) with `dwTickCount < 10000` -> returns `150`.
     - Timeout when `dwTickCount >= 10000` -> returns `-1` (cancel).
6. **Class App MSIX Auto-Update Engine**:
   - Version parsing and semantic comparison (`_isNewerVersion` with 4-part versioning).
   - Explicit `.msix` extension prioritization over `.appx` preventing binary format mismatch.
7. **Teacher Lesson Tools Suite**:
   - Countdown timer and stopwatch state transitions, pause/resume, and completion events.
   - Random picker within `[min, max]` bounds and history tracking.
   - Fair multi-sided dice roll calculation.

### Tier 2: Boundary & Corner Cases (Stress & Fault Injection)
Exercises robustness under degenerate, out-of-spec, and extreme edge conditions:
1. **Hash Degeneracy & Null Handling**:
   - Empty, whitespace-only, or `null` dHash strings handled safely without crashing or overwriting default configurations.
   - Unknown dHash falls back gracefully to `default.json` or blank template without cross-page stroke contamination.
2. **Rapid Page Turn Throttling & Cooldown**:
   - Multi-key burst input simulated within 50ms cooldown window.
   - 350ms navigation throttle blocks 2-page skipping and drops duplicate key events.
3. **Coordinate & Canvas Boundary Clamping**:
   - Zero, negative, and extreme coordinate points (`(-100, -50)`, `(10000, 50000)`) clamped or safely handled during stroke recording.
   - Zero-point and single-point strokes serialization and SVG export resilience.
4. **Network Disconnection & Offline Resiliency**:
   - Assessment fetching simulated with timeout / HTTP 500 / network drop -> immediate fallback to local `SharedPreferences` cache.
   - Cloud drive synchronization failure recovery without data loss.
5. **Corrupted & Malformed Archive Packaging**:
   - Corrupted ZIP header, empty byte array, or malformed JSON manifest in `.pen` file unpack handled cleanly without uncaught exceptions.

### Tier 3: Cross-Feature Interactions (Orchestration & State Invariants)
Verifies complex multi-module interactions and state synchronization:
1. **Slide Navigation + Pen Persistence + Classroom Switching**:
   - Classroom A writes notes on Slide 1 -> slides forward to Slide 2 -> writes notes on Slide 2.
   - Switch active classroom from `1반` to `2반` -> verify notes are strictly isolated per classroom ID.
   - Return to Slide 1 under `1반` -> verify strokes restore instantly from memory cache (`_pageStrokesMemory`) in 0ms without disk race condition.
2. **Offline Mode + Assessment Sync + Background Storage Sync**:
   - Offline mutation of student assessment -> offline queue persistence.
   - Network restoration -> state reconciliation without duplicate or lost items.
3. **Tool Overlay Interactivity with Board Writing**:
   - Running lesson timer concurrently with real-time pen strokes on active canvas.
   - Modal opening and closing preserves background drawing buffer and zoom scale.

### Tier 4: Real-World Scenarios (End-to-End Lesson Simulation)
Simulates an authentic 45-minute lesson lifecycle:
1. **Lesson Phase 1: Initiation (00:00 - 05:00)**:
   - Teacher boots classroom app (`1학년 3반`, ID: `[103]`).
   - Loads textbook package (.bstTBP) -> initializes 1536px zoom factor.
   - Displays timetable and notices for Class 103.
2. **Lesson Phase 2: Instruction & Active Annotation (05:00 - 25:00)**:
   - Teacher navigates from Page 1 to Page 15 -> draws board notes and underlines key formulas.
   - Launches 5-minute group activity Timer tool from teacher dock.
   - Rolls virtual dice for student group presentation selection.
3. **Lesson Phase 3: Dynamic Slide Transition & Retrieval (25:00 - 35:00)**:
   - Navigates through Slides 16-20 with rapid page turns (verifying zero double-page jump).
   - Jumps backward to Page 15 -> verifies 100% instant restoration of original notes from memory cache.
4. **Lesson Phase 4: Assessment & Classroom Close (35:00 - 45:00)**:
   - Broadcasts real-time assessment / quiz notification to student roster.
   - Saves final lesson board package as `[103]dhash.pen` to storage.
   - Performs clean teardown and updates local sync state.

---

## 4. Execution Commands & Verification

### Running the Full E2E Test Suite:
```bash
flutter test test/e2e/all_e2e_test.dart
```

### Running Individual Tiers:
```bash
# Tier 1: Feature Coverage
flutter test test/e2e/tier1_feature_coverage_test.dart

# Tier 2: Boundary & Corner Cases
flutter test test/e2e/tier2_boundary_corner_test.dart

# Tier 3: Cross-Feature Interactions
flutter test test/e2e/tier3_cross_feature_interaction_test.dart

# Tier 4: Real-World Lesson Simulation
flutter test test/e2e/tier4_real_world_simulation_test.dart

# 25-Component Full Matrix Verification
flutter test test/e2e/component_matrix_test.dart
```

---

## 5. Ecosystem 25-Component Verification Matrix (C01 - C25)

The test suite provides 100% assertion coverage across all 25 ecosystem components defined in `PROJECT.md`:

| # | Component Name | Target App / Module | Primary Verification Test | Assertion Type |
|---|----------------|---------------------|---------------------------|----------------|
| C01 | TBP E-Textbook Viewer | `apps/boardest`, `bst_tbp` | `C01: TBP E-Textbook Viewer` | 1536px native zoom calculation & perceptual dHash Hamming distance |
| C02 | Canva Presentation Viewer | `apps/boardest`, `bst_canva` | `C02: Canva Presentation Viewer` | DOM regex slide extraction & Canva URL embed formatting |
| C03 | Electronic Blackboard Canvas | `apps/boardest`, `bst_pen` | `C03: Electronic Blackboard Canvas` | 3-mode canvas stroke serialization & JSON deserialization |
| C04 | Annotation Floating Dock | `apps/boardest`, `bst_pen` | `C04: Annotation Floating Dock` | ToolMode transitions (pen/eraser), stroke addition, undo, & clear |
| C05 | Timer & Stopwatch Tool | `apps/boardest_teacher` | `C05: Timer & Stopwatch Tool` | Countdown timer ticks, state transitions, pause & resume |
| C06 | Dice & Random Student Picker | `apps/boardest_teacher` | `C06: Dice & Random Student Picker` | Range constraints `[min, max]`, fair distribution |
| C07 | Spotlight & Magnifier Tool | `apps/boardest_teacher` | `C07: Spotlight & Magnifier Tool` | Radial focus geometry & distance calculations |
| C08 | Split Screen Dual Board | `apps/boardest_teacher` | `C08: Split Screen Dual Board` | 2-way vertical & 4-way quadrant pixel partitioning |
| C09 | Assessment Notice Isolation | `apps/boardest_teacher`, `apps/boardest` | `C09: Assessment Notice Isolation` | Per-classroom notice partitioning & data secrecy |
| C10 | Assessment Real-Time Sync | `apps/boardest_teacher`, `apps/boardest` | `C10: Assessment Real-Time Sync` | 1~12 class fallback protection when RTDB state is empty |
| C11 | NEIS School Timetable Sync | `apps/boardest_teacher`, `boardest_teacher_lite` | `C11: NEIS School Timetable Sync` | Timetable slot structure & period lookup |
| C12 | NEIS School Meals Viewer | `apps/boardest_teacher`, `boardest_teacher_lite` | `C12: NEIS School Meals Viewer` | HTML tag removal, allergy code cleanup, & formatting |
| C13 | Comcigan Timetable Engine | `apps/boardest_teacher`, `bst_timetable` | `C13: Comcigan Timetable Engine` | Weekly day schedule grid & period assignment |
| C14 | School Calendar & Events | `apps/boardest_teacher` | `C14: School Calendar & Events` | Academic milestone parsing (exams, breaks) |
| C15 | PPT Overlay COM Controller | `apps/boardest/boardest_ppt_overlay.cs` | `C15: PPT Overlay COM Controller` | 10s auto-retry on rejection (SERVERCALL_RETRYLATER/REJECTED) |
| C16 | HWP Document Overlay | `packages/plugins/bst_native` | `C16: HWP Document Overlay` | Transparent overlay initialization & click-through flags |
| C17 | Screen Recorder & Smart Capture | `packages/plugins/bst_video`, `bst_native` | `C17: Screen Recorder & Smart Capture` | Selection bounding box geometry & dimensions |
| C18 | Cloud Drive & Lesson Asset Sync | `packages/common/bst_cloud` | `C18: Cloud Drive & Lesson Asset Sync` | Lesson asset metadata serialization |
| C19 | DriveCast & Remote Pairing | `packages/common/bst_cast`, `apps/boardest` | `C19: DriveCast & Remote Pairing` | 6-digit board pairing OTP regex format & validation |
| C20 | Boardest Class Lite | `apps/boardest_class_lite` | `C20: Boardest Class Lite` | Query parameter parsing (`room`, `mode`) |
| C21 | Boardest Teacher Lite | `apps/boardest_teacher_lite` | `C21: Boardest Teacher Lite` | Teacher session credential persistence |
| C22 | MSIX Class Auto-Updater | `apps/boardest/lib/services/update_service.dart` | `C22: MSIX Class Auto-Updater` | Explicit `.msix` priority matching over `.appx` |
| C23 | Unified Online Installer | `tools/installer/BoardestInstaller.cs` | `C23: Unified Online Installer` | Bootstrapper launch arguments & channel options |
| C24 | Teacher Uninstaller & Shortcuts | `tools/installer/BoardestTeacherUninstaller.cs` | `C24: Teacher Uninstaller & Shortcuts` | Windows Start Menu shortcut path resolution |
| C25 | TOTP Security & Passkey Engine | `packages/common/bst_auth`, `bst_core` | `C25: TOTP Security & Passkey Engine` | RFC 6238 HMAC-SHA1 Base32 OTP generation & verification |

---

## 6. Pass/Fail Criteria & Quality Gates
- **Exit Code**: Must return `0` (100% pass across all test cases).
- **Zero Flakiness**: No timing race conditions or unhandled asynchronous exceptions.
- **Contract Fidelity**: All outputs strictly conform to specifications in `PROJECT.md` and `ORIGINAL_REQUEST.md`.
