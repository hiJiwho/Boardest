# Dispatch: Explorer Shared Packages

## Mission
Investigate all shared packages in `packages/` (`bst_core`, `bst_ui`, `bst_cast`, `bst_platform_io`, `bst_sync`, and any others).

## Scope
- `packages/` directory across all packages.
- Architecture, interface contracts, shared data models, serialization protocols.
- Resource management: stream subscriptions, controllers, disposal, unhandled async errors.
- Platform abstraction and conditional imports / web vs desktop differences.
- Locate all bugs, code smells, fragile assumptions.

## Required Outputs
Write comprehensive findings in `.agents/explorer_shared_packages/analysis.md` and standard 5-component `handoff.md`.
Report back when finished.
