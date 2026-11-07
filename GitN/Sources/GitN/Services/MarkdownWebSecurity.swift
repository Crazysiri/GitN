import Foundation
import WebKit

enum MarkdownWebSecurity {
    static func contentSecurityPolicy(nonce: String) -> String {
        "default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'"
    }

    private static let bundledRuntime: String? = {
        guard let directory = GitNResources.markdownPreviewDirectoryURL else { return nil }
        return try? String(contentsOf: directory.appendingPathComponent("mermaid.min.js"), encoding: .utf8)
    }()

    /// Native injection avoids file:// origin ambiguities without granting arbitrary file scripts.
    static func installBundledRuntime(on controller: WKUserContentController) {
        guard let bundledRuntime else { return }
        controller.addUserScript(WKUserScript(source: bundledRuntime, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    static func javaScriptLiteral(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        // JSON escaping alone is not an HTML script-element escaping boundary.
        return String(json.dropFirst().dropLast())
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    static func allowsNavigation(to url: URL?, isInitialLoad: Bool, resourceDirectory: URL?) -> Bool {
        guard isInitialLoad, let url else { return false }
        if url.absoluteString == "about:blank" { return true }
        guard url.isFileURL, let resourceDirectory else { return false }
        return url.standardizedFileURL == resourceDirectory.standardizedFileURL
    }
}
