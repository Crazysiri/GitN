# Feature Intake: Pull Auto-Stash Restore Safety

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

If fallback branch pull fails, restore auto-stashed changes only after confirming the original branch is active. Report checkout or stash restore failures and preserve the stash when that branch cannot be restored.

## Behavior Change

- Failed pull recovery never applies the auto-stash on the target branch.
- The error toast includes checkout or stash recovery failures.

## Non-Goals

- No change to fast-forward fetch or normal pull behavior; no destructive reset.

## Change Boundary

- In scope: fallback pull recovery in RepoViewModel and focused tests.
- Out of scope: fetch, merge, rebase, and generic operation logging.
- Protected hotspots reviewed: RepoViewModel already owns this branch-switching workflow.

## Ownership

- Primary owner layer: RepoViewModel, using GitService for the authoritative branch read.
- Why this layer is the right owner: this pull workflow and feedback already live there.
- Which larger type is intentionally not taking more responsibility: GitService retains primitive Git operations.

## Test Scope

- Unit tests: failed target pull with a dirty tree returns to the original branch and restores changes.
- Unit/integration tests: failed target pull with dirty tree; branch verification logic.
- Manual verification: checkout-back failure and stash-pop failure.
- Failure modes / edge cases: detached HEAD, checkout-back failure, stash-pop failure.
- Known coverage blockers: a checkout-back failure is difficult to force deterministically in a local fixture.

## Design Records

- RFC required? Yes; non-trivial ViewModel change.
- ADR required? No; no durable new boundary.

## Completion Criteria

- Failure recovery checks the actual branch before Pop and makes incomplete recovery visible.
