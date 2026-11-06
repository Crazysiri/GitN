# RFC: Worktree Management

- Status: Implemented; manual sidebar interaction review pending
- Owner: GitN
- Date: 2026-11-06

## Design

Use `git worktree list --porcelain -z` to preserve paths containing spaces or newlines and parse it in a pure helper. A focused service wraps `git worktree add` and `remove`, passing arguments directly through GitCLI. The service rejects removal of the main/current, locked or prunable worktree and never supplies `--force`; Git itself rejects dirty removal.

RepoViewModel publishes the list during metadata loading and refreshes it after mutations without reloading the commit graph. A sidebar section lists worktrees and opens each through AppModel's existing tab path. The add sheet requires a user-selected destination and branch name; local branch rows can create a worktree for that branch. Removal requires an explicit confirmation, with open tabs protected.

The repository watcher classifies changes under the shared `worktrees/` metadata directory separately and refreshes only the worktree list when those are the sole events. Paths are canonicalized before current-worktree and open-tab checks, including macOS `/var` versus `/private/var` aliases.

## Validation

Test the parser with NUL-delimited fixtures, then exercise real temporary repos. Compile the app target and check the sidebar workflow manually. A failed add/remove must leave existing worktrees unchanged and show the Git error.
