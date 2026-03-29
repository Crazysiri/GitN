import SwiftUI
import AppKit

enum ChromePalette {
    static var navigationBackground: Color { Color(nsColor: navigationBackgroundNS) }
    static var toolbarBackground: Color { Color(nsColor: toolbarBackgroundNS) }
    static var selectedTabBackground: Color { toolbarBackground }
    static var tabHoverBackground: Color { Color(nsColor: tabHoverBackgroundNS) }
    static var toolbarHoverBackground: Color { tabHoverBackground }
    static var divider: Color { Color(nsColor: dividerNS) }
    static var panelBackground: Color { Color(nsColor: panelBackgroundNS) }
    static var panelBackgroundNSColor: NSColor { panelBackgroundNS }
    static var panelMutedBackground: Color { Color(nsColor: panelMutedBackgroundNS) }
    static var panelMutedBackgroundNSColor: NSColor { panelMutedBackgroundNS }
    static var panelOverlay: Color { Color(nsColor: panelOverlayNS) }
    static var panelOverlayNSColor: NSColor { panelOverlayNS }
    static var panelBorder: Color { Color(nsColor: panelBorderNS) }
    static var panelBorderNSColor: NSColor { panelBorderNS }
    static var panelGutterBackground: Color { Color(nsColor: panelGutterBackgroundNS) }
    static var panelGutterBackgroundNSColor: NSColor { panelGutterBackgroundNS }
    static var panelGutterSeparator: Color { Color(nsColor: panelGutterSeparatorNS) }
    static var panelGutterSeparatorNSColor: NSColor { panelGutterSeparatorNS }
    static var terminalAccent: Color { Color(nsColor: terminalAccentNS) }
    static var terminalAccentNSColor: NSColor { terminalAccentNS }
    static var terminalPrimaryText: Color { Color(nsColor: terminalPrimaryTextNS) }
    static var terminalPrimaryTextNSColor: NSColor { terminalPrimaryTextNS }
    static var terminalSecondaryText: Color { Color(nsColor: terminalSecondaryTextNS) }
    static var terminalSecondaryTextNSColor: NSColor { terminalSecondaryTextNS }
    static var markdownHeadingNSColor: NSColor { markdownHeadingNS }
    static var markdownCodeNSColor: NSColor { markdownCodeNS }
    static var chromeButtonBorder: Color { Color(nsColor: chromeButtonBorderNS) }
    static var chromeButtonFill: Color { Color(nsColor: chromeButtonFillNS) }
    static var chromeButtonHoverBorder: Color { Color(nsColor: chromeButtonHoverBorderNS) }
    static var chromeButtonHoverFill: Color { Color(nsColor: chromeButtonHoverFillNS) }
    static var reflogAccent: Color { Color(nsColor: reflogAccentNS) }
    static var reflogToggleBorder: Color { Color(nsColor: reflogToggleBorderNS) }
    static var reflogToggleFill: Color { Color(nsColor: reflogToggleFillNS) }
    static var monacoUsesDarkAppearance: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static var navigationBackgroundNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1)
            default:
                return NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
            }
        }
    }

    private static var toolbarBackgroundNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
            default:
                return NSColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
            }
        }
    }

    private static var tabHoverBackgroundNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor(red: 0.89, green: 0.89, blue: 0.91, alpha: 1)
            default:
                return NSColor(red: 0.19, green: 0.20, blue: 0.23, alpha: 1)
            }
        }
    }

    private static var dividerNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor.black.withAlphaComponent(0.08)
            default:
                return NSColor.white.withAlphaComponent(0.10)
            }
        }
    }

    private static var panelBackgroundNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return .windowBackgroundColor
            default:
                return NSColor(red: 0.118, green: 0.125, blue: 0.145, alpha: 1)
            }
        }
    }

    private static var panelMutedBackgroundNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return toolbarBackgroundNS
            default:
                return NSColor.black.withAlphaComponent(0.16)
            }
        }
    }

    private static var panelOverlayNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor.black.withAlphaComponent(0.12)
            default:
                return NSColor.black.withAlphaComponent(0.34)
            }
        }
    }

    private static var panelBorderNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor.black.withAlphaComponent(0.08)
            default:
                return NSColor.white.withAlphaComponent(0.08)
            }
        }
    }

    private static var panelGutterBackgroundNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return toolbarBackgroundNS
            default:
                return NSColor(red: 0.094, green: 0.098, blue: 0.110, alpha: 1)
            }
        }
    }

    private static var panelGutterSeparatorNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return dividerNS
            default:
                return NSColor.white.withAlphaComponent(0.06)
            }
        }
    }

    private static var terminalAccentNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return .controlAccentColor
            default:
                return .systemGreen
            }
        }
    }

    private static var terminalPrimaryTextNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return .labelColor
            default:
                return NSColor.white.withAlphaComponent(0.8)
            }
        }
    }

    private static var terminalSecondaryTextNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return .secondaryLabelColor
            default:
                return NSColor.white.withAlphaComponent(0.5)
            }
        }
    }

    private static var markdownHeadingNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor.controlAccentColor.shadow(withLevel: 0.18) ?? NSColor.controlAccentColor
            default:
                return NSColor.controlAccentColor.highlight(withLevel: 0.14) ?? NSColor.controlAccentColor
            }
        }
    }

    private static var markdownCodeNS: NSColor {
        NSColor(name: nil) { appearance in
            let accent = NSColor.controlAccentColor
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return accent.shadow(withLevel: 0.28) ?? accent
            default:
                return accent.highlight(withLevel: 0.22) ?? accent
            }
        }
    }

    private static var chromeButtonBorderNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor.black.withAlphaComponent(0.14)
            default:
                return NSColor.white.withAlphaComponent(0.18)
            }
        }
    }

    private static var chromeButtonFillNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor.white.withAlphaComponent(0.42)
            default:
                return NSColor.white.withAlphaComponent(0.05)
            }
        }
    }

    private static var chromeButtonHoverBorderNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor.black.withAlphaComponent(0.20)
            default:
                return NSColor.white.withAlphaComponent(0.28)
            }
        }
    }

    private static var chromeButtonHoverFillNS: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return NSColor.white.withAlphaComponent(0.68)
            default:
                return NSColor.white.withAlphaComponent(0.10)
            }
        }
    }

    private static var reflogAccentNS: NSColor {
        NSColor(name: nil) { appearance in
            let accent = NSColor.controlAccentColor
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return accent.highlight(withLevel: 0.04) ?? accent
            default:
                return accent.shadow(withLevel: 0.04) ?? accent
            }
        }
    }

    private static var reflogToggleBorderNS: NSColor {
        NSColor(name: nil) { appearance in
            let accent = NSColor.controlAccentColor
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return accent.withAlphaComponent(0.36)
            default:
                return accent.withAlphaComponent(0.46)
            }
        }
    }

    private static var reflogToggleFillNS: NSColor {
        NSColor(name: nil) { appearance in
            let accent = NSColor.controlAccentColor
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return accent.withAlphaComponent(0.12)
            default:
                return accent.withAlphaComponent(0.18)
            }
        }
    }
}
