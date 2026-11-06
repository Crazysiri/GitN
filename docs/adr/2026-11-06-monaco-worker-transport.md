# ADR: Transport Monaco workers through a native asset bridge

- Status: Accepted
- Date: 2026-11-06

Monaco's webpack plugin emits separate editor/language worker files. WKWebView loads the host from `file://`, where both direct Worker construction and page `fetch()` of those files fail. The app therefore exposes only five known worker assets through a reply-capable WebKit handler; JavaScript launches their source as Blob workers on demand. The already embedded diff worker remains independent. This preserves background language services while keeping large worker bundles out of initial page parsing.

The bridge never accepts a path or URL from the page: only exact allowlisted filenames. Blob URLs live no longer than the page. A future switch to an HTTP or custom-scheme origin may revisit this transport.
