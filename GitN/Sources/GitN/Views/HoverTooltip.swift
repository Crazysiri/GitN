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

private final class HoverTooltipPanel: NSPanel {
    static let shared = HoverTooltipPanel()

    private let hostingView = NSHostingView(rootView: HoverTooltipBubble(text: ""))
    private var pendingShow: DispatchWorkItem?
    /// The anchorView that owns the current pendingShow work item, used to
    /// decide whether cancelAndHide should cancel the in-flight show.
    private weak var pendingShowAnchor: NSView?
    private var pendingHide: DispatchWorkItem?
    /// Timestamp of the last successful present(); used to let hide closures
    /// detect that a newer show happened after they were scheduled.
    private var lastPresentDate: Date = .distantPast

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
        // Cancel any scheduled hide — a new hover-in wins.
        pendingHide?.cancel()
        pendingHide = nil
        pendingShow?.cancel()

        // Track which view owns this pending show so cancelAndHide can decide
        // whether to cancel it (same element quick-exit) or leave it alive
        // (adjacent element's incoming show).
        pendingShowAnchor = anchorView

        let item = DispatchWorkItem { [weak self, weak anchorView] in
            guard let self, let anchorView else { return }
            self.pendingShow = nil
            self.pendingShowAnchor = nil
            self.lastPresentDate = Date()
            self.present(text: text, placement: placement, from: anchorView)
        }
        pendingShow = item
        // When already visible (tab-to-tab), update quickly; otherwise use the
        // standard initial-show delay so we don't flash on quick mouse passes.
        let delay: TimeInterval = isVisible ? 0.05 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancelAndHide(from callerAnchor: NSView? = nil) {
        pendingHide?.cancel()
        pendingHide = nil

        guard isVisible else {
            // Tooltip never appeared — safe to cancel the pending show outright.
            pendingShow?.cancel()
            pendingShow = nil
            pendingShowAnchor = nil
            return
        }

        // If the caller is the same element that owns the in-flight pendingShow,
        // cancel it now. This closes the race where a quick hover-in/out causes
        // pendingShow to fire *after* cancelAndHide captures snapDate, updating
        // lastPresentDate to a time after snapDate and silently blocking the hide.
        //
        // If a *different* (adjacent) element owns pendingShow, leave it alive:
        // that element's scheduleShow has already cancelled the previous
        // pendingHide, so its upcoming present() will correctly take ownership.
        if let callerAnchor, pendingShowAnchor === callerAnchor {
            pendingShow?.cancel()
            pendingShow = nil
            pendingShowAnchor = nil
        }

        let snapDate = Date()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            // A present() that happened after we decided to hide means a new
            // element took over — don't dismiss.
            guard self.lastPresentDate <= snapDate else { return }
            self.orderOut(nil)
        }
        pendingHide = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
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
                HoverTooltipPanel.shared.cancelAndHide(from: anchorView)
            }
    }

    private func updateTooltip(isHovering: Bool) {
        guard isEnabled, isHovering, let anchorView else {
            HoverTooltipPanel.shared.cancelAndHide(from: anchorView)
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
