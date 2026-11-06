# Feature Intake: Per-Block Conflict Resolution Gate

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Saving a text conflict must not stage the whole file while any conflict block remains unaddressed. Each block is resolved by a selected side, a manual edit touching that block, or an explicit Keep Base choice. The toolbar shows the unresolved count and directs the user to the remaining block.

## Behavior Change

- Saving with unresolved blocks no longer marks the whole file resolved.
- The UI shows the unresolved count and supports an explicit Keep Base choice.

## Non-Goals

- No rewrite of three-way diff generation, line mapping, or output editor.
- No silent acceptance of untouched ancestor content. No draft persistence in this batch.

## Change Boundary

- In scope: ConflictEditorDocument resolution intent, save guard, and conflict toolbar.
- Out of scope: three-way diff algorithm, line mapping, and draft persistence.
- Protected hotspots reviewed: RepoViewModel only gates save and routes existing commands.

## Ownership

- Primary owner layer: ConflictEditorDocument for resolution intent; ViewModel for save guard; View for controls.
- Why this layer is the right owner: resolution state belongs to the document model and save policy to orchestration.
- Which larger type is intentionally not taking more responsibility: GitService does not infer block intent.

## Test Scope

- Unit tests: two-block partial resolution, manual edit, empty deletion, Keep Base, deselection, and reset.
- Manual verification: resolve one of two blocks and confirm the remaining block cannot be silently staged.
- Failure modes / edge cases: untouched ancestor content, empty output, and partial selection.
- Known coverage blockers: no automated full UI interaction test.

## Design Records

- RFC required? Yes; model, ViewModel, and view behavior change together.
- ADR required? No; no repository-wide policy is established.

## Completion Criteria

- All blocks need explicit resolution before stage, and the focused tests pass.
