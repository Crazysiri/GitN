import SwiftUI
import AppKit
import WebKit
import MarkdownUI
import HighlightSwift

// MARK: - String extension

extension String {
    var isMarkdownFile: Bool {
        let lower = lowercased()
        return lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || lower.hasSuffix(".mdown")
    }
}

enum MarkdownPreviewFence {
    static func normalizedLanguage(_ fenceInfo: String?) -> String? {
        guard let fenceInfo else { return nil }
        let trimmed = fenceInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased()
    }

    static func isMermaid(_ fenceInfo: String?) -> Bool {
        normalizedLanguage(fenceInfo) == "mermaid"
    }

    static func shouldSyntaxHighlight(_ fenceInfo: String?) -> Bool {
        guard let language = normalizedLanguage(fenceInfo) else { return false }
        return language != "text" && language != "plaintext" && language != "plain"
    }
}

enum MarkdownCodeBlockCapabilities {
    static func shouldUseSyntaxHighlighting(
        _ fenceInfo: String?,
        isHighlightingAvailable: Bool
    ) -> Bool {
        MarkdownPreviewFence.shouldSyntaxHighlight(fenceInfo) && isHighlightingAvailable
    }
}

enum MarkdownPreviewPerformance {
    static let richPreviewCharacterLimit = 12_000
    static let richPreviewLineLimit = 320
    /// Markdown_Render_Cap: hard upper bound (256 KB) for rich Markdown rendering.
    /// Declared adjacent to the legacy char/line heuristics as the single source of truth (R2.1).
    static let renderCapBytes = 262_144

    static func shouldUseRichPreview(for text: String) -> Bool {
        let utf16Length = (text as NSString).length
        guard utf16Length <= richPreviewCharacterLimit else { return false }
        return lineCount(for: text) <= richPreviewLineLimit
    }

    static func lineCount(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }
}

enum MarkdownEditorHighlightPolicy {
    // Whole-document regex passes run on the main thread. Above this size the
    // editor keeps its plain-text presentation instead of rescanning on each key.
    static func shouldHighlight(utf16Length: Int) -> Bool {
        utf16Length <= MarkdownPreviewPerformance.renderCapBytes
    }
}

/// Outcome of the Markdown preview render decision (R2).
enum MarkdownRenderDecision: Equatable {
    case rich
    case plain
}

/// Pure decision boundary for choosing between rich Markdown rendering and the
/// plain-text fallback. Kept free of SwiftUI so it can be unit tested directly (R2.8).
enum MarkdownRenderDecider {
    /// Decides how a Markdown document should be rendered.
    ///
    /// - Parameters:
    ///   - text: the full Markdown source.
    ///   - forceRich: `true` when the user has opted in to rich rendering for this file.
    /// - Returns: `.rich` or `.plain` per Requirements 2.2 / 2.3.
    ///
    /// Priority:
    /// 1. `forceRich == true` → `.rich` (highest priority opt-in).
    /// 2. UTF-8 byte length `> renderCapBytes` → `.plain` (R2.3, the only hard gate).
    /// 3. UTF-8 byte length `<= renderCapBytes` → always `.rich`, even when the legacy
    ///    line/char heuristics (`shouldUseRichPreview`) would return `false` (R2.2).
    static func decide(text: String, forceRich: Bool) -> MarkdownRenderDecision {
        if forceRich { return .rich }
        if text.utf8.count > MarkdownPreviewPerformance.renderCapBytes { return .plain }
        return .rich
    }
}

/// Tracks the per-file "Render Anyway" opt-in for the Markdown preview, scoped to the
/// current preview session.
///
/// Extracted from `MarkdownInspectorContentView` so the session-scope semantics (R2.4)
/// are unit-testable without instantiating a SwiftUI view body. The opt-in applies to a
/// single file at a time: switching to a different file clears it, so a second over-cap
/// file opened in the same session reverts to the default decision (`.plain`).
struct MarkdownForceRichScope: Equatable {
    /// The file path the opt-in currently applies to, or `nil` when no file is opted in.
    private(set) var optedInPath: String?

    init(optedInPath: String? = nil) {
        self.optedInPath = optedInPath
    }

    /// Whether rich rendering is currently forced for `path`.
    func isForced(for path: String) -> Bool {
        optedInPath != nil && optedInPath == path
    }

    /// User activated "Render Anyway" while viewing `path`.
    mutating func optIn(path: String) {
        optedInPath = path
    }

    /// Call when the previewed file changes. Clears the opt-in unless the new path is the
    /// same file the opt-in already applied to, so the opt-in never leaks to another file
    /// (R2.4: "SHALL NOT alter the rendering decision for any other file opened before or after").
    mutating func fileDidChange(to path: String) {
        if optedInPath != path {
            optedInPath = nil
        }
    }

    /// Render decision for `path` with `text`, honoring this scope's per-file opt-in.
    func decision(forPath path: String, text: String) -> MarkdownRenderDecision {
        MarkdownRenderDecider.decide(text: text, forceRich: isForced(for: path))
    }
}

enum MermaidSourceHeuristics {
    static func isFlowchart(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("flowchart") || trimmed.hasPrefix("graph ")
    }
}

enum MermaidSourcePreprocessor {
    static func preparedSource(_ source: String) -> String {
        guard MermaidSourceHeuristics.isFlowchart(source) else { return source }

        let lines = source.components(separatedBy: .newlines)
        var linkIndex = 0
        var dottedLinkIndexes: [Int] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("%%") || trimmed.hasPrefix("linkStyle ") {
                continue
            }

            let dottedCount = trimmed.matches(of: #/\-.->/#).count
            for _ in 0..<dottedCount {
                dottedLinkIndexes.append(linkIndex)
                linkIndex += 1
            }

            let normalDirectedCount = trimmed.matches(of: #/-->/#).count
            linkIndex += max(0, normalDirectedCount - dottedCount)

            let thickCount = trimmed.matches(of: #/==>/#).count
            linkIndex += thickCount
        }

        guard !dottedLinkIndexes.isEmpty else { return source }

        let styles = dottedLinkIndexes.map {
            "linkStyle \($0) stroke-dasharray: 6 4, stroke-linecap: round;"
        }

        return source + "\n" + styles.joined(separator: "\n")
    }
}

private enum MarkdownCodeBlockColors {
    static let background = ChromePalette.panelMutedBackground
    static let backgroundNS = ChromePalette.panelMutedBackgroundNSColor
    static let border = ChromePalette.panelBorder
    static let pageBackground = ChromePalette.panelBackground
    static let pageBackgroundNS = ChromePalette.panelBackgroundNSColor
}

private enum MarkdownCodeHighlightTheme {
    static func colors(for colorScheme: ColorScheme) -> CodeTextColors {
        switch colorScheme {
        case .dark:
            return .custom(dark: .dark(.tokyoNight), light: .light(.github))
        default:
            return .custom(dark: .dark(.tokyoNight), light: .light(.xcode))
        }
    }
}

private func mermaidDebugLog(_ message: @autoclosure () -> String) {
    print("[MermaidDebug] \(message())")
}

private extension Theme {
    static let gitNPreview = Theme.gitHub.codeBlock { configuration in
        MarkdownCodeBlockView(configuration: configuration)
    }
}

// MARK: - Editor color scheme

private enum EditorColors {
    static let background = ChromePalette.panelBackgroundNSColor
    static let text = NSColor.labelColor
    static let heading = ChromePalette.markdownHeadingNSColor
    static let code = ChromePalette.markdownCodeNSColor
    static let link = NSColor.linkColor
    static let bold = NSColor.labelColor
    static let blockquote = NSColor.secondaryLabelColor
    static let marker = NSColor.tertiaryLabelColor
    static let cursor = NSColor.controlAccentColor
    static let selection = NSColor.selectedTextBackgroundColor
}

// MARK: - Syntax highlight engine

private enum MDHighlighter {
    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    private struct Rule {
        let pattern: String
        let options: NSRegularExpression.Options
        let apply: (NSMutableAttributedString, NSRange) -> Void
    }

    private static let rules: [Rule] = [
        Rule(pattern: "```[\\s\\S]*?```", options: [.dotMatchesLineSeparators]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.code, range: range)
        },
        Rule(pattern: "`[^`\n]+`", options: []) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.code, range: range)
        },
        Rule(pattern: "^#{1,6}[ \t].+", options: [.anchorsMatchLines]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.heading, range: range)
            attr.addAttribute(.font, value: boldFont, range: range)
        },
        Rule(pattern: "^>[ \t]?.+", options: [.anchorsMatchLines]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.blockquote, range: range)
        },
        Rule(pattern: "\\*\\*[^*\n]+\\*\\*|__[^_\n]+__", options: []) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.bold, range: range)
            attr.addAttribute(.font, value: boldFont, range: range)
        },
        Rule(pattern: "(?<![*_])\\*[^*\n]+\\*(?![*])|(?<![_])_[^_\n]+_(?![_])", options: []) { attr, range in
            attr.addAttribute(.obliqueness, value: Float(0.2), range: range)
        },
        Rule(pattern: "\\[[^\n\\]]*\\]\\([^\n)]*\\)", options: []) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.link, range: range)
        },
        Rule(pattern: "^(-{3,}|\\*{3,}|_{3,})\\s*$", options: [.anchorsMatchLines]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.marker, range: range)
        },
        Rule(pattern: "^[ \t]*[-*+][ \t]|^[ \t]*\\d+\\.[ \t]", options: [.anchorsMatchLines]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.marker, range: range)
        },
    ]

    static func highlight(_ storage: NSTextStorage) {
        let str = storage.string
        let fullRange = NSRange(location: 0, length: (str as NSString).length)
        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: EditorColors.text], range: fullRange)
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            regex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match else { return }
                rule.apply(storage, match.range)
            }
        }
        storage.endEditing()
    }

    static func resetToPlain(_ storage: NSTextStorage) {
        storage.beginEditing()
        storage.setAttributes(
            [.font: baseFont, .foregroundColor: EditorColors.text],
            range: NSRange(location: 0, length: storage.length)
        )
        storage.endEditing()
    }
}

private struct MarkdownDocumentView: View {
    let text: String

    var body: some View {
        ScrollView {
            Markdown(text)
                .markdownTheme(.gitNPreview)
                .textSelection(.enabled)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MarkdownCodeBlockColors.pageBackground)
    }
}

private struct PlainMarkdownDocumentView: View {
    let text: String

    var body: some View {
        MarkdownPlainTextView(text: text)
            .background(MarkdownCodeBlockColors.pageBackground)
    }
}

private struct MarkdownCodeBlockView: View {
    let configuration: CodeBlockConfiguration

    var body: some View {
        Group {
            if MarkdownPreviewFence.isMermaid(configuration.language) {
                MermaidCodeBlockView(source: configuration.content)
            } else if MarkdownCodeBlockCapabilities.shouldUseSyntaxHighlighting(
                configuration.language,
                isHighlightingAvailable: GitNResources.highlightScriptURL != nil
            ) {
                SyntaxHighlightedCodeBlockView(
                    content: configuration.content,
                    language: MarkdownPreviewFence.normalizedLanguage(configuration.language)
                )
            } else {
                PlainCodeBlockView(content: configuration.content)
            }
        }
        .padding(16)
        .background(MarkdownCodeBlockColors.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MarkdownCodeBlockColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .markdownMargin(top: 0, bottom: 16)
    }
}

private struct PlainCodeBlockView: View {
    let content: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(content)
                .textSelection(.enabled)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }
}

private struct SyntaxHighlightedCodeBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: String
    let language: String?

    var body: some View {
        ScrollView(.horizontal) {
            CodeText(content)
                .highlightMode(highlightMode)
                .codeTextColors(MarkdownCodeHighlightTheme.colors(for: colorScheme))
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }

    private var highlightMode: HighlightMode {
        if let language, !language.isEmpty {
            return .languageAlias(language)
        }
        return .automatic
    }
}

private struct MermaidCodeBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    let source: String

    @State private var contentHeight: CGFloat = 320
    @StateObject private var detailPanelController = MermaidDetailPanelController()
    @State private var anchorView: NSView?

    var body: some View {
        if let baseDirectoryURL = GitNResources.markdownPreviewDirectoryURL,
           GitNResources.mermaidScriptURL != nil {
            VStack(alignment: .trailing, spacing: 10) {
                Button("查看详情") {
                    detailPanelController.present(
                        source: source,
                        isDark: colorScheme == .dark,
                        baseDirectoryURL: baseDirectoryURL,
                        from: anchorView
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .medium))

                MermaidDiagramWebView(
                    source: source,
                    isDark: colorScheme == .dark,
                    baseDirectoryURL: baseDirectoryURL,
                    zoomScale: 1,
                    displayMode: .inline,
                    reportsContentHeight: true,
                    contentHeight: $contentHeight
                )
                .frame(height: max(240, contentHeight))
                .allowsHitTesting(false)
            }
            .overlay(
                MermaidPanelAnchorView { anchorView = $0 }
                    .allowsHitTesting(false)
            )
            .onDisappear {
                detailPanelController.close()
            }
        } else {
            SyntaxHighlightedCodeBlockView(content: source, language: "mermaid")
        }
    }
}

private struct MermaidPanelAnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView)
        }
    }
}

private struct MermaidDiagramWebView: NSViewRepresentable {
    enum DisplayMode {
        case inline
        case detail
    }

    let source: String
    let isDark: Bool
    let baseDirectoryURL: URL
    let zoomScale: CGFloat
    let displayMode: DisplayMode
    let reportsContentHeight: Bool
    @Binding var contentHeight: CGFloat
    var onMagnifyChanged: ((CGFloat) -> Void)? = nil
    var onMagnifyEnded: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MermaidContainerView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mermaid")
        mermaidDebugLog("makeNSView mode=\(displayMode == .detail ? "detail" : "inline")")

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.setValue(false, forKey: "drawsTransparentBackground")
        webView.isInspectable = false
        let containerView = MermaidContainerView(webView: webView)
        let scrollView = internalScrollView(for: webView)
        scrollView?.drawsBackground = false
        if displayMode == .detail {
            let recognizer = NSMagnificationGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleMagnificationGestureRecognizer(_:))
            )
            recognizer.delaysPrimaryMouseButtonEvents = false
            recognizer.delaysSecondaryMouseButtonEvents = false
            recognizer.delaysOtherMouseButtonEvents = false
            containerView.addGestureRecognizer(recognizer)
            mermaidDebugLog("detail recognizer installed view=\(ObjectIdentifier(containerView))")
            containerView.onMagnify = { [weak coordinator = context.coordinator] magnification, locationInContainer, phase in
                coordinator?.handleMagnification(
                    magnification: magnification,
                    locationInContainer: locationInContainer,
                    phase: phase
                )
            }
            context.coordinator.installMagnifyMonitorIfNeeded()
        }
        context.coordinator.containerView = containerView
        context.coordinator.webView = webView
        context.coordinator.scrollView = scrollView
        context.coordinator.contentHeight = $contentHeight
        context.coordinator.onMagnifyChanged = onMagnifyChanged
        context.coordinator.onMagnifyEnded = onMagnifyEnded
        context.coordinator.lastAppliedZoomScale = zoomScale
        return containerView
    }

    func updateNSView(_ containerView: MermaidContainerView, context: Context) {
        let webView = containerView.webView
        mermaidDebugLog("updateNSView mode=\(displayMode == .detail ? "detail" : "inline") zoom=\(String(format: "%.3f", zoomScale)) htmlChanged=\(context.coordinator.lastHTML == nil)")
        context.coordinator.containerView = containerView
        context.coordinator.webView = webView
        context.coordinator.scrollView = internalScrollView(for: webView)
        context.coordinator.contentHeight = $contentHeight
        context.coordinator.onMagnifyChanged = onMagnifyChanged
        context.coordinator.onMagnifyEnded = onMagnifyEnded
        configureScrolling(for: webView)
        if displayMode == .detail {
            context.coordinator.installMagnifyMonitorIfNeeded()
        }
        let html = MermaidHTMLRenderer.document(
            source: source,
            isDark: isDark,
            displayMode: displayMode,
            reportsContentHeight: reportsContentHeight
        )

        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.lastAppliedZoomScale = zoomScale
            webView.loadHTMLString(html, baseURL: baseDirectoryURL)
            return
        }

        guard displayMode == .detail,
              abs(context.coordinator.lastAppliedZoomScale - zoomScale) > 0.0001
        else { return }

        context.coordinator.lastAppliedZoomScale = zoomScale
        context.coordinator.applyZoom(scale: zoomScale)
    }

    private func configureScrolling(for webView: WKWebView) {
        guard let scrollView = internalScrollView(for: webView) else { return }
        switch displayMode {
        case .inline:
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
        case .detail:
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .allowed
        }
        scrollView.autohidesScrollers = true
    }

    private func internalScrollView(for webView: WKWebView) -> NSScrollView? {
        webView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
    }

    final class MermaidContainerView: NSView {
        let webView: WKWebView
        var onMagnify: ((CGFloat, CGPoint, NSEvent.Phase) -> Void)?

        init(webView: WKWebView) {
            self.webView = webView
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            allowedTouchTypes = [.indirect]
            webView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func magnify(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            mermaidDebugLog("nsview magnify phase=\(event.phase.rawValue) mag=\(String(format: "%.4f", event.magnification)) point=\(NSStringFromPoint(location))")
            onMagnify?(event.magnification, location, event.phase)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var containerView: MermaidContainerView?
        weak var webView: WKWebView?
        weak var scrollView: NSScrollView?
        var lastHTML: String?
        var contentHeight: Binding<CGFloat>?
        var onMagnifyChanged: ((CGFloat) -> Void)?
        var onMagnifyEnded: ((CGFloat) -> Void)?
        var lastAppliedZoomScale: CGFloat = 1
        private var magnifyMonitor: Any?

        deinit {
            if let magnifyMonitor {
                NSEvent.removeMonitor(magnifyMonitor)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "mermaid",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            switch type {
            case "contentHeight":
                guard let height = body["height"] as? Double else { return }
                DispatchQueue.main.async {
                    mermaidDebugLog("contentHeight=\(height)")
                    self.contentHeight?.wrappedValue = CGFloat(height)
                }
            case "debug":
                if let message = body["message"] as? String {
                    mermaidDebugLog("js \(message)")
                }
            default:
                return
            }
        }

        func handleMagnification(
            magnification: CGFloat,
            locationInContainer: CGPoint,
            phase: NSEvent.Phase
        ) {
            guard let containerView else {
                mermaidDebugLog("handleMagnification dropped: missing containerView")
                return
            }
            guard let webView else {
                mermaidDebugLog("handleMagnification dropped: missing webView")
                return
            }
            let scaleDelta = 1 + magnification
            guard scaleDelta.isFinite, scaleDelta > 0 else { return }
            let point = webView.convert(locationInContainer, from: containerView)
            let newScale = max(0.5, min(3, lastAppliedZoomScale * scaleDelta))
            mermaidDebugLog(
                "handleMagnification phase=\(phase.rawValue) raw=\(String(format: "%.4f", magnification)) " +
                "delta=\(String(format: "%.4f", scaleDelta)) scale=\(String(format: "%.4f", newScale)) " +
                "point=\(NSStringFromPoint(point))"
            )
            lastAppliedZoomScale = newScale
            applyZoom(scale: newScale, anchor: point)
            onMagnifyChanged?(newScale)
            if phase == .ended || phase == .cancelled {
                onMagnifyEnded?(newScale)
            }
        }

        @objc
        func handleMagnificationGestureRecognizer(_ recognizer: NSMagnificationGestureRecognizer) {
            guard let containerView else { return }
            mermaidDebugLog(
                "recognizer state=\(recognizer.state.rawValue) mag=\(String(format: "%.4f", recognizer.magnification)) " +
                "point=\(NSStringFromPoint(recognizer.location(in: containerView)))"
            )
            handleMagnification(
                magnification: recognizer.magnification,
                locationInContainer: recognizer.location(in: containerView),
                phase: eventPhase(for: recognizer.state)
            )
        }

        private func eventPhase(for state: NSGestureRecognizer.State) -> NSEvent.Phase {
            switch state {
            case .possible:
                return .mayBegin
            case .began:
                return .began
            case .changed:
                return .changed
            case .ended:
                return .ended
            case .cancelled, .failed:
                return .cancelled
            @unknown default:
                return .changed
            }
        }

        func applyZoom(scale: CGFloat, anchor: CGPoint? = nil) {
            guard let webView else { return }
            let anchorX = anchor?.x ?? (webView.bounds.width / 2)
            let anchorY = anchor?.y ?? (webView.bounds.height / 2)
            mermaidDebugLog(
                "applyZoom scale=\(String(format: "%.4f", scale)) anchor=(\(String(format: "%.1f", anchorX)),\(String(format: "%.1f", anchorY)))"
            )
            let script = """
            window.gitnMermaid && window.gitnMermaid.setZoom(\(scale), \(anchorX), \(anchorY));
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func installMagnifyMonitorIfNeeded() {
            guard magnifyMonitor == nil else { return }
            mermaidDebugLog("installMagnifyMonitor")
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self,
                      let containerView,
                      let window = containerView.window else { return event }
                let point = containerView.convert(event.locationInWindow, from: nil)
                guard window == event.window, containerView.bounds.contains(point) else {
                    return event
                }
                mermaidDebugLog(
                    "localMonitor phase=\(event.phase.rawValue) mag=\(String(format: "%.4f", event.magnification)) " +
                    "point=\(NSStringFromPoint(point))"
                )
                self.handleMagnification(
                    magnification: event.magnification,
                    locationInContainer: point,
                    phase: event.phase
                )
                return nil
            }
        }

    }
}

private enum MermaidHTMLRenderer {
    static func document(
        source: String,
        isDark: Bool,
        displayMode: MermaidDiagramWebView.DisplayMode,
        reportsContentHeight: Bool
    ) -> String {
        let background = isDark ? "#1E2025" : "#F7F7F9"
        let cardBackground = isDark ? "#191B20" : "#F0F1F4"
        let foreground = isDark ? "rgba(255,255,255,0.86)" : "#111418"
        let secondary = isDark ? "rgba(255,255,255,0.58)" : "rgba(17,20,24,0.62)"
        let border = isDark ? "rgba(255,255,255,0.10)" : "rgba(17,20,24,0.12)"
        let encodedSource = javaScriptStringLiteral(MermaidSourcePreprocessor.preparedSource(source))
        let theme = isDark ? "dark" : "neutral"
        let colorScheme = isDark ? "dark" : "light"
        let isInlineMode = displayMode == .inline
        let viewportHeightStyle = isInlineMode ? "height: auto;" : "height: 100vh;"
        let pageHeightStyle = isInlineMode ? "height: auto;" : "height: 100%;"
        let overflowStyle = isInlineMode ? "overflow: hidden;" : "overflow: auto;"
        let minHeightStyle = isInlineMode ? "min-height: 232px;" : "min-height: 100%;"
        let contentWidthStyle = isInlineMode ? "width: 100%; min-width: 100%; justify-content: center;" : "width: max-content; min-width: 100%; justify-content: flex-start;"
        let diagramWidthStyle = isInlineMode ? "width: 100%;" : "width: max-content;"
        let reportHeightScript = reportsContentHeight ? """
            function reportHeight() {
              const content = document.getElementById("content");
              const diagram = document.getElementById("diagram");
              const svg = diagram ? diagram.querySelector("svg") : null;
              const contentRectHeight = content ? content.getBoundingClientRect().height : 0;
              const contentScrollHeight = content ? content.scrollHeight : 0;
              const diagramRectHeight = diagram ? diagram.getBoundingClientRect().height : 0;
              const diagramScrollHeight = diagram ? diagram.scrollHeight : 0;
              const svgRectHeight = svg ? svg.getBoundingClientRect().height : 0;
              const svgScrollHeight = svg ? svg.scrollHeight : 0;
              const nextHeight = Math.ceil(Math.max(
                contentRectHeight,
                contentScrollHeight,
                diagramRectHeight + 24,
                diagramScrollHeight + 24,
                svgRectHeight + 24,
                svgScrollHeight + 24
              ));
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mermaid) {
                window.webkit.messageHandlers.mermaid.postMessage({
                  type: "contentHeight",
                  height: nextHeight
                });
              }
            }
        """ : "function reportHeight() {}"

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: \(colorScheme);
            }
            html, body {
              margin: 0;
              padding: 0;
              \(pageHeightStyle)
              background: \(background);
              color: \(foreground);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
            }
            body {
              padding: 0;
              overflow: hidden;
            }
            #viewport {
              box-sizing: border-box;
              \(viewportHeightStyle)
              \(overflowStyle)
              background: \(background);
            }
            #content {
              display: flex;
              align-items: flex-start;
              box-sizing: border-box;
              background: \(cardBackground);
              border-radius: 8px;
              padding: 20px;
              \(contentWidthStyle)
              \(minHeightStyle)
            }
            #diagram {
              display: flex;
              justify-content: center;
              align-items: flex-start;
              \(diagramWidthStyle)
            }
            #diagram svg {
              display: block;
              background: transparent !important;
              overflow: visible !important;
            }
            #diagram .label,
            #diagram .nodeLabel,
            #diagram .edgeLabel,
            #diagram .cluster-label,
            #diagram .label text,
            #diagram .nodeLabel text,
            #diagram .edgeLabel text,
            #diagram .cluster-label text,
            #diagram span,
            #diagram p {
              color: \(foreground) !important;
              fill: \(foreground) !important;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif !important;
            }
            #diagram foreignObject,
            #diagram foreignObject div,
            #diagram foreignObject span,
            #diagram foreignObject p {
              background: transparent !important;
              color: \(foreground) !important;
            }
            #diagram .edgeLabel,
            #diagram .edgeLabel foreignObject {
              overflow: visible !important;
            }
            #diagram .edgeLabel foreignObject div,
            #diagram .edgeLabel foreignObject span,
            #diagram .edgeLabel foreignObject p {
              display: inline !important;
              background: \(isDark ? "rgba(56,60,68,0.96)" : "rgba(232,235,240,0.96)") !important;
              color: \(foreground) !important;
              font-size: 0.92em !important;
              border: none !important;
              border-radius: 3px !important;
              padding: 0 2px 0 1px !important;
              margin: 0 !important;
              line-height: 1.15 !important;
              box-sizing: border-box !important;
              white-space: nowrap !important;
              box-shadow: none !important;
              transform: translateX(-1px) !important;
            }
            #diagram .node rect,
            #diagram .node circle,
            #diagram .node ellipse,
            #diagram .node polygon,
            #diagram .node path,
            #diagram .cluster rect,
            #diagram .cluster polygon,
            #diagram .label-container {
              fill: \(cardBackground) !important;
              stroke: \(border) !important;
            }
            #diagram .edgeLabel rect {
              fill: transparent !important;
              stroke: none !important;
              rx: 4px !important;
              ry: 4px !important;
            }
            #diagram .flowchart-link,
            #diagram .edgePath path {
              stroke: \(secondary) !important;
              fill: none !important;
            }
            #diagram marker path,
            #diagram .arrowheadPath {
              fill: \(secondary) !important;
              stroke: \(secondary) !important;
            }
            #fallback {
              display: none;
              margin: 0;
              padding: 12px;
              border: 1px solid \(border);
              border-radius: 8px;
              background: rgba(127, 127, 127, 0.08);
              color: \(foreground);
              white-space: pre-wrap;
              word-break: break-word;
              font: 13px ui-monospace, SFMono-Regular, Menlo, monospace;
            }
            #error {
              display: none;
              margin: 0 0 10px 0;
              color: \(secondary);
              font-size: 12px;
            }
          </style>
          <script src="mermaid.min.js"></script>
        </head>
        <body>
          <p id="error"></p>
          <div id="viewport">
            <div id="content">
              <div id="diagram"></div>
            </div>
          </div>
          <pre id="fallback"></pre>
          <script>
            const source = \(encodedSource);
            \(reportHeightScript)
            const diagram = document.getElementById("diagram");
            const content = document.getElementById("content");
            const viewport = document.getElementById("viewport");
            const fallback = document.getElementById("fallback");
            const error = document.getElementById("error");
            const isInlineMode = \(isInlineMode ? "true" : "false");
            let currentZoomScale = 1;

            function sendDebug(message) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mermaid) {
                window.webkit.messageHandlers.mermaid.postMessage({
                  type: "debug",
                  message
                });
              }
            }

            function measureSvg(svg) {
              const viewBox = svg.viewBox && svg.viewBox.baseVal;
              if (viewBox && viewBox.width > 0 && viewBox.height > 0) {
                return { width: viewBox.width, height: viewBox.height };
              }
              const bbox = svg.getBBox();
              return {
                width: Math.max(1, bbox.width),
                height: Math.max(1, bbox.height)
              };
            }

            function applyLayout(anchorX = viewport.clientWidth / 2, anchorY = viewport.clientHeight / 2) {
              const svg = diagram.querySelector("svg");
              if (!svg) {
                sendDebug("applyLayout skipped: missing svg");
                reportHeight();
                return;
              }

              const natural = measureSvg(svg);
              const contentPadding = 40;
              const availableWidth = Math.max(1, viewport.clientWidth - contentPadding);

              if (isInlineMode) {
                const fittedWidth = availableWidth;
                const fittedHeight = fittedWidth * (natural.height / natural.width);
                diagram.style.width = `${fittedWidth}px`;
                diagram.style.height = `${fittedHeight}px`;
                svg.style.width = `${fittedWidth}px`;
                svg.style.height = `${fittedHeight}px`;
                content.style.minHeight = `${Math.ceil(fittedHeight + contentPadding)}px`;
              } else {
                const viewportRect = viewport.getBoundingClientRect();
                const previousDiagramRect = diagram.getBoundingClientRect();
                const previousWidth = parseFloat(svg.style.width) || previousDiagramRect.width || natural.width;
                const previousHeight = parseFloat(svg.style.height) || previousDiagramRect.height || natural.height;
                const baseScale = availableWidth / natural.width;
                const effectiveScale = Math.max(0.1, baseScale * currentZoomScale);
                const fittedWidth = natural.width * effectiveScale;
                const fittedHeight = natural.height * effectiveScale;
                const previousScrollLeft = viewport.scrollLeft;
                const previousScrollTop = viewport.scrollTop;
                const clampedAnchorX = Math.max(0, Math.min(anchorX, viewport.clientWidth));
                const clampedAnchorY = Math.max(0, Math.min(anchorY, viewport.clientHeight));
                const diagramOriginXInContent = previousScrollLeft + (previousDiagramRect.left - viewportRect.left);
                const diagramOriginYInContent = previousScrollTop + (previousDiagramRect.top - viewportRect.top);
                const localAnchorX = Math.max(0, Math.min(previousWidth, clampedAnchorX - (previousDiagramRect.left - viewportRect.left)));
                const localAnchorY = Math.max(0, Math.min(previousHeight, clampedAnchorY - (previousDiagramRect.top - viewportRect.top)));
                const anchorRatioX = previousWidth > 0 ? localAnchorX / previousWidth : 0.5;
                const anchorRatioY = previousHeight > 0 ? localAnchorY / previousHeight : 0.5;
                diagram.style.width = `${fittedWidth}px`;
                diagram.style.height = `${fittedHeight}px`;
                svg.style.width = `${fittedWidth}px`;
                svg.style.height = `${fittedHeight}px`;
                content.style.width = `${Math.ceil(Math.max(availableWidth, fittedWidth) + contentPadding)}px`;
                content.style.minHeight = `${Math.max(viewport.clientHeight, fittedHeight + contentPadding)}px`;
                viewport.scrollLeft = Math.max(0, diagramOriginXInContent + anchorRatioX * fittedWidth - clampedAnchorX);
                viewport.scrollTop = Math.max(0, diagramOriginYInContent + anchorRatioY * fittedHeight - clampedAnchorY);
                sendDebug(
                  `anchor local=(${localAnchorX.toFixed(1)},${localAnchorY.toFixed(1)}) ` +
                  `ratio=(${anchorRatioX.toFixed(4)},${anchorRatioY.toFixed(4)}) ` +
                  `scroll=(${viewport.scrollLeft.toFixed(1)},${viewport.scrollTop.toFixed(1)})`
                );
              }

              sendDebug(`applyLayout zoom=${currentZoomScale.toFixed(4)} anchor=(${anchorX.toFixed(1)},${anchorY.toFixed(1)}) size=${svg.style.width}x${svg.style.height}`);

              requestAnimationFrame(reportHeight);
            }

            function showFallback(message) {
              if (message) {
                error.textContent = "Mermaid render failed, showing source.";
                error.style.display = "block";
              }
              fallback.textContent = source;
              fallback.style.display = "block";
              content.style.display = "none";
              requestAnimationFrame(reportHeight);
            }

            async function renderDiagram() {
              if (!window.mermaid) {
                showFallback("Mermaid runtime unavailable");
                return;
              }
              try {
                mermaid.initialize({
                  startOnLoad: false,
                  securityLevel: "loose",
                  theme: "\(theme)",
                  look: "classic",
                  flowchart: {
                    curve: "linear",
                    htmlLabels: true,
                    useMaxWidth: true,
                    nodeSpacing: 60,
                    rankSpacing: 80,
                    padding: 20
                  },
                  themeVariables: {
                    background: "transparent",
                    primaryColor: "\(cardBackground)",
                    secondaryColor: "\(cardBackground)",
                    tertiaryColor: "\(cardBackground)",
                    primaryTextColor: "\(foreground)",
                    secondaryTextColor: "\(foreground)",
                    tertiaryTextColor: "\(foreground)",
                    primaryBorderColor: "\(border)",
                    secondaryBorderColor: "\(border)",
                    tertiaryBorderColor: "\(border)",
                    lineColor: "\(secondary)",
                    textColor: "\(foreground)",
                    mainBkg: "\(cardBackground)",
                    nodeBkg: "\(cardBackground)",
                    clusterBkg: "\(cardBackground)",
                    clusterBorder: "\(border)",
                    edgeLabelBackground: "\(cardBackground)",
                    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro SC', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif"
                  }
                });
                const renderResult = await mermaid.render("gitn-mermaid-diagram", source);
                diagram.innerHTML = renderResult.svg;
                applyLayout();
                if (typeof renderResult.bindFunctions === "function") {
                  renderResult.bindFunctions(diagram);
                }
              } catch (err) {
                console.error(err);
                showFallback(err && err.message ? err.message : "Render failed");
              }
            }

            window.gitnMermaid = {
              setZoom(scale, anchorX, anchorY) {
                if (isInlineMode) return;
                currentZoomScale = Math.max(0.5, Math.min(3, scale));
                sendDebug(`setZoom scale=${currentZoomScale.toFixed(4)} anchor=(${Number(anchorX).toFixed(1)},${Number(anchorY).toFixed(1)})`);
                applyLayout(anchorX, anchorY);
              }
            };

            window.addEventListener("load", renderDiagram);
            window.addEventListener("resize", applyLayout);
            if (typeof ResizeObserver !== "undefined") {
              const resizeObserver = new ResizeObserver(() => {
                if (isInlineMode) {
                  requestAnimationFrame(() => applyLayout());
                } else {
                  requestAnimationFrame(reportHeight);
                }
              });
              resizeObserver.observe(document.body);
              resizeObserver.observe(viewport);
              resizeObserver.observe(content);
              resizeObserver.observe(diagram);
            }
          </script>
        </body>
        </html>
        """
    }

    private static func javaScriptStringLiteral(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [string])
        guard let data, let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }
}

private struct MermaidDetailView: View {
    let source: String
    let isDark: Bool
    let baseDirectoryURL: URL
    let onClose: () -> Void

    @State private var zoomScale: CGFloat = 1
    @State private var gestureBaseZoomScale: CGFloat?

    private let baseWidth: CGFloat = 980
    private let baseHeight: CGFloat = 720

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Mermaid 详情")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    zoomScale = max(0.5, zoomScale - 0.2)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(zoomScale <= 0.5)
                Button {
                    zoomScale = min(3, zoomScale + 0.2)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(zoomScale >= 3)
                Button("关闭") {
                    onClose()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MarkdownCodeBlockColors.pageBackground)

            Divider()

            MermaidDiagramWebView(
                source: source,
                isDark: isDark,
                baseDirectoryURL: baseDirectoryURL,
                zoomScale: zoomScale,
                displayMode: .detail,
                reportsContentHeight: false,
                contentHeight: .constant(0),
                onMagnifyChanged: { newScale in
                    zoomScale = newScale
                },
                onMagnifyEnded: { newScale in
                    zoomScale = newScale
                }
            )
            .frame(
                width: baseWidth,
                height: baseHeight
            )
            .background(MarkdownCodeBlockColors.pageBackground)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let baseScale = gestureBaseZoomScale ?? zoomScale
                        if gestureBaseZoomScale == nil {
                            gestureBaseZoomScale = zoomScale
                        }
                        zoomScale = max(0.5, min(3, baseScale * value))
                    }
                    .onEnded { _ in
                        gestureBaseZoomScale = nil
                    }
            )
        }
        .frame(
            width: baseWidth,
            height: baseHeight + 49
        )
        .preferredColorScheme(isDark ? .dark : .light)
    }
}

private final class MermaidDetailPanel: NSPanel {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 769),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Mermaid 详情"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 720, height: 520)
        contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func present(source: String, isDark: Bool, baseDirectoryURL: URL, from anchorView: NSView?) {
        mermaidDebugLog("panel present isDark=\(isDark) anchorWindow=\(anchorView?.window != nil)")
        hostingView.rootView = AnyView(
            MermaidDetailView(
                source: source,
                isDark: isDark,
                baseDirectoryURL: baseDirectoryURL,
                onClose: { [weak self] in self?.close() }
            )
        )
        setContentSize(NSSize(width: 980, height: 769))
        center(relativeTo: anchorView?.window)
        makeKeyAndOrderFront(nil)
        mermaidDebugLog("panel visible=\(isVisible) key=\(isKeyWindow)")
    }

    private func center(relativeTo window: NSWindow?) {
        if let window {
            let frame = self.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 980, height: 769))
            let parentFrame = window.frame
            let origin = NSPoint(
                x: parentFrame.midX - frame.width / 2,
                y: parentFrame.midY - frame.height / 2
            )
            setFrameOrigin(origin)
        } else {
            center()
        }
    }
}

private final class MermaidDetailPanelController: ObservableObject {
    private let panel = MermaidDetailPanel()

    func present(source: String, isDark: Bool, baseDirectoryURL: URL, from anchorView: NSView?) {
        panel.present(source: source, isDark: isDark, baseDirectoryURL: baseDirectoryURL, from: anchorView)
    }

    func close() {
        mermaidDebugLog("panel close")
        panel.orderOut(nil)
    }

    deinit {
        DispatchQueue.main.async { [panel] in
            panel.orderOut(nil)
        }
    }
}

private extension Color {
    var nsColor: NSColor {
        NSColor(self)
    }
}

private extension NSColor {
    var hexString: String {
        let color = usingColorSpace(.deviceRGB) ?? self
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        let alpha = color.alphaComponent

        if alpha < 0.999 {
            return String(format: "#%02X%02X%02X%02X", red, green, blue, Int(round(alpha * 255)))
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// MARK: - NSTextView editor wrapper

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()

        let textView = LineNumberTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.backgroundColor = EditorColors.background
        textView.drawsBackground = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = EditorColors.text
        textView.selectedTextAttributes = [.backgroundColor: EditorColors.selection]
        textView.insertionPointColor = EditorColors.cursor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.backgroundColor = EditorColors.background
        scrollView.drawsBackground = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? LineNumberTextView,
              !context.coordinator.isUpdating else { return }
        guard textView.string != text else { return }
        textView.string = text
        if let storage = textView.textStorage {
            context.coordinator.updateHighlighting(storage)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        var isUpdating = false
        private var hasHighlightedContent = false

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        func updateHighlighting(_ storage: NSTextStorage) {
            if MarkdownEditorHighlightPolicy.shouldHighlight(utf16Length: storage.length) {
                MDHighlighter.highlight(storage)
                hasHighlightedContent = true
            } else if hasHighlightedContent {
                // Reset once when a small styled document grows beyond the cap.
                // Subsequent keystrokes leave the large document untouched.
                MDHighlighter.resetToPlain(storage)
                hasHighlightedContent = false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            if let storage = textView.textStorage {
                let selection = textView.selectedRange()
                updateHighlighting(storage)
                textView.setSelectedRange(selection)
            }
            isUpdating = false
        }
    }
}

private struct MarkdownPlainTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.backgroundColor = EditorColors.background
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = EditorColors.text

        scrollView.backgroundColor = EditorColors.background
        scrollView.drawsBackground = true
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
    }
}

// MARK: - Top-level preview / edit window view

struct MarkdownPreviewView: View {
    @Environment(ThemeManager.self) private var theme
    let title: String
    @State private var content: String
    @State private var isEditing = false

    init(title: String, content: String) {
        self.title = title
        self._content = State(initialValue: content)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isEditing {
                MarkdownEditorView(text: $content)
            } else if usesRichPreview {
                MarkdownDocumentView(text: content)
            } else {
                PlainMarkdownDocumentView(text: content)
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private var usesRichPreview: Bool {
        MarkdownPreviewPerformance.shouldUseRichPreview(for: content)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if !isEditing && !usesRichPreview {
                Text("Large file")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Picker("", selection: $isEditing) {
                Label("Preview", systemImage: "eye").tag(false)
                Label("Edit", systemImage: "pencil").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor))
    }
}

struct MarkdownInspectorContentView: View {
    /// Repo-relative path of the previewed file. Drives the per-file opt-in scope reset (R2.4).
    let filePath: String
    @Environment(ThemeManager.self) private var theme
    @Binding var text: String
    let isEditable: Bool

    @State private var isEditing = false
    /// User opted in to rich rendering for the current file via "Render Anyway" (R2.3/R2.4).
    /// Scoped to the current preview session and reset whenever `filePath` changes.
    @State private var forceRich = false
    /// Watchdog fired: rich rendering threw or produced no first frame within the timeout (R2.6).
    @State private var richRenderTimedOut = false
    /// The `filePath` whose rich document has actually appeared. Compared by the watchdog so it
    /// only falls back when the *current* file's rich view never reports appearance (R2.6).
    @State private var renderedPath: String?

    /// Seconds the watchdog waits for the first frame before falling back to plain (R2.6).
    private static let richRenderTimeout: Duration = .seconds(5)

    init(filePath: String, text: Binding<String>, isEditable: Bool) {
        self.filePath = filePath
        self._text = text
        self.isEditable = isEditable
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if isEditing && isEditable {
                MarkdownEditorView(text: $text)
            } else if showsRichPreview {
                // R2.5: rich rendering still flows through MarkdownDocumentView, preserving
                // zoom/link/anchor behavior. The watchdog (R2.6) only reverts to plain when
                // the first frame never arrives.
                MarkdownDocumentView(text: text)
                    // Fresh identity per file so onAppear fires on every switch (rich→rich included).
                    .id(filePath)
                    .onAppear { renderedPath = filePath }
                    .task(id: filePath) { await runRichRenderWatchdog(for: filePath) }
            } else {
                // Markdown_Plain_Fallback shows the complete contents without truncation (R2.6).
                PlainMarkdownDocumentView(text: text)
            }
        }
        .onChange(of: isEditable) { _, editable in
            if !editable {
                isEditing = false
            }
        }
        .onChange(of: filePath) { _, _ in
            // R2.4: opt-in and watchdog state are scoped to a single file. Switching files
            // (or reopening the same file in a later session) reverts to the default decision.
            // The rendered marker is not reset here — it is re-established by the rich view's
            // .onAppear (which fires on every switch thanks to .id(filePath)).
            forceRich = false
            richRenderTimedOut = false
        }
        .preferredColorScheme(theme.preferredColorScheme)
    }

    /// Render decision for the current file, honoring the per-file opt-in (R2.2–R2.4).
    private var decision: MarkdownRenderDecision {
        MarkdownRenderDecider.decide(text: text, forceRich: forceRich)
    }

    /// Whether the rich document should be shown. A fired watchdog forces plain (R2.6).
    private var showsRichPreview: Bool {
        decision == .rich && !richRenderTimedOut
    }

    /// True while the persistent "shown as plain text" indicator + opt-in control apply (R2.3).
    private var showsPlainFallbackIndicator: Bool {
        !isEditing && decision == .plain
    }

    /// Waits for the timeout; if the current file's rich view never reported its appearance,
    /// reverts to the plain fallback and surfaces a non-blocking message (R2.6). Cancellation
    /// (file change or view teardown) is treated as "no fallback needed".
    private func runRichRenderWatchdog(for target: String) async {
        do {
            try await Task.sleep(for: Self.richRenderTimeout)
        } catch {
            // Cancelled (file change / view teardown) → no fallback needed.
            return
        }
        guard !Task.isCancelled else { return }
        // Only fall back if the current file's rich view never reported its appearance.
        if renderedPath != target {
            richRenderTimedOut = true
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if !isEditing && richRenderTimedOut {
                // R2.6: non-blocking message describing the automatic fallback.
                Label("Markdown rendering timed out — showing plain text", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if showsPlainFallbackIndicator {
                Text("Large Markdown shown as plain text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("Render Anyway") {
                    forceRich = true
                    richRenderTimedOut = false
                }
                .controlSize(.small)
                .help("Render this large Markdown file as rich text for the current preview session")
            }
            Spacer()

            if isEditable {
                Picker("", selection: $isEditing) {
                    Label("Preview", systemImage: "eye").tag(false)
                    Label("Edit", systemImage: "pencil").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor))
    }
}
