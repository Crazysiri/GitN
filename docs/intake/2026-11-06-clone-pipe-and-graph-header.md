# Feature Intake: Clone Pipe Safety and Graph Header Legibility

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Clone drains process output through GitCLI and the narrow graph header keeps Reflog legible.

## Behavior Change

- Clone drains process output through GitCLI and the narrow graph header keeps Reflog legible.

## Non-Goals

- Credential handling, URL parsing, repository initialization and reflog semantics.

## Change Boundary

- In scope: Clone process transport and GraphView header layout.
- Out of scope: Credential handling, URL parsing, repository initialization and reflog semantics.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: GitCLI owns pipe draining; GraphView owns layout.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: Clone a local committed repository from a non-repository parent and verify its file.
- Manual verification: Inspect Reflog in a narrow graph pane.
- Failure modes / edge cases: Large stderr must not deadlock Clone and Reflog must not wrap.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? No; existing process and view boundaries suffice.
- ADR required? No; no durable boundary changes.

## Completion Criteria

- Clone and Reflog checks pass with a release build.

## Earlier Intake Detail

### Summary and behavior change

Repository cloning should use the already tested GitCLI runner so large Git diagnostics cannot fill an unread pipe and stall Clone. The graph header should keep the Reflog label on one line in a narrow middle pane.

### Non-goals and boundary

- No change to clone credentials, URL handling, repository initialization, or tab persistence.
- No graph data or reflog behavior change; only the toggle's layout is adjusted.
- AppModel continues to coordinate tab opening. GitCLI owns process pipes; GraphView owns header presentation.

### Test scope and completion

- A temporary local repository clone exercises GitCLI from a non-repository parent and verifies committed content at the destination.
- Check a running narrow graph pane visually for a single-line Reflog control.
- The clone test and Swift build must pass; no network clone or user repository mutation is needed.

### Design records

- Intake only: this reuses the existing GitCLI process boundary without introducing a new service or workflow policy.
