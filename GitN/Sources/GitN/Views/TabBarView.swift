import SwiftUI
import AppKit
import MarkdownUI

struct TabBarView: View {
    @Environment(AppModel.self) private var appModel
    @State private var windowWidth: CGFloat = 1100
    @State private var hostingWindow: NSWindow? = nil
    @State private var isHoveringAddButton = false

    private enum Layout {
        static let barHeight: CGFloat = 47
        static let trailingControlsWidth: CGFloat = 30
        static let trailingGap: CGFloat = 10
        static let addButtonSize = CGSize(width: 24, height: 24)
        static let maxTabWidth: CGFloat = 220
        static let contentHorizontalPadding: CGFloat = 10
        static let maxToolbarFraction: CGFloat = 0.68
        static let tabCornerRadius: CGFloat = 7
        /// Fixed chrome overhead: left-pad(12) + SF-symbol(~20) + spacing(8) + spacing(8) + close(16) + right-pad(12) + safety(8)
        static let tabChromeOverhead: CGFloat = 84
        static let maxVisibleCharacters = 20
    }

    var body: some View {
        let maxTabAreaWidth = windowWidth * Layout.maxToolbarFraction
        let tabWidths = resolvedTabWidths(for: maxTabAreaWidth)
        let totalTabsWidth = tabWidths.reduce(0, +)
        let visibleTabAreaWidth = min(maxTabAreaWidth, totalTabsWidth + Layout.contentHorizontalPadding + 1)
        let toolbarWidth = visibleTabAreaWidth + Layout.trailingGap + Layout.trailingControlsWidth

        HStack(spacing: Layout.trailingGap) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(zip(appModel.tabs.indices, appModel.tabs)), id: \.1.id) { index, tab in
                        TabItemView(
                            tab: tab,
                            isSelected: tab.id == appModel.selectedTabID,
                            maxWidth: tabWidths[index],
                            onSelect: {
                                appModel.selectedTabID = tab.id
                                appModel.showNewTab = false
                            },
                            onClose: { appModel.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.leading, 1)
                .padding(.trailing, Layout.contentHorizontalPadding)
            }
            .frame(width: visibleTabAreaWidth, alignment: .leading)

            Button(action: { appModel.showNewTabView() }) {
                Image(systemName: "plus")
                    .font(AppTypography.Chrome.tabIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: Layout.addButtonSize.width, height: Layout.addButtonSize.height)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHoveringAddButton ? ChromePalette.chromeButtonHoverFill : ChromePalette.chromeButtonFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                isHoveringAddButton ? ChromePalette.chromeButtonHoverBorder : ChromePalette.chromeButtonBorder,
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: Layout.trailingControlsWidth, height: Layout.barHeight)
            .onHover { isHoveringAddButton = $0 }
        }
        .frame(width: toolbarWidth, height: Layout.barHeight, alignment: .leading)
        .background(ChromePalette.navigationBackground)
        .background(
            HostingWindowAccessor { window in
                guard hostingWindow == nil, let window else { return }
                hostingWindow = window
                windowWidth = window.frame.width
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window === hostingWindow else { return }
            windowWidth = window.frame.width
        }
    }

    private func resolvedTabWidths(for availableWidth: CGFloat) -> [CGFloat] {
        appModel.tabs.map(idealWidth(for:))
    }

    private static let tabLabelFont = AppTypography.Chrome.tabLabelNS

    private func idealWidth(for tab: RepoTab) -> CGFloat {
        let displayName = String(tab.name.prefix(Layout.maxVisibleCharacters))
        let textWidth = (displayName as NSString).size(withAttributes: [.font: Self.tabLabelFont]).width
        // Pure content-driven width — no minTabWidth floor applied here.
        // minTabWidth is only a compression floor in resolvedTabWidths.
        return min(Layout.maxTabWidth, Layout.tabChromeOverhead + ceil(textWidth))
    }
}

private struct HostingWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}

private struct TabDivider: View {
    var body: some View {
        Rectangle()
            .fill(ChromePalette.divider)
            .frame(width: 1)
    }
}

// MARK: - Features sheet

struct FeaturesView: View {
    @Environment(ThemeManager.self) private var theme
    let content: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(AppTypography.Chrome.toolbarTitle)
                    .foregroundStyle(.secondary)
                Text("FEATURES.md")
                    .font(AppTypography.Chrome.toolbarTitle)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .hoverTooltip("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.windowBackgroundColor))

            Divider()

            ScrollView {
                Markdown(content)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .preferredColorScheme(theme.preferredColorScheme)
    }
}

// MARK: -

struct TabItemView: View {
    private static let tabCornerRadius: CGFloat = 7
    private static let topInset: CGFloat = 5
    private static let innerHeight: CGFloat = 42

    let tab: RepoTab
    let isSelected: Bool
    let maxWidth: CGFloat
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .leading) {
            if !isSelected {
                TabDivider()
                    .padding(.vertical, 7)
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(AppTypography.Chrome.tabIcon)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(tab.name)
                    .font(AppTypography.Chrome.tabLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(AppTypography.Chrome.tabClose)
                        .foregroundStyle(closeIconColor)
                        .frame(width: 16, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill((isHovering || isSelected) ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.innerHeight)
            .background(tabShape.fill(backgroundColor))
        }
        .padding(.top, Self.topInset)
        .frame(width: maxWidth, height: 47, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .hoverTooltip(tooltipText, placement: .below)
    }

    private var tooltipText: String {
        "\(tab.name)\n\(tab.path)"
    }

    private var backgroundColor: Color {
        if isSelected {
            return ChromePalette.selectedTabBackground
        }
        if isHovering {
            return ChromePalette.tabHoverBackground
        }
        return ChromePalette.navigationBackground
    }

    private var closeIconColor: Color {
        isSelected ? Color.primary.opacity(0.8) : Color.secondary
    }

    private var tabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.tabCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Self.tabCornerRadius
        )
    }
}
