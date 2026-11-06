# Feature Intake: Stable Stash Identity

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Use the stash commit OID as the identity for inspection, apply, pop, drop, and auto-stash restoration. A stash display index may shift when another entry is added or removed.

## Behavior Change

- Selection keeps showing the originally selected stash even if its display position changes.
- Apply, pop, and drop locate the selected OID immediately before mutation and fail safely if it disappeared.
- Auto-stash restores only the entry created by the current operation.

## Non-Goals

- No change to stash content rendering or the general Git write-operation scheduler.
- No deletion of unrelated stashes or local refs.

## Change Boundary

- In scope: StashInfo, GitService stash enumeration and mutations, RepoViewModel stash actions, AutoStashRunner.
- Out of scope: FileSnapshotSource and full inspector request-generation work.
- Protected hotspots reviewed: GitService owns its synchronous libgit2 transaction; RepoViewModel only passes identity.

## Ownership

- Primary owner layer: GitService resolves OIDs to current indices; AutoStashRunner carries the created OID.
- Why this layer is the right owner: actor-isolated lookup and mutation prevent stale index selection.
- Which larger type is intentionally not taking more responsibility: RepoViewModel does not parse reflogs.
- Why: The lookup and libgit2 mutation must share one actor-isolated synchronous step.
- Larger type intentionally not expanded: RepoViewModel does not parse reflogs or implement stash policy.

## Affected Areas

- Screens / flows: stash sidebar, inspector, context-menu actions, auto-stash during pull/squash.
- Services / helpers / view models: GitService, AutoStashRunner, RepoViewModel.
- Files likely to change: GitModels.swift and those three types, with behavior tests.

## Test Scope

- Unit tests: runner restores the OID returned by push.
- Integration tests: insert another stash after selection; selected OID is read and mutated, missing OID is rejected.
- Manual verification: select a stash, create another, then use context actions.
- Failure modes / edge cases: index shift, removed stash, auto-stash push followed by another stash insertion.
- Known coverage blockers: none for service and runner paths.

## Design Records

- RFC required? Yes; model, service, and orchestration share stash identity.
- ADR required? No; this is a bounded correctness fix.
- RFC required: yes, this crosses model, service, and operation orchestration.
- ADR required: no, this is a bounded correctness fix rather than repository-wide policy.

## Completion Criteria

- Every selected-stash read uses its OID; user-selected mutations never silently act on a different index; auto-stash restores its own OID; focused tests pass.

## Open Questions

- None.
