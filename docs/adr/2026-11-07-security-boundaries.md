# Credential and External-Content Trust Boundaries

- Status: Accepted
- Date: 2026-11-07

Hosted-review secrets belong in macOS Keychain, behind a shared throwing storage boundary. Preferences store configuration only. Callers must surface save/delete failures and must never fall back to plaintext storage.

SSH trust requires reviewing fingerprints and persisting the exact reviewed key material. Scanning is discovery, not authentication; confirmation must instruct independent fingerprint verification. Changed known host keys are not silently replaced.

Untrusted diagram rendering defaults to strict sanitization, bundled scripts and restricted navigation/network resources. AI commit generation must explicitly use a read-only, non-interactive execution policy rather than inherit writable permissions from user configuration.

Interactive terminals and explicitly selected Git hooks/tools retain normal user semantics; these boundaries do not claim to sandbox arbitrary repositories or third-party CLIs.
