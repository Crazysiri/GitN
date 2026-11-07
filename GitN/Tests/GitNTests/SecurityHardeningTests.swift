import Foundation
import XCTest
import WebKit
@testable import GitN

@MainActor
final class HostedCredentialStoreTests: XCTestCase {
    private final class Backend: CredentialBackend {
        var values: [String: String] = [:]
        var fail = false
        struct Unavailable: Error {}
        func read(account: String) throws -> String? {
            if fail { throw Unavailable() }; return values[account]
        }
        func write(_ value: String, account: String) throws {
            if fail { throw Unavailable() }; values[account] = value
        }
        func delete(account: String) throws {
            if fail { throw Unavailable() }; values[account] = nil
        }
    }

    func testCredentialCRUDNeverStoresPlaintextPreferences() throws {
        let suite = "GitN.SecurityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("obsolete", forKey: "GitN.githubToken")
        let backend = Backend()
        let store = HostedCredentialStore(backend: backend, defaults: defaults)
        XCTAssertEqual(store.token(for: .github), "") // No legacy migration requested.
        XCTAssertNil(defaults.object(forKey: "GitN.githubToken"))
        try store.save("test-github-value", for: .github)
        try store.save("test-gitlab-value", for: .gitlab)
        XCTAssertEqual(store.token(for: .github), "test-github-value")
        XCTAssertEqual(store.token(for: .gitlab), "test-gitlab-value")
        XCTAssertNil(defaults.object(forKey: "GitN.githubToken"))
        XCTAssertNil(defaults.object(forKey: "GitN.gitlabToken"))
        try store.save("", for: .github)
        XCTAssertEqual(store.token(for: .github), "")
        XCTAssertEqual(store.token(for: .gitlab), "test-gitlab-value")
    }

    func testFailuresAreVisibleAndNeverOverwriteExistingCredential() throws {
        let suite = "GitN.SecurityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = Backend()
        let store = HostedCredentialStore(backend: backend, defaults: defaults)
        try store.save("existing", for: .github)
        backend.fail = true
        XCTAssertThrowsError(try store.save("new", for: .github))
        XCTAssertThrowsError(try store.save("", for: .github))
        XCTAssertEqual(backend.values["github"], "existing")
        XCTAssertEqual(store.token(for: .github), "")
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasSuffix("Token") })
        backend.fail = false
        try store.save("replacement", for: .github)
        XCTAssertNil(store.errorMessage)
    }
}

final class SSHHostKeyServiceTests: XCTestCase {
    private let encoded = "AAAAC3NzaC1lZDI1NTE5AAAAIAcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcH"

    func testHostValidationRejectsOptionsAndShellTextAndPreservesPorts() throws {
        for host in ["-f", "host\nother", "host;touch", "user@host", "unknown host", "", "a..b", "[host]:0", "[host]:65536"] {
            XCTAssertThrowsError(try SSHHostKeyService.Endpoint(host), host)
        }
        XCTAssertEqual(try SSHHostKeyService.Endpoint("example.com").knownHostsName, "example.com")
        XCTAssertEqual(try SSHHostKeyService.Endpoint("[example.com]:2222").knownHostsName, "[example.com]:2222")
        XCTAssertEqual(try SSHHostKeyService.Endpoint("[::1]:2222").host, "::1")
    }

    func testWireKeyParsingHasStableOpenSSHFingerprintAndRejectsUnexpectedData() throws {
        let endpoint = try SSHHostKeyService.Endpoint("example.com")
        let line = "example.com ssh-ed25519 \(encoded)"
        let candidate = try SSHHostKeyService.parse("# banner\n\(line)\n\(line)\n", endpoint: endpoint)
        XCTAssertEqual(candidate.keys.count, 1)
        XCTAssertEqual(candidate.keys[0].fingerprint, "SHA256:gNSIRW+2Iyiuvsdp/bgjy38bvWHw6wQm3tuoXrl3WjQ")
        for bad in ["", "other.com ssh-ed25519 \(encoded)", "example.com ssh-rsa \(encoded)",
                    "example.com ssh-ed25519 YWJj", line + " injected", "example.com ssh-ed25519 " + encoded + "AAAA"] {
            XCTAssertThrowsError(try SSHHostKeyService.parse(bad, endpoint: endpoint))
        }
    }

    func testTrustWritesExactlyReviewedKeyAndRestrictsPermissions() throws {
        try withDirectory { directory in
            let candidate = try SSHHostKeyService.parse("example.com ssh-ed25519 \(encoded)", endpoint: .init("example.com"))
            try SSHHostKeyService.trust(candidate, directory: directory)
            let file = directory.appendingPathComponent("known_hosts")
            XCTAssertEqual(try String(contentsOf: file), "\nexample.com ssh-ed25519 \(encoded)\n")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertThrowsError(try SSHHostKeyService.trust(candidate, directory: directory))
        }
    }

    func testTrustRejectsSymlinkAndExistingHashedHost() throws {
        try withDirectory { directory in
            let candidate = try SSHHostKeyService.parse("example.com ssh-ed25519 \(encoded)", endpoint: .init("example.com"))
            let target = directory.appendingPathComponent("target")
            try "untouched".write(to: target, atomically: true, encoding: .utf8)
            let file = directory.appendingPathComponent("known_hosts")
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            XCTAssertThrowsError(try SSHHostKeyService.trust(candidate, directory: directory))
            XCTAssertEqual(try String(contentsOf: target), "untouched")
            try FileManager.default.removeItem(at: file)
            let hash = "|1|AAECAwQFBgcICQoLDA0ODxAREhM=|nnUK16ANsXd3hL31YfAkGOluSjU="
            try "\(hash) ssh-ed25519 \(encoded)\n".write(to: file, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try SSHHostKeyService.trust(candidate, directory: directory))
            XCTAssertTrue(SSHHostKeyService.matchesHost(hash, host: "example.com"))
            XCTAssertFalse(SSHHostKeyService.matchesHost(hash, host: "other.com"))
        }
    }

    func testChangedKeysAreNeverOfferedFirstUseTrust() {
        XCTAssertTrue(SSHHostKeyService.mayOfferTrust(error: "Host key verification failed."))
        XCTAssertFalse(SSHHostKeyService.mayOfferTrust(error: "REMOTE HOST IDENTIFICATION HAS CHANGED! Host key verification failed."))
        XCTAssertFalse(SSHHostKeyService.mayOfferTrust(error: "Offending ED25519 host key in known_hosts"))
        XCTAssertTrue(SSHHostKeyService.matchesHost("[host]:2222", host: "[host]:2222"))
        XCTAssertFalse(SSHHostKeyService.matchesHost("*.example.com,!bad.example.com", host: "bad.example.com"))
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

final class MarkdownWebSecurityTests: XCTestCase {
    @MainActor
    func testStrictRendererStillRendersBundledMermaidInWebKit() async throws {
        let directory = try XCTUnwrap(GitNResources.markdownPreviewDirectoryURL)
        let coordinator = MermaidDiagramWebView.Coordinator()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(coordinator, name: "mermaid")
        MarkdownWebSecurity.installBundledRuntime(on: configuration.userContentController)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = coordinator
        coordinator.webView = webView
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "mermaid") }
        webView.loadHTMLString(MermaidHTMLRenderer.document(source: "graph TD; A[Start]-->B[End]",
            isDark: false, displayMode: .inline, reportsContentHeight: false), baseURL: directory)
        for _ in 0..<200 {
            if let rendered = try? await webView.evaluateJavaScript("Boolean(document.querySelector('#diagram svg'))"),
               rendered as? Bool == true {
                let injected = try await webView.evaluateJavaScript("const s=document.createElement('script'); s.textContent='window.untrustedScriptRan=true'; document.body.appendChild(s); Boolean(window.untrustedScriptRan)")
                XCTAssertEqual(injected as? Bool, false, "CSP must reject scripts without the document nonce")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let diagnostics = try? await webView.evaluateJavaScript("JSON.stringify({url: location.href, mermaid: typeof mermaid, error: document.getElementById('error')?.textContent})")
        XCTFail("Bundled Mermaid failed under strict policy: \(String(describing: diagnostics))")
    }

    func testInlineScriptLiteralCannotCloseScriptAndRoundTripsContent() throws {
        let payload = "</script><script>alert('test')</script>\u{2028}\u{2029}\n\\\""
        let encoded = MarkdownWebSecurity.javaScriptLiteral(payload)
        XCTAssertFalse(encoded.contains("<"))
        let decoded = try JSONSerialization.jsonObject(with: Data("[\(encoded)]".utf8)) as? [String]
        XCTAssertEqual(decoded, [payload])
    }

    func testRendererRestrictsResourcesAndUsesStrictMermaid() {
        let html = MermaidHTMLRenderer.document(source: "graph TD; A-->B", isDark: false,
            displayMode: .inline, reportsContentHeight: false)
        XCTAssertTrue(html.contains("securityLevel: \"strict\""))
        XCTAssertTrue(html.contains("script-src 'nonce-"))
        XCTAssertFalse(html.contains("<script src="))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("frame-src 'none'"))
        let first = MermaidHTMLRenderer.document(source: "graph TD; A-->B", isDark: false,
            displayMode: .inline, reportsContentHeight: false, scriptNonce: "stable-document-nonce")
        let second = MermaidHTMLRenderer.document(source: "graph TD; A-->B", isDark: false,
            displayMode: .inline, reportsContentHeight: false, scriptNonce: "stable-document-nonce")
        XCTAssertEqual(first, second, "Layout updates must not reload an unchanged document")
    }

    func testNavigationOnlyPermitsBootstrapDocument() {
        let directory = URL(fileURLWithPath: "/tmp/resources/")
        XCTAssertTrue(MarkdownWebSecurity.allowsNavigation(to: directory, isInitialLoad: true, resourceDirectory: directory))
        for url in [URL(string: "https://example.com")!, URL(string: "javascript:alert(1)")!, URL(fileURLWithPath: "/etc/passwd")] {
            XCTAssertFalse(MarkdownWebSecurity.allowsNavigation(to: url, isInitialLoad: true, resourceDirectory: directory))
        }
        XCTAssertFalse(MarkdownWebSecurity.allowsNavigation(to: directory, isInitialLoad: false, resourceDirectory: directory))
    }
}

final class AICommitSecurityTests: XCTestCase {
    func testGenerationPolicyCannotInheritWritableConfigAndPromptIsNotAnArgument() {
        let directory = URL(fileURLWithPath: "/tmp/private-ai")
        let args = AICommitService.generationArguments(directory: directory, output: directory.appendingPathComponent("message"))
        XCTAssertEqual(Array(args.prefix(3)), ["--ask-for-approval", "never", "exec"])
        XCTAssertTrue(args.contains("--ignore-user-config"))
        XCTAssertTrue(args.contains("--ignore-rules"))
        XCTAssertTrue(args.contains("shell_tool"))
        XCTAssertTrue(args.contains("multi_agent"))
        XCTAssertEqual(args[args.firstIndex(of: "--sandbox")! + 1], "read-only")
        XCTAssertEqual(args[args.firstIndex(of: "--cd")! + 1], directory.path)
        XCTAssertEqual(args.last, "-")
        XCTAssertFalse(args.contains("--dangerously-bypass-approvals-and-sandbox"))
    }
}

final class BoundedProcessRunnerTests: XCTestCase {
    func testDeadlineReturnsWhenDescendantKeepsOutputPipeOpen() async {
        let started = Date()
        do {
            _ = try await BoundedProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "sleep 2 & exit 0"], timeout: 0.1)
            XCTFail("Expected timeout for inherited pipe")
        } catch { XCTAssertTrue(error is BoundedProcessRunner.Failure) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testCancellationStopsHelper() async {
        let task = Task { try await BoundedProcessRunner.run(executable: "/bin/sleep", arguments: ["5"]) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is BoundedProcessRunner.Failure) }
    }

    func testInputIsPassedLiterallyWithoutShellExpansion() async throws {
        let text = "$(touch /should-never-run); `id`\n中文"
        let result = try await BoundedProcessRunner.run(executable: "/bin/cat", arguments: [], input: Data(text.utf8))
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), text)
    }

    func testTimeoutAndOutputLimitAreErrors() async {
        do {
            _ = try await BoundedProcessRunner.run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.05)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is BoundedProcessRunner.Failure) }
        do {
            _ = try await BoundedProcessRunner.run(executable: "/usr/bin/yes", arguments: [], outputLimit: 1024)
            XCTFail("Expected output limit")
        } catch { XCTAssertTrue(error is BoundedProcessRunner.Failure) }
    }
}
