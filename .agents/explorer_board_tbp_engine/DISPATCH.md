# Dispatch: Explorer Board TBP Engine & Multi-mode Canvas

## Mission
Investigate Electronic Board app (`boardest`), Store Level 0 TBP package loading, dHash page matching, `.bstpen` drawing stroke persistence, 3-mode canvas, and touch/input event stability.

## Scope
- `apps/boardest`.
- Store Level 0 TBP package loading, parsing, page extraction, caching.
- dHash-based visual page matching algorithms and performance.
- `.bstpen` drawing stroke data serialization, auto-save, restoration, undo/redo.
- 3-mode canvas (mouse, smart, annotation), pointer/touch event passing, multi-platform stability (Web, Windows, Android).
- Locate all memory leaks, rendering glitches, serialization corruptions, touch event drops.

## Required Outputs
Write comprehensive findings in `.agents/explorer_board_tbp_engine/analysis.md` and standard 5-component `handoff.md`.
Report back when finished.
