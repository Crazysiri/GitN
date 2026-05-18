# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-05-18

## Summary

Add explicit loading feedback when the user clicks a file in the `Conflicted Files` list while GitN loads the conflict editor data. The feedback is shown as a centered app-level loading overlay and exists only for the duration of the open-conflict request.

## Behavior Change

- Clicking a file under `Conflicted Files` now shows a centered loading overlay across the repository screen until the conflict editor is ready or falls back to the non-text conflict state.
- The loading state is scoped to the conflict-open flow instead of general repository loading.

## Non-Goals

- Changing how conflict files are parsed or loaded.
- Redesigning the overall conflict panel layout.
- Adding new unrelated loading states outside the conflict-open flow.

## Change Boundary

- In scope:
  - Conflict-open loading state for the conflict list click interaction.
  - Centered repository overlay updates while conflict content loads.
- Out of scope:
  - Conflict editor internals.
  - Conflict parsing and save behavior.
  - Other sidebar or detail-panel file lists.
- Protected hotspots reviewed:
  - `RepoViewModel`: receives a small UI orchestration flag for an existing async action, without absorbing parsing or rendering logic.
  - `GitService`: no change.

## Ownership

- Primary owner layer: ViewModel state plus detail-panel presentation.
- Why this layer is the right owner: the async open action already lives in `RepoViewModel`, and the centered loading overlay belongs in the container view layer.
- Which larger type is intentionally not taking more responsibility: `GitService` is not being extended with UI loading policy.

## Affected Areas

- Screens / flows:
  - Detail panel conflict state -> `Conflicted Files` list -> open conflict editor
- Services / helpers / view models:
  - `RepoViewModel`
- Files likely to change:
  - `GitN/Sources/GitN/Models/RepoViewModel.swift`
  - `GitN/Sources/GitN/Views/RepoContainerView.swift`
  - `GitN/Sources/GitN/Views/Detail/DetailPanelView.swift`

## Test Scope

- Unit tests:
  - None planned for this local UI-feedback change.
- Integration tests:
  - None planned.
- Manual verification:
  - Click a conflicted file and confirm a centered repository loading overlay appears until the editor opens.
  - Click a binary or fallback conflict and confirm the loading state still clears correctly.
- Failure modes / edge cases:
  - Repeated clicks on the same file.
  - Loading state stuck after an error or fallback path.
- Known coverage blockers:
  - No lightweight automated UI interaction coverage for this panel.

## Design Records

- RFC required? Why or why not?
  - No. This is a local UI behavior change with clear ownership.
- ADR required? Why or why not?
  - No. No long-lived architectural policy is changing.

## Completion Criteria

- A centered repository loading overlay shows while `openConflictMerge` is in flight.
- Loading state clears on success, fallback, and close paths.
- The project still builds cleanly.

## Open Questions

- None.
