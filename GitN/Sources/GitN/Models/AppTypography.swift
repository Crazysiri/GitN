import SwiftUI
import AppKit

enum AppTypography {
    private static let bump: CGFloat = 1

    private static func size(_ base: CGFloat) -> CGFloat {
        base + bump
    }

    enum Chrome {
        static let tabLabel = Font.system(size: AppTypography.size(12), weight: .regular)
        static let tabIcon = Font.system(size: AppTypography.size(11), weight: .medium)
        static let tabClose = Font.system(size: AppTypography.size(9), weight: .semibold)
        static let tabLabelNS = NSFont.systemFont(ofSize: AppTypography.size(12), weight: .regular)

        static let toolbarTitle = Font.system(size: AppTypography.size(12), weight: .semibold)
        static let toolbarBody = Font.system(size: AppTypography.size(11), weight: .medium)
        static let toolbarMeta = Font.system(size: AppTypography.size(10))
        static let toolbarBadge = Font.system(size: AppTypography.size(9), weight: .medium)
        static let toolbarIcon = Font.system(size: AppTypography.size(12), weight: .semibold)
        static let toolbarMiniLabel = Font.system(size: AppTypography.size(8))
    }

    enum Sidebar {
        static let sectionHeader = Font.system(size: AppTypography.size(10), weight: .semibold)
        static let sectionCount = Font.system(size: AppTypography.size(9))
        static let sectionChevron = Font.system(size: AppTypography.size(8), weight: .bold)
        static let row = Font.system(size: AppTypography.size(11))
        static let rowEmphasis = Font.system(size: AppTypography.size(11), weight: .medium)
        static let rowMeta = Font.system(size: AppTypography.size(9))
        static let rowMetaStrong = Font.system(size: AppTypography.size(9), weight: .semibold)
        static let rowMono = Font.system(size: AppTypography.size(9), weight: .medium, design: .monospaced)
        static let rowMonoStrong = Font.system(size: AppTypography.size(9), weight: .semibold, design: .monospaced)
        static let rowMonoLarge = Font.system(size: AppTypography.size(11), weight: .medium, design: .monospaced)
        static let contextMenu = Font.system(size: AppTypography.size(11), weight: .medium)
    }

    enum Graph {
        static let header = Font.system(size: AppTypography.size(10), weight: .semibold)
        static let overlayTitle = Font.system(size: AppTypography.size(12), weight: .semibold)
        static let overlayBody = Font.system(size: AppTypography.size(10), weight: .medium)
        static let overlayAction = Font.system(size: AppTypography.size(11), weight: .semibold)
        static let loadingTitle = Font.system(size: AppTypography.size(16), weight: .semibold)
        static let loadingBody = Font.system(size: AppTypography.size(11), weight: .medium)
        static let editor = Font.system(size: AppTypography.size(12), design: .monospaced)

        static let conflictBannerNS = NSFont.systemFont(ofSize: AppTypography.size(11), weight: .medium)
        static let refBadgeNS = NSFont.systemFont(ofSize: AppTypography.size(9), weight: .medium)
        static let refBadgeStrongNS = NSFont.systemFont(ofSize: AppTypography.size(9), weight: .semibold)
        static let messageNS = NSFont.systemFont(ofSize: AppTypography.size(11))
        static let messageStrongNS = NSFont.systemFont(ofSize: AppTypography.size(11), weight: .medium)
        static let metaNS = NSFont.systemFont(ofSize: AppTypography.size(10))
        static let metaStrongNS = NSFont.systemFont(ofSize: AppTypography.size(9), weight: .semibold)
        static let metaMediumNS = NSFont.systemFont(ofSize: AppTypography.size(9), weight: .medium)
    }

    enum Detail {
        static let sectionTitle = Font.system(size: AppTypography.size(11), weight: .medium)
        static let commitLabel = Font.system(size: AppTypography.size(10))
        static let commitHash = Font.system(size: AppTypography.size(10), weight: .semibold, design: .monospaced)
        static let messageTitle = Font.system(size: AppTypography.size(12), weight: .semibold)
        static let body = Font.system(size: AppTypography.size(11))
        static let bodyMedium = Font.system(size: AppTypography.size(11), weight: .medium)
        static let meta = Font.system(size: AppTypography.size(10))
        static let metaStrong = Font.system(size: AppTypography.size(10), weight: .semibold)
        static let caption = Font.system(size: AppTypography.size(9))
        static let captionMedium = Font.system(size: AppTypography.size(9), weight: .medium)
        static let mono = Font.system(size: AppTypography.size(10), design: .monospaced)
        static let monoMedium = Font.system(size: AppTypography.size(10), weight: .medium, design: .monospaced)
        static let monoStrong = Font.system(size: AppTypography.size(10), weight: .semibold, design: .monospaced)
        static let titleFieldNS = NSFont.systemFont(ofSize: AppTypography.size(11), weight: .semibold)
        static let titleFieldRegularNS = NSFont.systemFont(ofSize: AppTypography.size(11))
        static let diffCodeNS = NSFont.monospacedSystemFont(ofSize: AppTypography.size(10), weight: .regular)
        static let diffPathNS = NSFont.monospacedSystemFont(ofSize: AppTypography.size(11), weight: .regular)
        static let textViewNS = NSFont.systemFont(ofSize: AppTypography.size(11))
    }
}
