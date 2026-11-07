# Security Hardening Intake

- Status: Implemented and automatically validated; native credential/trust UI checks remain manual
- Owner: GitN
- Date: 2026-11-07

## Summary

Store hosted-review tokens in macOS Keychain; require review of scanned SSH key fingerprints before persisting exactly those keys; restrict untrusted Mermaid content and navigation; run AI commit generation with an explicit read-only, non-interactive policy; update audited frontend build dependencies and use locked installs without lifecycle scripts.

## Behavior Change

Tokens must be re-entered once; no legacy migration is requested. Failed Keychain operations are visible. SSH trust uses a review step and refuses existing known-host entries. Mermaid uses strict sanitization, a bundled native-injected runtime and nonce-authorized bootstrap. AI generation ignores user config/rules, disables shell/multi-agent tools and sends prompts through stdin. Frontend builds use npm ci --ignore-scripts.

## Non-Goals

No legacy token migration (single-user instruction). No replacement of interactive terminals or Git's normal hooks/filters, no authentication redesign, no general sandbox for all repository operations, no unrelated conflict-editor changes. No claim that a clean dependency audit proves exploit absence.

## Change Boundary

- In scope: Shared credentials, SSH scan/review/persistence, Mermaid WebView policy, AI helper processes, frontend dependencies and generated assets.
- Out of scope: General Git hooks/filter execution, interactive terminals, provider API redesign and repository history/graph behavior.
- Protected hotspots reviewed: GitService loses SSH persistence; RepoViewModel retains prompt orchestration only. Existing conflict-editor work is preserved.

## Ownership

- Primary owner layer: Focused Security.framework credential backend, SSHHostKeyService, MarkdownWebSecurity, BoundedProcessRunner and existing AICommitService.
- Why this layer is the right owner: Validation, persistence and process policies can be exercised without SwiftUI; views render errors and reviewed fingerprints.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not acquire credential, parsing or SSH file persistence logic.

## Test Scope

- Unit tests: Fake credential CRUD/failures, SSH endpoint/wire-key validation, fingerprints, exact key persistence and symlink/existing-host rejection, script escaping/navigation, stable nonce generation and AI arguments.
- Integration tests: Bounded real local helper processes with stdin, cancellation, output limits, deadlines and inherited pipes; native WKWebView renders the bundled Mermaid under its production policy and rejects injected scripts. Existing Monaco WebKit smoke test and both frontend suites.
- Manual verification: Keychain authorization dialogs and SSH fingerprint banner layout require checking in the rebuilt app; no real user credentials or remote SSH trust are exercised by automated tests.
- Failure modes / edge cases: Locked or denied Keychain, invalid host/options, malformed/mismatched keys, existing hashed hosts, symlinks, script closing tags, forbidden URLs, process cancellation/output flooding and inherited pipes.
- Known coverage blockers: Automated credential tests use a fake backend rather than the user's login Keychain. Live AI generation is intentionally not invoked; CLI flags are checked against official docs and installed CLI help.

## Design Records

- RFC required? Yes, cross-module services and UI trust flow: docs/rfcs/2026-11-07-security-hardening.md.
- ADR required? Yes, durable credential and external-content trust boundaries: docs/adr/2026-11-07-security-boundaries.md; policy reflected in ENGINEERING_GUIDELINES.md.

## Completion Criteria

Tokens no longer read/write UserDefaults; failed saves are visible. SSH confirmation displays fingerprints and cannot rescan on accept. Mermaid renders with strict security and explicit resource/navigation restrictions. AI invocation fixes sandbox and approval behavior. Both frontend dependency audits are clean, generated assets are rebuilt, relevant automated checks pass or concrete blockers are documented.

## Open Questions

None; the user explicitly declined legacy token migration.

## Validation Results

- Final Swift suite: 517 tests, 5 existing git-lfs-dependent skips, 0 failures (89.116 seconds). Includes 16 security tests and production Mermaid WKWebView rendering/CSP checks.
- Monaco frontend: 35 tests passed; production build and native WebKit smoke passed (editor/json/TypeScript workers, zero worker failures).
- Xterm frontend: 14 tests passed; production build passed. Both generated resource directories synced.
- Both dependency trees: npm ci reported zero known vulnerabilities after locked updates; Webpack 5.112.2 and compatible patched transitive dependencies.
- git diff --check and build-script shell syntax passed.
- The security intake passed the repository harness validator with its changed-file input scoped to this task. The full-worktree harness remains blocked by the pre-existing docs/intake/2026-11-07-compact-monaco-three-way.md, which lacks five required fields. That unrelated in-progress document was preserved.
- No real tokens, remote SSH trust or AI generation were exercised. macOS Keychain authorization and the SSH banner require native manual acceptance in a rebuilt app. The installed CLI help and official docs establish the selected flags; unsupported versions fail closed.

## Follow-up Submission Validation

The remaining editor/document work was subsequently authorized for submission. Required fields in its existing intake records were completed; the full-worktree harness now passes. The conflict-editor native WebKit smoke also passed with zero script errors. The earlier harness blocker above records the state during the security-only change.
