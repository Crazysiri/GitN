import SwiftUI
import AppKit

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

private enum SourceHighlighter {
    private static let baseFont    = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont    = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    private static let textColor    = NSColor(red: 0.737, green: 0.745, blue: 0.769, alpha: 1)
    private static let keywordColor = NSColor(red: 0.812, green: 0.557, blue: 0.427, alpha: 1)
    private static let stringColor  = NSColor(red: 0.647, green: 0.784, blue: 0.514, alpha: 1)
    private static let commentColor = NSColor(red: 0.416, green: 0.416, blue: 0.416, alpha: 1)
    private static let numberColor  = NSColor(red: 0.431, green: 0.698, blue: 0.890, alpha: 1)

    private struct Rule {
        let pattern: String
        let options: NSRegularExpression.Options
        let color: NSColor
        let bold: Bool
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

    private static func rules(for language: SourceLanguage) -> [Rule] {
        var result: [Rule] = [
            // Multi-line comments (before single-line to take priority on /*…*/)
            Rule(pattern: "/\\*[\\s\\S]*?\\*/", options: [.dotMatchesLineSeparators], color: commentColor, bold: false),
            // Single-line // comments
            Rule(pattern: "//[^\n]*", options: [], color: commentColor, bold: false),
            // Shell / Python # comments
            Rule(pattern: "#[^\n]*", options: [], color: commentColor, bold: false),
            // Double-quoted strings
            Rule(pattern: #""(?:[^"\\]|\\.)*""#, options: [], color: stringColor, bold: false),
            // Single-quoted strings
            Rule(pattern: #"'(?:[^'\\]|\\.)*'"#, options: [], color: stringColor, bold: false),
            // Numbers
            Rule(pattern: #"\b\d+(\.\d+)?\b"#, options: [], color: numberColor, bold: false),
        ]
        let kw = keywords(for: language)
        if !kw.isEmpty {
            let pattern = "\\b(" + kw.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\b"
            result.append(Rule(pattern: pattern, options: [], color: keywordColor, bold: true))
        }
        return result
    }

    static func highlight(_ storage: NSTextStorage, language: SourceLanguage) {
        let str = storage.string
        let fullRange = NSRange(location: 0, length: (str as NSString).length)
        storage.beginEditing()
        storage.addAttributes([.font: baseFont, .foregroundColor: textColor], range: fullRange)
        for rule in rules(for: language) {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            regex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                guard let match else { return }
                var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: rule.color]
                if rule.bold { attrs[.font] = boldFont }
                storage.addAttributes(attrs, range: match.range)
            }
        }
        storage.endEditing()
    }
}

// MARK: - Read-only NSTextView wrapper

private struct SourceTextView: NSViewRepresentable {
    let text: String
    let language: SourceLanguage

    private static let background = NSColor(red: 0.118, green: 0.122, blue: 0.133, alpha: 1)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()

        let textView = LineNumberTextView(frame: .zero)
        textView.isEditable              = false
        textView.isSelectable            = true
        textView.isRichText              = false
        textView.backgroundColor         = Self.background
        textView.drawsBackground         = true
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = false
        textView.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                   height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask        = NSView.AutoresizingMask([.width])
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView    = textView
        scrollView.backgroundColor = Self.background
        scrollView.drawsBackground = true

        // Text is intentionally NOT set here.
        // makeNSView is called while the view still has a .zero frame;
        // setting text at that point causes the layout manager to compute glyph
        // positions for a zero-width container.  When the real frame arrives,
        // layout is re-queued but the view never gets a setNeedsDisplay, so
        // content stays invisible until a scroll event forces a redraw (which
        // is why large files appeared to work but small ones didn't).
        // updateNSView is called after SwiftUI has assigned a real frame, so
        // the initial text application happens with a correct container width.
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? LineNumberTextView,
              textView.string != text else { return }
        applyContent(to: textView)
    }

    private func applyContent(to textView: NSTextView) {
        textView.string = text
        if let storage = textView.textStorage {
            SourceHighlighter.highlight(storage, language: language)
        }
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
    let title: String
    let content: String
    let language: SourceLanguage

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            SourceTextView(text: content, language: language)
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
            Text(language.displayName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor))
    }
}
