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
        static let minTabWidth: CGFloat = 110
        static let maxTabWidth: CGFloat = 200
        static let contentHorizontalPadding: CGFloat = 10
        static let maxToolbarFraction: CGFloat = 0.68
        static let tabCornerRadius: CGFloat = 7
        static let tabBaseWidth: CGFloat = 72
        static let characterWidth: CGFloat = 7.2
        static let maxVisibleCharacters = 20
    }

    var body: some View {
        let maxTabAreaWidth = max(Layout.minTabWidth, windowWidth * Layout.maxToolbarFraction)
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
                    .font(.system(size: 11, weight: .medium))
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
        guard !appModel.tabs.isEmpty else { return [] }

        let idealWidths = appModel.tabs.map(idealWidth(for:))
        let totalIdealWidth = idealWidths.reduce(0, +)
        guard totalIdealWidth > availableWidth else { return idealWidths }

        let minimumTotalWidth = CGFloat(appModel.tabs.count) * Layout.minTabWidth
        guard minimumTotalWidth < totalIdealWidth else {
            return Array(repeating: Layout.minTabWidth, count: appModel.tabs.count)
        }

        let compressionRatio = max(0, min(1, (availableWidth - minimumTotalWidth) / (totalIdealWidth - minimumTotalWidth)))
        return idealWidths.map { width in
            let compressed = Layout.minTabWidth + (width - Layout.minTabWidth) * compressionRatio
            return floor(compressed)
        }
    }

    private func idealWidth(for tab: RepoTab) -> CGFloat {
        let visibleCount = min(tab.name.count, Layout.maxVisibleCharacters)
        let estimated = Layout.tabBaseWidth + CGFloat(visibleCount) * Layout.characterWidth
        return min(Layout.maxTabWidth, max(Layout.minTabWidth, ceil(estimated)))
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
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("FEATURES.md")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
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
    private static let maxVisibleCharacters = 20

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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(displayTitle)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
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

    private var displayTitle: String {
        if tab.name.count <= Self.maxVisibleCharacters { return tab.name }
        return String(tab.name.prefix(Self.maxVisibleCharacters))
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
