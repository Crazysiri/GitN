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
        textView.selectedTextAttributes = [.backgroundColor: EditorColors.selection]
        textView.insertionPointColor = EditorColors.cursor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
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
        if let storage = textView.textStorage { MDHighlighter.highlight(storage) }
        _ = textView.layoutManager?.numberOfGlyphs
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
            } else {
                ScrollView {
                    Markdown(content)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .preferredColorScheme(theme.preferredColorScheme)
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
    @Environment(ThemeManager.self) private var theme
    @Binding var text: String
    let isEditable: Bool

    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if isEditing && isEditable {
                MarkdownEditorView(text: $text)
            } else {
                ScrollView {
                    Markdown(text)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: isEditable) { _, editable in
            if !editable {
                isEditing = false
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
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
