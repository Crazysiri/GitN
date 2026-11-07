import SwiftUI
import WebKit

struct MonacoPreviewPayload: Encodable, Equatable {
    let path: String
    let language: String
    let content: String
    let isEditable: Bool
}

struct MonacoDiffHunkControlPayload: Encodable, Equatable {
    let row: Int
    let hunkIndex: Int
    let lineIDs: [Int]
    let tooltip: String?
    let anchorKind: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let oldStartLine: Int?
    let oldEndLine: Int?
    let newStartLine: Int?
    let newEndLine: Int?
    let hasDeletionLines: Bool
}

struct MonacoLineBlamePayload: Encodable, Equatable {
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let tooltip: String
}

struct MonacoDiffPayload: Encodable, Equatable, Identifiable {
    let path: String
    let language: String
    let originalText: String
    let modifiedText: String
    let isEditable: Bool
    let primaryHunkAction: String?
    let showsDiscardAction: Bool
    let hunkControls: [MonacoDiffHunkControlPayload]
    let lineBlames: [MonacoLineBlamePayload]

    var id: String { path }
}

enum DiffDisplayMode: String, CaseIterable {
    case inline, hunk, split

    var title: String { rawValue.capitalized }
}

struct MonacoHostPayload: Encodable, Equatable {
    let mode: String
    let isDark: Bool
    let preview: MonacoPreviewPayload?
    let items: [MonacoDiffPayload]
    var sourceID: String = ""
    var conflict: MonacoConflictPayload? = nil
    var diffDisplay: String = "inline"
}

struct MonacoLocalEdit: Equatable {
    let path: String
    let content: String
}

enum MonacoLocalEditEchoPolicy {
    static func isEcho(
        _ next: MonacoHostPayload,
        after edit: MonacoLocalEdit,
        comparedTo previous: MonacoHostPayload?
    ) -> Bool {
        guard let previous, next.mode == previous.mode else { return false }
        switch previous.mode {
        case "preview":
            guard let preview = previous.preview, preview.path == edit.path else { return false }
            let editedPreview = MonacoPreviewPayload(
                path: preview.path, language: preview.language, content: edit.content,
                isEditable: preview.isEditable
            )
            return next == MonacoHostPayload(
                mode: previous.mode, isDark: previous.isDark,
                preview: editedPreview, items: previous.items, sourceID: previous.sourceID,
                diffDisplay: previous.diffDisplay
            )
        case "diff":
            guard previous.items.filter({ $0.path == edit.path }).count == 1 else { return false }
            let editedItems = previous.items.map { item in
                guard item.path == edit.path else { return item }
                return MonacoDiffPayload(
                    path: item.path, language: item.language, originalText: item.originalText,
                    modifiedText: edit.content, isEditable: item.isEditable,
                    primaryHunkAction: item.primaryHunkAction,
                    showsDiscardAction: item.showsDiscardAction,
                    hunkControls: item.hunkControls, lineBlames: item.lineBlames
                )
            }
            return next == MonacoHostPayload(
                mode: previous.mode, isDark: previous.isDark,
                preview: previous.preview, items: editedItems, sourceID: previous.sourceID,
                diffDisplay: previous.diffDisplay
            )
        default:
            return false
        }
    }
}

final class MonacoCommandBridge {
    weak var webView: WKWebView?

    func navigateDiff(next: Bool) {
        let direction = next ? "next" : "prev"
        let js = "window.gitnMonaco && window.gitnMonaco.navigateDiff('\(direction)');"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

struct MonacoInspectorView: NSViewRepresentable {
    let mode: RepoViewModel.FileInspectorMode
    let isDark: Bool
    let preview: MonacoPreviewPayload?
    let items: [MonacoDiffPayload]
    let commandBridge: MonacoCommandBridge?
    let onContentChange: (String, String) -> Void
    let onHunkAction: ((String, Int, [Int], String) -> Void)?
    let onSaveRequest: (() -> Void)?
    var sourceIdentity: String = ""
    var conflict: MonacoConflictPayload? = nil
    var diffDisplay: String = "inline"

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onContentChange: onContentChange,
            onHunkAction: onHunkAction,
            onSaveRequest: onSaveRequest
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "monaco")
        controller.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "monacoWorker")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        commandBridge?.webView = webView

        if let resourceURL = GitNResources.monacoDirectoryURL,
           let indexURL = GitNResources.monacoIndexURL {
            webView.loadFileURL(indexURL, allowingReadAccessTo: resourceURL)
        } else {
            print("[Monaco] editor resources not found")
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onContentChange = onContentChange
        context.coordinator.onHunkAction = onHunkAction
        context.coordinator.onSaveRequest = onSaveRequest
        context.coordinator.pendingPayload = hostPayload
        context.coordinator.flushPayloadIfReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "monaco")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "monacoWorker", contentWorld: .page)
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    private var hostPayload: MonacoHostPayload {
        MonacoHostPayload(
            mode: conflict == nil ? mode.rawValue : "conflict",
            isDark: isDark,
            preview: preview,
            items: items,
            sourceID: sourceIdentity,
            conflict: conflict,
            diffDisplay: diffDisplay
        )
    }
}

extension MonacoInspectorView {
    private static let isDebugEnabled = ProcessInfo.processInfo.environment["GITN_MONACO_DEBUG"] == "1"

    private static func emitDebugLog(_ message: @autoclosure () -> String) {
        guard isDebugEnabled else { return }
        print("[MonacoBridge] \(message())")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
        private static let workerFiles: Set<String> = [
            "editor.worker.js", "json.worker.js", "css.worker.js",
            "html.worker.js", "ts.worker.js"
        ]
        var onContentChange: (String, String) -> Void
        var onHunkAction: ((String, Int, [Int], String) -> Void)?
        var onSaveRequest: (() -> Void)?
        weak var webView: WKWebView?
        var pendingPayload: MonacoHostPayload?

        private var isNavigationFinished = false
        private var isHostReady = false
        private var acknowledgedConflictEdit = 0
        private var conflictSourceID = ""
        private var pendingLocalEdit: MonacoLocalEdit?
        private var lastHostPayload: MonacoHostPayload?
        private var lastPayloadData: Data?

        init(
            onContentChange: @escaping (String, String) -> Void,
            onHunkAction: ((String, Int, [Int], String) -> Void)?,
            onSaveRequest: (() -> Void)?
        ) {
            self.onContentChange = onContentChange
            self.onHunkAction = onHunkAction
            self.onSaveRequest = onSaveRequest
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isNavigationFinished = true
            flushPayloadIfReady()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            print("[Monaco] navigation failed: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            print("[Monaco] provisional navigation failed: \(error.localizedDescription)")
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "monaco",
                  let body = message.body as? [String: Any],
                  let event = body["event"] as? String
            else { return }

            if pendingPayload?.mode == "conflict", event != "ready", event != "error", event != "debug" {
                guard let source = body["sourceID"] as? String, source == pendingPayload?.sourceID else { return }
                if conflictSourceID != source { conflictSourceID = source; acknowledgedConflictEdit = 0 }
            }

            if event == "contentChanged",
               let path = body["path"] as? String,
               let encodedContent = body["content"] as? String,
               let data = Data(base64Encoded: encodedContent),
               let content = String(data: data, encoding: .utf8) {
                if pendingPayload?.mode == "conflict", let revision = body["editRevision"] as? Int {
                    acknowledgedConflictEdit = max(acknowledgedConflictEdit, revision)
                }
                pendingLocalEdit = MonacoLocalEdit(path: path, content: content)
                onContentChange(path, content)
                return
            }

            if event == "hunkAction",
               let path = body["path"] as? String,
               let action = body["action"] as? String,
               let hunkIndex = body["hunkIndex"] as? Int {
                onHunkAction?(path, hunkIndex, body["lineIDs"] as? [Int] ?? [], action)
                return
            }

            if event == "saveRequest" {
                onSaveRequest?()
                return
            }

            if event == "ready" {
                isHostReady = true
                flushPayloadIfReady()
                return
            }

            if event == "error" {
                let message = body["message"] as? String ?? "Unknown Monaco host error"
                let detail = body["detail"] as? String ?? ""
                if detail.isEmpty {
                    print("[Monaco] host error: \(message)")
                } else {
                    print("[Monaco] host error: \(message)\n\(detail)")
                }
                return
            }

            if event == "debug" {
                guard MonacoInspectorView.isDebugEnabled else { return }
                let message = body["message"] as? String ?? "Unknown Monaco debug log"
                let detail = body["detail"] as? String ?? ""
                if detail.isEmpty {
                    print("[MonacoDebug] \(message)")
                } else {
                    print("[MonacoDebug] \(message) \(detail)")
                }
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage,
            replyHandler: @escaping (Any?, String?) -> Void
        ) {
            guard message.name == "monacoWorker",
                  let request = message.body as? [String: Any],
                  let filename = request["filename"] as? String,
                  Self.workerFiles.contains(filename),
                  let directory = GitNResources.monacoDirectoryURL else {
                replyHandler(nil, "Invalid Monaco worker request")
                return
            }
            do {
                let source = try String(contentsOf: directory.appendingPathComponent(filename), encoding: .utf8)
                replyHandler(source, nil)
            } catch {
                replyHandler(nil, "Monaco worker resource unavailable: \(filename)")
            }
        }

        func flushPayloadIfReady() {
            guard isNavigationFinished,
                  isHostReady,
                  let webView,
                  var payload = pendingPayload
            else { return }
            if payload.conflict != nil {
                if conflictSourceID != payload.sourceID { conflictSourceID = payload.sourceID; acknowledgedConflictEdit = 0 }
                payload.conflict?.acknowledgedEdit = acknowledgedConflictEdit
            }
            guard let data = try? JSONEncoder().encode(payload) else { return }

            let mode = payload.mode
            let previewPath = payload.preview?.path ?? ""
            let diffPath = payload.items.first?.path ?? ""
            MonacoInspectorView.emitDebugLog(
                "flushPayloadIfReady mode=\(mode) previewPath=\(previewPath) diffPath=\(diffPath) pendingLocalEdit=\(pendingLocalEdit != nil) samePayload=\(data == lastPayloadData)"
            )

            if let edit = pendingLocalEdit,
               MonacoLocalEditEchoPolicy.isEcho(payload, after: edit, comparedTo: lastHostPayload) {
                pendingLocalEdit = nil
                lastHostPayload = payload
                lastPayloadData = data
                MonacoInspectorView.emitDebugLog(
                    "flushPayloadIfReady skippedLocalEcho mode=\(mode) previewPath=\(previewPath) diffPath=\(diffPath)"
                )
                return
            }

            guard data != lastPayloadData else {
                MonacoInspectorView.emitDebugLog(
                    "flushPayloadIfReady skippedSamePayload mode=\(mode) previewPath=\(previewPath) diffPath=\(diffPath)"
                )
                return
            }
            pendingLocalEdit = nil
            lastHostPayload = payload
            lastPayloadData = data
            let encodedPayload = data.base64EncodedString()
            let script = "window.gitnMonaco && window.gitnMonaco.loadPayload('\(encodedPayload)');"
            MonacoInspectorView.emitDebugLog(
                "flushPayloadIfReady evaluateJS mode=\(mode) previewPath=\(previewPath) diffPath=\(diffPath)"
            )
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
