# Security Hardening

- Status: Accepted
- Date: 2026-11-07
- Intake: ../intake/2026-11-07-security-hardening.md

## Design

Use a small injectable credential backend with a Security.framework generic-password implementation. Provider accessors become read-only; explicit throwing save functions allow Settings to retain dirty state and display failures. No migration from UserDefaults is requested; remove obsolete plaintext values when writing/clearing credentials.

Extract SSH scanning from GitService. Validate host input before passing it to ssh-keyscan, parse bounded output into supported SSH key records, compute SHA256 fingerprints from the wire-format key, and retain a candidate batch in prompt state. Only a confirmed candidate batch can be written; acceptance must never perform another scan. Display the keys in a second confirmation step after the existing unknown-host prompt. Reject invalid hosts/keys and changed-host-key errors rather than offering replacement. Persist with restrictive permissions and do not follow a known_hosts symlink.

Keep Mermaid code generation in the renderer, but centralize strict security settings, safe inline JSON and resource/navigation policy. Inject the bundled Mermaid runtime using WKUserScript (file-origin CSP cannot reliably load it with script-src self), and authorize only the renderer bootstrap with a nonce stable for that WebView. Disallow remote diagram resource loading and web navigation; normal Markdown remote images are outside the Mermaid WebView and retain existing behavior.

AI generation uses explicit read-only sandbox/never approval, disabled shell and multi-agent tools, ignored user config/rules, a private empty working directory, no shell interpolation, stdin prompt delivery, concurrent nonblocking pipe draining, bounded output, and a deadline (including inherited pipes). Keep user login/authentication; do not invoke the AI in tests. A recent CLI supporting ignore-user-config/ignore-rules is required; unsupported versions fail closed rather than retry with weaker permissions. Official references: https://developers.openai.com/codex/cli/reference/ and https://developers.openai.com/codex/config-reference/.

Update pinned frontend build tool versions and compatible transitive lockfile entries, use npm ci --ignore-scripts, rebuild local assets, and rerun audits/tests. Do not run an indiscriminate npm audit fix --force.

## Validation

Use injected in-memory credential storage, temporary known_hosts files and deterministic public keys, pure argv/navigation assertions, renderer tests and existing native WebKit smoke tests where feasible. Full Swift suite checks integration with current uncommitted work. No network SSH scans or AI API calls in tests.
