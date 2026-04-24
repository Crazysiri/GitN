# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-24

## Summary

Add a `File History` action to the left sidebar `FILES` context menu for file rows so users can open the existing file-inspector history flow directly from the working-tree file list.

## Behavior Change

- Users can right-click a file in the left `FILES` section and choose `File History`.
- That action opens the existing source preview / file inspector history mode for the selected path using the current working tree context.

## Non-Goals

- Do not add file history to folder context menus.
- Do not create a new standalone history surface or alternate navigation flow.
- Do not broaden the general working-tree file inspector mode picker behavior beyond this explicit context-menu entry.

## Change Boundary

- In scope: sidebar file-row context menu, existing file history action wiring, targeted working-tree history behavior test.
- Out of scope: folder actions, detail-panel file lists, history rendering UI, git log parsing behavior.
- Protected hotspots reviewed: `RepoViewModel` and `GitService` remain unchanged in responsibility; existing `openFileHistory` behavior is reused instead of adding new orchestration there.

## Ownership

- Primary owner layer: View, with existing `RepoViewModel` action reuse.
- Why this layer is the right owner: the new behavior is an additional UI entry point to an existing action.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` is not gaining sidebar-specific menu policy and `GitService` is not changing.

## Affected Areas

- Screens / flows: left sidebar `FILES` section, file inspector history presentation.
- Services / helpers / view models: existing `RepoViewModel.openFileHistory`.
- Files likely to change:
  - `GitN/Sources/GitN/Views/Sidebar/SidebarView.swift`
  - `GitN/Tests/GitNTests/RepoViewModelBehaviorTests.swift`

## Test Scope

- Unit tests: verify a working-tree file can open the existing history flow with `.unstaged` context and load commit history.
- Integration tests: none planned.
- Manual verification: right-click tracked and untracked files from `FILES`, open history, verify the existing history panel appears and shows expected empty/non-empty states.
- Failure modes / edge cases: file with no history should show the existing empty-history state; opening from working-tree context should not require the source preview mode picker path.
- Known coverage blockers: sidebar SwiftUI context menu interaction is not directly covered by existing automated tests.

## Design Records

- RFC required? No. This is a local UI entry-point change with clear ownership and no new architectural seam.
- ADR required? No. No repository-wide policy or long-lived architecture decision changes.

## Completion Criteria

- `File History` appears in the sidebar file context menu.
- The action opens the existing file history inspector for the clicked file.
- Automated coverage exists for the reused working-tree history path.

## Open Questions

- None.
