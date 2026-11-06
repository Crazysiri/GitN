# Feature Intake: Monaco Local Edit Echo

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Drop pure local Monaco edit echoes while applying changed metadata without resetting undo.

## Behavior Change

- Drop pure local Monaco edit echoes while applying changed metadata without resetting undo.

## Non-Goals

- New editor engine, cross-document cache and Git diff behavior.

## Change Boundary

- In scope: Swift bridge echo classification and Monaco same-text model updates.
- Out of scope: New editor engine, cross-document cache and Git diff behavior.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: Swift bridge owns classification; Monaco host owns editor model.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: Echo versus file, diff and theme change; identical-text setValue avoidance.
- Manual verification: Edit, switch files quickly and test undo after metadata refresh.
- Failure modes / edge cases: Changed metadata must not be mistaken for a pure edit echo.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? Yes; Swift and JavaScript behavior crosses the bridge.
- ADR required? No; editor architecture unchanged.

## Completion Criteria

- Pure echoes are skipped and unchanged text retains undo history.

## Earlier Intake Detail

### Summary and behavior change

The WebView bridge suppresses only an unchanged-metadata payload that echoes the content just edited in Monaco. A file switch, theme or diff metadata update must still reach the host. When the host receives new metadata with identical text, it must keep the existing model value and undo history.
Routine bridge debug messages are opt-in so editing and payload updates do not synchronously send diagnostics to Swift and print them on every update.

### Non-goals and boundary

- No new editor engine, file-source protocol, cross-document model cache, or change to Git diff semantics.
- Swift bridge owns echo classification; Monaco host owns model-value updates. RepoViewModel and GitService do not gain responsibilities.

### Test scope and completion

- Unit-test pure content echo, changed file, changed diff metadata and theme.
- Host test or smoke check that identical text does not call `setValue`.
- Verify routine host debug messages are absent by default and can be explicitly enabled.
- Swift and Monaco tests pass; manual check rapid edit-then-file-switch and undo after hunk metadata refresh.

RFC: `../rfcs/2026-11-06-monaco-local-edit-echo.md` because behavior crosses Swift/WKWebView and JavaScript. No ADR: editor architecture is unchanged.
