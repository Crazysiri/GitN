# Feature Intake

- Status: Draft
- Owner: GitN sidebar / working tree file helper
- Date: 2026-04-24

## Summary

Optimize path search in the left sidebar FILES section. Typing in the FILES search field waits for a short pause, then filters the displayed working-tree directory tree to matching files and folders plus the ancestor folders needed to reveal those matches, excluding paths ignored by Git.

## Behavior Change

- Users can type in a compact search field under the expanded FILES header.
- The FILES search field is visually distinct, responds on hover, and uses the shared focus animation used by other inputs.
- Empty search keeps the existing lazy, user-collapsible tree behavior.
- Non-empty search waits 0.3 seconds after the latest keystroke before executing.
- Search excludes files and folders ignored by `.gitignore` / Git exclude rules, in addition to `.git`.
- Search matches file names only; directory names do not produce matches by themselves.
- Results render matching files as a pruned directory tree with ancestor folders expanded while search is active.
- Search processes top-level FILES entries one by one in visible order and publishes results after each entry with new matches instead of waiting for the whole repository to finish.
- When the user appends characters to an existing query, search narrows the existing matched file set instead of scanning the full repository again.
- A small non-blocking loading indicator appears beside the FILES search field while a search task is running.
- File clicks and visible row context menus continue to use the existing working-tree actions.

## Non-Goals

- No file-content search.
- No drag/drop file or folder movement.
- No changes to commit history, diff loading, or provider integrations.
- No new persistent sidebar search preference.

## Change Boundary

- In scope: FILES sidebar rendering, search field styling/focus feedback, search text state, debounce scheduling, Git-ignore-aware file search, existing-result narrowing, non-blocking search progress state, and incremental search snapshot building.
- Out of scope: `RepoViewModel` search orchestration, `GitService`, hosted review services, drag/drop mutation flows.
- Protected hotspots reviewed: `RepoViewModel` and `GitService` should not receive search policy for this local sidebar feature.

## Ownership

- Primary owner layer: `SidebarView` for presentation state/debounce/progressive display and `WorkingTreeFileTreeBuilder` for Git-aware working-tree file search.
- Why this layer is the right owner: the view already owns FILES expansion/collapse presentation, and the builder already owns working-tree directory enumeration and sorting. Git-ignore-aware path filtering is local helper policy, not repo-wide orchestration.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` remains limited to existing file preview and folder-loading actions; `GitService` remains unchanged.

## Affected Areas

- Screens / flows: left sidebar FILES section.
- Services / helpers / view models: `WorkingTreeFileTreeBuilder`.
- Files likely to change: `SidebarView.swift`, `WorkingTreeFileTreeBuilder.swift`, `WorkingTreeFileTreeBuilderTests.swift`.

## Test Scope

- Unit tests: recursive file search, case-insensitive file-name matching, ancestor folder inclusion, directory-name non-matching, `.git` exclusion, Git ignore exclusion, folder-before-file sorting, incremental top-level search snapshots, and existing-result narrowing.
- Integration tests: none required; behavior stays inside a view plus helper boundary.
- Manual verification: type into FILES search, search a deeply nested collapsed file, clear search and confirm prior collapse state returns, open a file result.
- Failure modes / edge cases: empty search, nested paths, `.git` content, ignored files/folders, directory names that match the query, sorted mixed folders/files, stale debounced searches.
- Known coverage blockers: SwiftUI text-field rendering and live typing are manual in this pass.

## Design Records

- RFC required? No. This is a local sidebar feature with a focused testable helper and no new cross-module service boundary.
- ADR required? No. This does not establish durable architecture or repository-wide policy.

## Completion Criteria

- FILES search field filters the tree after a 0.3 second typing pause without changing empty-query behavior.
- Search excludes Git-ignored paths.
- Search only matches files, not directory names.
- Appending to a query narrows the previous matched file set.
- Search updates visible file matches incrementally in top-level FILES display order.
- Search shows a non-blocking loading indicator while work is still running.
- Search field has hover feedback and the shared animated input focus border.
- Search results show matching files in tree context with ancestor folders expanded.
- Existing file preview and context menu actions still work on visible rows.
- Unit tests cover the recursive search helper.

## Open Questions

- None.
