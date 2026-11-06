# RFC: xterm.js Terminal Overhaul (native forkpty backend)

- Status: Implemented behind GITN_XTERM flag (M0–M4)
- Owner: GitN
- Date: 2026-11-06

## Summary

Replace the SwiftTerm terminal with an xterm.js 6.0.0 renderer hosted in a WKWebView, backed by a native Swift PTY built on `forkpty`. Deliver, in stages, multi-tab sessions, shell context, command suggestions with prompt tracking, settings, shortcuts, and theming. Gate everything behind an M0 technical validation.

## Implementation Note (2026-11-06)

All milestones M0–M4 landed behind `GITN_XTERM=1`, with SwiftTerm kept as the default fallback. One design correction during implementation: the prompt marker must be appended to the END of PS1 (the input-start column), not emitted in precmd before the prompt — otherwise the recorded cursorX is 0 and the whole prompt is misread as user input. See the ADR and the ShellPromptIntegration wrapper.

## Scope

- In scope: terminal rendering/parsing (xterm.js), native PTY transport, session workspace store, shell context observer, suggestion service, terminal web host + build pipeline, panel/settings/shortcuts/theme wiring.
- Out of scope: Git operation logic, Monaco/diff, sidebar, graph. Node/node-pty, split panes, cross-restart live-process restoration, generic PATH/history completion.

## Problem

SwiftTerm's `LocalProcessTerminalView` fuses VT parsing, screen buffer, rendering, and PTY into one AppKit view. The goal is to align the terminal's rendering/parsing core with xterm.js while keeping GitN a native, arm64-only, Node-free app. The decision to use xterm.js rendering with a native `forkpty` backend (not node-pty) is recorded in ADR 2026-11-06-terminal-renderer-and-pty.

## Proposed Design

A repo-tab-scoped store owns sessions for their lifetime, independent of panel visibility (carried forward from the terminal-sessions RFC). Per session:

- A **Swift PTY transport** opens a PTY with `forkpty`, execs the user's login shell with a de-duplicated inherited environment (HOME/PATH/proxy/SSH_AUTH_SOCK/locale preserved; `TERM=xterm-256color`, `TERM_PROGRAM=GitN` overridden), and owns resize (`TIOCSWINSZ`), signals, exit, and child reaping (process-group SIGHUP → bounded SIGKILL, reusing the existing logic).
- A **WKWebView host** loads a bundled `index.html` from `file://` (via `GitNResources.xtermDirectoryURL` + `allowingReadAccessTo`), runs one xterm.js instance per session, and bridges to Swift through WebKit message handlers: JS→Swift `{event, ...}` with a `ready` handshake; Swift→JS imperative calls. PTY bytes cross as base64 payloads (never interpolated into JS source); the renderer ACKs consumed bytes for flow control.
- A **pure selection reducer** (`TerminalSessionSelection`, reused) owns ordering/active transitions.
- A **context observer** derives cwd and foreground-process name with an explicit `unknown` state; suggestions are suppressed when context is untrustworthy.
- A **suggestion service** holds static git/cd/npm/yarn schema plus read-only providers (branches, files, scripts) keyed by session + cwd + prompt generation + input revision, cancelable, replacing only the active token and never executing input. Prompt tracking injects a GitN-owned CSI/OSC marker via an opt-in, re-entrancy-safe shell wrapper that does not overwrite user dotfiles or prompt hooks.

Byte I/O is strictly ordered per session; normal output must not trigger a full SwiftUI/`RepoViewModel` update. Hidden panels keep draining/retaining buffer to the scrollback bound.

Build pipeline mirrors Monaco: an `Xterm/` npm+webpack project (`publicPath: './'`, hand-written `index.html`/`host.js`/`host.css`), a `Scripts/build_xterm.sh` that builds and rsyncs into `Resources/Xterm/` excluding the hand-crafted host files, and a `Package.swift` `.copy("Resources/Xterm")`.

## Layer Ownership

- Primary owner: terminal store (session identity/lifecycle), Swift PTY transport (forkpty/IO/resize/exit), pure reducer (ordering), context observer, suggestion service, WKWebView host (render/input).
- Why this layer is the right owner: matches the existing Monaco (web host + native bridge) and terminal-sessions (store + pure model) boundaries.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` (visibility flag only), `GitService` (no terminal processes), `RepoContainerView` (wiring/layout only).

## Alternatives Considered

- Route A (node-pty helper): strict library parity but forces a bundled Node runtime + ABI-bound native addon + arch matrix + extra signing surface; net-new cost for a non-Electron app. Rejected (ADR).
- Route C (keep SwiftTerm): least churn but does not align the rendering/parsing core. Kept only as migration-period fallback.

## Test Plan

- Unit: reducer, workspace identity, env/argv, protocol framing/seq/generation, token parser + quoting, suggestion matching/provider mapping, stale-request dropping, prompt-marker parsing across chunk/line/resize.
- Integration: real disposable PTY + fixture shell — ordering, large output, resize, termination/reaping, crash paths (not mock-only).
- Web: node `--test` for xterm parser/prompt, input, paste, ACK, retained buffer, WebGL fallback.
- Manual: Chinese IME, Option-as-Meta, Ctrl-C/D/Z, Cmd-C/V, vim/less/top, CJK/emoji width, resize `stty size`, multi-session hide/show, final signed bundle.

## Migration / Rollout

Staged M0→M4. M0 ships a minimal single-terminal bundle and must pass the CORE matrix (IME/TUI/UTF-8 chunking/resize/WebGL/reaping/packaging) before M1. SwiftTerm and its `Package.swift` dependency stay until migration completes; removal is a later, separate step. Each milestone is independently reviewable. Independent of the terminal work, `build_libgit2.sh` is reduced to arm64-only (no x86_64 lipo) and `BUILDING.md` updated, since GitN does not support x86.

## Risks

- WebKit ≠ Chromium: IME, key handling, WebGL, clipboard, bridge throughput may differ; M0 is the gate.
- Native PTY parity: `forkpty`/exec, resize, signals, UTF-8 chunk boundaries, foreground-process queries need independent verification.
- Suggestion correctness: tokenization/quoting and stale-request filtering are error-prone; must not misinsert or auto-execute, and must not intercept TUI/IME/history keys.
- Prompt wrapper must not break user shell init or custom prompts; opt-in and re-entrancy-safe.
