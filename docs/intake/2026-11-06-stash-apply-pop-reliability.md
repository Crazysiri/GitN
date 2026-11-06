# Feature Intake: Stash Apply and Pop Reliability

- Status: Implemented; user's live stash not mutated
- Owner: GitN
- Date: 2026-11-06

## Summary

Restore reliable Apply and Pop for a selected stash, with useful failure feedback. Keep the OID-based identity fix already in progress and verify behavior against temporary repositories, including staged and untracked changes.

## Behavior Change

- Apply restores the selected stash without deleting it; Pop drops it only after a successful apply.
- A failed operation reports the Git error, refreshes any partial state, and leaves the stash available for retry.
- Normal Apply/Pop semantics match Git's default behavior; restoring the original index is an explicit mode, not an unavoidable condition.

## Non-Goals

- No mutation of a user's repository during tests or diagnosis.
- No broad replacement of libgit2 or unrelated stash UI redesign.

## Change Boundary

- In scope: GitService stash apply options, RepoViewModel action feedback, targeted tests.
- Out of scope: general repository write queue and unrelated remote operations.
- Protected hotspots reviewed: GitService owns the libgit2 transaction; RepoViewModel only coordinates action status and error display.

## Ownership

- Primary owner layer: GitService for stash semantics; RepoViewModel for UI error presentation.
- Why this layer is the right owner: GitService controls Apply/Pop ordering and the ViewModel owns the toast.
- Which larger type is intentionally not taking more responsibility: RepoViewModel does not implement stash Git commands.
- Why: Options and safe Pop behavior belong next to the libgit2 call; UI state stays in the ViewModel.
- Larger type intentionally not expanded: no new Git implementation or policy added to the ViewModel.

## Affected Areas

- Screens / flows: stash context menu and toolbar Pop.
- Services / helpers / view models: GitService, RepoViewModel.
- Files likely to change: stash methods and behavior tests.

## Test Scope

- Unit tests: temporary repositories cover unrelated staged edits, successful Apply/Pop, and failed Pop retention.
- Failure modes / edge cases: index conflict, dirty tree, missing OID, and partial restore.
- Unit/integration tests: Apply and Pop with staged, unstaged, and untracked data; selected OID after index movement; conflict/failure retains stash.
- Manual verification: Apply and Pop from sidebar; surface any error in the app.
- Known coverage blockers: user's exact failing repository and error have not yet been supplied; its stash was not applied or popped during verification.

## Design Records

- RFC required? Yes; GitService behavior and UI feedback change together.
- ADR required? No; this is a scoped compatibility fix.

## Completion Criteria

- Temporary-repository tests pass; neither failed Apply nor failed Pop loses a stash, and visible errors explain unsuccessful actions.

## Verification (2026-11-06)

- Stash-filtered Swift tests: 28 tests, 0 failures. Fixtures cover Apply/Pop, failed-Pop retention, OID selection, and Markdown stash snapshots.
- The full Swift suite passed with 405 tests, 2 skipped for missing git-lfs, and 0 failures. The user's live stash remains untouched; its original failure has not been reproduced in that repository.
