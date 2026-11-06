import AppKit
import Foundation
import WebKit

/// Bridges one xterm.js page to its PTY transport. Owned by an `XtermSession`
/// (not by a SwiftUI view) so it outlives panel hide/show and tab switches.
///
/// JS→Swift arrives on the `gitnTerminal` message handler as `{event, ...}`.
/// Swift→JS is imperative `window.gitnXterm.*` via evaluateJavaScript. PTY
/// bytes cross as base64 so byte boundaries (and multi-byte UTF-8) stay intact.
@MainActor
final class XtermBridge: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let transport: XtermPTYTransport
    private var isDark: Bool
    weak var webView: WKWebView?

    var onTitle: ((String) -> Void)?
    var onExit: (() -> Void)?
    var onPrompt: ((Int) -> Void)?

    /// Supplies the session's current working directory for suggestions.
    /// Returns nil when context is not trustworthy (suggestions then skip
    /// dynamic, cwd-dependent data).
    var currentCwd: (() -> String?)?

    private let sessionID: UUID
    private let suggestionService = SuggestionService()
    private var promptGeneration = 0
    private var suggestionsEnabled = true

    private var isNavigationFinished = false
    private var isHostReady = false
    private var didStart = false

    init(sessionID: UUID, transport: XtermPTYTransport, isDark: Bool) {
        self.sessionID = sessionID
        self.transport = transport
        self.isDark = isDark
        super.init()

        transport.onOutput = { [weak self] data in
            self?.writeToTerminal(data)
        }
        transport.onExit = { [weak self] in
            self?.onExit?()
        }
        suggestionService.onResult = { [weak self] result in
            self?.pushSuggestions(result)
        }
    }

    // MARK: - Suggestions

    private func handleSuggestRequest(_ body: [String: Any]) {
        guard suggestionsEnabled else { return }
        guard let line = body["line"] as? String,
              let cursor = body["cursor"] as? Int,
              let inputRevision = body["inputRevision"] as? Int else { return }
        let promptGen = body["promptGeneration"] as? Int ?? promptGeneration
        let cwd = currentCwd?() ?? transport.launchCwd
        let request = SuggestionRequest(
            sessionID: sessionID,
            cwd: cwd,
            line: line,
            cursor: cursor,
            promptGeneration: promptGen,
            inputRevision: inputRevision
        )
        suggestionService.request(request)
    }

    private func pushSuggestions(_ result: SuggestionService.Result) {
        guard let webView else { return }
        // prefixLength = how many chars of the active token are already typed,
        // so the frontend can delete them before inserting.
        let prefixLength: Int = {
            guard let range = result.replacementRange else { return 0 }
            return max(0, range.upperBound - range.lowerBound)
        }()
        let payload: [String: Any] = [
            "inputRevision": result.request.inputRevision,
            "prefixLength": prefixLength,
            "suggestions": result.suggestions.map { s -> [String: Any] in
                var dict: [String: Any] = [
                    "displayName": s.displayName,
                    "insertText": s.insertText,
                ]
                if let detail = s.detail { dict["detail"] = detail }
                return dict
            },
        ]
        let json = Self.jsonString(payload)
        webView.evaluateJavaScript(
            "window.gitnXterm && window.gitnXterm.showSuggestions(\(Self.jsLiteral(json)));",
            completionHandler: nil
        )
    }

    // MARK: - Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isNavigationFinished = true
        startIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[Xterm] navigation failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        print("[Xterm] provisional navigation failed: \(error.localizedDescription)")
    }

    // MARK: - JS → Swift

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "gitnTerminal",
              let body = message.body as? [String: Any],
              let event = body["event"] as? String
        else { return }

        switch event {
        case "ready":
            isHostReady = true
            startIfReady()

        case "input":
            if let base64 = body["bytes"] as? String,
               let data = Data(base64Encoded: base64) {
                transport.write(data)
            }

        case "resize":
            if let cols = body["cols"] as? Int, let rows = body["rows"] as? Int {
                transport.resize(cols: UInt16(clamping: cols), rows: UInt16(clamping: rows))
            }

        case "openLink":
            if let uriString = body["uri"] as? String,
               let url = URL(string: uriString),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
            }

        case "title":
            if let title = body["title"] as? String { onTitle?(title) }

        case "prompt":
            if let generation = body["generation"] as? Int {
                promptGeneration = generation
                onPrompt?(generation)
            }

        case "suggestRequest":
            handleSuggestRequest(body)

        case "error":
            let msg = body["message"] as? String ?? "unknown"
            let detail = body["detail"] as? String ?? ""
            print("[Xterm] host error: \(msg) \(detail)")

        case "debug":
            #if DEBUG
            print("[XtermDebug] \(body["message"] as? String ?? "") \(body["detail"] as? String ?? "")")
            #endif

        default:
            break
        }
    }

    // MARK: - Lifecycle

    private func startIfReady() {
        guard isNavigationFinished, isHostReady, !didStart, let webView else { return }
        didStart = true

        let settings = TerminalSettings.load()
        suggestionsEnabled = settings.suggestionsEnabled
        var options = settings.startOptionsDictionary
        options["isDark"] = isDark
        let optionsJSON = Self.jsonString(options)
        webView.evaluateJavaScript(
            "window.gitnXterm && window.gitnXterm.start(\(Self.jsLiteral(optionsJSON)));",
            completionHandler: nil
        )

        if !transport.isRunning {
            transport.start(cols: 80, rows: 24)
        }
    }

    private func writeToTerminal(_ data: Data) {
        guard isHostReady, let webView else { return }
        let base64 = data.base64EncodedString()
        webView.evaluateJavaScript(
            "window.gitnXterm && window.gitnXterm.write(\(Self.jsLiteral(base64)));",
            completionHandler: nil
        )
    }

    func updateTheme(_ newValue: Bool) {
        guard newValue != isDark else { return }
        isDark = newValue
        webView?.evaluateJavaScript(
            "window.gitnXterm && window.gitnXterm.setTheme(\(newValue ? "true" : "false"));",
            completionHandler: nil
        )
    }

    func focusTerminal() {
        webView?.evaluateJavaScript("window.gitnXterm && window.gitnXterm.focus();", completionHandler: nil)
        // Also fit in case the view was resized while detached.
        webView?.evaluateJavaScript("window.gitnXterm && window.gitnXterm.fit();", completionHandler: nil)
    }

    // MARK: - Context-menu actions

    /// Copy the current selection to the system pasteboard.
    func copySelection() {
        webView?.evaluateJavaScript("window.gitnXterm ? window.gitnXterm.getSelection() : ''") { value, _ in
            guard let text = value as? String, !text.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    func paste(_ text: String) {
        let json = Self.jsLiteral(text)
        webView?.evaluateJavaScript("window.gitnXterm && window.gitnXterm.paste(\(json));", completionHandler: nil)
    }

    /// Paste shell-escaped dropped file paths (space-joined, trailing space).
    /// Never executes; relies on the shell's paste handling.
    func pasteDroppedPaths(_ paths: [String]) {
        let escaped = paths.filter { !$0.isEmpty }.map(ShellWordEscaping.escape)
        guard !escaped.isEmpty else { return }
        paste(escaped.joined(separator: " ") + " ")
    }

    func selectAll() {
        webView?.evaluateJavaScript("window.gitnXterm && window.gitnXterm.selectAll();", completionHandler: nil)
    }

    func clear() {
        webView?.evaluateJavaScript("window.gitnXterm && window.gitnXterm.clear();", completionHandler: nil)
    }

    // MARK: - JS encoding

    private static func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func jsLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let array = String(data: data, encoding: .utf8) {
            return String(array.dropFirst().dropLast())
        }
        return "\"\""
    }
}
