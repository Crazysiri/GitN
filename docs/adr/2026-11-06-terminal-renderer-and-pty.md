# ADR: Adopt xterm.js rendering with a native forkpty backend for the terminal

- Status: Accepted
- Date: 2026-11-06

## Context

GitN currently embeds a terminal via SwiftTerm's `LocalProcessTerminalView`, which couples VT parsing, screen buffer, rendering, and the PTY into one AppKit view. We want to rebuild the terminal to align its rendering and parsing behavior with a reference Electron Git client that uses xterm.js 6.0.0 for the terminal core and node-pty for the PTY.

GitN is a native SwiftUI/AppKit app. It already hosts Monaco in a WKWebView loaded from `file://`, with a proven native asset bridge (see the Monaco worker transport ADR). It ships arm64-only; `swift build` produces a native binary and there is no x86_64 or universal step for the app itself. The only universal (fat) artifact in the repo is the vendored libgit2 static library, built by `build_libgit2.sh` for arm64 + x86_64 and lipo-merged.

## Decision Drivers

- Rendering/parsing parity: matching xterm.js is the main lever for terminal behavior parity (ANSI semantics, character width, TUI apps).
- Distribution cost: anything added to the app bundle must fit the existing arm64-only, ad-hoc-signed (`codesign --deep`) packaging without new classes of artifacts.
- Maintenance surface: avoid runtime/ABI coupling that forces rebuilds on unrelated version bumps.
- Reuse: the Monaco WKWebView bridge pattern is already in production and can host xterm.js.

## Decision

Use **xterm.js 6.0.0 (plus addon-fit / addon-web-links / addon-webgl) rendered inside a WKWebView, with the PTY provided by a native Swift backend built on the system `forkpty` call.** This is route B of the delivery spec (`xterm + native macOS PTY helper`). We do not embed a Node runtime or node-pty.

The WKWebView owns rendering and input only. A Swift-owned PTY (via `forkpty`) spawns the user's login shell, and raw bytes flow between the PTY and xterm.js over the existing WebKit message-handler bridge (base64 byte payloads, not string interpolation into JS source). PTY lifecycle, resize (`TIOCSWINSZ`), signals, and child reaping are owned in Swift, reusing the process-group SIGHUP → bounded SIGKILL reaping already proven in `TerminalSessionStore`.

## Consequences

- Positive: no Node runtime, no native N-API addon, no ABI-to-Node coupling, no extra executables/dylibs to sign or notarize. `forkpty` is a system call; the current `codesign --deep` packaging is unchanged. Naturally arm64-only. We still get xterm.js's rendering/parsing core for parity.
- Positive: reuses the Monaco bridge conventions (`loadFileURL` + `allowingReadAccessTo`, `ready` handshake, reply-handler asset whitelist) and the `TerminalSessionSelection` / reaping logic.
- Negative: PTY behavior parity with node-pty is not automatic. `forkpty`/exec, argv, environment, resize, signals, exit reaping, UTF-8 chunk handling, and foreground-process behavior must be verified independently (see the M0 CORE matrix in the RFC).
- Negative: WebKit is not Chromium. IME, key handling, WebGL, clipboard, and bridge throughput must pass M0 before committing to M1–M4.
- Follow-up: if M0 shows WebKit cannot meet hard acceptance criteria, report the specific limitation and re-review route A (node-pty helper) or route C (keep SwiftTerm). Keep the SwiftTerm path as a migration-period fallback; do not remove the dependency until migration completes.

## Alternatives Considered

- Route A — xterm.js + node-pty helper: strictest library-level alignment, but requires bundling a Node runtime plus a version-ABI-bound native addon, with x86_64/arm64 matrix and extra signing/notarization surface. The reference client pays ~zero marginal cost for node-pty because it is already an Electron/Node app; GitN is not, so the cost is real and net-new. Rejected for a personal native app.
- Route C — keep SwiftTerm, add features only: no renderer change, lowest churn, but does not align the rendering/parsing core, which is the stated goal. Kept only as fallback.

## Related

- Supersedes the renderer choice implied by `docs/rfcs/2026-11-06-terminal-sessions.md` (which kept SwiftTerm). The session-ownership and reaping decisions there remain valid and are carried forward.
- Reuses the transport pattern from `docs/adr/2026-11-06-monaco-worker-transport.md`.
