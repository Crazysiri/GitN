# RFC: repository mutation queue

GitService actor isolation does not span awaits. Public mutation APIs acquire a shared FIFO gate identified by the canonical common Git directory; sync libgit2 implementations also enter through async public wrappers. Unqueued implementation methods may compose one another under that ownership, avoiding recursive acquisition. Worktree mutations use the same gate. Reads stay outside it.

The registry stores weak gates; active operations/waiters retain their gate. Cancellation removes waiters and resumes them with CancellationError. A granted operation checks cancellation before its first mutation. Both success and failure release ownership. Locks are process-local and do not claim protection against external Git clients. Git's lockfiles and conflict snapshots remain necessary.

Validation covers FIFO across actor suspension, cancelled waiters, errors, independent repos, canonical linked-worktree aliases, and actual staged changes through two GitService instances. Existing operation semantics and return values remain intact.
