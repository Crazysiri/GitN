import SwiftUI
import AppKit

struct ConflictMergeView: View {
    let viewModel: RepoViewModel
    @State private var currentConflictIndex = 0
    @State private var scrollOffset: CGPoint = .zero
    @State private var isUserScrolling = false

    private var file: ConflictFile? { viewModel.conflictMergeFile }
    private var sides: ConflictSides? { viewModel.conflictSides }
    private var totalConflicts: Int { sides?.markers.count ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            VSplitView {
                HSplitView {
                    oursPanel
                    theirsPanel
                }
                .frame(minHeight: 200)

                outputPanel
                    .frame(minHeight: 150)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
                Text(file?.path ?? "")
                    .font(.system(size: 12, weight: .semibold))
                if totalConflicts > 0 {
                    Text("(\(totalConflicts) conflict\(totalConflicts == 1 ? "" : "s"))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if totalConflicts > 0 {
                HStack(spacing: 4) {
                    Text("conflict \(currentConflictIndex + 1) of \(totalConflicts)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button(action: { navigateConflict(-1) }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(currentConflictIndex <= 0)

                    Button(action: { navigateConflict(1) }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(currentConflictIndex >= totalConflicts - 1)
                }
            }

            Divider().frame(height: 16)

            Button(action: { Task { await viewModel.saveConflictResolution() } }) {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10))
                    Text("Save")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(action: { viewModel.closeConflictMerge() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Panels

    private var oursPanel: some View {
        VStack(spacing: 0) {
            panelHeader(label: "A", labelColor: .blue, title: sides?.oursLabel ?? "Ours")
            Divider()
            SyncedScrollCodeView(
                lines: sides?.oursContent.components(separatedBy: "\n") ?? [],
                conflictRegions: sides?.markers ?? [],
                side: .ours,
                highlightColor: .blue,
                regionChoices: viewModel.regionChoices,
                scrollOffset: $scrollOffset,
                onToggleRegion: { idx in toggleRegion(idx, side: .ours) }
            )
        }
        .background(Color(.textBackgroundColor))
    }

    private var theirsPanel: some View {
        VStack(spacing: 0) {
            panelHeader(label: "B", labelColor: .orange, title: sides?.theirsLabel ?? "Theirs")
            Divider()
            SyncedScrollCodeView(
                lines: sides?.theirsContent.components(separatedBy: "\n") ?? [],
                conflictRegions: sides?.markers ?? [],
                side: .theirs,
                highlightColor: .orange,
                regionChoices: viewModel.regionChoices,
                scrollOffset: $scrollOffset,
                onToggleRegion: { idx in toggleRegion(idx, side: .theirs) }
            )
        }
        .background(Color(.textBackgroundColor))
    }

    private var outputPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Output")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.controlBackgroundColor).opacity(0.5))

            Divider()

            SyncedScrollCodeView(
                lines: viewModel.conflictOutputLines,
                conflictRegions: [],
                side: nil,
                highlightColor: .clear,
                regionChoices: [:],
                scrollOffset: $scrollOffset,
                onToggleRegion: { _ in }
            )
        }
        .background(Color(.textBackgroundColor))
    }

    // MARK: - Helpers

    private func panelHeader(label: String, labelColor: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(labelColor))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private func navigateConflict(_ delta: Int) {
        let newIdx = currentConflictIndex + delta
        guard newIdx >= 0, newIdx < totalConflicts else { return }
        currentConflictIndex = newIdx
    }

    private func toggleRegion(_ regionIndex: Int, side: ConflictSide) {
        let currentChoice = viewModel.regionChoices[regionIndex]
        switch side {
        case .ours:
            if currentChoice == true {
                viewModel.regionChoices.removeValue(forKey: regionIndex)
                viewModel.takeOurs(regionIndex)
            } else {
                viewModel.takeOurs(regionIndex)
            }
        case .theirs:
            if currentChoice == false {
                viewModel.regionChoices.removeValue(forKey: regionIndex)
                viewModel.takeTheirs(regionIndex)
            } else {
                viewModel.takeTheirs(regionIndex)
            }
        }
    }
}

// MARK: - Synced Scroll Code View (NSScrollView-based for scroll synchronization)

struct SyncedScrollCodeView: NSViewRepresentable {
    let lines: [String]
    let conflictRegions: [ConflictRegion]
    let side: ConflictSide?
    let highlightColor: Color
    let regionChoices: [Int: Bool]
    @Binding var scrollOffset: CGPoint
    let onToggleRegion: (Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let contentView = CodeContentView(frame: .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        context.coordinator.scrollView = scrollView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let contentView = scrollView.documentView as? CodeContentView else { return }

        let nsHighlight = NSColor(highlightColor)
        contentView.configure(
            lines: lines,
            conflictRegions: conflictRegions,
            side: side,
            highlightColor: nsHighlight,
            regionChoices: regionChoices,
            onToggleRegion: onToggleRegion
        )
        contentView.needsDisplay = true

        let contentHeight = CGFloat(lines.count) * CodeContentView.lineHeight + 16
        let contentWidth = max(scrollView.bounds.width, estimateWidth(lines))
        contentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)

        if !context.coordinator.isScrolling {
            let currentOrigin = scrollView.contentView.bounds.origin
            if abs(currentOrigin.y - scrollOffset.y) > 1 || abs(currentOrigin.x - scrollOffset.x) > 1 {
                context.coordinator.isSyncing = true
                scrollView.contentView.scroll(to: scrollOffset)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                context.coordinator.isSyncing = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func estimateWidth(_ lines: [String]) -> CGFloat {
        let maxLen = lines.reduce(0) { max($0, $1.count) }
        return CGFloat(maxLen) * 7.2 + 60
    }

    final class Coordinator: NSObject {
        var parent: SyncedScrollCodeView
        weak var scrollView: NSScrollView?
        var isSyncing = false
        var isScrolling = false

        init(_ parent: SyncedScrollCodeView) {
            self.parent = parent
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard !isSyncing, let scrollView else { return }
            isScrolling = true
            let origin = scrollView.contentView.bounds.origin
            DispatchQueue.main.async {
                self.parent.scrollOffset = origin
                self.isScrolling = false
            }
        }
    }
}

// MARK: - Code Content View (custom NSView for rendering lines)

final class CodeContentView: NSView {
    static let lineHeight: CGFloat = 17
    static let lineNumWidth: CGFloat = 40
    static let checkboxWidth: CGFloat = 20

    private var lines: [String] = []
    private var conflictRegions: [ConflictRegion] = []
    private var side: ConflictSide?
    private var highlightColor: NSColor = .clear
    private var regionChoices: [Int: Bool] = [:]
    private var onToggleRegion: ((Int) -> Void)?
    private var trackingArea: NSTrackingArea?

    func configure(
        lines: [String],
        conflictRegions: [ConflictRegion],
        side: ConflictSide?,
        highlightColor: NSColor,
        regionChoices: [Int: Bool],
        onToggleRegion: @escaping (Int) -> Void
    ) {
        self.lines = lines
        self.conflictRegions = conflictRegions
        self.side = side
        self.highlightColor = highlightColor
        self.regionChoices = regionChoices
        self.onToggleRegion = onToggleRegion
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let lineNumFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let lineNumColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5)
        let separatorColor = NSColor.separatorColor.withAlphaComponent(0.3)

        let lineHeight = Self.lineHeight
        let lineNumWidth = Self.lineNumWidth

        let visibleRect = self.visibleRect
        let startLine = max(0, Int(visibleRect.minY / lineHeight) - 1)
        let endLine = min(lines.count, Int(visibleRect.maxY / lineHeight) + 2)

        for i in startLine..<endLine {
            let y = CGFloat(i) * lineHeight
            let lineRect = NSRect(x: 0, y: y, width: bounds.width, height: lineHeight)

            if let regionIdx = conflictRegionIndex(for: i) {
                let isChosen: Bool
                if let choice = regionChoices[regionIdx] {
                    isChosen = (side == .ours && choice == true) || (side == .theirs && choice == false)
                } else {
                    isChosen = false
                }

                ctx.setFillColor(highlightColor.withAlphaComponent(isChosen ? 0.15 : 0.06).cgColor)
                ctx.fill(lineRect)

                let isFirstLine = isFirstLineOfRegion(i, regionIdx)
                if isFirstLine && side != nil {
                    let checkX: CGFloat = 2
                    let checkY = y + (lineHeight - 14) / 2
                    let checkRect = NSRect(x: checkX, y: checkY, width: 14, height: 14)

                    ctx.setStrokeColor(highlightColor.withAlphaComponent(0.6).cgColor)
                    ctx.setLineWidth(1.0)
                    let path = CGPath(roundedRect: checkRect.insetBy(dx: 1, dy: 1), cornerWidth: 2, cornerHeight: 2, transform: nil)
                    ctx.addPath(path)

                    if isChosen {
                        ctx.setFillColor(highlightColor.withAlphaComponent(0.3).cgColor)
                        ctx.fillPath()
                        ctx.addPath(path)
                        ctx.strokePath()

                        let checkmark = NSAttributedString(
                            string: "\u{2713}",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                                .foregroundColor: highlightColor
                            ]
                        )
                        checkmark.draw(at: NSPoint(x: checkX + 2, y: checkY))
                    } else {
                        ctx.strokePath()
                    }
                }
            }

            // Separator
            ctx.setStrokeColor(separatorColor.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: lineNumWidth + 2, y: y))
            ctx.addLine(to: CGPoint(x: lineNumWidth + 2, y: y + lineHeight))
            ctx.strokePath()

            // Line number
            let lineNumStr = NSAttributedString(
                string: "\(i + 1)",
                attributes: [.font: lineNumFont, .foregroundColor: lineNumColor]
            )
            let numSize = lineNumStr.size()
            lineNumStr.draw(at: NSPoint(x: lineNumWidth - numSize.width - 4, y: y + (lineHeight - numSize.height) / 2))

            // Content
            guard i < lines.count else { continue }
            let content = lines[i].isEmpty ? " " : lines[i]
            let textColor: NSColor = .labelColor
            let contentStr = NSAttributedString(
                string: content,
                attributes: [.font: font, .foregroundColor: textColor]
            )
            let textX = lineNumWidth + 8 + (side != nil && conflictRegionIndex(for: i) != nil ? Self.checkboxWidth : 0)
            let textSize = contentStr.size()
            contentStr.draw(at: NSPoint(x: textX, y: y + (lineHeight - textSize.height) / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let lineIdx = Int(location.y / Self.lineHeight)
        guard lineIdx >= 0, lineIdx < lines.count else { return }

        if let regionIdx = conflictRegionIndex(for: lineIdx), isFirstLineOfRegion(lineIdx, regionIdx) {
            if location.x < Self.lineNumWidth {
                onToggleRegion?(regionIdx)
                needsDisplay = true
                return
            }
        }

        super.mouseDown(with: event)
    }

    override var isFlipped: Bool { true }

    private func conflictRegionIndex(for lineIdx: Int) -> Int? {
        guard let side else { return nil }
        for (i, region) in conflictRegions.enumerated() {
            let range = side == .ours ? region.oursRange : region.theirsRange
            if range.contains(lineIdx) { return i }
        }
        return nil
    }

    private func isFirstLineOfRegion(_ lineIdx: Int, _ regionIdx: Int) -> Bool {
        guard let side else { return false }
        let range = side == .ours ? conflictRegions[regionIdx].oursRange : conflictRegions[regionIdx].theirsRange
        return range.lowerBound == lineIdx
    }
}
