# Feature Intake: Worktree Watcher and Deferred Refresh

- Status: Implemented; external-event manual check pending
- Owner: GitN
- Date: 2026-11-06

## Summary

Resolve the actual per-worktree git directory and common directory before watching repository metadata. Preserve events received while a load or Git operation is active and refresh after the busy phase. Remove folder-name filtering that incorrectly hides tracked or unignored build/dist paths.

## Behavior Change

- Linked worktrees observe their real index/HEAD and shared refs/packed-refs.
- Filesystem changes during a load or operation trigger a later refresh instead of disappearing.
- A tracked path under a commonly ignored folder name can refresh the UI.

## Non-Goals

- No general repository write queue or FSEvents replacement.
- No eager history reload for worktree-only edits.

## Change Boundary

- In scope: metadata path resolver, RepositoryFileWatcher path classification, RepoViewModel refresh scheduling.
- Out of scope: network fetch policy and non-file-based Git state.
- Protected hotspots reviewed: RepoViewModel owns refresh scheduling; path parsing is extracted from it.

## Ownership

- Primary owner layer: GitRepositoryMetadataPaths for path resolution; watcher for event classification; ViewModel for deferred refresh.
- Why this layer is the right owner: filesystem locations and event coalescing are not view rendering concerns.
- Which larger type is intentionally not taking more responsibility: GitService does not gain watcher scheduling.

## Test Scope

- Unit tests: standard repo and linked worktree metadata paths; metadata event classification where feasible.
- Manual verification: external checkout and index changes during an active load.
- Failure modes / edge cases: relative gitdir, separate common-dir, event while busy, tracked build/dist file.
- Known coverage blockers: deterministic FSEvents delivery is machine-specific; integration assertions use resolver and refresh state instead.

## Design Records

- RFC required? Yes; new path helper crosses watcher and UI refresh flow.
- ADR required? No; no repository-wide policy changes.

## Completion Criteria

- Linked worktree metadata paths resolve correctly; pending refreshes drain after busy work; tests pass.

## Verification (2026-11-06)

- Temporary standard and linked-worktree tests cover gitdir/commondir resolution, event classification, and deferred refresh coalescing.
- The full Swift suite passed with 405 tests, 2 skipped (the machine lacks git-lfs), and 0 failures. The remaining manual check is an external checkout or index edit while a load is active.
