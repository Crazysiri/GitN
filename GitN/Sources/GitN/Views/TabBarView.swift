import SwiftUI
import AppKit
import MarkdownUI

struct TabBarView: View {
    @Environment(AppModel.self) private var appModel
    @State private var windowWidth: CGFloat = 1100
    @State private var hostingWindow: NSWindow? = nil
    @State private var isHoveringAddButton = false

    // Drag-to-reorder state
    @State private var dragState = TabDragState()

    private enum Layout {
        static let barHeight: CGFloat = 43
        static let trailingControlsWidth: CGFloat = 30
        static let trailingGap: CGFloat = 10
        static let addButtonSize = CGSize(width: 22, height: 22)
        static let maxTabWidth: CGFloat = 220
        static let contentHorizontalPadding: CGFloat = 10
        static let maxToolbarFraction: CGFloat = 0.68
        static let tabCornerRadius: CGFloat = 7
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
                        let isDragging = dragState.draggingTabID == tab.id && dragState.phase == .dragging
                        let visualOffset = computeVisualOffset(for: tab, at: index, tabWidths: tabWidths)

                        TabItemView(
                            tab: tab,
                            isSelected: tab.id == appModel.selectedTabID,
                            maxWidth: tabWidths[index],
                            isDragActive: isDragging,
                            onSelect: {
                                appModel.selectedTabID = tab.id
                                appModel.showNewTab = false
                            },
                            onClose: { appModel.closeTab(tab.id) }
                        )
                        .offset(x: visualOffset)
                        .zIndex(isDragging ? 100 : 0)
                        .animation(isDragging ? nil : .easeInOut(duration: 0.2), value: visualOffset)
                        .simultaneousGesture(
                            tabDragGesture(for: tab, index: index, tabWidths: tabWidths)
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
            .hoverTooltip("New Tab", placement: .below)
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

    // MARK: - Drag Gesture (long-press activated via timer)

    /// A DragGesture that only activates reorder mode after being held for 0.6s.
    /// Before that threshold, dragging is a no-op and normal clicks pass through.
    private func tabDragGesture(for tab: RepoTab, index: Int, tabWidths: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let elapsed = Date().timeIntervalSince(value.time)

                if dragState.phase == .idle {
                    // Check if we've been pressing long enough
                    if elapsed >= 0.6 {
                        // Activate drag
                        NSCursor.closedHand.push()
                        dragState.phase = .dragging
                        dragState.draggingTabID = tab.id
                        dragState.startX = value.startLocation.x
                        dragState.currentOffset = value.translation.width
                    }
                    // Otherwise still waiting — do nothing (no visual effect)
                } else if dragState.phase == .dragging && dragState.draggingTabID == tab.id {
                    // Already dragging — update offset
                    dragState.currentOffset = value.translation.width
                }
            }
            .onEnded { value in
                guard dragState.phase == .dragging, dragState.draggingTabID == tab.id else {
                    // Was never activated — this was a short press, ignore
                    dragState.reset()
                    return
                }

                // Compute destination
                let currentIndex = appModel.tabs.firstIndex(where: { $0.id == tab.id }) ?? index
                let destIndex = dragState.proposedDestinationIndex(
                    dragIndex: currentIndex,
                    tabWidths: tabWidths
                )

                withAnimation(.easeOut(duration: 0.2)) {
                    dragState.reset()
                }

                if destIndex != currentIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        appModel.moveTab(fromIndex: currentIndex, toIndex: destIndex)
                    }
                }

                NSCursor.pop()
            }
    }

    /// Compute visual X offset for each tab during drag
    private func computeVisualOffset(for tab: RepoTab, at index: Int, tabWidths: [CGFloat]) -> CGFloat {
        guard dragState.phase == .dragging, let dragID = dragState.draggingTabID else { return 0 }

        if tab.id == dragID {
            return dragState.currentOffset
        }

        guard let dragIndex = appModel.tabs.firstIndex(where: { $0.id == dragID }) else { return 0 }
        let proposedSlot = dragState.proposedDestinationIndex(
            dragIndex: dragIndex,
            tabWidths: tabWidths
        )

        if dragIndex < index && index <= proposedSlot {
            return -tabWidths[dragIndex]
        } else if dragIndex > index && index >= proposedSlot {
            return tabWidths[dragIndex]
        }

        return 0
    }

    private func resolvedTabWidths(for availableWidth: CGFloat) -> [CGFloat] {
        appModel.tabs.map(idealWidth(for:))
    }

    private static let tabLabelFont = AppTypography.Chrome.tabLabelNS

    private func idealWidth(for tab: RepoTab) -> CGFloat {
        let displayName = String(tab.name.prefix(Layout.maxVisibleCharacters))
        let textWidth = (displayName as NSString).size(withAttributes: [.font: Self.tabLabelFont]).width
        return min(Layout.maxTabWidth, Layout.tabChromeOverhead + ceil(textWidth))
    }
}

// MARK: - Drag State

struct TabDragState {
    enum Phase {
        case idle
        case dragging
    }

    var phase: Phase = .idle
    var draggingTabID: UUID? = nil
    var currentOffset: CGFloat = 0
    var startX: CGFloat = 0

    mutating func reset() {
        phase = .idle
        draggingTabID = nil
        currentOffset = 0
        startX = 0
    }

    func proposedDestinationIndex(dragIndex: Int, tabWidths: [CGFloat]) -> Int {
        var originX: CGFloat = 0
        for i in 0..<dragIndex {
            originX += tabWidths[i]
        }
        let draggedCenter = originX + tabWidths[dragIndex] / 2 + currentOffset

        var slotX: CGFloat = 0
        for i in 0..<tabWidths.count {
            let slotEnd = slotX + tabWidths[i]
            if draggedCenter < slotEnd {
                return i
            }
            slotX = slotEnd
        }
        return tabWidths.count - 1
    }
}

// MARK: - Helpers

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

// MARK: - Tab Item

struct TabItemView: View {
    private static let tabCornerRadius: CGFloat = 7
    private static let topInset: CGFloat = 3
    private static let innerHeight: CGFloat = 40

    let tab: RepoTab
    let isSelected: Bool
    let maxWidth: CGFloat
    var isDragActive: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .leading) {
            if !isSelected && !isDragActive {
                TabDivider()
                    .padding(.vertical, 6)
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
        .frame(width: maxWidth, height: 43, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .scaleEffect(isDragActive ? 1.05 : 1.0)
        .shadow(color: isDragActive ? Color.black.opacity(0.4) : .clear, radius: isDragActive ? 8 : 0, y: 2)
        .opacity(isDragActive ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDragActive)
        .hoverTooltip(tooltipText, placement: .below)
    }

    private var tooltipText: String {
        "\(tab.name)\n\(tab.path)"
    }

    private var backgroundColor: Color {
        if isDragActive {
            return ChromePalette.toolbarBackground
        }
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
