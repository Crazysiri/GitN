- Status: Draft
- Owner: Codex
- Date: 2026-05-20

## Summary

Allow the conflict merge save action to proceed when the output buffer has been manually edited away from the initial conflict output, even if no conflict hunks remain selected.

## Behavior Change

- Users can save a conflict resolution when the output text differs from the initial unresolved output, regardless of whether any hunk checkbox is still selected.
- The existing warning remains only for the untouched state where no hunk is selected and the output has not changed.

## Non-Goals

- Changing conflict block selection semantics or manual edit remapping behavior.
- Changing fallback-mode conflict resolution behavior.
- Reworking the conflict merge UI layout or toolbar actions.

## Change Boundary

- In scope: conflict merge save eligibility, conflict editor document dirty detection, targeted regression tests.
- Out of scope: git staging logic, conflict parsing, unrelated save flows.
- Protected hotspots reviewed: `RepoViewModel` remains orchestration-only; the new dirty check lives on `ConflictEditorDocument`.

## Ownership

- Primary owner layer: service/helper-style document model plus existing ViewModel orchestration.
- Why this layer is the right owner: whether the conflict output is meaningfully changed is document state, while `RepoViewModel` only decides whether to allow save.
- Which larger type is intentionally not taking more responsibility: `GitService` is not gaining UI save-policy logic.

## Affected Areas

- Screens / flows: conflict merge editor save flow.
- Services / helpers / view models: `ConflictEditorDocument`, `RepoViewModel`.
- Files likely to change: `GitN/Sources/GitN/Models/ConflictEditorDocument.swift`, `GitN/Sources/GitN/Models/RepoViewModel.swift`, `GitN/Tests/GitNTests/RepoViewModelBehaviorTests.swift`.

## Test Scope

- Unit tests: none beyond existing document behavior coverage unless a helper needs direct coverage.
- Integration tests: add a `RepoViewModel` regression test for saving a real conflicted file after manual output edits with no selected hunks.
- Manual verification: confirm the conflict editor still warns when nothing is selected and output is unchanged.
- Failure modes / edge cases: unchanged output with no selections must still warn; manually edited output with no selections must save and mark resolved.
- Known coverage blockers: none.

## Design Records

- RFC required? No. This is a focused bug fix with clear ownership and no new cross-cutting boundary.
- ADR required? No. No durable architecture or policy change is being introduced.

## Completion Criteria

- Saving a conflict resolution succeeds when the output text changed from the initial unresolved content, even if no hunk remains selected.
- The untouched no-selection case still shows the warning instead of writing the file.
- Automated regression coverage is added for the manual-output save path.

## Open Questions

- None.
