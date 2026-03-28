import SwiftUI
import AppKit

enum ChromePalette {
    static var navigationBackground: Color { Color(nsColor: navigationBackgroundNS) }
    static var toolbarBackground: Color { Color(nsColor: toolbarBackgroundNS) }
    static var selectedTabBackground: Color { toolbarBackground }
    static var tabHoverBackground: Color { Color(nsColor: tabHoverBackgroundNS) }
    static var toolbarHoverBackground: Color { tabHoverBackground }
    static var divider: Color { Color(nsColor: dividerNS) }

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
}
