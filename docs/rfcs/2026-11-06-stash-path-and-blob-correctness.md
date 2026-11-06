# RFC: Stash Paths and Blob Bytes

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Design

Read tracked stash changes using git diff --name-status -z -M and --numstat -z -M between the stash base and WIP commit. Read the optional untracked third-parent tree with ls-tree -z. Parse raw Data at NUL boundaries before UTF-8 decoding each path; status records may consume two paths for rename/copy. Preserve status and old path on DiffFile. Do not allow Git's quotePath display encoding into path-based commands.

For stash blobs, use GitCLI.outputData and decode the original bytes. Recognize UTF-16 BOM before treating NUL bytes as a binary-file signal. Keep missing blobs distinct from empty blobs by returning nil only when neither tree contains the path.

## Boundaries and risk

- GitService retains command sequencing; StashDiffFileParser owns strict output parsing.
- This batch does not migrate stash identities from display indices to stable OIDs; that is a later action because it crosses selection and mutations.
- Malformed command output throws. A missing third parent is expected; failures to read an existing third parent must propagate.

## Tests

Use real local Git fixtures for Unicode and control-character names, tracked rename, deleted and untracked files, plus UTF-16 blob decoding. Unit-test malformed NUL framing.
