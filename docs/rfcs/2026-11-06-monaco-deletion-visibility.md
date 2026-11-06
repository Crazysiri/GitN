# RFC: Monaco Deleted-Line Rendering and Async Diff

- Status: Implemented and preview-verified
- Owner: GitN
- Date: 2026-11-06

## Design

Keep a single Monaco editor for the modified text. Render removed lines in Monaco view zones, with viewport-scoped red gutter/content overlays. Compute the line model in a worker so text can paint first; transfer the structured-cloneable model (including Maps) to the host. Cancel superseded requests and verify a request generation before decorating. Reuse the editor/model when only metadata changes; release replaced models. Show a small status on worker failure rather than hiding file content.

The diff editor's line-number gutter is sized for both old and new columns at creation and on reuse. Reusing an editor must reapply this width after editorOptions because the generic preview default would otherwise shrink it to four characters. The gutter grows with the maximum line-number digit count.

WKWebView rejects a file:// Worker even when the page has read access to the resource directory. Build the diff worker separately and embed its source in the main bundle; create a blob URL in the host page. Keep the worker isolated from Monaco's language-service workers. The build script must detect source/config changes and sync the generated bundle even when compilation is skipped.

## Validation

Test model construction, renderer DOM, and actual WKWebView with a replacement, a pure deletion, and a 10k+ line file. Confirm CSS computed background is red-tinted in both themes. Compare only user-visible semantics with GitKraken: deleted lines stay visible next to additions and Pop keeps a failed stash.

Node host tests passed 11/11. WKWebView smoke passed replacement, pure deletion, red contrast in both themes, three-digit old/new columns, and 12,000-line reuse. The running InspectorPreview also displayed a red removed package.json build line beside a green added line without overlapping numbers.
