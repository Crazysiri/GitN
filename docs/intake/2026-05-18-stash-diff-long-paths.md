# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-05-18

## Summary

Fix stash diff loading so GitN keeps full repository-relative paths for stash file entries instead of parsing truncated `git stash show --stat` display output. This allows selecting long nested files from a stash and loading their patch content reliably.

## Behavior Change

- Stash file lists now preserve full repo-relative paths even for long nested files.
- Selecting a stash file should load its diff using the exact path reported by Git, instead of failing when the stat view abbreviated the path with `...`.

## Non-Goals

- No change to regular commit diff loading.
- No new stash UI states or stash metadata.
- No redesign of rename/copy classification for stash entries beyond keeping exact file paths.

## Change Boundary

- In scope:
- `GitService.stashDiffFiles` parsing logic.
- Targeted stash behavior tests in `GitServiceBehaviorTests`.
- Out of scope:
- `RepoViewModel` selection flow.
- General diff parser behavior outside stash loading.
- Protected hotspots reviewed:
- `GitService` is touched only to swap human-oriented stash stat parsing for machine-oriented stash path/stat parsing. No new ownership is added to `RepoViewModel`.

## Ownership

- Primary owner layer: Service/helper
- Why this layer is the right owner: The bug is in how Git command output is parsed and mapped into `DiffFile` models.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` should continue consuming already-correct `DiffFile` paths instead of compensating for malformed stash output.

## Affected Areas

- Screens / flows:
- Stash selection in the sidebar/detail diff flow.
- Services / helpers / view models:
- `GitService`
- Files likely to change:
- `GitN/Sources/GitN/Services/GitService.swift`
- `GitN/Tests/GitNTests/GitServiceBehaviorTests.swift`

## Test Scope

- Unit tests:
- Verify stash file enumeration preserves a long nested path exactly.
- Verify the exact returned stash path can be fed back into stash diff loading.
- Integration tests:
- None beyond the existing temporary git repository behavior tests.
- Manual verification:
- Open a stash containing long nested Swift paths and confirm selecting them renders the diff.
- Failure modes / edge cases:
- Long paths that `git stash show --stat` would abbreviate.
- Stashes that also include untracked `^3` files.
- Known coverage blockers:
- No automated UI coverage for the sidebar/detail interaction.

## Design Records

- RFC required? Why or why not?
- No. This is a focused bug fix inside existing `GitService` responsibility and does not add a new service boundary or workflow.
- ADR required? Why or why not?
- No. No durable architecture or repository-wide policy changes are introduced.

## Completion Criteria

- `stashDiffFiles` no longer depends on truncated `--stat` path display output.
- A stash entry with a long nested path is returned with its full path.
- The returned path can be passed into `stashFileDiff` and produce patch text.

## Open Questions

- None.
