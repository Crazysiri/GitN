# RFC: Monaco Local Edit Echo

- Status: Accepted for implementation
- Owner: GitN
- Date: 2026-11-06

## Design

Keep the last submitted host payload and the path/content of the most recent editor callback. Compare the next payload's mode, path, theme, editor flags and diff metadata against the last payload, ignoring only the edited text field. Skip the bridge round-trip only when the content equals that callback and all other fields match. Otherwise forward the payload. In the host, avoid `setValue` if the model already contains the incoming text so metadata updates do not reset undo or cursor state.

The callback remains a full-text update in this batch. Streaming text deltas and bounded document-model caching require separate performance measurement and design.
Debug bridge traffic defaults off. Native logging uses `GITN_MONACO_DEBUG=1`; host diagnostics use `window.gitnMonacoDebug = true` when explicitly investigating the embedded page. Error events remain unconditional.
