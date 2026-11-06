# RFC: Native-backed Monaco worker loading

WKWebView cannot start the generated Monaco workers at `./editor.worker.js` and `./json.worker.js` from its `file://` page. `fetch()` also fails for those local resources. Keep the plugin-generated worker bundles as separate app resources. Override `MonacoEnvironment.getWorker` in the Monaco entry: map labels to one of five bundled worker filenames, request the source using a WebKit message handler with a reply, then construct a Blob URL and a Worker. Cache Blob URLs by filename for the page lifetime and revoke them on pagehide. A normal web development page without the native handler may use relative worker URLs.

The native coordinator checks the requested filename against a fixed allowlist, reads only from `GitNResources.monacoDirectoryURL`, and returns source text or an error. Its role is resource transport, not editor policy. Worker lookup is lazy, so the 6 MB TypeScript worker does not inflate the initial app.js parse cost.

Tests cover routing, reuse and error handling plus the actual WKWebView launch of editor and JSON workers, with the existing diff and large-file smoke assertions.
