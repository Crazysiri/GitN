# Feature Intake: Stash Paths and Blob Bytes

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Stash file lists must use Git NUL-delimited path output so quoted Chinese, Tab, and newline names are returned as real paths. Stash document loading must retain original blob bytes through decoding, including BOM-marked UTF-16 Markdown. Rename metadata and file status should survive list parsing.

## Behavior Change

- Stash paths with Chinese, Tab, and newline characters resolve to their actual blobs.
- UTF-16 Markdown contents and rename metadata remain available to the inspector.

## Non-Goals

- No redesign of stash apply/drop, multi-stash OID identity, or all inspector snapshot sources in this batch.
- No automatic transcoding of arbitrary unknown encodings.

## Change Boundary

- In scope: NUL-delimited stash path parsing, blob bytes, status and rename metadata.
- Out of scope: Apply/Pop semantics and the full inspector snapshot-source redesign.
- Protected hotspots reviewed: GitService runs Git and delegates path parsing; RepoViewModel consumes existing models.

## Ownership

- Primary owner layer: stash path parser for protocol mapping; GitCLI for raw bytes.
- Why this layer is the right owner: NUL records and encoding are data-boundary concerns.
- Which larger type is intentionally not taking more responsibility: RepoViewModel does not parse Git output.

## Test Scope

- Unit tests: parser handles Chinese, Tab, newline, rename, and malformed NUL records.
- Manual verification: inspect staged, deleted, and untracked Markdown from a disposable stash.
- Failure modes / edge cases: quoted paths, missing blobs, UTF-16, invalid records, and binary content.
- Known coverage blockers: no automated image preview UI test.

## Design Records

- RFC required? Yes; new parser crosses the Git and inspector data boundary.
- ADR required? No; no general snapshot architecture is introduced.

## Completion Criteria

- Real temporary stash fixtures expose exact paths and bytes; malformed input fails visibly.
