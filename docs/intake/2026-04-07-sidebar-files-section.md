# Feature Intake

- Status: Approved
- Owner: Codex
- Date: 2026-04-07

## Summary

Add a new `FILES` section to the repository sidebar that shows the current working tree as a collapsible directory tree. Selecting a file should open it in the center file inspector using preview mode so the user can edit and save the working-tree file without going through the diff list first.

## Behavior Change

- Users can browse repository files from the left sidebar in a dedicated `FILES` section.
- The section renders directories as expandable tree nodes and files as selectable leaves.
- Clicking a file opens the center `SourcePreview` inspector in preview mode with editable working-tree content.
- The file tree refreshes when repository state reloads or working-tree changes are observed.

## Non-Goals

- No create, rename, move, or delete actions for files in the new section.
- No new right-click menus or Finder/editor shortcuts for file tree rows.
- No changes to the right detail pane layout or commit graph data model.
- No attempt to merge file-tree rows into `commits`, `diffFiles`, or existing status lists.

## Change Boundary

- In scope:
  - Sidebar `FILES` section UI and tree row rendering.
  - A focused helper that builds a working-tree directory tree from the repository root.
  - `RepoViewModel` state needed to load, refresh, and open working-tree files in the file inspector.
- Out of scope:
  - File mutations outside the existing preview editor save flow.
  - Provider/network logic, hosted review flows, and git operation changes.
  - New repository-wide architecture or theme policy.
- Protected hotspots reviewed:
  - `RepoViewModel`: only thin orchestration/state is added; directory scanning stays outside the view model.
  - `GitService`: no new filesystem tree scanning logic is added there.

## Ownership

- Primary owner layer: Service/helper + ViewModel orchestration + Sidebar view rendering.
- Why this layer is the right owner:
  - Directory scanning is non-trivial filesystem logic and belongs in a focused helper.
  - `RepoViewModel` already owns per-repo inspector state and is the correct place to wire sidebar selection into existing preview/save flows.
  - `SidebarView` should remain presentation-focused and render preloaded tree state.
- Which larger type is intentionally not taking more responsibility:
  - `GitService` is intentionally not expanded with generic filesystem tree traversal.

## Affected Areas

- Screens / flows:
  - Repository left sidebar
  - Center file inspector preview flow
- Services / helpers / view models:
  - New working-tree file tree builder helper
  - `RepoViewModel`
  - `SidebarView`
- Files likely to change:
  - `GitN/Sources/GitN/Views/Sidebar/SidebarView.swift`
  - `GitN/Sources/GitN/Models/RepoViewModel.swift`
  - `GitN/Sources/GitN/Services/WorkingTreeFileTreeBuilder.swift`
  - `GitN/Tests/GitNTests/*`

## Test Scope

- Unit tests:
  - Tree builder excludes `.git`.
  - Tree builder preserves relative paths and nested structure.
  - Tree builder sorts folders before files and sorts names stably.
- Integration tests:
  - None planned; current coverage target is the extracted helper seam.
- Manual verification:
  - Expand/collapse `FILES` section and nested folders.
  - Open a regular text file from the sidebar and edit/save in preview mode.
  - Confirm the tree refreshes after saving and after external working-tree changes.
  - Confirm selecting a file still opens working-tree content even when a historical commit is selected.
- Failure modes / edge cases:
  - Hidden files should still appear except `.git`.
  - Empty directories should render if present.
  - Non-text/binary files should continue to use existing preview fallback behavior.
- Known coverage blockers:
  - SwiftUI sidebar interaction is covered manually, not with automated UI tests in this change.

## Design Records

- RFC required? Why or why not?
  - No. This is a single-screen feature with clear ownership and no new cross-module workflow or durable policy.
- ADR required? Why or why not?
  - No. The change does not establish a new repository-wide architecture decision.

## Completion Criteria

- The sidebar shows a `FILES` section with a working-tree directory tree.
- Clicking a file opens the center inspector in preview mode with editable working-tree content.
- The implementation does not add filesystem tree traversal to `GitService`.
- Helper coverage is added for the file-tree builder.
- Manual verification confirms the new flow works alongside existing commit/diff navigation.

## Open Questions

- None for this implementation slice.
