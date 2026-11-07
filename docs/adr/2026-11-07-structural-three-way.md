# ADR: Structural three-way model and Monaco rendering

- Status: Accepted
- Date: 2026-11-07

## Context
GitN's custom conflict editor and marker-parsing reconstruction diverge from the requested Kraken merge behavior. Monaco is already bundled for the inspector.

## Decision
Conflict editor partitioning uses a pure line-array diff3 helper with exact input ranges, independent of rendered conflict markers. Document state owns merge membership and resolution intent. Three Monaco editors in one WebView own rendering and scroll geometry, using the shared local runtime/worker transport. Git remains responsible for index stages, writes, encoding and stage validation.
An absent side in the conflict index is resolved through an explicit modify/delete choice, not synthesized as a zero-length text side; Git checkout-index preserves the selected stage's mode and filters.

## Consequences
Repeated text and literal marker lines no longer require heuristic position recovery. UI scrolling does not round-trip through SwiftUI. This adds a JS/Swift protocol that needs integration coverage. Existing save guards and explicit resolution intent remain required even when the reference allows less strict unresolved output.
