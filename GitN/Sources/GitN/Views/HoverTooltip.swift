import SwiftUI
import AppKit

enum HoverTooltipPlacement {
    case above
    case below
}

struct HoverTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 240, alignment: .leading)
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

private final class HoverTooltipPanel: NSPanel {
    static let shared = HoverTooltipPanel()

    private let hostingView = NSHostingView(rootView: HoverTooltipBubble(text: ""))
    private var pendingShow: DispatchWorkItem?

    private init() {
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

    func scheduleShow(text: String, placement: HoverTooltipPlacement, from anchorView: NSView) {
        pendingShow?.cancel()
        let item = DispatchWorkItem { [weak self, weak anchorView] in
            guard let self, let anchorView else { return }
            self.present(text: text, placement: placement, from: anchorView)
        }
        pendingShow = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
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

private struct HoverTooltipModifier: ViewModifier {
    let text: String
    let placement: HoverTooltipPlacement
    let isEnabled: Bool

    @State private var isHovering = false
    @State private var anchorView: NSView?

    func body(content: Content) -> some View {
        content
            .background(
                HoverTooltipAnchorView { anchorView = $0 }
                    .frame(width: 0, height: 0)
            )
            .onHover { isHovering = $0 }
            .onChange(of: isHovering) { _, hovering in
                updateTooltip(isHovering: hovering)
            }
            .onChange(of: text) { _, _ in
                updateTooltip(isHovering: isHovering)
            }
            .onDisappear {
                HoverTooltipPanel.shared.cancelAndHide()
            }
    }

    private func updateTooltip(isHovering: Bool) {
        guard isEnabled, isHovering, let anchorView else {
            HoverTooltipPanel.shared.cancelAndHide()
            return
        }
        HoverTooltipPanel.shared.scheduleShow(text: text, placement: placement, from: anchorView)
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
