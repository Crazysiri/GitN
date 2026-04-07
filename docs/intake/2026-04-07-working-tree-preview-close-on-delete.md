# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-07

## Summary

Close the right-side source preview when it is showing a working-tree file that has been deleted from disk, so the inspector does not remain open on a file that no longer exists.

## Behavior Change

- When a working-tree file is open in the source preview and that file is deleted externally, GitN closes the current file inspector.
- The working-tree file selection for that deleted path is also cleared.

## Non-Goals

- Do not change committed or stash preview behavior.
- Do not redesign working-tree folder refresh or stale cache invalidation.
- Do not change diff-context selection behavior.

## Change Boundary

- In scope:
- Working-tree file preview state sync in `RepoViewModel`
- Closing the file inspector when the selected working-tree path becomes invalid
- Targeted `RepoViewModel` behavior coverage
- Out of scope:
- Sidebar tree caching strategy
- Commit/stash preview lifecycle
- Monaco rendering behavior
- Protected hotspots reviewed:
- `RepoViewModel` is touched only because it already owns file inspector presentation state and working-tree selection orchestration.

## Ownership

- Primary owner layer: ViewModel
- Why this layer is the right owner: the behavior is a state transition between working-tree selection state and inspector presentation state.
- Which larger type is intentionally not taking more responsibility: `GitService` is not being given UI-state policy.

## Affected Areas

- Screens / flows:
- Right-side source preview for files opened from `FILES`
- External delete / watcher-driven working-tree refresh
- Services / helpers / view models:
- `RepoViewModel`
- Files likely to change:
- `GitN/Sources/GitN/Models/RepoViewModel.swift`
- `GitN/Tests/GitNTests/RepoViewModelBehaviorTests.swift`

## Test Scope

- Unit tests:
- Verify a missing working-tree preview path clears selection and closes the inspector
- Integration tests:
- None
- Manual verification:
- Open a file from `FILES`, delete it externally, confirm preview closes
- Failure modes / edge cases:
- Only close for working-tree preview state, not for committed previews
- Clearing selection should not leave the inspector visible
- Known coverage blockers:
- File-watcher delivery is not directly exercised in unit tests

## Design Records

- RFC required? Why or why not?
- No. This is a local bug fix in existing `RepoViewModel` ownership without a new seam or cross-cutting design change.
- ADR required? Why or why not?
- No. No long-lived architectural or policy decision changes.

## Completion Criteria

- A deleted working-tree preview file closes the current source preview
- The stale working-tree selection is cleared for that path
- Targeted automated coverage is added or updated

## Open Questions

- None
