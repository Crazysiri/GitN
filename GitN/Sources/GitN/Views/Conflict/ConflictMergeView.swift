import SwiftUI
import AppKit

struct ConflictMergeView: View {
    let viewModel: RepoViewModel
    @State private var currentConflictIndex = 0
    @State private var scrollOffset: CGPoint = .zero

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
                highlightColor: NSColor.systemBlue,
                regionChoices: viewModel.regionChoices,
                scrollOffset: $scrollOffset,
                onToggleRegion: { idx in viewModel.toggleOurs(idx) }
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
                highlightColor: NSColor.systemOrange,
                regionChoices: viewModel.regionChoices,
                scrollOffset: $scrollOffset,
                onToggleRegion: { idx in viewModel.toggleTheirs(idx) }
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

                Button("Reset") {
                    viewModel.resetConflictChoices()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.controlBackgroundColor).opacity(0.5))

            Divider()

            OutputScrollCodeView(
                lines: viewModel.conflictOutputLines,
                conflictSides: sides,
                regionChoices: viewModel.regionChoices,
                scrollOffset: $scrollOffset
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
}

// MARK: - Synced Scroll Code View (ours/theirs panels)

struct SyncedScrollCodeView: NSViewRepresentable {
    let lines: [String]
    let conflictRegions: [ConflictRegion]
    let side: ConflictSide
    let highlightColor: NSColor
    let regionChoices: [Int: RepoViewModel.RegionChoice]
    @Binding var scrollOffset: CGPoint
    let onToggleRegion: (Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let contentView = SideCodeContentView(frame: .zero)
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
        guard let contentView = scrollView.documentView as? SideCodeContentView else { return }

        contentView.configure(
            lines: lines, conflictRegions: conflictRegions, side: side,
            highlightColor: highlightColor, regionChoices: regionChoices,
            onToggleRegion: onToggleRegion
        )

        let lineH = SideCodeContentView.lineHeight
        let contentHeight = CGFloat(lines.count) * lineH + 16
        let contentWidth = max(scrollView.bounds.width, estimateWidth())
        contentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        contentView.needsDisplay = true

        if !context.coordinator.isScrolling {
            let cur = scrollView.contentView.bounds.origin
            if abs(cur.y - scrollOffset.y) > 1 || abs(cur.x - scrollOffset.x) > 1 {
                context.coordinator.isSyncing = true
                scrollView.contentView.scroll(to: scrollOffset)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                context.coordinator.isSyncing = false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func estimateWidth() -> CGFloat {
        let maxLen = lines.reduce(0) { max($0, $1.count) }
        return CGFloat(maxLen) * 7.2 + 80
    }

    final class Coordinator: NSObject {
        var parent: SyncedScrollCodeView
        weak var scrollView: NSScrollView?
        var isSyncing = false
        var isScrolling = false
        init(_ parent: SyncedScrollCodeView) { self.parent = parent }

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

// MARK: - Output Scroll Code View

struct OutputScrollCodeView: NSViewRepresentable {
    let lines: [String]
    let conflictSides: ConflictSides?
    let regionChoices: [Int: RepoViewModel.RegionChoice]
    @Binding var scrollOffset: CGPoint

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let contentView = OutputCodeContentView(frame: .zero)
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
        guard let contentView = scrollView.documentView as? OutputCodeContentView else { return }
        contentView.configure(lines: lines, conflictSides: conflictSides, regionChoices: regionChoices)

        let lineH = OutputCodeContentView.lineHeight
        let contentHeight = CGFloat(lines.count) * lineH + 16
        let contentWidth = max(scrollView.bounds.width, estimateWidth())
        contentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        contentView.needsDisplay = true

        if !context.coordinator.isScrolling {
            let cur = scrollView.contentView.bounds.origin
            if abs(cur.y - scrollOffset.y) > 1 || abs(cur.x - scrollOffset.x) > 1 {
                context.coordinator.isSyncing = true
                scrollView.contentView.scroll(to: scrollOffset)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                context.coordinator.isSyncing = false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func estimateWidth() -> CGFloat {
        let maxLen = lines.reduce(0) { max($0, $1.count) }
        return CGFloat(maxLen) * 7.2 + 80
    }

    final class Coordinator: NSObject {
        var parent: OutputScrollCodeView
        weak var scrollView: NSScrollView?
        var isSyncing = false
        var isScrolling = false
        init(_ parent: OutputScrollCodeView) { self.parent = parent }

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

// MARK: - Side Code Content View (ours/theirs with checkboxes)

final class SideCodeContentView: NSView {
    static let lineHeight: CGFloat = 17
    private static let lineNumWidth: CGFloat = 40
    private static let checkboxSize: CGFloat = 14

    private var lines: [String] = []
    private var conflictRegions: [ConflictRegion] = []
    private var side: ConflictSide = .ours
    private var highlightColor: NSColor = .systemBlue
    private var regionChoices: [Int: RepoViewModel.RegionChoice] = [:]
    private var onToggleRegion: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    func configure(
        lines: [String], conflictRegions: [ConflictRegion], side: ConflictSide,
        highlightColor: NSColor, regionChoices: [Int: RepoViewModel.RegionChoice],
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
        let lineH = Self.lineHeight
        let lnW = Self.lineNumWidth

        let visibleRect = self.visibleRect
        let startLine = max(0, Int(visibleRect.minY / lineH) - 1)
        let endLine = min(lines.count, Int(visibleRect.maxY / lineH) + 2)

        for i in startLine..<endLine {
            let y = CGFloat(i) * lineH
            let lineRect = NSRect(x: 0, y: y, width: bounds.width, height: lineH)
            let regionIdx = conflictRegionIndex(for: i)
            let isConflict = regionIdx != nil
            let isChecked: Bool = {
                guard let ri = regionIdx, let choice = regionChoices[ri] else { return false }
                return side == .ours ? choice.oursChecked : choice.theirsChecked
            }()

            if isConflict {
                ctx.setFillColor(highlightColor.withAlphaComponent(isChecked ? 0.15 : 0.06).cgColor)
                ctx.fill(lineRect)
            }

            // Checkbox for first line of each conflict region
            if isConflict, let ri = regionIdx, isFirstLineOfRegion(i, ri) {
                let ckX: CGFloat = 3
                let ckY = y + (lineH - Self.checkboxSize) / 2
                let ckRect = NSRect(x: ckX, y: ckY, width: Self.checkboxSize, height: Self.checkboxSize)
                let path = CGPath(roundedRect: ckRect.insetBy(dx: 1, dy: 1), cornerWidth: 2, cornerHeight: 2, transform: nil)

                if isChecked {
                    ctx.setFillColor(highlightColor.withAlphaComponent(0.3).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                    ctx.setStrokeColor(highlightColor.withAlphaComponent(0.8).cgColor)
                    ctx.setLineWidth(1.0)
                    ctx.addPath(path)
                    ctx.strokePath()
                    let checkAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                        .foregroundColor: highlightColor
                    ]
                    let check = NSAttributedString(string: "\u{2713}", attributes: checkAttrs)
                    check.draw(at: NSPoint(x: ckX + 2, y: ckY))
                } else {
                    ctx.setStrokeColor(highlightColor.withAlphaComponent(0.5).cgColor)
                    ctx.setLineWidth(1.0)
                    ctx.addPath(path)
                    ctx.strokePath()
                }
            }

            // Separator line
            ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: lnW + 2, y: y))
            ctx.addLine(to: CGPoint(x: lnW + 2, y: y + lineH))
            ctx.strokePath()

            // Line number
            let numStr = NSAttributedString(
                string: "\(i + 1)",
                attributes: [.font: lineNumFont, .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.5)]
            )
            let numSz = numStr.size()
            numStr.draw(at: NSPoint(x: lnW - numSz.width - 4, y: y + (lineH - numSz.height) / 2))

            // Content text
            guard i < lines.count else { continue }
            let text = lines[i].isEmpty ? " " : lines[i]
            let textX: CGFloat = lnW + 8 + (isConflict ? 20 : 0)
            let contentStr = NSAttributedString(
                string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
            let textSz = contentStr.size()
            contentStr.draw(at: NSPoint(x: textX, y: y + (lineH - textSz.height) / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let lineIdx = Int(loc.y / Self.lineHeight)
        guard lineIdx >= 0, lineIdx < lines.count else { super.mouseDown(with: event); return }
        if let ri = conflictRegionIndex(for: lineIdx), isFirstLineOfRegion(lineIdx, ri), loc.x < Self.lineNumWidth {
            onToggleRegion?(ri)
            return
        }
        super.mouseDown(with: event)
    }

    private func conflictRegionIndex(for lineIdx: Int) -> Int? {
        for (i, region) in conflictRegions.enumerated() {
            let range = side == .ours ? region.oursRange : region.theirsRange
            if range.contains(lineIdx) { return i }
        }
        return nil
    }

    private func isFirstLineOfRegion(_ lineIdx: Int, _ regionIdx: Int) -> Bool {
        let range = side == .ours ? conflictRegions[regionIdx].oursRange : conflictRegions[regionIdx].theirsRange
        return range.lowerBound == lineIdx
    }
}

// MARK: - Output Code Content View (with A/B origin markers)

final class OutputCodeContentView: NSView {
    static let lineHeight: CGFloat = 17
    private static let lineNumWidth: CGFloat = 40
    private static let originBadgeWidth: CGFloat = 18

    private var lines: [String] = []
    private var conflictSides: ConflictSides?
    private var regionChoices: [Int: RepoViewModel.RegionChoice] = [:]
    private var lineOrigins: [(origin: Character?, color: NSColor?)] = []

    override var isFlipped: Bool { true }

    func configure(lines: [String], conflictSides: ConflictSides?, regionChoices: [Int: RepoViewModel.RegionChoice]) {
        self.lines = lines
        self.conflictSides = conflictSides
        self.regionChoices = regionChoices
        computeLineOrigins()
    }

    private func computeLineOrigins() {
        guard let sides = conflictSides else {
            lineOrigins = lines.map { _ in (nil, nil) }
            return
        }
        let oursLines = sides.oursContent.components(separatedBy: "\n")
        let theirsLines = sides.theirsContent.components(separatedBy: "\n")

        var origins: [(Character?, NSColor?)] = []
        var oursIdx = 0

        while oursIdx < oursLines.count {
            var handledRegion = false
            for (i, marker) in sides.markers.enumerated() {
                if marker.oursRange.lowerBound == oursIdx {
                    let choice = regionChoices[i]
                    let includeOurs = choice?.oursChecked ?? false
                    let includeTheirs = choice?.theirsChecked ?? false

                    if includeOurs {
                        for j in marker.oursRange {
                            if j < oursLines.count {
                                origins.append(("A", .systemBlue))
                            }
                        }
                    }
                    if includeTheirs {
                        for j in marker.theirsRange {
                            if j < theirsLines.count {
                                origins.append(("B", .systemOrange))
                            }
                        }
                    }
                    if !includeOurs && !includeTheirs {
                        for j in marker.oursRange {
                            if j < oursLines.count {
                                origins.append((nil, nil))
                            }
                        }
                    }

                    oursIdx = marker.oursRange.upperBound
                    handledRegion = true
                    break
                }
            }
            if !handledRegion {
                origins.append((nil, nil))
                oursIdx += 1
            }
        }
        lineOrigins = origins
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let lineNumFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let lineH = Self.lineHeight
        let lnW = Self.lineNumWidth

        let visibleRect = self.visibleRect
        let startLine = max(0, Int(visibleRect.minY / lineH) - 1)
        let endLine = min(lines.count, Int(visibleRect.maxY / lineH) + 2)

        for i in startLine..<endLine {
            let y = CGFloat(i) * lineH
            let origin: (Character?, NSColor?) = i < lineOrigins.count ? lineOrigins[i] : (nil, nil)

            // Highlight conflict lines
            if let color = origin.1 {
                let lineRect = NSRect(x: 0, y: y, width: bounds.width, height: lineH)
                ctx.setFillColor(color.withAlphaComponent(0.08).cgColor)
                ctx.fill(lineRect)
            }

            // Origin badge (A/B)
            if let label = origin.0, let color = origin.1 {
                let badgeFont = NSFont.systemFont(ofSize: 8, weight: .bold)
                let badgeStr = NSAttributedString(
                    string: String(label),
                    attributes: [.font: badgeFont, .foregroundColor: color]
                )
                let bSz = badgeStr.size()
                badgeStr.draw(at: NSPoint(x: 3, y: y + (lineH - bSz.height) / 2))

                // Green checkmark
                let checkStr = NSAttributedString(
                    string: "\u{2713}",
                    attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.systemGreen]
                )
                let cSz = checkStr.size()
                checkStr.draw(at: NSPoint(x: 12, y: y + (lineH - cSz.height) / 2))
            }

            // Separator
            ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: lnW + 2, y: y))
            ctx.addLine(to: CGPoint(x: lnW + 2, y: y + lineH))
            ctx.strokePath()

            // Line number
            let numStr = NSAttributedString(
                string: "\(i + 1)",
                attributes: [.font: lineNumFont, .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.5)]
            )
            let numSz = numStr.size()
            numStr.draw(at: NSPoint(x: lnW - numSz.width - 4, y: y + (lineH - numSz.height) / 2))

            // Content
            guard i < lines.count else { continue }
            let text = lines[i].isEmpty ? " " : lines[i]
            let contentStr = NSAttributedString(
                string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
            let textSz = contentStr.size()
            contentStr.draw(at: NSPoint(x: lnW + 8, y: y + (lineH - textSz.height) / 2))
        }
    }
}
