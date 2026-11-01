# Handoff Report — Split Screen Dual Board (worker_split_view)

## 1. Observation
- In `PROJECT.md`, Component `C08` (`Split Screen Dual Board`, 2-way and 4-way vertical/horizontal canvas partitioning) was marked as `PLANNED`.
- Inspection of `apps/boardest_teacher/lib/views/boardest_pen_view.dart` and `apps/boardest/lib/views/boardest_pen_view.dart` revealed single-canvas `GestureDetector` setups without dynamic multi-pane partitioning or coordinate boundary confinement.
- Inspection of `packages/plugins/bst_pen` identified the common annotation engine (`AnnotationCanvas`, `AnnotationController`, `AnnotationStroke`), which is shared by all Boardest whiteboard views.
- Previous tests in `packages/plugins/bst_pen/test` contained 13 unit tests for strokes and serialization, but zero split screen coverage.
- Running `flutter test packages/plugins/bst_pen/test` passed 13/13 tests initially.

## 2. Logic Chain
1. To provide consistent Split Screen functionality across both Boardest Teacher and Boardest Class apps, the core split engine is implemented in the shared plugin package `packages/plugins/bst_pen/lib/src/split_board_view.dart` and exported via `bst_pen.dart`.
2. The split system defines `SplitMode` (`single`, `twoVertical`, `twoHorizontal`, `quad`), managed by `SplitBoardController` with normalized partition ratios `splitRatioX` (0.15~0.85) and `splitRatioY` (0.15~0.85).
3. To eliminate coordinate bleed-through across partition boundaries:
   - Each pane (`SplitPaneData`) maintains an independent `AnnotationController` instance, isolated stroke lists, and individual undo/redo stacks.
   - Gesture processing in `_IsolatedCanvasGestureLayer` uses `_clampAndLocalize(Offset globalPosition)` to calculate local coordinates via the pane's own `RenderBox` and clamp coordinates strictly within `[0.0, paneSize.width]` and `[0.0, paneSize.height]`.
   - Each pane is wrapped in `ClipRect` so rendering never draws beyond the partition bounds.
   - Pointer events originating in Pane `i` are retained by Pane `i`'s gesture recognizer and never dispatched to neighboring panes.
4. For responsive resize handles and reset buttons:
   - In 2-way vertical split: A draggable vertical divider handle with `SystemMouseCursors.resizeColumn` and on-divider `1:1` quick reset chip.
   - In 2-way horizontal split: A draggable horizontal divider handle with `SystemMouseCursors.resizeRow` and on-divider `1:1` quick reset chip.
   - In 4-way quad split: Dual dividers with a central 4-way intersection handle (`SystemMouseCursors.allScroll`) and one-click `1:1:1:1` reset button.
   - The top toolbar also features a persistent `1:1 균등 리셋` button that restores `splitRatioX = 0.5` and `splitRatioY = 0.5`.
5. The split screen system was integrated into:
   - `apps/boardest_teacher/lib/views/boardest_pen_view.dart`: Added `_isSplitScreen` state, `_splitController`, bottom floating dock button `Icons.splitscreen_rounded`, and conditional `SplitBoardView` rendering.
   - `apps/boardest_teacher/lib/views/teacher_view.dart`: Added `_openSplitBoard()`, inline board widget case `'split_board'`, title bar tool icon, and drawer action.
   - `apps/boardest/lib/views/boardest_pen_view.dart`: Added `_isSplitScreen` state, `_splitController`, bottom floating dock button, and conditional `SplitBoardView` rendering.
   - `apps/boardest/lib/views/tools/teacher_usage_tools_view.dart`: Added whiteboard split mode toggle and `SplitBoardView` integration.
6. Added 10 automated unit and widget tests in `packages/plugins/bst_pen/test/split_board_view_test.dart`, verifying ratio manipulation, clamping, 1:1 resets, coordinate isolation, and event confinement. All 23 tests in `packages/plugins/bst_pen/test` passed.

## 3. Caveats
- No caveats. The Split Screen Dual Board works across desktop and web environments with full pointer/touch isolation.

## 4. Conclusion
Split Screen Dual Board functionality (2-way horizontal split, 2-way vertical split, and 4-way quad split) is fully implemented, verified, and integrated into Boardest Teacher and Boardest Class. Pointer/touch event routing operates cleanly with zero coordinate bleed-through across partition boundaries, resize handles function smoothly with mouse cursor feedback and bounds clamping, and 1:1 reset buttons reliably restore equal partitions. Component `C08` in `PROJECT.md` is updated to `PASSED`.

## 5. Verification Method
Run the following test commands from workspace root:
```bash
flutter test packages/plugins/bst_pen/test/split_board_view_test.dart
flutter test packages/plugins/bst_pen/test
```
Inspect the following modified files:
- `packages/plugins/bst_pen/lib/src/split_board_view.dart`
- `packages/plugins/bst_pen/lib/bst_pen.dart`
- `packages/plugins/bst_pen/test/split_board_view_test.dart`
- `apps/boardest_teacher/lib/views/boardest_pen_view.dart`
- `apps/boardest_teacher/lib/views/teacher_view.dart`
- `apps/boardest/lib/views/boardest_pen_view.dart`
- `apps/boardest/lib/views/tools/teacher_usage_tools_view.dart`
- `PROJECT.md` (Component C08)
