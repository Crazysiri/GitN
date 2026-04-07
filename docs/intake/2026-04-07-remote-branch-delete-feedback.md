# Feature Intake

- Status: Completed
- Owner: Codex
- Date: 2026-04-07

## Summary

Make remote branch deletion resilient when the remote ref has already been removed elsewhere, ensure the local remote-tracking branch disappears immediately after the action, and show clear user feedback for both the normal delete case and the already-missing case.

## Behavior Change

- Deleting `remote/branch` from GitN no longer fails when the remote ref has already been deleted upstream.
- After remote branch deletion completes, the local `refs/remotes/<remote>/<branch>` tracking ref is removed so sidebar and graph reloads no longer show stale remote branches.
- The UI now shows a toast for both `Remote Branch Deleted` and `Remote Branch Already Gone`.

## Non-Goals

- No changes to local branch deletion semantics.
- No new background fetch or prune workflow.
- No changes to remote tag deletion behavior in this change.

## Change Boundary

- In scope: `GitService.deleteRemoteBranch`, `RepoViewModel.performDeleteRemoteBranch`, and remote branch deletion behavior tests.
- Out of scope: generic remote operation toast behavior, remote tag deletion, fetch/sync workflows, and context menu structure.
- Protected hotspots reviewed: `RepoViewModel`, `GitService`.

## Ownership

- Primary owner layer: `GitService` for deletion result handling and remote-tracking ref cleanup, `RepoViewModel` for user-facing toast feedback.
- Why this layer is the right owner: the service owns git/CLI semantics and ref cleanup, while the view model owns operation UX and toast messaging.
- Which larger type is intentionally not taking more responsibility: no new provider-specific or network workflow logic was added to `RepoViewModel`.

## Affected Areas

- Screens / flows: sidebar and graph context-menu remote branch deletion.
- Services / helpers / view models: `GitService`, `RepoViewModel`.
- Files likely to change: `GitN/Sources/GitN/Services/GitService.swift`, `GitN/Sources/GitN/Models/RepoViewModel.swift`, `GitN/Tests/GitNTests/GitServiceBehaviorTests.swift`.

## Test Scope

- Unit tests: extend `GitServiceBehaviorTests` to verify first delete returns success, second delete returns already-missing, and `remoteBranches()` no longer includes the deleted remote branch.
- Integration tests: none beyond the real git bare-remote behavior test in `GitServiceBehaviorTests`.
- Manual verification: delete a remote branch from the sidebar or graph context menu and confirm the loading state ends, the branch disappears, and the correct toast appears.
- Failure modes / edge cases: remote branch already missing, local tracking ref stale after delete, and real remote deletion failures still surfacing as errors.
- Known coverage blockers: none.

## Design Records

- RFC required? No. This is a focused bug fix within existing ownership boundaries.
- ADR required? No. No long-lived architecture or repository-wide policy changed.

## Completion Criteria

- Remote branch deletion succeeds when the remote ref exists.
- Remote branch deletion also completes when the remote ref is already gone.
- The stale remote branch no longer appears after reload.
- The UI shows an explicit completion toast.

## Open Questions

- Whether remote tag deletion should adopt the same already-missing feedback behavior in a follow-up change.
