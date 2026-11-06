import AppKit
import Foundation
import WebKit

/// One xterm.js terminal session: a retained WKWebView (holding the live xterm
/// buffer in JS) bound to its own `XtermPTYTransport`. The store retains these
/// so hiding the panel or switching repo tabs never tears down the PTY or the
/// scrollback — only the active session's view is mounted into the panel.
@MainActor
final class XtermSession {
    let id: UUID
    let transport: XtermPTYTransport
    let webView: WKWebView
    private let bridge: XtermBridge

    /// Forwarded to the store so the session tab can show the OSC title.
    var onTitle: ((String) -> Void)? {
        get { bridge.onTitle }
        set { bridge.onTitle = newValue }
    }
    /// Forwarded to the store when the shell exits / PTY closes.
    var onExit: (() -> Void)? {
        get { bridge.onExit }
        set { bridge.onExit = newValue }
    }

    /// Supplies the live cwd (from the context observer) for suggestions.
    var currentCwd: (() -> String?)? {
        get { bridge.currentCwd }
        set { bridge.currentCwd = newValue }
    }

    /// Invoked when the context menu's "Close Terminal" is chosen.
    var onRequestClose: (() -> Void)?

    init(id: UUID, repoPath: String, shellPath: String?, isDark: Bool) {
        self.id = id
        self.transport = XtermPTYTransport(
            repoPath: repoPath,
            shellPath: shellPath,
            promptIntegration: true
        )

        let bridge = XtermBridge(sessionID: id, transport: transport, isDark: isDark)
        self.bridge = bridge

        let controller = WKUserContentController()
        controller.add(bridge, name: "gitnTerminal")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = XtermWebView(frame: .zero, configuration: configuration)
        // Opaque so the JS-painted theme background fills the whole view,
        // including any partial row below the last line (no dark gap strip).
        webView.setValue(true, forKey: "drawsBackground")
        webView.navigationDelegate = bridge
        self.webView = webView
        bridge.webView = webView

        webView.onCopy = { [weak bridge] in bridge?.copySelection() }
        webView.onPaste = { [weak bridge] text in bridge?.paste(text) }
        webView.onSelectAll = { [weak bridge] in bridge?.selectAll() }
        webView.onClear = { [weak bridge] in bridge?.clear() }
        webView.onClose = { [weak self] in self?.onRequestClose?() }
        webView.onDropPaths = { [weak bridge] paths in bridge?.pasteDroppedPaths(paths) }

        if let resourceURL = GitNResources.xtermDirectoryURL,
           let indexURL = GitNResources.xtermIndexURL {
            webView.loadFileURL(indexURL, allowingReadAccessTo: resourceURL)
        } else {
            print("[Xterm] terminal resources not found")
        }
    }

    func setTheme(isDark: Bool) {
        bridge.updateTheme(isDark)
    }

    func focus() {
        bridge.focusTerminal()
    }

    func terminate() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "gitnTerminal")
        webView.navigationDelegate = nil
        transport.terminate()
    }
}
