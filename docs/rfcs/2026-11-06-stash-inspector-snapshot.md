# RFC: Stash Inspector Snapshot

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Decision

GitService resolves the selected stash OID and reads the base tree (first parent), WIP tree (stash commit), and optional untracked tree (third parent) through the existing libgit2 blob reader. Return old and new Data separately: nil means no blob, while empty Data means an empty file. Use oldPath for the base side of a rename. Resolve LFS pointers through the existing blob path.

RepoViewModel uses those bytes for diff base, current text, and visual preview. A stash selection never falls through to working-tree content. Increment request generations on stash and inspector selection, and check them after asynchronous loads before publishing UI state.

## Tests

Use disposable Git repositories for modified, deleted, untracked, renamed, UTF-16, and image cases. Assert inspector preview/diff sides. Rapid selection remains a manual check until there is a controllable service delay seam.
