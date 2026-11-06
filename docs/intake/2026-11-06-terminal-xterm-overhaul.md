# Feature Intake: xterm.js Terminal Overhaul

- Status: Implemented behind GITN_XTERM flag (M0–M4); SwiftTerm retained as fallback
- Owner: GitN
- Date: 2026-11-06

## Summary

Rebuild GitN's terminal to render and parse with xterm.js 6.0.0 inside a WKWebView, backed by a native Swift `forkpty` PTY, replacing the SwiftTerm `LocalProcessTerminalView`. Deliver multi-tab sessions, shell context (cwd / foreground process), command suggestions with prompt tracking, settings, keyboard shortcuts, and theming. Staged M0 (technical validation) → M1 sessions/transport → M2 shell/context → M3 suggestions → M4 experience/release.

## Implementation Status (2026-11-06)

- M0: xterm.js in WKWebView over native forkpty verified (IME, vim/less TUI, CJK, resize, WebGL fallback, child reaping). Opt-in via `GITN_XTERM=1`.
- M1: multi-tab sessions sharing `TerminalSessionSelection`; retained per-session WKWebView keeps PTY + buffer alive across hide/switch; process-group reaping on close.
- M2: cwd + foreground-process observation via `proc_pidinfo`/`tcgetpgrp` (no shell injection) with known/stale/unknown states; opt-in prompt marker (`CSI 7000 ~`) appended to PS1 end via a re-entrancy-safe ZDOTDIR/rcfile wrapper that sources the user's own config and does not touch dotfiles.
- M3: cd/git/npm/yarn suggestions — static schema + read-only providers (branches, `status --porcelain -z` files, directories, package scripts); quote/escape-aware tokenizer; stale-request filtering; Tab modes; suppressed in TUI/IME/no-prompt.
- M4: context menu (Copy/Paste/Select All/Clear/Close), file drag-drop (escaped paste, no auto-exec), Ctrl-` toggle, Terminal settings tab (font/cursor/scrollback/suggestions/tab-mode), theme-synced backgrounds.

Deferred (not blocking): precise app-level shortcut responder bindings beyond Ctrl-` (SPEC §8.1 "V"), remote npm/yarn network suggestions, overflow-tab horizontal browser, flipping the default on and removing SwiftTerm.

## Behavior Change

- Terminal rendering/parsing moves to xterm.js; the PTY is owned in Swift via `forkpty`.
- Multi-tab terminal sessions survive hide/show and repo-tab switches (carried forward from the existing terminal-sessions work).
- Command suggestions appear while typing (cd / git / npm / yarn), replacing only the active token, never auto-executing. Prompt tracking locates the input region so suggestions anchor correctly.
- Shell context (cwd, foreground process name) is observed and shown, with an explicit `unknown` state when not trustworthy.
- Settings (font, size, line height, cursor style, scrollback, suggestions toggle, tab behavior), macOS shortcuts, right-click menu, overflow tabs, and system-driven light/dark theming.

## Non-Goals

- No Node runtime and no node-pty (decided: native `forkpty`, ADR 2026-11-06-terminal-renderer-and-pty).
- No live-process restoration across app relaunch; no terminal screen-snapshot restore.
- No split panes.
- No generic PATH/history completion in the first delivery (git/cd/npm/yarn only); anything broader is marked a GitN extension.
- No remote-suggestion network calls enabled by default; if built, behind an explicit toggle with offline degradation.
- No copying of any external/reference application code. Clean-room from the behavioral spec only.

## Change Boundary

- In scope: `Views/Terminal/`, new `Models/Terminal/` and `Services/Terminal/`, a new `Xterm/` web frontend + build pipeline, `Resources/Xterm/` host files, `Scripts/build_xterm.sh`, `GitNResources` xterm accessors, `Package.swift` resources, `build.sh` wiring. Plus a separate arm64-only cleanup of `build_libgit2.sh` + `BUILDING.md`.
- Out of scope: Git operation logic, graph, diff/Monaco, sidebar.
- Protected hotspots reviewed: `RepoViewModel` keeps only `showTerminal` visibility wiring and gains no PTY/shell/suggestion/network logic. `GitService` does not run terminal processes. Git-backed suggestion data uses read-only provider calls against the real cwd, not `RepoViewModel` refs, and does not add provider-specific policy to the hotspots.

## Ownership

- Primary owner layer: a terminal workspace store owns session identity and lifecycle; a Swift PTY transport owns `forkpty`/IO/resize/exit; a pure reducer owns ordering/selection; a context observer owns cwd/foreground; a suggestion service owns schema/providers; a WKWebView host owns rendering/input. Pure logic (reducer, tokenizer, quoting, protocol framing, suggestion matching) lives in testable types.
- Why this layer is the right owner: mirrors the existing Monaco (web host + native bridge) and terminal-sessions (store + pure selection model) boundaries already in the codebase.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel`, `GitService`, `RepoContainerView` (wiring/layout only).

## Affected Areas

- Screens / flows: terminal panel in `RepoContainerView.centerPanel`; toolbar toggle; settings.
- Services / helpers / view models: new terminal store, PTY transport, context observer, suggestion service; `GitNResources`; `RepoViewModel.showTerminal` only.
- Files likely to change: `Views/Terminal/*`, `Models/Terminal/*` (new), `Services/Terminal/*` (new), `App/GitNResources.swift`, `Package.swift`, `build.sh`, `Scripts/build_xterm.sh` (new), `Xterm/*` (new), `build_libgit2.sh`, `BUILDING.md`.

## Test Scope

- Unit tests: selection reducer (reuse existing), workspace identity, env/argv construction, PTY protocol framing/seq/generation, token parser + quoting, suggestion matching and provider result mapping, stale-request dropping, prompt-marker parsing across chunks/resize.
- Integration tests: real disposable PTY with a fixture shell — output ordering, large output, resize, helper/child termination and reaping, crash paths.
- Web tests: xterm parser/prompt handling, input events, paste, renderer ACK, retained buffer, WebGL fallback (node `--test` harness mirroring the Monaco tests).
- Manual verification: Chinese IME, Option-as-Meta, Ctrl-C/D/Z, Cmd-C/V, vim/less/top (alternate screen), CJK/emoji width, resize `stty size`, multi-session hide/show, final signed `.app` bundle launch.
- Failure modes / edge cases: PTY child reaping (SIGHUP → bounded SIGKILL), WebContent loss vs PTY loss reported separately, no auto command replay, no orphan processes, `unknown` prompt/context must not intercept TUI keys.
- Known coverage blockers: WebKit frame-time, IME, and responder/shortcut behavior are not fully automatable; covered by manual checks.

## Design Records

- RFC required? Yes — new web frontend, new PTY transport, new long-lived session-owner boundary, cross-SwiftUI/AppKit/WebKit lifetime. See docs/rfcs/2026-11-06-terminal-xterm-overhaul.md.
- ADR required? Yes — durable renderer + PTY-backend decision (route B over A/C). See docs/adr/2026-11-06-terminal-renderer-and-pty.md.

## Completion Criteria

- M0: a minimal signed `.app` bundle runs a single xterm.js terminal over native `forkpty`; the applicable CORE matrix (IME, TUI/alternate screen, UTF-8 chunking, resize, WebGL fallback, child reaping) passes with no unexplained failure, and the route decision is recorded. M0 failure blocks M1.
- M1–M4 each independently reviewable against their acceptance rows; SwiftTerm path retained as fallback until migration completes.

## Open Questions

- Final tuning parameters (chunk size, unacked window, poll cadence) are placeholders to calibrate in M0/M1.
- Whether remote npm/yarn suggestions are in the first suggestion delivery or deferred as a GitN extension.
