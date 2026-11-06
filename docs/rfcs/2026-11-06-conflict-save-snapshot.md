# RFC: Conflict Save Snapshot

- Status: Accepted for implementation
- Owner: GitN
- Date: 2026-11-06

## Design

`GitService.loadConflictSession` reads a before/after fingerprint around the existing three-way read and rejects a source that changed during loading. The fingerprint contains the three index-stage object IDs and the SHA-256 of current working-tree bytes, including a distinct missing-file state. `RepoViewModel` retains it only for the open conflict session.

When Mark Resolved is requested, `GitService.saveConflictResolution` rechecks the fingerprint and then writes output and stages the file without an actor suspension between these steps. A mismatch tells the user to reopen the conflict. A stage failure distinguishes a file already written from a fully resolved operation. Closing or switching the conflict clears the fingerprint.

## Scope and tests

The change spans Git service and view-model state, so it requires this RFC. It does not serialize unrelated CLI processes or add an application-wide transaction coordinator. Tests use real temporary Git repositories and file/index changes. An external process could still race after the fingerprint check, so a future cross-process lock may be warranted; this protects the common delayed-save case and same-actor interleaving.
