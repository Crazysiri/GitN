# RFC: Persistent Terminal Sessions

- Status: Implementing
- Date: 2026-11-06

## Problem

RepoContainerView conditionally constructs TerminalPanelView; its NSViewRepresentable starts a shell in makeNSView. Hiding the panel removes that view, so showing it starts a fresh shell. The analyzed GitKraken terminal distinguishes hiding a panel from terminating its sessions and exposes multiple session tabs.

## Design

The repository container owns a terminal-specific store for its lifetime. The store creates and retains one LocalProcessTerminalView per session and explicitly terminates views on session close or repository-tab disappearance. A lightweight TerminalSessionSelection value tracks ordered IDs and the active ID and is testable without AppKit. A representable mounts only the active view into a container, detaching it when the panel is removed or a different session is selected; retained views keep their PTYs alive. The panel shows session tabs and new/close controls. Hiding only changes panel visibility.
When closing, the store sends SIGHUP to the shell's dedicated process group, asks SwiftTerm to close its PTY, and reaps the child asynchronously. A short timeout escalates to SIGKILL only for that session's process group. This avoids leaving interactive zsh and zombie processes after a tab closes.

The owning repo view already remains in ContentView after switching app tabs, so the store remains alive. The store does not live in RepoViewModel; it owns a UI/PTY resource rather than Git state. Shell launching and path escaping retain existing behavior.

## Validation

Test the selection model edge cases and compile the app. With a disposable repo, create two sessions, run distinct commands, switch tabs, hide/show, and check output remains. Close one session and verify the other remains usable. Closing the repository tab should terminate its sessions.

## Limits

This does not claim GitKraken terminal feature parity. Shell-aware suggestions, keymap parity, persistent sessions across app restart, and split panes need separate specifications and tests.
