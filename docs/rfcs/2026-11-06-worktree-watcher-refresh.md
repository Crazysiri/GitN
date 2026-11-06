# RFC: Worktree Watcher and Deferred Refresh

- Status: Implemented; external-event manual check pending
- Owner: GitN
- Date: 2026-11-06

## Decision

Resolve a directory-style .git or a gitdir pointer file, then resolve an optional commondir file relative to that git directory. Watch worktree root, per-worktree gitdir, and common-dir; classify index and HEAD against the former and refs/packed-refs against the latter. Avoid treating a sibling path with the same prefix as inside a directory. Do not discard events solely because a directory is named build, dist, or node_modules; the name is not proof that Git ignores it.

RepoViewModel unions incoming change kinds while loading, refreshing, or mutating. When the busy flag clears, one drain processes accumulated changes and repeats if new changes arrived during its awaits. Worktree-only refreshes do not recalculate current-branch commit reachability when HEAD and branch identity are unchanged.

## Tests

Temporary standard and linked worktree fixtures verify gitdir and common-dir resolution. Unit coverage verifies deferred-change coalescing where accessible. Manual verification covers FSEvents delivery and UI state after an external checkout.

The temporary-repository and deferred-refresh tests passed in the full Swift suite (405 tests, 2 skipped for missing git-lfs, 0 failures). A live external-checkout/FSEvents check remains pending.
