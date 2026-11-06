# RFC: Responsive File History Selection

- Status: Accepted
- Owner: GitN
- Date: 2026-11-06

## Problem / Scope

File history currently computes a synthetic text diff on the main actor after reading two snapshots. Large revisions can block interaction. Multiple in-flight selections can publish out of order, and a result can arrive after history closes.

## Design

Use a dedicated instance of the existing FileInspectorSelectionState for the history lifecycle. Opening, selecting, and closing history each advance its generation. Clear the previous selection result before awaiting Git reads. Capture the selection token and history path; check both before every publication after an await. Compute the existing TextDiffEngine result in a detached user-initiated task for files under the configured diff size limit. Files above that limit retain the existing plain-text fallback. Do not change the Git reads or diff semantics.

## Alternatives

Replacing the synthetic diff with a Git patch risks changing file-history semantics for renames and skipped revisions. Running TextDiffEngine on the main actor in smaller chunks requires a new diff API. Both are outside this fix.

## Tests / Rollout / Risks

Exercise file-history selection and close behavior with local fixture repos, run the full Swift suite, and manually switch revisions quickly in the app. Detached work may finish after cancellation; the generation check, rather than task cancellation, owns publication safety. No persistent state or migration.
