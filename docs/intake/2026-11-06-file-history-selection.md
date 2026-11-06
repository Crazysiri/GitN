# Feature Intake: Responsive File History Selection

- Status: Implemented; manual rapid-selection review pending
- Owner: GitN
- Date: 2026-11-06

## Summary

Move file-history text diff computation away from the main actor and prevent older asynchronous selections from replacing the latest file-history result.

## Behavior Change

- Selecting a large file-history revision leaves the interface responsive while its text diff is prepared.
- Switching revisions or closing history discards stale results and clears the prior revision's visible diff immediately.

## Non-Goals

- No change to commit ordering, Git diff semantics, Monaco rendering or Git mutations.

## Change Boundary

- In scope: file-history load/selection lifecycle within RepoViewModel.
- Out of scope: other file-inspector modes and GitService.
- Protected hotspots reviewed: changes only existing RepoViewModel orchestration; no new parsing or Git logic is added there.

## Ownership

- Primary owner layer: RepoViewModel owns screen selection state; existing TextDiffEngine runs in a detached task.
- Why this layer is the right owner: the race concerns publication of UI state after existing async reads.
- Which larger type is intentionally not taking more responsibility: GitService.

## Affected Areas

- Screens / flows: file history list and selected revision diff.
- Services / helpers / view models: RepoViewModel; reuse FileInspectorSelectionState as the token boundary.
- Files likely to change: RepoViewModel.swift and file-history behavior tests.

## Test Scope

- Unit tests: revision selection clears old content, displays expected diff, and closing clears state; existing token tests cover stale-token rejection.
- Integration tests: full Swift suite and app build.
- Manual verification: switch quickly between revisions of a large file and close during loading.
- Failure modes / edge cases: a completed old load cannot overwrite a newer selection or a closed history panel.
- Known coverage blockers: deterministic Git read delay injection is not available in this view model.

## Design Records

- RFC required? Yes; this adjusts async publication and a protected RepoViewModel hotspot.
- ADR required? No; it uses the existing generation-token boundary.

## Completion Criteria

- Main actor performs no large TextDiffEngine computation in file history; only the latest live request publishes its payload; tests pass.

## Verification (2026-11-06)

- Full Swift suite: 445 tests, 5 skipped, 0 failures; Release build passed.
- Behavior tests verify selection clears previous content, the selected revision publishes its diff, and closing history clears state.
- In the signed feature-preview app, a disposable repository displayed two `small.md` revisions; selecting the latest showed its changed-file diff, and selecting the initial revision showed its added lines.
- Rapid revision switching and closing during a delayed real Git read remain a manual interaction check; the view model has no deterministic delay injection for that read.
