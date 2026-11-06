# Feature Intake: Stash Inspector Snapshot

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Read stash inspector content and image bytes from the selected stash and its parents. Deleted files have an empty new side even if the working tree has a same-named file. Ignore stale async selections.

## Behavior Change

- Tracked before/after data comes from the stash base and WIP trees; untracked data comes from the third parent.
- Deleted Markdown and images show the correct old side; stale requests cannot overwrite a newer selection.

## Non-Goals

- No change to stash Apply/Pop or other history content sources.

## Change Boundary

- In scope: stash reads in GitService and inspector/selection orchestration in RepoViewModel.
- Out of scope: remote Git and general-purpose snapshot architecture.
- Protected hotspots reviewed: these existing types already own stash reads and inspector state.

## Ownership

- Primary owner layer: GitService for blob versions; RepoViewModel for request identity and presentation.
- Why this layer is the right owner: Git tree lookups belong in the service; selection state belongs in the view model.
- Which larger type is intentionally not taking more responsibility: views gain no Git logic.

## Test Scope

- Unit tests: stash tree version mapping and inspector snapshot content.
- Integration tests: temporary stash with modified, deleted, untracked, renamed, UTF-16, and image paths.
- ViewModel tests: content and image sides remain tied to stash despite different working-tree data.
- Manual verification: rapid stash/file selection and deleted-file preview.
- Failure modes / edge cases: empty blob, missing path, shifted index, stale asynchronous load.
- Known coverage blockers: no controllable GitService delay seam for deterministic UI race tests.

## Design Records

- RFC required? Yes; this crosses service and view model.
- ADR required? No; the snapshot boundary is local to stash inspection.

## Completion Criteria

- Stash preview and diff never read a same-named working-tree file; tests pass.
