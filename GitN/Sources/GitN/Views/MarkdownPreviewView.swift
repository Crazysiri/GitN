import SwiftUI
import AppKit
import MarkdownUI

// MARK: - String extension

extension String {
    var isMarkdownFile: Bool {
        let lower = lowercased()
        return lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || lower.hasSuffix(".mdown")
    }
}

// MARK: - Editor color scheme

private enum EditorColors {
    static let background = NSColor(red: 0.118, green: 0.122, blue: 0.133, alpha: 1) // #1E1F22
    static let text       = NSColor(red: 0.737, green: 0.745, blue: 0.769, alpha: 1) // #BCBEC4
    static let heading    = NSColor(red: 0.812, green: 0.557, blue: 0.427, alpha: 1) // #CF8E6D
    static let code       = NSColor(red: 0.416, green: 0.671, blue: 0.451, alpha: 1) // #6AAB73
    static let link       = NSColor(red: 0.306, green: 0.580, blue: 0.808, alpha: 1) // #4E94CE
    static let bold       = NSColor(red: 0.95,  green: 0.95,  blue: 0.95,  alpha: 1)
    static let blockquote = NSColor(red: 0.416, green: 0.416, blue: 0.416, alpha: 1) // #6A6A6A
    static let marker     = NSColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1) // #808080
    static let cursor     = NSColor.white
    static let selection  = NSColor(red: 0.239, green: 0.369, blue: 0.533, alpha: 1)
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
        // Fenced code blocks
        Rule(pattern: "```[\\s\\S]*?```", options: [.dotMatchesLineSeparators]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.code, range: range)
        },
        // Inline code
        Rule(pattern: "`[^`\n]+`", options: []) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.code, range: range)
        },
        // ATX headings
        Rule(pattern: "^#{1,6}[ \t].+", options: [.anchorsMatchLines]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.heading, range: range)
            attr.addAttribute(.font, value: boldFont, range: range)
        },
        // Blockquote
        Rule(pattern: "^>[ \t]?.+", options: [.anchorsMatchLines]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.blockquote, range: range)
        },
        // Bold **text** or __text__
        Rule(pattern: "\\*\\*[^*\n]+\\*\\*|__[^_\n]+__", options: []) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.bold, range: range)
            attr.addAttribute(.font, value: boldFont, range: range)
        },
        // Italic *text* or _text_ (avoid matching bold markers)
        Rule(pattern: "(?<![*_])\\*[^*\n]+\\*(?![*])|(?<![_])_[^_\n]+_(?![_])", options: []) { attr, range in
            attr.addAttribute(.obliqueness, value: Float(0.2), range: range)
        },
        // Links [text](url)
        Rule(pattern: "\\[[^\n\\]]*\\]\\([^\n)]*\\)", options: []) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.link, range: range)
        },
        // Horizontal rules
        Rule(pattern: "^(-{3,}|\\*{3,}|_{3,})\\s*$", options: [.anchorsMatchLines]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.marker, range: range)
        },
        // List markers (- / * / 1.)
        Rule(pattern: "^[ \t]*[-*+][ \t]|^[ \t]*\\d+\\.[ \t]", options: [.anchorsMatchLines]) { attr, range in
            attr.addAttribute(.foregroundColor, value: EditorColors.marker, range: range)
        },
    ]

    static func highlight(_ storage: NSTextStorage) {
        let str = storage.string
        let fullRange = NSRange(location: 0, length: (str as NSString).length)
        storage.beginEditing()
        storage.addAttributes([.font: baseFont, .foregroundColor: EditorColors.text], range: fullRange)
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            regex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match else { return }
                rule.apply(storage, match.range)
            }
        }
        storage.endEditing()
    }
}

// MARK: - NSTextView editor wrapper

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.backgroundColor = EditorColors.background
        textView.selectedTextAttributes = [.backgroundColor: EditorColors.selection]
        textView.insertionPointColor = EditorColors.cursor
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.backgroundColor = EditorColors.background
        scrollView.drawsBackground = true

        textView.string = text
        if let storage = textView.textStorage { MDHighlighter.highlight(storage) }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              !context.coordinator.isUpdating,
              textView.string != text else { return }
        textView.string = text
        if let storage = textView.textStorage { MDHighlighter.highlight(storage) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        var isUpdating = false

        init(_ parent: MarkdownEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            if let storage = textView.textStorage {
                let sel = textView.selectedRange()
                MDHighlighter.highlight(storage)
                textView.setSelectedRange(sel)
            }
            isUpdating = false
        }
    }
}

// MARK: - Preview color scheme

enum PreviewScheme: String, CaseIterable {
    case light      = "Light"
    case dark       = "Dark"
    case sepia      = "Sepia"
    case githubDark = "GitHub Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .light:      return .light
        case .dark:       return .dark
        case .sepia:      return .light
        case .githubDark: return .dark
        }
    }

    var background: Color {
        switch self {
        case .light:      return Color(nsColor: .textBackgroundColor)
        case .dark:       return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .sepia:      return Color(red: 0.961, green: 0.941, blue: 0.902)
        case .githubDark: return Color(red: 0.051, green: 0.067, blue: 0.090)
        }
    }

    var swatch: Color {
        switch self {
        case .light:      return .white
        case .dark:       return Color(red: 0.18, green: 0.18, blue: 0.20)
        case .sepia:      return Color(red: 0.9, green: 0.86, blue: 0.78)
        case .githubDark: return Color(red: 0.051, green: 0.067, blue: 0.090)
        }
    }

    var iconName: String { "circle.fill" }
}

// MARK: - Top-level preview / edit window view

struct MarkdownPreviewView: View {
    let title: String
    @State private var content: String
    @State private var isEditing = false
    @AppStorage("GitN.markdownPreviewScheme") private var scheme: PreviewScheme = .light

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
            } else {
                ScrollView {
                    Markdown(content)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(scheme.background)
                .preferredColorScheme(scheme.colorScheme)
            }
        }
        .frame(minWidth: 680, minHeight: 500)
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
            // Scheme picker — only visible in preview mode
            if !isEditing {
                Menu {
                    ForEach(PreviewScheme.allCases, id: \.rawValue) { s in
                        Button {
                            scheme = s
                        } label: {
                            HStack {
                                Image(systemName: scheme == s ? "checkmark.circle.fill" : "circle")
                                Text(s.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(scheme.swatch)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Preview color scheme")
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
