# Feature Intake: Linked Worktree Conflict Metadata

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Read merge and rebase metadata from the linked worktree real Git directory.

## Behavior Change

- Read merge and rebase metadata from the linked worktree real Git directory.

## Non-Goals

- Merge/rebase command semantics, conflict algorithm and shared refs.

## Change Boundary

- In scope: Per-worktree metadata path resolution and existing GitService reads.
- Out of scope: Merge/rebase command semantics, conflict algorithm and shared refs.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: GitRepositoryMetadataPaths owns resolution; GitService consumes it.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: Real linked-worktree merge and rebase metadata fixtures.
- Manual verification: Inspect labels in a linked-worktree conflict.
- Failure modes / edge cases: A .git pointer file must resolve to the correct per-worktree directory.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? No; correction inside an existing service flow.
- ADR required? No; no new durable policy.

## Completion Criteria

- All relevant metadata reads use the resolved worktree gitdir.

## Earlier Intake Detail

### Summary and behavior change

Read merge and rebase metadata from the real per-worktree git directory, including linked worktrees whose `.git` is a pointer file. Conflict labels, source branch, message and continue flow must use the same metadata location already resolved by the repository watcher.

### Non-goals and boundary

- No change to merge/rebase command semantics, the conflict algorithm, or shared refs.
- `GitRepositoryMetadataPaths` owns path resolution; `GitService` only consumes its `gitDirPath`. No new metadata parser in `GitService` or UI logic in views.

### Test scope

- A disposable linked worktree verifies merge source/message and rebase metadata lookup.
- Run focused and full Swift tests; use real Git state rather than a fabricated `.git` directory.
- No GUI change, so manual UI check is limited to presenting a linked-worktree conflict.

### Completion criteria and records

Every merge/rebase metadata read and edited message uses the resolved per-worktree gitdir. Intake only: this is a local path correction within existing service behavior; no new workflow or durable policy.
