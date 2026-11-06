import Foundation

/// User-configurable terminal options, persisted in UserDefaults. Defaults match
/// SPEC §9. Changing font/cursor/scrollback only re-themes/fits the renderer; it
/// never restarts a running PTY (applied to new sessions and pushed live where
/// the renderer supports it).
struct TerminalSettings: Equatable {
    var fontSize: Int
    var lineHeight: Double
    var cursorStyle: String   // "bar" | "block" | "underline"
    var scrollback: Int
    var suggestionsEnabled: Bool
    var tabMode: String       // "DEFAULT" | "ENTER" | "NAVIGATION"

    static let fontSizeRange = 8...72
    static let lineHeightRange = 1.0...2.0
    static let cursorStyles = ["bar", "block", "underline"]
    static let tabModes = ["DEFAULT", "ENTER", "NAVIGATION"]

    static let `default` = TerminalSettings(
        fontSize: 12,
        lineHeight: 1.2,
        cursorStyle: "bar",
        scrollback: 5000,
        suggestionsEnabled: true,
        tabMode: "NAVIGATION"
    )

    private enum Key {
        static let fontSize = "GitN.terminal.fontSize"
        static let lineHeight = "GitN.terminal.lineHeight"
        static let cursorStyle = "GitN.terminal.cursorStyle"
        static let scrollback = "GitN.terminal.scrollback"
        static let suggestions = "GitN.terminal.suggestionsEnabled"
        static let tabMode = "GitN.terminal.tabMode"
    }

    static func load(from defaults: UserDefaults = .standard) -> TerminalSettings {
        var s = TerminalSettings.default
        if defaults.object(forKey: Key.fontSize) != nil {
            s.fontSize = clampFontSize(defaults.integer(forKey: Key.fontSize))
        }
        if defaults.object(forKey: Key.lineHeight) != nil {
            s.lineHeight = clampLineHeight(defaults.double(forKey: Key.lineHeight))
        }
        if let style = defaults.string(forKey: Key.cursorStyle), cursorStyles.contains(style) {
            s.cursorStyle = style
        }
        if defaults.object(forKey: Key.scrollback) != nil {
            s.scrollback = max(100, defaults.integer(forKey: Key.scrollback))
        }
        if defaults.object(forKey: Key.suggestions) != nil {
            s.suggestionsEnabled = defaults.bool(forKey: Key.suggestions)
        }
        if let mode = defaults.string(forKey: Key.tabMode), tabModes.contains(mode) {
            s.tabMode = mode
        }
        return s
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(fontSize, forKey: Key.fontSize)
        defaults.set(lineHeight, forKey: Key.lineHeight)
        defaults.set(cursorStyle, forKey: Key.cursorStyle)
        defaults.set(scrollback, forKey: Key.scrollback)
        defaults.set(suggestionsEnabled, forKey: Key.suggestions)
        defaults.set(tabMode, forKey: Key.tabMode)
    }

    static func clampFontSize(_ value: Int) -> Int {
        min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    static func clampLineHeight(_ value: Double) -> Double {
        min(max(value, lineHeightRange.lowerBound), lineHeightRange.upperBound)
    }

    /// The JSON options object passed to `window.gitnXterm.start`.
    var startOptionsDictionary: [String: Any] {
        [
            "fontSize": fontSize,
            "lineHeight": lineHeight,
            "cursorStyle": cursorStyle,
            "scrollback": scrollback,
            "suggestionsEnabled": suggestionsEnabled,
            "tabMode": tabMode,
        ]
    }
}
