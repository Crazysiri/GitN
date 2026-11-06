# Feature Intake: Conflict Save Snapshot

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Validate the conflict session snapshot before Mark Resolved writes and stages.

## Behavior Change

- Validate the conflict session snapshot before Mark Resolved writes and stages.

## Non-Goals

- Automatic merge of external edits and changes to ordinary inspector saves.

## Change Boundary

- In scope: Git conflict snapshot, verified save/stage, and session failure messaging.
- Out of scope: Automatic merge of external edits and changes to ordinary inspector saves.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: GitService owns validation and write; RepoViewModel owns session state.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: Disposable conflict tests for valid save, external file/index changes and index lock.
- Manual verification: Change a conflict file externally and verify reopen guidance.
- Failure modes / edge cases: Stale snapshots must never overwrite or stage newer content.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? Yes; service, model and UI cooperate.
- ADR required? No; scoped conflict-session policy.

## Completion Criteria

- Valid snapshots stage once; stale snapshots fail without writing.

## Earlier Intake Detail

### Summary and behavior change

Opening a three-way conflict captures the index stages and working-tree content identity. Mark Resolved saves and stages only if both still match. An external file edit or Git index change makes the action fail with a reopen instruction, leaving the newer content intact.

### Non-goals and boundary

- No automatic merge of external edits, no new draft file format, and no change to explicit external-editor fallback.
- `GitService` owns the snapshot and atomic save/stage operation; `RepoViewModel` holds the session snapshot and reports failures; the view keeps its existing action.
- No new Git policy in SwiftUI and no change to ordinary file inspector saves.

### Test scope

- Real temporary merge conflicts: unchanged snapshot stages the intended output; external worktree edit blocks the save; external index resolution blocks the save.
- An index-lock failure reports that the file was saved, retains the editor, and permits a retry only with the new verified snapshot.
- Existing two-block resolution tests and full Swift suite remain green.
- Manual check: an externally changed conflict file prompts reopen without being overwritten.

### Completion criteria and records

Snapshot mismatch never writes a file or stage-0 index entry. A valid save writes and stages in one actor operation. RFC: `../rfcs/2026-11-06-conflict-save-snapshot.md`; no ADR because the policy is scoped to conflict sessions.
