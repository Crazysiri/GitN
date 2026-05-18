# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-30

## Summary

Speed up the sidebar FILES search by moving repository file enumeration off the per-keystroke path. Build a repo-scoped filename index once, reuse it for in-memory filtering while the repo is active, and invalidate/re-prewarm that index when working-tree changes make it stale.

## Behavior Change

- Sidebar FILES search no longer shells out to `git ls-files` on every query.
- Opening the FILES section or refreshing the active repo can prewarm a repo-scoped filename index in the background.
- Searching after the index is warm filters filenames in memory and should feel much closer to instant for typical repositories.
- Existing search semantics stay the same: filename-only matching, Git-ignore-aware results, ancestor folders expanded while searching, and folder-before-file ordering.

## Non-Goals

- No full-text search.
- No global project search UI outside the FILES sidebar.
- No persistent on-disk search database.
- No change to file preview, file history, or drag/drop behavior.

## Change Boundary

- In scope: sidebar FILES search execution path, repo-scoped filename indexing/cache, search invalidation/prewarm hooks, and focused tests for cache reuse/invalidation.
- Out of scope: commit graph, diff loading, provider integrations, and working-tree mutation UX.
- Protected hotspots reviewed: `RepoViewModel` only orchestrates invalidation/prewarm and does not own search policy or caching details. `GitService` remains unchanged.

## Ownership

- Primary owner layer: focused service/helper plus thin sidebar wiring.
- Why this layer is the right owner: filename indexing, cache reuse, and invalidation are reusable search infrastructure concerns, not SwiftUI rendering logic.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` is intentionally not becoming the search index implementation owner.

## Affected Areas

- Screens / flows: left sidebar FILES section.
- Services / helpers / view models: `WorkingTreeFileTreeBuilder`, new `WorkingTreeFileSearchIndex`, `RepoViewModel` orchestration hooks.
- Files likely to change: `SidebarView.swift`, `WorkingTreeFileTreeBuilder.swift`, new search index helper, related tests.

## Test Scope

- Unit tests: cache reuse, invalidation, and tree snapshot building from indexed path matches.
- Integration tests: repo-backed behavior that confirms refreshed repos expose updated search results after invalidation.
- Manual verification: open a large repo, type into FILES search, verify the first warm search is acceptable and repeated searches are near-instant; verify file create/rename/delete and external repo refresh still update search results.
- Failure modes / edge cases: ignored files remain hidden, empty query resets the search state, narrowed queries reuse previous results, stale cache is invalidated after repo changes.
- Known coverage blockers: subjective UX improvement still requires manual timing in a large real repo.

## Design Records

- RFC required? Yes. This introduces a new repo-scoped helper/service and a new caching/testing seam.
- ADR required? No. This does not establish a repository-wide architectural rule.

## Completion Criteria

- Sidebar FILES search no longer launches git for each query on the warm path.
- Repeated filename searches reuse an in-memory repo index.
- Repo refresh paths invalidate stale indexed data and trigger background re-prewarm.
- Tests cover the cache seam and preserve existing search semantics.

## Open Questions

- None.
