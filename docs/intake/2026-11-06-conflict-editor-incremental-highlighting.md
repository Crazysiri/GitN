# Feature Intake: Incremental Conflict Output Highlighting

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Highlight only the edited logical lines in three-way output when the changed range is known.

## Behavior Change

- Highlight only the edited logical lines in three-way output when the changed range is known.

## Non-Goals

- Merge decisions, save and stage, undo policy, Git content and syntax parser redesign.

## Change Boundary

- In scope: AppKit conflict-output highlighting and UTF-16 range handling.
- Out of scope: Merge decisions, save and stage, undo policy, Git content and syntax parser redesign.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: Conflict output editor owns attributed text updates.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: Late-line edit, newline insertion/deletion and Unicode inline-comment offsets.
- Manual verification: Type and scroll in a disposable conflict fixture.
- Failure modes / edge cases: Unknown edit ranges must safely fall back to a full highlight.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? No; the change stays in the existing editor.
- ADR required? No; no architecture policy changes.

## Completion Criteria

- Ordinary edits touch only affected lines and preserve text and selection.

## Earlier Intake Detail

### Summary and behavior change

Typing in the three-way output editor currently rebuilds attributed text for the entire file after every edit. Re-highlight only the edited logical lines for normal text edits. Keep full highlighting for externally replaced documents and edits whose affected range cannot be determined. Correct UTF-16 offsets when finding inline comments after non-ASCII text.

### Non-goals and boundary

- No change to conflict resolution, save/stage, undo policy, or Git content.
- No syntax parser redesign or multiline lexical state; the current highlighter is line-based.
- ConflictOutputEditorView owns presentation updates. RepoViewModel and GitService gain no editor logic.

### Test scope

- Test an edit in a later line leaves attributes on an untouched line intact.
- Test inserted/deleted newline and Unicode near an inline comment.
- Run focused Swift tests and a release build; inspect typing and scrolling in a disposable conflict fixture if feasible.

### Completion criteria and records

Normal edits touch only their affected lines and preserve text/selection; syntax colors and line breaks remain correct. Intake only: this is local UI rendering work within the existing editor boundary.
