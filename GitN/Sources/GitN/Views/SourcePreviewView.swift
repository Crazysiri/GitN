import SwiftUI
import AppKit
import HighlightSwift

private enum DiffIMELog {
    static func emit(_ message: @autoclosure () -> String) {
        print("[DiffIME] \(message())")
    }
}

private enum SourceEditorStyle {
    struct Palette {
        let background: NSColor
        let surface: NSColor
        let toolbar: NSColor
        let border: NSColor
        let text: NSColor
        let keyword: NSColor
        let string: NSColor
        let comment: NSColor
        let number: NSColor
        let type: NSColor
        let call: NSColor
        let preprocessor: NSColor
        let gutterBackground: NSColor
        let gutterText: NSColor
        let gutterSeparator: NSColor
    }

    static let editorFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let editorBoldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    static let lineHeight: CGFloat = 20

    static func palette(isDark: Bool) -> Palette {
        if isDark {
            return Palette(
                background: NSColor(red: 0.086, green: 0.094, blue: 0.110, alpha: 1),
                surface: NSColor(red: 0.118, green: 0.125, blue: 0.145, alpha: 1),
                toolbar: NSColor(red: 0.133, green: 0.141, blue: 0.161, alpha: 1),
                border: NSColor.white.withAlphaComponent(0.08),
                text: NSColor(red: 0.839, green: 0.859, blue: 0.902, alpha: 1),
                keyword: NSColor(red: 0.988, green: 0.572, blue: 0.384, alpha: 1),
                string: NSColor(red: 0.639, green: 0.851, blue: 0.557, alpha: 1),
                comment: NSColor(red: 0.451, green: 0.478, blue: 0.525, alpha: 1),
                number: NSColor(red: 0.493, green: 0.733, blue: 0.976, alpha: 1),
                type: NSColor(red: 0.510, green: 0.820, blue: 0.780, alpha: 1),
                call: NSColor(red: 0.947, green: 0.792, blue: 0.471, alpha: 1),
                preprocessor: NSColor(red: 0.776, green: 0.612, blue: 0.976, alpha: 1),
                gutterBackground: NSColor(red: 0.098, green: 0.106, blue: 0.122, alpha: 1),
                gutterText: NSColor(red: 0.388, green: 0.412, blue: 0.459, alpha: 1),
                gutterSeparator: NSColor.white.withAlphaComponent(0.06)
            )
        }

        return Palette(
            background: NSColor(red: 0.952, green: 0.960, blue: 0.976, alpha: 1),
            surface: NSColor(red: 0.985, green: 0.989, blue: 0.997, alpha: 1),
            toolbar: NSColor(red: 0.943, green: 0.952, blue: 0.972, alpha: 1),
            border: NSColor.black.withAlphaComponent(0.08),
            text: NSColor(red: 0.137, green: 0.161, blue: 0.220, alpha: 1),
            keyword: NSColor(red: 0.690, green: 0.278, blue: 0.188, alpha: 1),
            string: NSColor(red: 0.173, green: 0.514, blue: 0.243, alpha: 1),
            comment: NSColor(red: 0.486, green: 0.529, blue: 0.596, alpha: 1),
            number: NSColor(red: 0.102, green: 0.400, blue: 0.733, alpha: 1),
            type: NSColor(red: 0.086, green: 0.557, blue: 0.561, alpha: 1),
            call: NSColor(red: 0.667, green: 0.478, blue: 0.106, alpha: 1),
            preprocessor: NSColor(red: 0.506, green: 0.341, blue: 0.741, alpha: 1),
            gutterBackground: NSColor(red: 0.957, green: 0.965, blue: 0.980, alpha: 1),
            gutterText: NSColor(red: 0.545, green: 0.573, blue: 0.639, alpha: 1),
            gutterSeparator: NSColor.black.withAlphaComponent(0.07)
        )
    }
}

// MARK: - Source language

enum SourceLanguage: String {
    case swift, python, javascript, typescript, go, rust, c, cpp, java, shell,
         json, yaml, dart, kotlin, ruby, php, css, html, xml, toml, text

    var displayName: String {
        switch self {
        case .swift:      return "Swift"
        case .python:     return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .go:         return "Go"
        case .rust:       return "Rust"
        case .c:          return "C"
        case .cpp:        return "C++"
        case .java:       return "Java"
        case .shell:      return "Shell"
        case .json:       return "JSON"
        case .yaml:       return "YAML"
        case .dart:       return "Dart"
        case .kotlin:     return "Kotlin"
        case .ruby:       return "Ruby"
        case .php:        return "PHP"
        case .css:        return "CSS"
        case .html:       return "HTML"
        case .xml:        return "XML"
        case .toml:       return "TOML"
        case .text:       return "Plain Text"
        }
    }
}

extension String {
    var isPreviewableFile: Bool { true }

    var sourceLanguage: SourceLanguage {
        let ext = (self as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                          return .swift
        case "py":                             return .python
        case "js", "mjs", "cjs":              return .javascript
        case "ts", "tsx", "jsx":              return .typescript
        case "go":                             return .go
        case "rs":                             return .rust
        case "c", "h":                         return .c
        case "cpp", "cc", "cxx", "hpp":       return .cpp
        case "java":                           return .java
        case "sh", "bash", "zsh", "fish":     return .shell
        case "json", "jsonc":                  return .json
        case "yml", "yaml":                    return .yaml
        case "dart":                           return .dart
        case "kt", "kts":                      return .kotlin
        case "rb", "rake", "gemspec":          return .ruby
        case "php":                            return .php
        case "css", "scss", "sass", "less":   return .css
        case "html", "htm", "xhtml":           return .html
        case "xml", "plist", "svg":            return .xml
        case "toml":                           return .toml
        default:                               return .text
        }
    }
}

// MARK: - Syntax highlighter

private extension SourceLanguage {
    var highlightIdentifier: String? {
        switch self {
        case .swift: return "swift"
        case .python: return "python"
        case .javascript: return "javascript"
        case .typescript: return "typescript"
        case .go: return "go"
        case .rust: return "rust"
        case .c: return "c"
        case .cpp: return "cpp"
        case .java: return "java"
        case .shell: return "bash"
        case .json: return "json"
        case .yaml: return "yaml"
        case .dart: return "dart"
        case .kotlin: return "kotlin"
        case .ruby: return "ruby"
        case .php: return "php"
        case .css: return "css"
        case .html: return "html"
        case .xml: return "xml"
        case .toml: return "toml"
        case .text: return nil
        }
    }
}

private actor SourceHighlightEngine {
    static let shared = SourceHighlightEngine()

    private let highlight = Highlight()

    func highlightedText(
        _ text: String,
        language: SourceLanguage,
        isDark: Bool
    ) async -> AttributedString? {
        guard let languageID = language.highlightIdentifier else { return nil }

        do {
            return try await highlight.attributedText(
                text,
                language: languageID,
                colors: isDark ? .dark(.github) : .light(.github)
            )
        } catch {
            return nil
        }
    }
}

private enum SourceHighlighter {
    private struct Rule {
        let pattern: String
        let options: NSRegularExpression.Options
        let attributes: [NSAttributedString.Key: Any]
    }

    private static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = SourceEditorStyle.lineHeight
        style.maximumLineHeight = SourceEditorStyle.lineHeight
        return style
    }

    private static func keywords(for language: SourceLanguage) -> [String] {
        switch language {
        case .swift:
            return ["import", "class", "struct", "enum", "protocol", "extension", "func",
                    "var", "let", "if", "else", "guard", "return", "switch", "case", "default",
                    "for", "in", "while", "do", "try", "catch", "throw", "throws", "async", "await",
                    "self", "super", "init", "deinit", "nil", "true", "false", "static", "final",
                    "private", "public", "internal", "open", "fileprivate", "mutating", "override",
                    "some", "any", "where", "as", "is", "typealias", "associatedtype", "subscript"]
        case .python:
            return ["import", "from", "class", "def", "if", "elif", "else", "for", "while",
                    "return", "yield", "try", "except", "finally", "raise", "with", "as",
                    "pass", "break", "continue", "lambda", "and", "or", "not", "in", "is",
                    "None", "True", "False", "global", "nonlocal", "del", "assert", "async", "await"]
        case .javascript, .typescript:
            return ["import", "export", "from", "class", "function", "const", "let", "var",
                    "if", "else", "for", "while", "return", "try", "catch", "finally", "throw",
                    "new", "this", "super", "extends", "typeof", "instanceof", "null", "undefined",
                    "true", "false", "async", "await", "switch", "case", "default", "break",
                    "continue", "delete", "void", "in", "of", "static", "interface", "type",
                    "enum", "namespace", "abstract", "implements", "readonly"]
        case .go:
            return ["package", "import", "func", "var", "const", "type", "struct", "interface",
                    "map", "chan", "go", "defer", "return", "if", "else", "for", "range",
                    "switch", "case", "default", "select", "break", "continue", "fallthrough",
                    "nil", "true", "false", "make", "new", "len", "cap", "append", "copy", "delete"]
        case .rust:
            return ["use", "mod", "fn", "let", "mut", "const", "static", "struct", "enum",
                    "impl", "trait", "pub", "self", "super", "crate", "if", "else", "match",
                    "for", "while", "loop", "return", "break", "continue", "where", "type",
                    "as", "in", "ref", "move", "unsafe", "extern", "dyn", "async", "await",
                    "true", "false", "Some", "None", "Ok", "Err"]
        case .java:
            return ["import", "package", "class", "interface", "enum", "extends", "implements",
                    "public", "private", "protected", "static", "final", "abstract", "void",
                    "if", "else", "for", "while", "do", "return", "try", "catch", "finally",
                    "throw", "throws", "new", "this", "super", "null", "true", "false",
                    "synchronized", "volatile", "instanceof", "switch", "case", "default"]
        case .c, .cpp:
            return ["int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                    "struct", "union", "enum", "typedef", "const", "static", "extern",
                    "if", "else", "for", "while", "do", "return", "switch", "case", "default",
                    "break", "continue", "goto", "sizeof", "nullptr", "true", "false",
                    "class", "public", "private", "protected", "virtual", "override", "template"]
        case .shell:
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                    "case", "esac", "function", "return", "export", "local", "echo", "exit", "source"]
        case .dart:
            return ["import", "export", "library", "part", "class", "abstract", "interface",
                    "enum", "extension", "mixin", "typedef", "var", "final", "const", "late",
                    "void", "dynamic", "null", "true", "false", "if", "else", "for", "while",
                    "do", "switch", "case", "default", "break", "continue", "return", "try",
                    "catch", "finally", "throw", "rethrow", "new", "this", "super", "extends",
                    "implements", "with", "on", "in", "is", "as", "async", "await", "yield",
                    "static", "get", "set", "required", "covariant", "external", "factory",
                    "operator", "show", "hide", "deferred"]
        case .kotlin:
            return ["package", "import", "class", "interface", "object", "enum", "sealed",
                    "data", "abstract", "open", "final", "override", "fun", "val", "var",
                    "if", "else", "when", "for", "while", "do", "return", "try", "catch",
                    "finally", "throw", "in", "is", "as", "null", "true", "false", "this",
                    "super", "companion", "constructor", "init", "get", "set", "by", "where",
                    "typealias", "inline", "reified", "suspend", "lateinit", "it", "out",
                    "internal", "private", "protected", "public"]
        case .ruby:
            return ["require", "require_relative", "include", "extend", "module", "class",
                    "def", "end", "if", "elsif", "else", "unless", "case", "when", "then",
                    "for", "while", "until", "do", "begin", "rescue", "ensure", "raise",
                    "return", "yield", "self", "super", "nil", "true", "false", "and", "or",
                    "not", "in", "lambda", "proc", "attr_reader", "attr_writer",
                    "attr_accessor", "private", "protected", "public"]
        case .php:
            return ["namespace", "use", "class", "interface", "trait", "abstract",
                    "extends", "implements", "function", "return", "if", "elseif", "else",
                    "for", "foreach", "while", "do", "switch", "case", "default", "break",
                    "continue", "try", "catch", "finally", "throw", "new", "echo", "print",
                    "null", "true", "false", "static", "public", "protected", "private",
                    "final", "readonly", "match", "fn", "array", "list", "isset", "empty",
                    "unset", "include", "require", "include_once", "require_once"]
        case .css:
            return ["import", "media", "keyframes", "supports", "charset", "font-face",
                    "from", "to", "not", "and", "or", "only", "all", "screen", "print",
                    "important", "var", "calc", "url", "rgb", "rgba", "hsl", "hsla",
                    "linear-gradient", "radial-gradient", "none", "auto", "inherit",
                    "initial", "unset", "revert"]
        case .html, .xml:
            return ["doctype", "html", "head", "body", "div", "span", "p", "a", "img",
                    "script", "style", "link", "meta", "title", "h1", "h2", "h3", "h4",
                    "h5", "h6", "ul", "ol", "li", "table", "tr", "td", "th", "form",
                    "input", "button", "select", "option", "textarea", "label", "nav",
                    "header", "footer", "main", "section", "article", "aside", "true", "false"]
        case .toml:
            return ["true", "false", "inf", "nan"]
        default:
            return []
        }
    }

    private static func rules(for language: SourceLanguage, isDark: Bool) -> [Rule] {
        let palette = SourceEditorStyle.palette(isDark: isDark)
        var result: [Rule] = [
            // Multi-line comments (before single-line to take priority on /*…*/)
            Rule(pattern: "/\\*[\\s\\S]*?\\*/", options: [.dotMatchesLineSeparators], attributes: [.foregroundColor: palette.comment]),
            // Single-line // comments
            Rule(pattern: "//[^\n]*", options: [], attributes: [.foregroundColor: palette.comment]),
            // Shell / Python # comments
            Rule(pattern: "#[^\n]*", options: [], attributes: [.foregroundColor: palette.comment]),
            // Double-quoted strings
            Rule(pattern: #""(?:[^"\\]|\\.)*""#, options: [], attributes: [.foregroundColor: palette.string]),
            // Single-quoted strings
            Rule(pattern: #"'(?:[^'\\]|\\.)*'"#, options: [], attributes: [.foregroundColor: palette.string]),
            // Numbers
            Rule(pattern: #"\b(0x[0-9A-Fa-f]+|0b[01]+|0o[0-7]+|\d+(\.\d+)?([eE][+-]?\d+)?)\b"#, options: [], attributes: [.foregroundColor: palette.number]),
        ]
        let kw = keywords(for: language)
        if !kw.isEmpty {
            let pattern = "\\b(" + kw.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\b"
            result.append(Rule(pattern: pattern, options: [], attributes: [
                .foregroundColor: palette.keyword,
                .font: SourceEditorStyle.editorBoldFont
            ]))
        }
        result.append(Rule(pattern: #"(?m)^\s*#\w+.*$"#, options: [], attributes: [.foregroundColor: palette.preprocessor]))
        result.append(Rule(pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#, options: [], attributes: [.foregroundColor: palette.type]))
        result.append(Rule(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"#, options: [], attributes: [.foregroundColor: palette.call]))
        return result
    }

    static func highlight(_ storage: NSTextStorage, language: SourceLanguage, isDark: Bool) {
        let str = storage.string
        let fullRange = NSRange(location: 0, length: (str as NSString).length)
        let palette = SourceEditorStyle.palette(isDark: isDark)
        storage.beginEditing()
        storage.setAttributes([
            .font: SourceEditorStyle.editorFont,
            .foregroundColor: palette.text,
            .paragraphStyle: paragraphStyle()
        ], range: fullRange)
        for rule in rules(for: language, isDark: isDark) {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            regex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match else { return }
                storage.addAttributes(rule.attributes, range: match.range)
            }
        }
        storage.endEditing()
    }

    static func highlightedText(_ text: String, language: SourceLanguage, isDark: Bool) async -> AttributedString? {
        guard let attributed = await SourceHighlightEngine.shared.highlightedText(text, language: language, isDark: isDark) else {
            return nil
        }
        return normalizedAttributedString(from: attributed)
    }

    private static func normalizedAttributedString(from attributed: AttributedString) -> AttributedString? {
        let input = NSAttributedString(attributed)
        let fullRange = NSRange(location: 0, length: input.length)
        let normalized = NSMutableAttributedString(attributedString: input)
        var boldRanges: [NSRange] = []

        input.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? NSFont else { return }
            if font.fontDescriptor.symbolicTraits.contains(.bold) {
                boldRanges.append(range)
            }
        }

        normalized.addAttributes([
            .font: SourceEditorStyle.editorFont,
            .paragraphStyle: paragraphStyle()
        ], range: fullRange)

        for range in boldRanges {
            normalized.addAttribute(.font, value: SourceEditorStyle.editorBoldFont, range: range)
        }

        return try? AttributedString(normalized, including: \.appKit)
    }
}

// MARK: - Read-only NSTextView wrapper

private struct SourceTextView: NSViewRepresentable {
    let text: String
    let language: SourceLanguage
    let isDark: Bool

    final class Coordinator {
        var task: Task<Void, Never>?
        private var requestID = 0

        deinit {
            task?.cancel()
        }

        func scheduleHighlight(
            for textView: NSTextView,
            text: String,
            language: SourceLanguage,
            isDark: Bool
        ) {
            requestID += 1
            let currentRequestID = requestID
            task?.cancel()

            task = Task {
                guard let highlighted = await SourceHighlighter.highlightedText(text, language: language, isDark: isDark) else {
                    return
                }

                await MainActor.run {
                    guard !Task.isCancelled,
                          currentRequestID == self.requestID,
                          textView.string == text,
                          let storage = textView.textStorage
                    else { return }

                    storage.setAttributedString(NSAttributedString(highlighted))
                    _ = textView.layoutManager?.numberOfGlyphs
                    textView.needsDisplay = true
                    textView.enclosingScrollView?.contentView.needsDisplay = true
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func background(for isDark: Bool) -> NSColor {
        SourceEditorStyle.palette(isDark: isDark).surface
    }

    func makeNSView(context: Context) -> NSView {
        let scrollView = NSTextView.scrollableTextView()

        let textView = LineNumberTextView(frame: .zero)
        textView.drawsInlineGutter        = false
        textView.isEditable              = false
        textView.isSelectable            = true
        textView.isRichText              = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.backgroundColor         = Self.background(for: isDark)
        textView.drawsBackground         = true
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = true
        textView.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                   height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask        = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        let palette = SourceEditorStyle.palette(isDark: isDark)
        textView.lineColor = palette.gutterText
        textView.gutterBackgroundColor = palette.gutterBackground
        textView.gutterSeparatorColor = palette.gutterSeparator

        scrollView.hasHorizontalScroller = true

        scrollView.documentView    = textView
        scrollView.backgroundColor = Self.background(for: isDark)
        scrollView.drawsBackground = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let gutterView = StickyGutterOverlayView(frame: .zero)
        gutterView.textView = textView

        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: nil
        ) { [weak gutterView] _ in
            gutterView?.needsDisplay = true
        }

        // Text is intentionally NOT set here.
        // makeNSView is called while the view still has a .zero frame;
        // setting text at that point causes the layout manager to compute glyph
        // positions for a zero-width container.  When the real frame arrives,
        // layout is re-queued but the view never gets a setNeedsDisplay, so
        // content stays invisible until a scroll event forces a redraw (which
        // is why large files appeared to work but small ones didn't).
        // updateNSView is called after SwiftUI has assigned a real frame, so
        // the initial text application happens with a correct container width.
        return GutterHostingView(
            scrollView: scrollView,
            gutterView: gutterView,
            gutterWidth: LineNumberTextView.gutterWidth
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? GutterHostingView,
              let textView = container.scrollView.documentView as? LineNumberTextView,
              textView.string != text else { return }
        applyContent(to: textView, coordinator: context.coordinator)
        container.gutterView.needsDisplay = true
    }

    private func applyContent(to textView: NSTextView, coordinator: Coordinator) {
        textView.string = text
        if let storage = textView.textStorage {
            SourceHighlighter.highlight(storage, language: language, isDark: isDark)
        }
        coordinator.scheduleHighlight(for: textView, text: text, language: language, isDark: isDark)
        // Force a synchronous layout pass immediately after setting text.
        //
        // Why: NSLayoutManager is lazy — glyph positions are only computed on
        // demand.  When the text container width later changes (because
        // widthTracksTextView fires once SwiftUI assigns the real frame),
        // NSTextView calls textContainerChangedGeometry, which compares old
        // glyph rects with new ones to build the dirty rect for the redraw.
        // If no layout has run yet there are no "old rects", the dirty set is
        // empty, and drawBackground is never called for the full view — content
        // stays invisible.  Accessing numberOfGlyphs forces the full layout now
        // so the geometry-change path has a valid baseline to diff against.
        _ = textView.layoutManager?.numberOfGlyphs
    }
}

// MARK: - SourcePreviewView

struct SourcePreviewView: View {
    @Environment(ThemeManager.self) private var theme
    let title: String
    let content: String
    let language: SourceLanguage

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            SourceTextView(text: content, language: language, isDark: theme.isDark)
        }
        .background(Color(SourceEditorStyle.palette(isDark: theme.isDark).background))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(SourceEditorStyle.palette(isDark: theme.isDark).border), lineWidth: 1)
        )
        .padding(12)
        .frame(minWidth: 680, minHeight: 500)
    }

    private var toolbar: some View {
        let palette = SourceEditorStyle.palette(isDark: theme.isDark)
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.33)).frame(width: 9, height: 9)
                Circle().fill(Color(red: 0.98, green: 0.74, blue: 0.18)).frame(width: 9, height: 9)
                Circle().fill(Color(red: 0.18, green: 0.80, blue: 0.44)).frame(width: 9, height: 9)
            }
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(palette.text))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(language.displayName)
                .font(.system(size: 11))
                .foregroundStyle(Color(palette.gutterText))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(palette.background), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(palette.toolbar))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(palette.border))
                .frame(height: 1)
        }
    }
}

// MARK: - Overlay File Inspector

private enum SourceDiffDecorationKind: Equatable {
    case addition
    case deletion

    var fillColor: NSColor {
        switch self {
        case .addition:
            return NSColor.systemGreen.withAlphaComponent(0.11)
        case .deletion:
            return NSColor.systemRed.withAlphaComponent(0.11)
        }
    }

    var accentColor: Color {
        switch self {
        case .addition:
            return .green
        case .deletion:
            return .red
        }
    }

    var accentNSColor: NSColor {
        switch self {
        case .addition:
            return .systemGreen
        case .deletion:
            return .systemRed
        }
    }
}

private extension RepoViewModel.FileInspectorChangeKind {
    var sourceDecorationKind: SourceDiffDecorationKind {
        switch self {
        case .addition:
            return .addition
        case .deletion:
            return .deletion
        }
    }
}

private extension RepoViewModel.FileInspectorInlineHighlight {
    var backgroundColor: NSColor {
        switch kind {
        case .addition:
            return NSColor.systemGreen.withAlphaComponent(0.30)
        case .deletion:
            return NSColor.systemRed.withAlphaComponent(0.28)
        }
    }
}

private final class HighlightedSourceTextView: LineNumberTextView {
    static let diffGutterWidth: CGFloat = 104
    static let diffGutterVerticalOffset: CGFloat = 2

    var lineHighlights: [Int: SourceDiffDecorationKind] = [:]
    var inlineHighlights: [RepoViewModel.FileInspectorInlineHighlight] = []
    var lineNumberPairs: [Int: (old: Int?, new: Int?)] = [:]
    var hunkActionLines: [Int: Int] = [:] {
        didSet {
            guard hunkActionLines != oldValue else { return }
            refreshHunkToolTips()
        }
    }
    var hunkActionToolTips: [Int: String] = [:] {
        didSet {
            guard hunkActionToolTips != oldValue else { return }
            refreshHunkToolTips()
        }
    }
    var lineBlames: [Int: RepoViewModel.FileInspectorBlameInfo] = [:] {
        didSet {
            guard lineBlames != oldValue else { return }
            refreshHunkToolTips()
        }
    }
    var hunkActionSymbol = "+" {
        didSet {
            guard hunkActionSymbol != oldValue else { return }
            refreshHunkToolTips()
        }
    }
    var showsDiffGutter = false {
        didSet {
            guard showsDiffGutter != oldValue else { return }
            refreshHunkToolTips()
        }
    }
    var onHunkAction: ((Int) -> Void)?
    var onSave: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var isDarkTheme = true

    private let diffLineFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private let diffActionFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private var diffLineColor: NSColor {
        isDarkTheme ? NSColor(white: 0.46, alpha: 1) : .secondaryLabelColor
    }
    private var diffGutterBg: NSColor {
        isDarkTheme ? NSColor(red: 0.094, green: 0.098, blue: 0.110, alpha: 1) : NSColor.windowBackgroundColor
    }
    private var hoverTrackingArea: NSTrackingArea?
    private var lastTooltipKey: String?

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        enumerateVisibleLogicalLines(in: rect) { lineNum, _, frag in
            if let highlight = lineHighlights[lineNum] {
                let lineY = frag.minY + 16
                let rowRect = NSRect(x: 0, y: lineY, width: bounds.width, height: frag.height)
                highlight.fillColor.setFill()
                rowRect.fill()
            }
        }

        guard drawsInlineGutter else { return }

        let gutterMinX = pinnedViewportMinX(for: rect)
        guard showsDiffGutter else { return }

        diffGutterBg.setFill()
        NSRect(x: gutterMinX, y: rect.minY, width: Self.diffGutterWidth, height: rect.height).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: diffLineFont,
            .foregroundColor: diffLineColor
        ]

        enumerateVisibleLogicalLines(in: rect) { lineNum, _, frag in
            let lineY = frag.minY + 16
            let pair = lineNumberPairs[lineNum] ?? (lineNum, lineNum)
            if hunkActionLines[lineNum] != nil {
                drawHunkActionSymbol(x: gutterMinX + 12, y: lineY, height: frag.height)
            }
            drawDiffLineNumber(pair.old, x: gutterMinX + 52, y: lineY, height: frag.height, attrs: attrs)
            drawDiffLineNumber(pair.new, x: gutterMinX + 94, y: lineY, height: frag.height, attrs: attrs)

            if let highlight = lineHighlights[lineNum] {
                highlight.accentNSColor.withAlphaComponent(0.95).setFill()
                let accentX = highlight == .deletion ? gutterMinX : gutterMinX + Self.diffGutterWidth / 2
                NSRect(x: accentX, y: lineY, width: 3, height: frag.height).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsDiffGutter,
           point.x < textContainerInset.width,
           point.x <= 24,
           let line = logicalLineNumber(at: point),
           let hunkIndex = hunkActionLines[line] {
            onHunkAction?(hunkIndex)
            return
        }
        super.mouseDown(with: event)
    }

    override func layout() {
        super.layout()
        refreshHunkToolTips()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard showsDiffGutter else {
            DiffLineTooltipPanel.shared.cancelAndHide()
            super.mouseMoved(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard point.x <= Self.diffGutterWidth else {
            lastTooltipKey = nil
            DiffLineTooltipPanel.shared.cancelAndHide()
            super.mouseMoved(with: event)
            return
        }

        guard let tooltipText = tooltipText(at: point), !tooltipText.isEmpty else {
            lastTooltipKey = nil
            DiffLineTooltipPanel.shared.cancelAndHide()
            super.mouseMoved(with: event)
            return
        }

        let tooltipKey = tooltipIdentity(at: point, text: tooltipText)
        if tooltipKey != lastTooltipKey {
            lastTooltipKey = tooltipKey
            DiffLineTooltipPanel.shared.cancelAndHide()
        }

        let windowPoint = convert(point, to: nil)
        let screenPoint = window?.convertPoint(toScreen: windowPoint) ?? .zero
        DiffLineTooltipPanel.shared.scheduleShow(
            text: tooltipText,
            at: NSPoint(x: screenPoint.x + 14, y: screenPoint.y - 8)
        )

        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        lastTooltipKey = nil
        DiffLineTooltipPanel.shared.cancelAndHide()
        super.mouseExited(with: event)
    }

    private func logicalLineNumber(at point: NSPoint) -> Int? {
        guard let layoutManager,
              let textContainer else { return nil }

        let containerPoint = NSPoint(
            x: max(point.x - textContainerInset.width, 0),
            y: max(point.y - textContainerInset.height, 0)
        )
        let charIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        return lineNumber(forCharacterIndex: charIndex)
    }

    private func lineNumber(forCharacterIndex charIndex: Int) -> Int {
        let text = string as NSString
        let safeIndex = min(max(charIndex, 0), text.length)
        var line = 1
        var location = 0
        while location < safeIndex {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            if location <= safeIndex {
                line += 1
            }
        }
        return line
    }

    private func drawHunkActionSymbol(x: CGFloat, y: CGFloat, height: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: diffActionFont,
            .foregroundColor: NSColor.labelColor
        ]
        let label = hunkActionSymbol as NSString
        let size = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: x - size.width / 2, y: y + (height - size.height) / 2),
            withAttributes: attrs
        )
    }

    private func refreshHunkToolTips() {
        guard showsDiffGutter,
              (!hunkActionLines.isEmpty || !lineBlames.isEmpty) else { return }
    }

    private func tooltipText(at point: NSPoint) -> String? {
        guard point.x <= Self.diffGutterWidth else { return nil }
        guard let line = logicalLineNumber(at: point) else { return nil }
        if point.x <= 24, let range = hunkActionToolTips[line] {
            let action = hunkActionSymbol == "-" ? "取消暂存" : "暂存"
            return "\(action)这个区块 (\(range))"
        }
        return lineBlames[line]?.toolTipText
    }

    private func tooltipIdentity(at point: NSPoint, text: String) -> String {
        let line = logicalLineNumber(at: point) ?? 0
        let lane = point.x <= 24 ? "hunk" : "line"
        return "\(lane)-\(line)-\(text)"
    }

    private func logicalLineRect(
        for lineNumber: Int,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        guard lineNumber > 0 else { return nil }
        let nsText = string as NSString
        var currentLine = 1
        var location = 0

        while currentLine < lineNumber && location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            currentLine += 1
        }

        guard currentLine == lineNumber else { return nil }
        let targetRange = nsText.lineRange(for: NSRange(location: min(location, nsText.length), length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: targetRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect
    }

    private func drawDiffLineNumber(_ value: Int?, x: CGFloat, y: CGFloat, height: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let label = (value.map(String.init) ?? "") as NSString
        let size = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(
                x: x - size.width,
                y: y + (height - size.height) / 2 + Self.diffGutterVerticalOffset
            ),
            withAttributes: attrs
        )
    }

    override func keyDown(with event: NSEvent) {
        if handleShortcut(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let supportsShortcut = flags.contains(.command) || (flags.contains(.control) && !flags.contains(.command))
        guard supportsShortcut else { return false }
        let activeUndoManager = undoManager ?? window?.undoManager

        switch key {
        case "c":
            copy(nil)
        case "v":
            paste(nil)
        case "x":
            cut(nil)
        case "z":
            if flags.contains(.shift) {
                if let onRedo {
                    onRedo()
                } else {
                    activeUndoManager?.redo()
                }
            } else {
                if let onUndo {
                    onUndo()
                } else {
                    activeUndoManager?.undo()
                }
            }
        case "a":
            selectAll(nil)
        case "s":
            onSave?()
        default:
            return false
        }
        return true
    }
}

private final class DiffLineTooltipPanel: NSPanel {
    static let shared = DiffLineTooltipPanel()
    private let tooltipView = DiffLineTooltipView()
    private var pendingShow: DispatchWorkItem?

    private init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        contentView = tooltipView
    }

    func scheduleShow(text: String, at origin: NSPoint) {
        pendingShow?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.present(text: text, at: origin)
        }
        pendingShow = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    func cancelAndHide() {
        pendingShow?.cancel()
        pendingShow = nil
        if isVisible { orderOut(nil) }
    }

    private func present(text: String, at origin: NSPoint) {
        let size = tooltipView.configure(text: text)
        setContentSize(size)
        setFrameOrigin(origin)
        if !isVisible {
            orderFront(nil)
        }
    }
}

private final class DiffLineTooltipView: NSView {
    private var text = ""
    override var isFlipped: Bool { true }

    func configure(text: String) -> CGSize {
        guard self.text != text else {
            return fittingSize(for: text)
        }
        self.text = text
        needsDisplay = true
        return fittingSize(for: text)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textRect = bounds.insetBy(dx: 8, dy: 6)
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
    }

    private func fittingSize(for text: String) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraph
        ]
        let maxWidth: CGFloat = 320
        let raw = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).integral
        return CGSize(width: max(80, raw.width + 16), height: max(24, raw.height + 12))
    }
}

private final class StickyGutterOverlayView: NSView {
    weak var textView: LineNumberTextView?
    var showsDiffGutter = false { didSet { needsDisplay = true } }
    var lineHighlights: [Int: SourceDiffDecorationKind] = [:] { didSet { needsDisplay = true } }
    var lineNumberPairs: [Int: (old: Int?, new: Int?)] = [:] { didSet { needsDisplay = true } }
    var hunkActionLines: [Int: Int] = [:] { didSet { needsDisplay = true } }
    var hunkActionToolTips: [Int: String] = [:] { didSet { needsDisplay = true } }
    var hunkActionSymbol = "+" { didSet { needsDisplay = true } }
    var isDarkTheme = true { didSet { needsDisplay = true } }

    private let lineFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private var lineColor: NSColor { SourceEditorStyle.palette(isDark: isDarkTheme).gutterText }
    private let diffLineFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private let diffActionFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private var diffLineColor: NSColor { SourceEditorStyle.palette(isDark: isDarkTheme).gutterText }
    private var gutterBg: NSColor {
        SourceEditorStyle.palette(isDark: isDarkTheme).gutterBackground
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, let scrollView = textView.enclosingScrollView else { return }
        let visibleRect = scrollView.contentView.bounds

        gutterBg.setFill()
        bounds.fill()

        if showsDiffGutter {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: diffLineFont,
                .foregroundColor: diffLineColor
            ]

            textView.enumerateVisibleLogicalLines(in: visibleRect) { lineNum, _, frag in
                let lineY = frag.minY + 16 - visibleRect.minY
                let pair = self.lineNumberPairs[lineNum] ?? (lineNum, lineNum)
                if self.hunkActionLines[lineNum] != nil {
                    self.drawHunkActionSymbol(x: 12, y: lineY, height: frag.height)
                }
                self.drawDiffLineNumber(pair.old, x: 52, y: lineY, height: frag.height, attrs: attrs)
                self.drawDiffLineNumber(pair.new, x: 94, y: lineY, height: frag.height, attrs: attrs)

                if let highlight = self.lineHighlights[lineNum] {
                    highlight.accentNSColor.withAlphaComponent(0.95).setFill()
                    let accentX = highlight == .deletion ? 0 : HighlightedSourceTextView.diffGutterWidth / 2
                    NSRect(x: accentX, y: lineY, width: 3, height: frag.height).fill()
                }
            }
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: lineFont,
                .foregroundColor: lineColor
            ]

            textView.enumerateVisibleLogicalLines(in: visibleRect) { lineNum, _, frag in
                let label = "\(lineNum)" as NSString
                let sz = label.size(withAttributes: attrs)
                label.draw(
                    at: NSPoint(
                        x: LineNumberTextView.gutterWidth - sz.width - 8,
                        y: frag.minY + 16 + (frag.height - sz.height) / 2 - visibleRect.minY
                    ),
                    withAttributes: attrs
                )
            }
        }
    }

    private func drawDiffLineNumber(_ value: Int?, x: CGFloat, y: CGFloat, height: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let label = (value.map(String.init) ?? "") as NSString
        let size = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(
                x: x - size.width,
                y: y + (height - size.height) / 2 + HighlightedSourceTextView.diffGutterVerticalOffset
            ),
            withAttributes: attrs
        )
    }

    private func drawHunkActionSymbol(x: CGFloat, y: CGFloat, height: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: diffActionFont,
            .foregroundColor: NSColor.labelColor
        ]
        let label = hunkActionSymbol as NSString
        let size = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: x - size.width / 2, y: y + (height - size.height) / 2),
            withAttributes: attrs
        )
    }
}

private final class LockedHorizontalClipView: NSClipView {
    private var lockedHorizontalOriginX: CGFloat?
    private var horizontalLockDeadline: CFTimeInterval = 0
    private let horizontalLockDuration: CFTimeInterval = 0.35

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.size.width) > 0.5
        if widthChanged {
            lockedHorizontalOriginX = bounds.origin.x
            horizontalLockDeadline = CACurrentMediaTime() + horizontalLockDuration
        }

        super.setFrameSize(newSize)
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        let now = CACurrentMediaTime()

        if let lockedHorizontalOriginX, now <= horizontalLockDeadline {
            constrained.origin.x = lockedHorizontalOriginX
        } else if abs(proposedBounds.width - bounds.width) > 0.5 {
            constrained.origin.x = bounds.origin.x
        } else if lockedHorizontalOriginX != nil {
            self.lockedHorizontalOriginX = nil
        }

        return constrained
    }
}

private final class GutterHostingView: NSView {
    let scrollView: NSScrollView
    let gutterView: StickyGutterOverlayView
    private let gutterWidth: CGFloat

    init(scrollView: NSScrollView, gutterView: StickyGutterOverlayView, gutterWidth: CGFloat) {
        self.scrollView = scrollView
        self.gutterView = gutterView
        self.gutterWidth = gutterWidth
        super.init(frame: .zero)
        addSubview(scrollView)
        addSubview(gutterView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let clipFrame = scrollView.contentView.frame
        gutterView.frame = NSRect(x: clipFrame.minX, y: clipFrame.minY, width: gutterWidth, height: clipFrame.height)
    }
}

private struct EditableSourceTextView: NSViewRepresentable {
    let text: String
    let language: SourceLanguage
    let isEditable: Bool
    let isDark: Bool
    let lineHighlights: [Int: RepoViewModel.FileInspectorChangeKind]
    let inlineHighlights: [RepoViewModel.FileInspectorInlineHighlight]
    let lineNumberPairs: [Int: RepoViewModel.FileInspectorLinePair]
    let hunkActionLines: [Int: Int]
    let hunkActionToolTips: [Int: String]
    let lineBlames: [Int: RepoViewModel.FileInspectorBlameInfo]
    let hunkActionSymbol: String
    let showsDiffGutter: Bool
    let targetLine: Int?
    let selectedRange: NSRange?
    let onHunkAction: ((Int) -> Void)?
    let onSelectionChange: ((NSRange) -> Void)?
    let prepareTextChange: ((NSRange, String?) -> String?)?
    let onTextChange: (String, NSRange) -> Void
    let onUndo: (() -> Void)?
    let onRedo: (() -> Void)?
    let onSave: () -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableSourceTextView
        var isUpdating = false
        var lastScrolledLine: Int?
        var pendingModelText: String?
        var pendingSelection: NSRange?
        var lastLocalEditAt: CFTimeInterval = 0
        var compositionBaseText: String?
        var suppressSelectionSync = false

        init(parent: EditableSourceTextView) {
            self.parent = parent
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            DiffIMELog.emit(
                "shouldChange range=\(NSStringFromRange(affectedCharRange)) replacement=\(String(reflecting: replacementString)) selected=\(NSStringFromRange(textView.selectedRange())) marked=\(textView.hasMarkedText()) textLength=\((textView.string as NSString).length)"
            )
            if textView.hasMarkedText(), parent.prepareTextChange != nil {
                if compositionBaseText == nil {
                    compositionBaseText = textView.string
                    DiffIMELog.emit("shouldChange deferring IME composition with baseLength=\((textView.string as NSString).length)")
                }
                suppressSelectionSync = true
                pendingModelText = nil
                pendingSelection = nil
                return true
            }
            guard let prepareTextChange = parent.prepareTextChange else { return true }
            guard let modelText = prepareTextChange(affectedCharRange, replacementString) else {
                DiffIMELog.emit("shouldChange rejected")
                NSSound.beep()
                return false
            }

            pendingModelText = modelText
            pendingSelection = predictedSelection(
                from: textView.selectedRange(),
                affectedRange: affectedCharRange,
                replacementString: replacementString
            )
            suppressSelectionSync = true
            DiffIMELog.emit(
                "shouldChange accepted pendingSelection=\(NSStringFromRange(pendingSelection ?? NSRange(location: NSNotFound, length: 0))) modelLength=\((modelText as NSString).length)"
            )
            lastLocalEditAt = CACurrentMediaTime()
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let isComposingMarkedText = textView.hasMarkedText()
            isUpdating = true
            let liveSelection = textView.selectedRange()
            let selection = isComposingMarkedText
                ? liveSelection
                : (pendingSelection ?? liveSelection)
            DiffIMELog.emit(
                "textDidChange marked=\(isComposingMarkedText) selected=\(NSStringFromRange(textView.selectedRange())) effectiveSelection=\(NSStringFromRange(selection)) pendingSelection=\(NSStringFromRange(pendingSelection ?? NSRange(location: NSNotFound, length: 0))) viewLength=\((textView.string as NSString).length) modelLength=\(((pendingModelText ?? textView.string) as NSString).length)"
            )
            if isComposingMarkedText {
                pendingSelection = nil
                pendingModelText = nil
                isUpdating = false
                return
            }

            if let compositionBaseText, let prepareTextChange = parent.prepareTextChange {
                let currentText = textView.string
                guard let delta = Self.singleReplacement(from: compositionBaseText, to: currentText),
                      let modelText = prepareTextChange(delta.range, delta.replacement) else {
                    DiffIMELog.emit("textDidChange failed to map committed IME text; restoring base text")
                    textView.string = compositionBaseText
                    if let storage = textView.textStorage {
                        SourceHighlighter.highlight(storage, language: parent.language, isDark: parent.isDark)
                        EditableSourceTextView.applyInlineHighlights(parent.inlineHighlights, to: storage)
                    }
                    textView.setSelectedRange(liveSelection)
                    self.compositionBaseText = nil
                    suppressSelectionSync = false
                    isUpdating = false
                    NSSound.beep()
                    return
                }
                DiffIMELog.emit(
                    "textDidChange committed IME deltaRange=\(NSStringFromRange(delta.range)) replacement=\(String(reflecting: delta.replacement)) modelLength=\((modelText as NSString).length)"
                )
                parent.onTextChange(modelText, liveSelection)
                self.compositionBaseText = nil
            } else {
                parent.onTextChange(pendingModelText ?? textView.string, selection)
            }
            parent.onSelectionChange?(selection)
            if !isComposingMarkedText, let storage = textView.textStorage {
                SourceHighlighter.highlight(storage, language: parent.language, isDark: parent.isDark)
                EditableSourceTextView.applyInlineHighlights(parent.inlineHighlights, to: storage)
                textView.setSelectedRange(selection)
            }
            pendingModelText = nil
            suppressSelectionSync = false
            isUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isUpdating else { return }
            if suppressSelectionSync || textView.hasMarkedText() || compositionBaseText != nil {
                DiffIMELog.emit("selectionDidChange suppressed selected=\(NSStringFromRange(textView.selectedRange())) marked=\(textView.hasMarkedText())")
                return
            }
            let selection = textView.selectedRange()
            DiffIMELog.emit("selectionDidChange selected=\(NSStringFromRange(selection)) marked=\(textView.hasMarkedText())")
            parent.onSelectionChange?(selection)
        }

        private func predictedSelection(
            from selectedRange: NSRange,
            affectedRange: NSRange,
            replacementString: String?
        ) -> NSRange {
            let replacementLength = ((replacementString ?? "") as NSString).length
            let insertionPoint = affectedRange.location + replacementLength
            if selectedRange.location >= affectedRange.location {
                return NSRange(location: insertionPoint, length: 0)
            }
            return selectedRange
        }

        private static func singleReplacement(from source: String, to target: String) -> (range: NSRange, replacement: String)? {
            if source == target {
                return (NSRange(location: 0, length: 0), "")
            }

            let sourceChars = Array(source)
            let targetChars = Array(target)

            var prefixLength = 0
            while prefixLength < sourceChars.count,
                  prefixLength < targetChars.count,
                  sourceChars[prefixLength] == targetChars[prefixLength] {
                prefixLength += 1
            }

            var sourceSuffix = sourceChars.count
            var targetSuffix = targetChars.count
            while sourceSuffix > prefixLength,
                  targetSuffix > prefixLength,
                  sourceChars[sourceSuffix - 1] == targetChars[targetSuffix - 1] {
                sourceSuffix -= 1
                targetSuffix -= 1
            }

            let sourceStart = sourceChars.index(sourceChars.startIndex, offsetBy: prefixLength)
            let sourceEnd = sourceChars.index(sourceChars.startIndex, offsetBy: sourceSuffix)
            let targetStart = targetChars.index(targetChars.startIndex, offsetBy: prefixLength)
            let targetEnd = targetChars.index(targetChars.startIndex, offsetBy: targetSuffix)

            let utf16Location = String(sourceChars[..<sourceStart]).utf16.count
            let utf16Length = String(sourceChars[sourceStart..<sourceEnd]).utf16.count
            let replacement = String(targetChars[targetStart..<targetEnd])
            return (NSRange(location: utf16Location, length: utf16Length), replacement)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let scrollView = NSTextView.scrollableTextView()
        let clipView = LockedHorizontalClipView()
        clipView.drawsBackground = true
        clipView.backgroundColor = SourceTextView.background(for: isDark)
        scrollView.contentView = clipView

        let textView = HighlightedSourceTextView(frame: .zero)
        textView.drawsInlineGutter = false
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = onUndo == nil && onRedo == nil
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.backgroundColor = SourceTextView.background(for: isDark)
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.insertionPointColor = isDark ? .white : .labelColor
        textView.selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28)]
        textView.onSave = onSave
        textView.onUndo = onUndo
        textView.onRedo = onRedo
        textView.isDarkTheme = isDark
        textView.lineBlames = showsDiffGutter ? lineBlames : [:]
        let palette = SourceEditorStyle.palette(isDark: isDark)
        textView.lineColor = palette.gutterText
        textView.gutterBackgroundColor = palette.gutterBackground
        textView.gutterSeparatorColor = palette.gutterSeparator
        textView.textContainerInset = NSSize(
            width: showsDiffGutter ? HighlightedSourceTextView.diffGutterWidth : LineNumberTextView.gutterWidth + 16,
            height: 16
        )
        if let selectedRange {
            textView.setSelectedRange(selectedRange)
        }

        scrollView.documentView = textView
        scrollView.backgroundColor = SourceTextView.background(for: isDark)
        scrollView.drawsBackground = true
        scrollView.hasHorizontalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let gutterView = StickyGutterOverlayView(frame: .zero)
        gutterView.textView = textView
        gutterView.showsDiffGutter = showsDiffGutter
        gutterView.isDarkTheme = isDark

        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: nil
        ) { [weak gutterView] _ in
            gutterView?.needsDisplay = true
        }

        return GutterHostingView(
            scrollView: scrollView,
            gutterView: gutterView,
            gutterWidth: showsDiffGutter ? HighlightedSourceTextView.diffGutterWidth : LineNumberTextView.gutterWidth
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? GutterHostingView,
              let textView = container.scrollView.documentView as? HighlightedSourceTextView else { return }

        context.coordinator.parent = self
        textView.isEditable = isEditable
        textView.allowsUndo = onUndo == nil && onRedo == nil
        textView.lineHighlights = showsDiffGutter
            ? Dictionary(uniqueKeysWithValues: lineHighlights.map { ($0.key, $0.value.sourceDecorationKind) })
            : [:]
        textView.inlineHighlights = showsDiffGutter ? inlineHighlights : []
        textView.lineNumberPairs = showsDiffGutter
            ? Dictionary(uniqueKeysWithValues: lineNumberPairs.map { ($0.key, (old: $0.value.old, new: $0.value.new)) })
            : [:]
        textView.hunkActionLines = showsDiffGutter ? hunkActionLines : [:]
        textView.hunkActionToolTips = showsDiffGutter ? hunkActionToolTips : [:]
        textView.lineBlames = showsDiffGutter ? lineBlames : [:]
        textView.hunkActionSymbol = hunkActionSymbol
        textView.showsDiffGutter = showsDiffGutter
        textView.onHunkAction = onHunkAction
        textView.onSave = onSave
        textView.onUndo = onUndo
        textView.onRedo = onRedo
        textView.isDarkTheme = isDark
        textView.backgroundColor = SourceTextView.background(for: isDark)
        let palette = SourceEditorStyle.palette(isDark: isDark)
        textView.lineColor = palette.gutterText
        textView.gutterBackgroundColor = palette.gutterBackground
        textView.gutterSeparatorColor = palette.gutterSeparator
        container.gutterView.showsDiffGutter = showsDiffGutter
        container.gutterView.lineHighlights = textView.lineHighlights
        container.gutterView.lineNumberPairs = textView.lineNumberPairs
        container.gutterView.hunkActionLines = textView.hunkActionLines
        container.gutterView.hunkActionToolTips = textView.hunkActionToolTips
        container.gutterView.hunkActionSymbol = hunkActionSymbol
        container.gutterView.isDarkTheme = isDark
        container.scrollView.backgroundColor = SourceTextView.background(for: isDark)
        container.scrollView.contentView.backgroundColor = SourceTextView.background(for: isDark)

        let currentLineCount = max(textView.string.components(separatedBy: "\n").count, 1)
        let incomingLineCount = max(text.components(separatedBy: "\n").count, 1)
        let shouldForceDisplaySync = showsDiffGutter && (
            currentLineCount != incomingLineCount ||
            abs((textView.string as NSString).length - (text as NSString).length) > 1
        )
        let isWithinLocalEditWindow = showsDiffGutter &&
            CACurrentMediaTime() - context.coordinator.lastLocalEditAt < 0.35
        let isComposingMarkedText = textView.hasMarkedText()
        if showsDiffGutter {
            DiffIMELog.emit(
                "updateNSView marked=\(isComposingMarkedText) isUpdating=\(context.coordinator.isUpdating) localWindow=\(isWithinLocalEditWindow) currentLength=\((textView.string as NSString).length) incomingLength=\((text as NSString).length) selected=\(NSStringFromRange(textView.selectedRange())) modelSelected=\(NSStringFromRange(selectedRange ?? NSRange(location: NSNotFound, length: 0))) forceSync=\(shouldForceDisplaySync)"
            )
        }
        if !context.coordinator.isUpdating,
           !isComposingMarkedText,
           textView.string != text,
           (!isWithinLocalEditWindow || shouldForceDisplaySync) {
            DiffIMELog.emit("updateNSView applying external text sync")
            context.coordinator.isUpdating = true
            context.coordinator.suppressSelectionSync = true
            textView.string = text
            if let storage = textView.textStorage {
                SourceHighlighter.highlight(storage, language: language, isDark: isDark)
                Self.applyInlineHighlights(inlineHighlights, to: storage)
            }
            _ = textView.layoutManager?.numberOfGlyphs

            let selectionToRestore = showsDiffGutter
                ? selectedRange
                : (context.coordinator.pendingSelection ?? selectedRange)
            if let selectionToRestore {
                let clampedLocation = min(selectionToRestore.location, (textView.string as NSString).length)
                let clampedLength = min(selectionToRestore.length, (textView.string as NSString).length - clampedLocation)
                textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
                context.coordinator.pendingSelection = nil
            }
            context.coordinator.suppressSelectionSync = false
            context.coordinator.isUpdating = false
        }

        textView.needsDisplay = true
        container.gutterView.needsDisplay = true

        if let targetLine, context.coordinator.lastScrolledLine != targetLine {
            context.coordinator.lastScrolledLine = targetLine
            scroll(textView: textView, toLine: targetLine)
            container.gutterView.needsDisplay = true
        }
    }

    private static func applyInlineHighlights(
        _ highlights: [RepoViewModel.FileInspectorInlineHighlight],
        to storage: NSTextStorage
    ) {
        guard !highlights.isEmpty else { return }
        let storageLength = storage.length
        for highlight in highlights {
            guard highlight.range.length > 0,
                  highlight.range.location >= 0,
                  NSMaxRange(highlight.range) <= storageLength else {
                continue
            }
            storage.addAttribute(.backgroundColor, value: highlight.backgroundColor, range: highlight.range)
        }
    }

    private func scroll(textView: NSTextView, toLine lineNumber: Int) {
        guard lineNumber > 0,
              let scrollView = textView.enclosingScrollView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        let nsString = textView.string as NSString
        var currentLine = 1
        var location = 0

        while currentLine < lineNumber && location < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            currentLine += 1
        }

        let targetRange = nsString.lineRange(for: NSRange(location: min(location, nsString.length), length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: targetRange, actualCharacterRange: nil)
        var targetRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        targetRect.origin.x += textView.textContainerInset.width
        targetRect.origin.y += textView.textContainerInset.height

        let clipView = scrollView.contentView
        let visibleRect = clipView.documentVisibleRect
        let maxY = max(textView.bounds.height - visibleRect.height, 0)

        // Jump vertically while preserving the user's current horizontal position.
        let desiredY = min(max(targetRect.minY - (visibleRect.height * 0.2), 0), maxY)
        let targetOrigin = NSPoint(x: visibleRect.minX, y: desiredY)
        clipView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }
}

private struct DiffOverviewRail: View {
    let totalLines: Int
    let segments: [RepoViewModel.FileInspectorOverviewSegment]
    let onJump: (Int) -> Void

    private let minimumSegmentHeight: CGFloat = 6
    private let mergePixelGap: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.05))

                Canvas { context, size in
                    let columnWidth = max((size.width - 2) / 2, 1)
                    drawColumn(.deletion, x: 0, width: columnWidth, height: size.height, context: &context)
                    drawColumn(.addition, x: columnWidth + 2, width: columnWidth, height: size.height, context: &context)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = min(max(value.location.y / max(geo.size.height, 1), 0), 1)
                        let line = max(1, Int(CGFloat(totalLines) * ratio))
                        onJump(line)
                    }
            )
        }
    }

    private func drawColumn(
        _ kind: RepoViewModel.FileInspectorChangeKind,
        x: CGFloat,
        width: CGFloat,
        height: CGFloat,
        context: inout GraphicsContext
    ) {
        let decoration = kind.sourceDecorationKind
        let bgRect = CGRect(x: x, y: 0, width: width, height: height)
        context.fill(Path(roundedRect: bgRect, cornerRadius: 5), with: .color(decoration.accentColor.opacity(0.04)))

        for segment in coalescedSegments(for: kind, height: height) {
            let top = height * CGFloat(max(segment.startLine - 1, 0)) / CGFloat(max(totalLines, 1))
            let segmentHeight = max(minimumSegmentHeight, height * CGFloat(max(segment.endLine - segment.startLine + 1, 1)) / CGFloat(max(totalLines, 1)))
            let rect = CGRect(
                x: x,
                y: min(top, max(height - segmentHeight, 0)),
                width: width,
                height: segmentHeight
            )
            context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(decoration.accentColor.opacity(0.55)))
        }
    }

    private func coalescedSegments(
        for kind: RepoViewModel.FileInspectorChangeKind,
        height: CGFloat
    ) -> [RepoViewModel.FileInspectorOverviewSegment] {
        let filtered = segments.filter { $0.kind == kind }.sorted { $0.startLine < $1.startLine }
        guard var current = filtered.first else { return [] }

        var result: [RepoViewModel.FileInspectorOverviewSegment] = []

        for next in filtered.dropFirst() {
            let currentBottom = projectedBottom(for: current, height: height)
            let nextTop = projectedTop(for: next, height: height)

            if nextTop - currentBottom <= mergePixelGap {
                current = RepoViewModel.FileInspectorOverviewSegment(
                    startLine: current.startLine,
                    endLine: max(current.endLine, next.endLine),
                    kind: current.kind
                )
            } else {
                result.append(current)
                current = next
            }
        }

        result.append(current)
        return result
    }

    private func projectedTop(
        for segment: RepoViewModel.FileInspectorOverviewSegment,
        height: CGFloat
    ) -> CGFloat {
        height * CGFloat(max(segment.startLine - 1, 0)) / CGFloat(max(totalLines, 1))
    }

    private func projectedBottom(
        for segment: RepoViewModel.FileInspectorOverviewSegment,
        height: CGFloat
    ) -> CGFloat {
        projectedTop(for: segment, height: height)
            + max(minimumSegmentHeight, height * CGFloat(max(segment.endLine - segment.startLine + 1, 1)) / CGFloat(max(totalLines, 1)))
    }
}

struct FileInspectorOverlayView: View {
    @Environment(ThemeManager.self) private var theme
    let viewModel: RepoViewModel

    @State private var targetLine: Int?
    @State private var showCloseConfirmation = false
    @State private var pendingModeSwitch: RepoViewModel.FileInspectorMode?

    private var canToggleHunks: Bool {
        viewModel.fileInspectorMode == .diff &&
        !viewModel.isFileInspectorDiffEditing &&
        !viewModel.isFileInspectorDirty &&
        (viewModel.currentDiffContext == .staged || viewModel.currentDiffContext == .unstaged)
    }

    private var hunkActionSymbol: String {
        viewModel.currentDiffContext == .staged ? "-" : "+"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(theme.isDark ? 0.34 : 0.12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .zIndex(1)
                Divider().overlay(Color.white.opacity(0.08))

                Group {
                    if viewModel.fileInspectorMode == .history {
                        FileHistoryPanelContent(viewModel: viewModel, showsToolbar: false)
                    } else if viewModel.fileInspectorMode == .diff && viewModel.isFileTooLarge {
                        fileTooLargeState
                    } else if viewModel.fileInspectorMode != .diff &&
                                !viewModel.isFileInspectorEditable &&
                                viewModel.fileInspectorContent.isEmpty {
                        unsupportedContentState
                    } else {
                        let isDiffMode = viewModel.fileInspectorMode == .diff
                        let showsRenderedDiff = isDiffMode && !viewModel.isFileInspectorDiffEditing
                        if !isDiffMode && viewModel.fileInspectorPath.isMarkdownFile {
                            MarkdownInspectorContentView(
                                text: Binding(
                                    get: { viewModel.fileInspectorContent },
                                    set: { viewModel.fileInspectorContent = $0 }
                                ),
                                isEditable: viewModel.isFileInspectorEditable
                            )
                        } else {
                            HStack(spacing: 0) {
                                EditableSourceTextView(
                                    text: isDiffMode
                                        ? viewModel.fileInspectorDisplayContent
                                        : viewModel.fileInspectorContent,
                                    language: viewModel.fileInspectorPath.sourceLanguage,
                                    isEditable: viewModel.isFileInspectorEditable,
                                    isDark: theme.isDark,
                                    lineHighlights: viewModel.fileInspectorLineHighlights,
                                    inlineHighlights: viewModel.fileInspectorInlineHighlights,
                                    lineNumberPairs: viewModel.fileInspectorLinePairs,
                                    hunkActionLines: canToggleHunks ? viewModel.fileInspectorHunkControls : [:],
                                    hunkActionToolTips: canToggleHunks ? viewModel.fileInspectorHunkToolTips : [:],
                                    lineBlames: viewModel.fileInspectorLineBlames,
                                    hunkActionSymbol: hunkActionSymbol,
                                    showsDiffGutter: showsRenderedDiff,
                                    targetLine: targetLine,
                                    selectedRange: viewModel.fileInspectorSelectedRange,
                                    onHunkAction: canToggleHunks ? { hunkIndex in
                                        Task {
                                            if viewModel.currentDiffContext == .staged {
                                                await viewModel.unstageHunk(hunkIndex)
                                            } else {
                                                await viewModel.stageHunk(hunkIndex)
                                            }
                                            if let file = viewModel.selectedDiffFile {
                                                await viewModel.openFileInspector(
                                                    file,
                                                    context: viewModel.currentDiffContext,
                                                    preferredMode: .diff
                                                )
                                            }
                                        }
                                    } : nil,
                                    onSelectionChange: { selection in
                                        viewModel.fileInspectorSelectedRange = selection
                                    },
                                    prepareTextChange: isDiffMode ? { affectedRange, replacementString in
                                        viewModel.prepareFileInspectorDiffEdit(
                                            affectedRange: affectedRange,
                                            replacementString: replacementString
                                        )
                                    } : nil,
                                    onTextChange: { text, selection in
                                        if isDiffMode {
                                            viewModel.applyPreparedFileInspectorDiffEdit(
                                                content: text,
                                                renderedSelection: selection
                                            )
                                        } else {
                                            viewModel.fileInspectorContent = text
                                        }
                                    },
                                    onUndo: isDiffMode ? {
                                        viewModel.undoFileInspectorDiffEdit()
                                    } : nil,
                                    onRedo: isDiffMode ? {
                                        viewModel.redoFileInspectorDiffEdit()
                                    } : nil,
                                    onSave: {
                                        Task { await viewModel.saveFileInspector() }
                                    }
                                )

                                if isDiffMode && !viewModel.fileInspectorOverviewSegments.isEmpty {
                                    Divider().overlay(Color.white.opacity(0.08))
                                    DiffOverviewRail(totalLines: viewModel.fileInspectorTotalLines, segments: viewModel.fileInspectorOverviewSegments) { line in
                                        targetLine = line
                                    }
                                    .frame(width: 28)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 14)
                                    .background(theme.isDark ? Color.black.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
                                }
                            }
                        }
                    }
                }
                .clipped()
            }
            .background(Color(nsColor: SourceTextView.background(for: theme.isDark)))
            .overlay(
                Rectangle()
                    .strokeBorder(theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .onChange(of: viewModel.fileInspectorPath) { _, _ in
            targetLine = nil
        }
        .alert("Save Changes?", isPresented: $showCloseConfirmation) {
            Button("Save") {
                Task {
                    if await viewModel.saveFileInspector() {
                        handleConfirmedInspectorDismissal()
                    }
                }
            }
            Button("Don't Save", role: .destructive) {
                handleConfirmedInspectorDismissal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes in \(viewModel.fileInspectorTitle).")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(viewModel.fileInspectorTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    modePicker
                }

                HStack(spacing: 8) {
                    Text(viewModel.activeFileInspectorPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if viewModel.isFileInspectorEditable && viewModel.fileInspectorMode != .history {
                        saveHint
                    }
                }
            }

            Spacer()

            if viewModel.isFileInspectorDirty {
                Text("Edited")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .foregroundStyle(.orange)
            }

            Button {
                pendingModeSwitch = nil
                if viewModel.isFileInspectorDirty {
                    showCloseConfirmation = true
                } else {
                    viewModel.closeFileInspector()
                }
            } label: {
                Group {
                    if viewModel.isSavingFileInspector {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(viewModel.isSavingFileInspector)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.isDark ? Color.black.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.fileInspectorMode },
            set: { mode in
                if viewModel.fileInspectorMode != .history &&
                    mode == .history &&
                    viewModel.isFileInspectorDirty {
                    pendingModeSwitch = mode
                    showCloseConfirmation = true
                } else {
                    Task { await viewModel.setFileInspectorMode(mode) }
                }
            }
        )) {
            Label("Preview", systemImage: "doc.text")
                .tag(RepoViewModel.FileInspectorMode.preview)
            Label("Diff", systemImage: "square.split.2x1")
                .tag(RepoViewModel.FileInspectorMode.diff)
            Label("History", systemImage: "clock.arrow.circlepath")
                .tag(RepoViewModel.FileInspectorMode.history)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .scaleEffect(0.92)
        .frame(width: 280)
    }

    private var saveHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 8, weight: .medium))
            Text("Cmd+S")
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(theme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), in: Capsule())
        .foregroundStyle(.secondary)
    }

    private func handleConfirmedInspectorDismissal() {
        if let mode = pendingModeSwitch {
            pendingModeSwitch = nil
            Task { await viewModel.setFileInspectorMode(mode) }
        } else {
            viewModel.closeFileInspector()
        }
    }

    private var fileTooLargeState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Diff is too large to render")
                .font(.system(size: 13, weight: .medium))
            Text("\(viewModel.fileTooLargeSizeMB) MB")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Switch To Preview") {
                viewModel.fileInspectorMode = .preview
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedContentState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.zipper")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("This file can't be displayed as editable text")
                .font(.system(size: 13, weight: .medium))
            if let encoding = viewModel.fileInspectorEncodingName {
                Text("Detected encoding: \(encoding)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("Binary file or unsupported text encoding")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("Editing is disabled for this file.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let message = viewModel.fileInspectorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
