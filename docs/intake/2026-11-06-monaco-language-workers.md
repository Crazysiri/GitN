# Feature Intake: Monaco Language Workers in WKWebView

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Load allowlisted Monaco worker assets as Blob workers in WKWebView.

## Behavior Change

- Load allowlisted Monaco worker assets as Blob workers in WKWebView.

## Non-Goals

- Git diff algorithm, content persistence, editor controls and language set.

## Change Boundary

- In scope: Monaco worker routing and native bundle asset bridge.
- Out of scope: Git diff algorithm, content persistence, editor controls and language set.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: Monaco entry owns workers; WebView coordinator owns allowlisted reads.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: Worker mapping, URL reuse and failure cleanup, plus WKWebView smoke.
- Manual verification: Open JSON and TypeScript in a packaged editor.
- Failure modes / edge cases: Unknown worker labels or failed asset loads must not run arbitrary files.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? Yes; JavaScript and native WebKit boundary.
- ADR required? Yes; durable worker transport boundary.

## Completion Criteria

- Editor, JSON and TypeScript workers start lazily without file-URL failures.

## Earlier Intake Detail

### Summary and behavior change

Monaco's generated editor and language workers fail when launched from `file://` inside WKWebView. The existing diff worker already uses a Blob URL. Load the generated editor/language worker source from the app bundle on demand, create Blob workers in the page, and reuse the Blob URL for each worker type. This restores background language/editor work without adding all worker bytes to the initial editor bundle.

### Non-goals and boundary

- No change to the Git diff algorithm, content persistence, editor controls, or supported languages.
- The Monaco entry owns worker selection and lifetime. The WebView coordinator only returns allowlisted bundled assets.
- RepoViewModel and GitService remain outside this change.

### Test scope

- Unit-test label-to-file routing and URL reuse/failure cleanup.
- WKWebView smoke must start editor and JSON workers without script errors, and keep diff/color/large-file assertions passing.
- Run Node tests, Swift tests, and a release build.

### Design records and completion criteria

RFC and ADR required: this crosses JavaScript and native WebKit and establishes the worker-loading boundary. Complete when workers launch through Blob URLs in the packaged app, assets are allowlisted and fetched lazily, and diagnostics no longer show file-worker failures.
