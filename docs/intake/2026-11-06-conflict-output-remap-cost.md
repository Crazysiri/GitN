# Feature Intake: Conflict Output Edit Remapping Cost

- Status: Implemented
- Owner: GitN
- Date: 2026-11-06

## Summary

Compute the changed-line span once when manual conflict output is edited.

## Behavior Change

- Compute the changed-line span once when manual conflict output is edited.

## Non-Goals

- Merge decisions, save and stage, undo, Git operations and syntax coloring.

## Change Boundary

- In scope: ConflictEditorDocument line-origin and block remapping.
- Out of scope: Merge decisions, save and stage, undo, Git operations and syntax coloring.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: ConflictEditorDocument owns provenance state.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: No-op edit and late edit in a large output preserve origins and blocks.
- Manual verification: Inspect one representative large three-way output.
- Failure modes / edge cases: A true no-op must not remap state.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? No; local model optimization.
- ADR required? No; no architecture policy changes.

## Completion Criteria

- One span calculation per edit and existing behavior tests pass.

## Earlier Intake Detail

### Summary and behavior change

Manual edits in the three-way output currently split both document versions and compute the changed-line span twice. Compute that span once, use it for line-origin and block remapping, and skip a true no-op edit. This reduces work on large conflict files without changing the resolved output or provenance semantics.

### Non-goals and boundary

- No change to merge decisions, save/stage, undo behavior, Git operations, or syntax highlighting.
- `ConflictEditorDocument` owns the mapping; views and service layers gain no logic.
- `RepoViewModel` and `GitService` stay outside this change.

### Test scope

- Check no-op edits preserve block state and line origins.
- Check a late edit in a large output preserves preceding and following origins and block mapping.
- Run focused Swift tests and a release build.

### Design records and completion criteria

Intake only: this is a local non-UI refactor with a clear model owner. Existing behavioral tests pass, the added tests cover the two boundaries, and the edited path computes only one changed-line span.
