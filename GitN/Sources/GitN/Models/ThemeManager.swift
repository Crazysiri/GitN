import SwiftUI

enum AppTheme: String, CaseIterable {
    case dark, light, system

    var displayName: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
    }
}

@Observable
final class ThemeManager {
    private static let key = "GitN.appTheme"

    var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.key)
            apply()
        }
    }

    var isDark: Bool {
        switch currentTheme {
        case .dark: true
        case .light: false
        case .system:
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.key),
           let theme = AppTheme(rawValue: saved) {
            currentTheme = theme
        } else {
            currentTheme = .dark
        }
    }

    func apply() {
        NSApp.appearance = currentTheme.nsAppearance
    }

    /// Apply saved theme before any window is created (call from AppDelegate).
    static func applyInitialTheme() {
        let rawValue = UserDefaults.standard.string(forKey: key) ?? AppTheme.dark.rawValue
        let theme = AppTheme(rawValue: rawValue) ?? .dark
        NSApp.appearance = theme.nsAppearance
    }
}
