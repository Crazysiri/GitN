# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-05-18

## Summary

Fix the conflict merge side panels so files with tab-indented content, such as `project.pbxproj`, render with correct indentation, keep both sides vertically aligned even when one side of a conflict block is shorter or empty, and avoid avoidable scroll jank from per-frame line highlighting work. The change is limited to the conflict editor's presentation/layout path.

## Behavior Change

- The left and right conflict side panels now preserve visible tab indentation for code-like files.
- Each conflict block now occupies the same visual height on both sides, so the shorter side pads within the block instead of causing later lines to drift out of alignment.
- Scrolling large conflicted files in the side panels avoids repeated line-highlighting work and should stay more responsive.
- When scrolling from the output pane back to the side panes after conflict selections change block heights, scroll sync keeps later conflicts aligned instead of jumping to the wrong side-panel line.

## Non-Goals

- Changing merge parsing, conflict marker extraction, or save behavior.
- Reworking the output editor or conflict selection semantics.
- Moving conflict state or layout policy into `RepoViewModel` or `GitService`.

## Change Boundary

- In scope:
  - Conflict side-panel row layout and rendering.
  - Conflict side-panel drawing performance.
  - Conflict scroll-sync mapping between side panes and the output pane.
  - Testable helper logic for per-side display rows.
- Out of scope:
  - Conflict parsing in `GitService`.
  - Conflict output document behavior in `ConflictEditorDocument`.
  - General text editor infrastructure outside the conflict view.
- Protected hotspots reviewed:
  - `RepoViewModel`: no new responsibility added.
  - `GitService`: no new responsibility added.

## Ownership

- Primary owner layer: View-layer helper and rendering logic in the conflict editor.
- Why this layer is the right owner: the bug is purely about how already-parsed conflict content is laid out and painted.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` is not being extended with rendering/layout policy.

## Affected Areas

- Screens / flows:
  - Full-screen conflict resolver side-by-side panes
- Services / helpers / view models:
  - Conflict side display layout helper
  - Conflict side panel drawing in `ConflictMergeView`
- Files likely to change:
  - `GitN/Sources/GitN/Views/Conflict/ConflictMergeView.swift`
  - `GitN/Sources/GitN/Views/Conflict/ConflictSideDisplayLayout.swift`
  - `GitN/Tests/GitNTests/ConflictSideDisplayLayoutTests.swift`

## Test Scope

- Unit tests:
  - Mixed-height conflict blocks align to the same visual row span on both sides.
  - Empty-side conflict blocks still reserve visible rows.
- Integration tests:
  - None planned.
- Manual verification:
  - Open a conflicted `project.pbxproj` and verify both side panels stay aligned.
  - Confirm leading tab indentation matches the file content in both side panels.
  - Scroll a large conflicted file and confirm the side panes remain responsive.
  - Select multiple conflict hunks, then scroll the output pane and confirm the side panes do not jump at later conflicts.
- Failure modes / edge cases:
  - One side empty, the other non-empty.
  - One side much shorter than the other.
  - Files that rely on tab indentation for structure.
- Known coverage blockers:
  - No lightweight automated UI snapshot coverage for AppKit drawing in this view.

## Design Records

- RFC required? Why or why not?
  - No. This is a local UI bug fix with clear ownership and no new architectural boundary.
- ADR required? Why or why not?
  - No. No durable repository-wide architectural policy is changing.

## Completion Criteria

- Side panels preserve visible indentation for tab-indented files.
- Side panels keep conflict blocks vertically aligned when block heights differ across sides.
- Side panel scrolling does not rebuild visible-line highlighting work on every draw pass.
- Output-to-side scroll sync preserves conflict order even when selected output blocks collapse or expand to duplicate anchor positions.
- Automated tests cover the extracted side layout helper.

## Open Questions

- None.
