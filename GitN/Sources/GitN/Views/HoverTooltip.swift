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
    case leading
}

enum HoverTooltipTextStyle {
    case standard
    case plain
}

struct HoverTooltipBubble: View {
    let text: String
    let style: HoverTooltipTextStyle

    private var titleLine: String {
        let lines = normalizedLines
        return lines.first ?? text
    }

    private var detailLines: [String] {
        Array(normalizedLines.dropFirst())
    }

    private var normalizedLines: [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
    }

    var body: some View {
        Group {
            if style == .plain {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(normalizedLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: detailLines.isEmpty ? 0 : 4) {
                    Text(titleLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if !detailLines.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(detailLines.prefix(4).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 400, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
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
    private let hostingView = NSHostingView(rootView: HoverTooltipBubble(text: "", style: .standard))

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

    func cancelAndHide() {
        if isVisible {
            orderOut(nil)
        }
    }

    func present(text: String, style: HoverTooltipTextStyle, placement: HoverTooltipPlacement, from anchorView: NSView) {
        guard let window = anchorView.window else { return }

        hostingView.rootView = HoverTooltipBubble(text: text, style: style)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let panelSize = CGSize(width: fittingSize.width, height: fittingSize.height)

        let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRectOnScreen = window.convertToScreen(anchorRectInWindow)
        let gap: CGFloat = 6

        let originX: CGFloat
        let originY: CGFloat
        switch placement {
        case .above:
            originX = anchorRectOnScreen.midX - panelSize.width / 2
            originY = anchorRectOnScreen.maxY + gap
        case .below:
            originX = anchorRectOnScreen.midX - panelSize.width / 2
            originY = anchorRectOnScreen.minY - panelSize.height - gap
        case .leading:
            originX = anchorRectOnScreen.minX - panelSize.width - gap
            originY = anchorRectOnScreen.midY - panelSize.height / 2
        }

        setContentSize(panelSize)
        setFrameOrigin(NSPoint(x: originX, y: originY))
        if !isVisible {
            orderFront(nil)
        }
    }
}

final class HoverTooltipPanelController: ObservableObject {
    private var panel: HoverTooltipPanel?
    private var pendingShow: DispatchWorkItem?

    var hasCreatedPanel: Bool { panel != nil }

    func scheduleShow(text: String, style: HoverTooltipTextStyle, placement: HoverTooltipPlacement, from anchorView: NSView) {
        pendingShow?.cancel()
        let item = DispatchWorkItem { [weak self, weak anchorView] in
            guard let self, let anchorView, anchorView.window != nil else { return }
            self.pendingShow = nil
            let panel = self.panel ?? HoverTooltipPanel()
            self.panel = panel
            panel.present(text: text, style: style, placement: placement, from: anchorView)
        }
        pendingShow = item
        let delay: TimeInterval = panel?.isVisible == true ? 0.05 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancelAndHide() {
        pendingShow?.cancel()
        pendingShow = nil
        panel?.cancelAndHide()
    }

    deinit {
        pendingShow?.cancel()
        if let panel {
            DispatchQueue.main.async {
                panel.orderOut(nil)
            }
        }
    }
}

private struct HoverTooltipModifier: ViewModifier {
    let text: String
    let style: HoverTooltipTextStyle
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
                panelController.cancelAndHide()
            }
    }

    private func syncTooltip() {
        guard hoverTooltipHostActive, isEnabled, isHovering, let anchorView else {
            panelController.cancelAndHide()
            return
        }
        panelController.scheduleShow(text: text, style: style, placement: placement, from: anchorView)
    }
}

extension View {
    func hoverTooltip(
        _ text: String,
        style: HoverTooltipTextStyle = .standard,
        placement: HoverTooltipPlacement = .above,
        isEnabled: Bool = true
    ) -> some View {
        modifier(HoverTooltipModifier(text: text, style: style, placement: placement, isEnabled: isEnabled))
    }
}
