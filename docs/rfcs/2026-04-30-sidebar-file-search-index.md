# RFC 2026-04-30: Sidebar File Search Index

- Status: Draft
- Owner: Codex
- Date: 2026-04-30

## Summary

Introduce a repo-scoped in-memory filename index for the sidebar FILES search so typing filters cached file names instead of repeatedly invoking git during each query.

## Scope

- In scope: repo-scoped filename indexing, cache invalidation/prewarm hooks, updated sidebar search scheduling, and tests for the new cache seam.
- Out of scope: full-text search, non-sidebar search surfaces, persistent indexing, or changes to working-tree preview behavior.

## Problem

The current sidebar search path enumerates top-level entries and repeatedly runs `git ls-files -co --exclude-standard -- <pathspec>` while the user types. That means every new query pays process-launch and repository-scan cost before any filename filtering can happen. This is structurally slower than IDEs that reuse a prebuilt index, and it is especially noticeable on larger repositories.

## Proposed Design

Add a new `WorkingTreeFileSearchIndex` actor that owns repo-scoped cached file metadata.

The actor responsibilities:

- load all searchable file paths for a repo with a single `git ls-files -co --exclude-standard -z`
- normalize and cache per-file filename keys for case/diacritic-insensitive matching
- answer search queries by filtering the cached entries in memory
- invalidate cached entries when repo state changes
- coalesce concurrent warm/search requests for the same repo so repeated prewarm calls do not trigger duplicate scans

`WorkingTreeFileTreeBuilder` remains the owner of tree-shaping behavior. It gains a path-set-to-`TreeSnapshot` API used by the new index helper so ancestor-folder expansion, sorting, and filename-only semantics stay centralized.

`SidebarView` keeps debounce and local UI state, but its search task now calls the index actor instead of using the builder's repo-scan search API directly. Query narrowing continues to reuse the last matched path set when the new query extends the old one.

`RepoViewModel` only orchestrates invalidation/prewarm:

- invalidate the repo index when working-tree / index / ref refresh paths run
- trigger background prewarm after refresh work completes so the next visible search is warm
- keep all cache policy and matching behavior out of the view model itself

## Layer Ownership

- Primary owner: `WorkingTreeFileSearchIndex` service/helper plus `WorkingTreeFileTreeBuilder` tree shaping.
- Why this layer is the right owner: search indexing and cache reuse are non-trivial reusable logic with direct unit-test value and should not live in SwiftUI or `RepoViewModel`.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` stays focused on repo refresh/orchestration instead of becoming a search cache implementation.

## Alternatives Considered

- Option A: only lower debounce and keep per-query git scans.
  - Rejected because it reduces wait time without removing the dominant repo scan/process-launch cost.
- Option B: run a single full-repo git scan per query without caching.
  - Better than the current per-root scans, but still repeats avoidable work for every keystroke.
- Option C: persistent on-disk index.
  - Rejected for now because it adds storage, migration, and long-lived invalidation complexity that is unnecessary for this sidebar filename search.

## Test Plan

- Unit tests for `WorkingTreeFileTreeBuilder` path-set snapshot construction.
- Unit tests for `WorkingTreeFileSearchIndex` cache reuse, invalidation, and narrowed-query behavior with an injected loader seam.
- Repo-backed behavior coverage to confirm a repo refresh invalidates stale indexed data and updated search results become visible.
- Manual verification in a large repo for warm search latency and post-refresh correctness.

## Migration / Rollout

No migration or staged rollout is required. The change is internal to the active repo session and uses an in-memory cache only.

## Risks

- Cache invalidation gaps could surface stale search results after file mutations or external repo changes.
- Background prewarm may add some CPU work on active repo refreshes; coalescing and cache reuse need to keep this bounded.
- Replacing incremental per-root search publication with a cached single-pass result risks changing perceived result timing; tests and manual verification should ensure result correctness stays unchanged.
