# Feature Intake: repository mutation serialization

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Serialize app-owned Git writes across tabs and linked worktrees sharing a Git directory.

## Behavior Change

- Serialize app-owned Git writes across tabs and linked worktrees sharing a Git directory.

## Non-Goals

- Locking external Git clients, serializing reads and rolling back completed commands.

## Change Boundary

- In scope: GitService mutation entry points and WorktreeService add/remove.
- Out of scope: Locking external Git clients, serializing reads and rolling back completed commands.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: RepositoryMutationCoordinator owns FIFO; service wrappers acquire it.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: FIFO, cancellation, errors, nested stash pop and linked-worktree identity.
- Manual verification: Exercise two-tab writes in a disposable repository.
- Failure modes / edge cases: Cancelled waiters never mutate and errors always release ownership.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? Yes; cross-service mutation flow.
- ADR required? Yes; common-gitdir queue policy.

## Completion Criteria

- App-owned writes share a gate through awaited commands and tests pass.

## Earlier Intake Detail

### Change and boundary

Serialize GitService mutation entry points and WorktreeService add/remove by canonical Git common directory, across repository tabs and linked worktrees. Hold ownership through awaited CLI/LFS commands and composite service operations. Reads remain independent. Cancelled queued requests must never mutate the repository. Existing UI confirmations and operation history remain unchanged.

A focused coordinator owns FIFO scheduling; a GitService extension owns public mutation wrappers. Existing implementations become internal unqueued helpers used only within an owned operation. GitService does not gain queue policy. Non-goals: locking external Git clients, serializing reads, rolling back completed Git commands, or a new Git backend.

### Tests and completion

Test FIFO, separate repositories, cancellation and release after errors; test two GitService instances writing one repository, nested stash pop, and linked worktree identity. Run existing service tests and complete Swift suite. RFC and ADR required for this durable service boundary.
