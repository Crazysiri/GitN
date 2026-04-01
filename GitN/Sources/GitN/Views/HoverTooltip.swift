import SwiftUI
import AppKit

// MARK: - Host lifecycle (e.g. tab stack: cached inactive repo panes never disappear / never get hover-exit)

private struct HoverTooltipHostActiveKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

extension EnvironmentValues {
    /// `RepoContainerView` sets this from `isActive`. Default `true` for UI not under the tab stack.
    var hoverTooltipHostActive: Bool {
        get { self[HoverTooltipHostActiveKey.self] }
        set { self[HoverTooltipHostActiveKey.self] = newValue }
    }
}

// MARK: - Tooltip UI

enum HoverTooltipPlacement {
    case above
    case below
}

struct HoverTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 400, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.separatorColor).opacity(0.55), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
            .allowsHitTesting(false)
    }
}

// MARK: - Anchor (layout only; hits pass through to `content`)

private struct HoverTooltipAnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView)
        }
    }
}

// MARK: - Panel (one per `.hoverTooltip`)

private final class HoverTooltipPanel: NSPanel {
    private let hostingView = NSHostingView(rootView: HoverTooltipBubble(text: ""))
    private var pendingShow: DispatchWorkItem?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func scheduleShow(text: String, placement: HoverTooltipPlacement, from anchorView: NSView) {
        pendingShow?.cancel()
        let item = DispatchWorkItem { [weak self, weak anchorView] in
            guard let self, let anchorView, anchorView.window != nil else { return }
            self.pendingShow = nil
            self.present(text: text, placement: placement, from: anchorView)
        }
        pendingShow = item
        let delay: TimeInterval = isVisible ? 0.05 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancelAndHide() {
        pendingShow?.cancel()
        pendingShow = nil
        if isVisible {
            orderOut(nil)
        }
    }

    private func present(text: String, placement: HoverTooltipPlacement, from anchorView: NSView) {
        guard let window = anchorView.window else { return }

        hostingView.rootView = HoverTooltipBubble(text: text)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let panelSize = CGSize(width: fittingSize.width, height: fittingSize.height)

        let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRectOnScreen = window.convertToScreen(anchorRectInWindow)
        let gap: CGFloat = 6

        let originX = anchorRectOnScreen.midX - panelSize.width / 2
        let originY: CGFloat
        switch placement {
        case .above:
            originY = anchorRectOnScreen.maxY + gap
        case .below:
            originY = anchorRectOnScreen.minY - panelSize.height - gap
        }

        setContentSize(panelSize)
        setFrameOrigin(NSPoint(x: originX, y: originY))
        if !isVisible {
            orderFront(nil)
        }
    }
}

private final class HoverTooltipPanelController: ObservableObject {
    let panel: HoverTooltipPanel

    init() {
        panel = HoverTooltipPanel()
    }

    deinit {
        DispatchQueue.main.async { [panel] in
            panel.orderOut(nil)
        }
    }
}

private struct HoverTooltipModifier: ViewModifier {
    let text: String
    let placement: HoverTooltipPlacement
    let isEnabled: Bool

    @Environment(\.hoverTooltipHostActive) private var hoverTooltipHostActive
    @StateObject private var panelController = HoverTooltipPanelController()
    @State private var isHovering = false
    @State private var anchorView: NSView?

    func body(content: Content) -> some View {
        content
            .overlay(
                HoverTooltipAnchorView { anchorView = $0 }
                    .allowsHitTesting(false)
            )
            .onHover { hovering in
                isHovering = hovering
                syncTooltip()
            }
            .onChange(of: text) { _, _ in
                syncTooltip()
            }
            .onChange(of: isEnabled) { _, _ in
                syncTooltip()
            }
            .onChange(of: hoverTooltipHostActive) { _, _ in
                syncTooltip()
            }
            .onDisappear {
                panelController.panel.cancelAndHide()
            }
    }

    private func syncTooltip() {
        let panel = panelController.panel
        guard hoverTooltipHostActive, isEnabled, isHovering, let anchorView else {
            panel.cancelAndHide()
            return
        }
        panel.scheduleShow(text: text, placement: placement, from: anchorView)
    }
}

extension View {
    func hoverTooltip(
        _ text: String,
        placement: HoverTooltipPlacement = .above,
        isEnabled: Bool = true
    ) -> some View {
        modifier(HoverTooltipModifier(text: text, placement: placement, isEnabled: isEnabled))
    }
}
