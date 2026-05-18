# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-05-06

## Summary

Fix multi-commit squash so it behaves the same regardless of whether the user selects commits from top to bottom or bottom to top in the graph. The squash operation should canonicalize the selected commits into repository history order before interactive rebase is prepared.

## Behavior Change

- Squashing multiple selected commits from the graph now uses commit history order instead of raw click order.
- Users can select the same contiguous commit range in either direction and get the same squash result.

## Non-Goals

- Changing which commit range is eligible for squash.
- Changing the multi-select compare behavior or general graph selection UX.
- Reworking interactive rebase beyond commit order normalization for squash.

## Change Boundary

- In scope:
  - Multi-select squash ordering in the graph/history flow.
  - Squash command normalization at a testable non-UI boundary.
- Out of scope:
  - Other graph context menu actions.
  - Commit selection rendering and pagination behavior.
  - General rebase conflict handling.
- Protected hotspots reviewed:
  - `RepoViewModel`: no new responsibility added.
  - `GitService`: receives a small normalization step that belongs with squash preparation logic rather than in UI click-order tracking.

## Ownership

- Primary owner layer: Service/helper logic in `GitService.squashCommits`, with light action wiring in the graph view if needed.
- Why this layer is the right owner: squash preparation already lives in `GitService`, and commit-order normalization is operation policy that should not depend on UI gesture order.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` is not being extended with selection-order policy.

## Affected Areas

- Screens / flows:
  - Commit graph multi-selection context menu -> squash commits
- Services / helpers / view models:
  - `GitService`
  - Graph multi-select action wiring
- Files likely to change:
  - `GitN/Sources/GitN/Services/GitService.swift`
  - `GitN/Sources/GitN/Views/Graph/GraphView.swift`
  - `GitN/Tests/GitNTests/GitServiceBehaviorTests.swift`

## Test Scope

- Unit tests:
  - Squash succeeds when hashes are passed oldest-to-newest.
  - Existing newest-to-oldest squash coverage remains valid.
- Integration tests:
  - None planned beyond existing temporary git repository behavior tests.
- Manual verification:
  - In the graph, select the same commit range top-to-bottom and bottom-to-top and confirm both squash correctly.
- Failure modes / edge cases:
  - Reversed selection order.
  - Two-commit squash.
  - File contents preserved after squash.
- Known coverage blockers:
  - No lightweight automated UI coverage for AppKit table multi-selection gesture order in this change.

## Design Records

- RFC required? Why or why not?
  - No. This is a local bug fix with clear ownership and no new architectural boundary.
- ADR required? Why or why not?
  - No. No durable architecture or repository-wide policy is changing.

## Completion Criteria

- Squash produces the expected single combined commit for the selected range regardless of selection direction.
- Automated tests cover reversed-order input at the service layer.
- No unrelated graph selection behavior regresses.

## Open Questions

- None.
