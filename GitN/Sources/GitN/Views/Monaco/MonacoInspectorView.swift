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

struct MonacoHostPayload: Encodable, Equatable {
    let mode: String
    let isDark: Bool
    let preview: MonacoPreviewPayload?
    let items: [MonacoDiffPayload]
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
    let onHunkAction: ((String, Int, String) -> Void)?
    let onSaveRequest: (() -> Void)?

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

    private var hostPayload: MonacoHostPayload {
        MonacoHostPayload(
            mode: mode.rawValue,
            isDark: isDark,
            preview: preview,
            items: items
        )
    }
}

extension MonacoInspectorView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onContentChange: (String, String) -> Void
        var onHunkAction: ((String, Int, String) -> Void)?
        var onSaveRequest: (() -> Void)?
        weak var webView: WKWebView?
        var pendingPayload: MonacoHostPayload?

        private var isNavigationFinished = false
        private var isHostReady = false
        private var isApplyingLocalEdit = false
        private var lastPayloadData: Data?

        init(
            onContentChange: @escaping (String, String) -> Void,
            onHunkAction: ((String, Int, String) -> Void)?,
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

            if event == "contentChanged",
               let path = body["path"] as? String,
               let encodedContent = body["content"] as? String,
               let data = Data(base64Encoded: encodedContent),
               let content = String(data: data, encoding: .utf8) {
                isApplyingLocalEdit = true
                onContentChange(path, content)
                return
            }

            if event == "hunkAction",
               let path = body["path"] as? String,
               let action = body["action"] as? String,
               let hunkIndex = body["hunkIndex"] as? Int {
                onHunkAction?(path, hunkIndex, action)
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
                let message = body["message"] as? String ?? "Unknown Monaco debug log"
                let detail = body["detail"] as? String ?? ""
                if detail.isEmpty {
                    print("[MonacoDebug] \(message)")
                } else {
                    print("[MonacoDebug] \(message) \(detail)")
                }
            }
        }

        func flushPayloadIfReady() {
            guard isNavigationFinished,
                  isHostReady,
                  let webView,
                  let payload = pendingPayload,
                  let data = try? JSONEncoder().encode(payload)
            else { return }

            if isApplyingLocalEdit {
                isApplyingLocalEdit = false
                lastPayloadData = data
                return
            }

            guard data != lastPayloadData else { return }
            lastPayloadData = data
            let encodedPayload = data.base64EncodedString()
            let script = "window.gitnMonaco && window.gitnMonaco.loadPayload('\(encodedPayload)');"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
