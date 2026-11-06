import AppKit
import SwiftUI
import WebKit

/// Mounts the active xterm session's retained WKWebView into the panel. The
/// WebView (and its xterm buffer + PTY) is owned by the `XtermSession` in the
/// store, so detaching here on hide/switch does not destroy the session —
/// mirroring how `TerminalSessionHost` re-parents a retained SwiftTerm view.
struct XtermHostView: NSViewRepresentable {
    let session: XtermSession
    let isDark: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let webView = session.webView
        session.setTheme(isDark: isDark)

        for view in nsView.subviews where view !== webView {
            view.removeFromSuperview()
        }
        if webView.superview !== nsView {
            webView.removeFromSuperview()
            webView.frame = nsView.bounds
            webView.autoresizingMask = [.width, .height]
            nsView.addSubview(webView)
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView, webView.superview === nsView else { return }
                nsView.window?.makeFirstResponder(webView)
                session.focus()
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // Only detach; the session (and its WebView) stays alive in the store.
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }
}
