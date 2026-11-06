# Feature Intake: Persistent Terminal Sessions

- Status: Implemented; two-shell GUI lifecycle verified
- Owner: GitN
- Date: 2026-11-06

## Summary

Keep terminal PTYs alive across panel hiding and tab switches, with explicit session close.

## Behavior Change

- Keep terminal PTYs alive across panel hiding and tab switches, with explicit session close.

## Non-Goals

- Shell integration, profiles, restart restoration, remote shell and split panes.

## Change Boundary

- In scope: TerminalSessionStore, selection model and terminal panel.
- Out of scope: Shell integration, profiles, restart restoration, remote shell and split panes.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: Terminal store owns PTYs; pure model owns selection; panel owns controls.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: Selection and lifecycle tests, including shell reaping.
- Manual verification: Two-shell preview: closing first removes its PID; hiding/showing retains second PID.
- Failure modes / edge cases: Interactive zsh needs process-group SIGHUP and child reap.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? Yes; SwiftUI and AppKit lifetime boundary.
- ADR required? No; terminal-specific ownership only.

## Completion Criteria

- Closing removes only its shell and hidden panels preserve their session.

## Earlier Intake Detail

### Summary and behavior change

The terminal currently starts a new shell when hidden and shown again. Give each repository tab terminal sessions with visible tabs. Hiding the panel, switching repository tabs, or opening the conflict editor retains the shell, buffer, and current directory. Users can create, select, reorder, and close sessions; closing a repository tab terminates its sessions.
Manual preview testing found that SwiftTerm's SIGTERM does not stop an interactive zsh on this macOS build. Closing a session must hang up its process group and reap its child after the PTY is closed.

### Non-goals and boundary

- No shell integration, command suggestions, terminal profile editor, restoration after app relaunch, or remote shell support. Those require separate evidence and design.
- No changes to Git operations, RepoViewModel, or SwiftTerm internals.
- A terminal-specific store owns PTY views and termination. A pure selection model owns tab ordering and active-session transitions. The SwiftUI panel owns controls and mounting the selected view.

### Test scope

- Unit-test create/select/close/reorder/next/previous behavior, including closing active and last tabs.
- Compile the app and manually verify two sessions, hide/show, repository tab switching, and close/reopen behavior in a disposable repository.
- Verify a closed session is terminated and an active session survives panel removal.
- Verify the child PID disappears after closing a session, while the sibling PID remains alive.

### Design records and completion criteria

RFC required because session ownership crosses SwiftUI and AppKit. See docs/rfcs/2026-11-06-terminal-sessions.md. No ADR: this is a terminal-specific lifetime boundary. Complete when a hidden panel does not restart the shell and session actions preserve the correct active tab and PTY identity.
