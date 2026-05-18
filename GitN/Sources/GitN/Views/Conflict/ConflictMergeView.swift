import SwiftUI
import AppKit

private func conflictScrollDebugLog(_ message: @autoclosure () -> String) {
    print("[ConflictScroll] \(message())")
}

private enum ConflictEditorStyle {
    static let lineHeight: CGFloat = 19
    static let unresolvedBaseColor = NSColor.systemRed
}

enum ConflictScrollDriver {
    case sideA
    case sideB
    case output
}

private enum ConflictScrollSync {
    static func scalar(forTopLine topLine: Double, anchors: [Int], totalLines: Int) -> Double {
        let points = segmentPoints(anchors: anchors, totalLines: totalLines)
        guard points.count >= 2 else { return max(topLine, 0) }

        let clampedTopLine = max(topLine, 0)
        for index in 0..<(points.count - 1) {
            let start = Double(points[index])
            let end = Double(points[index + 1])
            let length = max(end - start, 1)
            if clampedTopLine < end || index == points.count - 2 {
                let progress = min(max((clampedTopLine - start) / length, 0), 1)
                return Double(index) + progress
            }
        }

        return Double(max(points.count - 2, 0))
    }

    static func topLine(forScalar scalar: Double, anchors: [Int], totalLines: Int) -> Double {
        let points = segmentPoints(anchors: anchors, totalLines: totalLines)
        guard points.count >= 2 else { return 0 }

        let maxSegmentIndex = max(points.count - 2, 0)
        let clampedScalar = min(max(scalar, 0), Double(maxSegmentIndex) + 0.999)
        let segmentIndex = min(Int(floor(clampedScalar)), maxSegmentIndex)
        let progress = clampedScalar - Double(segmentIndex)
        let start = Double(points[segmentIndex])
        let end = Double(points[min(segmentIndex + 1, points.count - 1)])
        return start + (end - start) * progress
    }

    static func sideAnchors(lines: [String], regions: [ConflictRegion], side: ConflictSide) -> [Int] {
        SideDisplayLayout.make(lines: lines, conflictRegions: regions, side: side).anchors
    }

    static func sideTotalLines(lines: [String], regions: [ConflictRegion], side: ConflictSide) -> Int {
        SideDisplayLayout.make(lines: lines, conflictRegions: regions, side: side).rows.count
    }

    static func outputAnchors(for blocks: [ConflictEditorBlock]) -> [Int] {
        blocks.map { block in
            block.activeRange?.lowerBound ?? block.initialAttachedRange.lowerBound
        }
    }

    private static func segmentPoints(anchors: [Int], totalLines: Int) -> [Int] {
        let uniqueAnchors = Array(Set(anchors.map { min(max($0, 0), totalLines) })).sorted()
        var points = [0]
        for anchor in uniqueAnchors where anchor > (points.last ?? -1) {
            points.append(anchor)
        }
        if totalLines > (points.last ?? -1) {
            points.append(totalLines)
        } else if points.count == 1 {
            points.append(totalLines)
        }
        return points
    }
}

struct ConflictMergeView: View {
    let viewModel: RepoViewModel
    @State private var currentConflictIndex = 0
    @State private var scrollOffset: CGPoint = .zero
    @State private var scrollDriver: ConflictScrollDriver = .sideA
    @State private var suppressSideScrollFeedback = false
    @State private var outputScrollTargetLine: Int?
    @State private var outputScrollRequestID = 0
    @State private var initialScrollDone = false

    private var file: ConflictFile? { viewModel.conflictMergeFile }
    private var sides: ConflictSides? { viewModel.conflictSides }
    private var document: ConflictEditorDocument? { viewModel.conflictEditorDocument }
    private var fallbackMessage: String? { viewModel.conflictFallbackMessage }
    private var isFallbackMode: Bool { fallbackMessage != nil && document == nil }
    private var totalConflicts: Int { document?.blocks.count ?? sides?.markers.count ?? 0 }
    private var currentBlock: ConflictEditorBlock? {
        guard let document, currentConflictIndex >= 0, currentConflictIndex < document.blocks.count else { return nil }
        return document.blocks[currentConflictIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isFallbackMode {
                fallbackContent
            } else {
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
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scrollToFirstConflict()
            }
        }
        .onChange(of: file?.id) { _, _ in
            initialScrollDone = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToFirstConflict()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 13))
                Text(file?.path ?? "")
                    .font(.system(size: 14, weight: .semibold))
                if totalConflicts > 0 {
                    Text("(\(totalConflicts) conflict\(totalConflicts == 1 ? "" : "s"))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Divider().frame(height: 16)

            Button(action: { Task { await viewModel.saveConflictResolution() } }) {
                HStack(spacing: 3) {
                    Image(systemName: isFallbackMode ? "checkmark.circle" : "square.and.arrow.down")
                        .font(.system(size: 12))
                    Text(isFallbackMode ? "Mark Resolved" : "Save")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(action: { viewModel.closeConflictMerge() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var fallbackContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("This conflict can't be edited as text in GitN.", systemImage: "doc.fill.badge.ellipsis")
                .font(.system(size: 16, weight: .semibold))

            Text("Resolve the file externally, then return here and choose `Mark Resolved` to stage the current working tree version.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if let fallbackMessage, !fallbackMessage.isEmpty {
                Text(fallbackMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor).opacity(0.55))
                    )
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.textBackgroundColor))
    }

    // MARK: - Panels

    private var oursPanel: some View {
        VStack(spacing: 0) {
            panelHeader(
                label: "A",
                labelColor: .blue,
                title: sides?.oursLabel ?? "Ours",
                isChecked: Binding(
                    get: { viewModel.allOursSelected },
                    set: { viewModel.setAllOursSelected($0) }
                )
            )
            Divider()
            SyncedScrollCodeView(
                lines: sides?.oursLines ?? [],
                conflictRegions: sides?.markers ?? [],
                side: .ours,
                highlightColor: NSColor.systemBlue,
                regionChoices: viewModel.regionChoices,
                scrollOffset: $scrollOffset,
                scrollDriver: $scrollDriver,
                suppressScrollFeedback: $suppressSideScrollFeedback,
                onToggleRegion: { idx in viewModel.toggleOurs(idx) },
                filePath: file?.path ?? ""
            )
        }
        .background(Color(.textBackgroundColor))
    }

    private var theirsPanel: some View {
        VStack(spacing: 0) {
            panelHeader(
                label: "B",
                labelColor: .orange,
                title: sides?.theirsLabel ?? "Theirs",
                isChecked: Binding(
                    get: { viewModel.allTheirsSelected },
                    set: { viewModel.setAllTheirsSelected($0) }
                )
            )
            Divider()
            SyncedScrollCodeView(
                lines: sides?.theirsLines ?? [],
                conflictRegions: sides?.markers ?? [],
                side: .theirs,
                highlightColor: NSColor.systemOrange,
                regionChoices: viewModel.regionChoices,
                scrollOffset: $scrollOffset,
                scrollDriver: $scrollDriver,
                suppressScrollFeedback: $suppressSideScrollFeedback,
                onToggleRegion: { idx in viewModel.toggleTheirs(idx) },
                filePath: file?.path ?? ""
            )
        }
        .background(Color(.textBackgroundColor))
    }

    private var outputPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Output")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
                    .frame(maxWidth: 150)

                if totalConflicts > 0 {
                    conflictNavigator
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                Button("Reset") {
                    viewModel.resetConflictChoices()
                }
                .font(.system(size: 13))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.controlBackgroundColor).opacity(0.5))

            Divider()

            ConflictOutputEditorView(
                text: Binding(
                    get: { viewModel.conflictOutputText },
                    set: { viewModel.updateConflictOutputText($0) }
                ),
                textRevision: viewModel.conflictOutputExternalRevision,
                blocks: document?.blocks ?? [],
                lineOrigins: document?.outputLineOrigins ?? [],
                currentBlockID: currentBlock?.id,
                scrollOffset: $scrollOffset,
                scrollDriver: $scrollDriver,
                suppressSideScrollFeedback: $suppressSideScrollFeedback,
                scrollTargetLine: outputScrollTargetLine,
                scrollRequestID: outputScrollRequestID,
                filePath: file?.path ?? "",
                undoManager: viewModel.conflictUndoManager,
                canUndoConflictAction: { viewModel.canUndoConflictAction },
                canRedoConflictAction: { viewModel.canRedoConflictAction },
                onUndoConflictAction: { viewModel.undoConflictAction() },
                onRedoConflictAction: { viewModel.redoConflictAction() },
                onSave: {
                    Task {
                        await viewModel.saveConflictResolution()
                    }
                }
            )
        }
        .background(Color(.textBackgroundColor))
    }

    // MARK: - Helpers

    private func panelHeader(label: String, labelColor: Color, title: String, isChecked: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: isChecked)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .controlSize(.small)
//                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.textBackgroundColor).opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white.opacity(0.92), lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(labelColor))
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var conflictNavigator: some View {
        HStack(spacing: 8) {
            Text("conflict")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Button(action: { navigateConflict(-1) }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(currentConflictIndex <= 0)

            Text("\(currentConflictIndex + 1) / \(totalConflicts)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 34)

            Button(action: { navigateConflict(1) }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(currentConflictIndex >= totalConflicts - 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func navigateConflict(_ delta: Int) {
        let newIdx = currentConflictIndex + delta
        guard newIdx >= 0, newIdx < totalConflicts else { return }
        currentConflictIndex = newIdx
        scrollToConflict(at: newIdx)
    }

    private func scrollToConflict(at index: Int) {
        guard let document, document.blocks.indices.contains(index), let sides else { return }
        let block = document.blocks[index]
        let sideLayout = SideDisplayLayout.make(lines: sides.oursLines, conflictRegions: sides.markers, side: .ours)
        let sideLine = sideLayout.regionDisplayRanges[index].lowerBound
        let outputLine = block.activeRange?.lowerBound ?? block.initialAttachedRange.lowerBound
        let paddedSideLine = max(Double(sideLine) - 2, 0)
        let scalar = ConflictScrollSync.scalar(
            forTopLine: paddedSideLine,
            anchors: sideLayout.anchors,
            totalLines: sideLayout.rows.count
        )
        conflictScrollDebugLog("scrollToConflict index=\(index) sideLine=\(sideLine) scalar=\(scalar) outputLine=\(outputLine)")
        scrollDriver = .sideA
        scrollOffset = CGPoint(x: scrollOffset.x, y: CGFloat(scalar) * SideCodeContentView.lineHeight)
        outputScrollTargetLine = outputLine
        outputScrollRequestID += 1
    }

    private func scrollToFirstConflict() {
        guard !initialScrollDone, let block = document?.blocks.first, let sides else { return }
        initialScrollDone = true
        let sideLayout = SideDisplayLayout.make(lines: sides.oursLines, conflictRegions: sides.markers, side: .ours)
        let paddedSideLine = max(Double(sideLayout.regionDisplayRanges[0].lowerBound) - 2, 0)
        let scalar = ConflictScrollSync.scalar(
            forTopLine: paddedSideLine,
            anchors: sideLayout.anchors,
            totalLines: sideLayout.rows.count
        )
        let outputLine = block.activeRange?.lowerBound ?? block.initialAttachedRange.lowerBound
        conflictScrollDebugLog("scrollToFirstConflict sideLine=\(sideLayout.regionDisplayRanges[0].lowerBound) scalar=\(scalar) outputLine=\(outputLine)")
        scrollDriver = .sideA
        scrollOffset = CGPoint(x: 0, y: CGFloat(scalar) * SideCodeContentView.lineHeight)
        outputScrollTargetLine = outputLine
        outputScrollRequestID += 1
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
    @Binding var scrollDriver: ConflictScrollDriver
    @Binding var suppressScrollFeedback: Bool
    let onToggleRegion: (Int) -> Void
    var filePath: String = ""

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

        let contentChanged = contentView.configure(
            lines: lines, conflictRegions: conflictRegions, side: side,
            highlightColor: highlightColor, regionChoices: regionChoices,
            onToggleRegion: onToggleRegion,
            filePath: filePath
        )

        let lineH = SideCodeContentView.lineHeight
        let contentHeight = CGFloat(contentView.displayLineCount) * lineH + 16
        let contentWidth = max(scrollView.bounds.width, contentView.cachedEstimatedWidth)
        let targetFrame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        let frameChanged = contentView.frame != targetFrame
        if frameChanged {
            contentView.frame = targetFrame
        }
        if contentChanged || frameChanged {
            contentView.needsDisplay = true
        }

        if !context.coordinator.isScrolling {
            let cur = scrollView.contentView.bounds.origin
            let scalar = Double(scrollOffset.y / SideCodeContentView.lineHeight)
            let targetTopLine = ConflictScrollSync.topLine(
                forScalar: scalar,
                anchors: contentView.displayAnchors,
                totalLines: contentView.displayLineCount
            )
            let targetY = CGFloat(targetTopLine) * SideCodeContentView.lineHeight
            if abs(cur.y - targetY) > 1 || abs(cur.x - scrollOffset.x) > 1 {
                conflictScrollDebugLog("syncSide side=\(side == .ours ? "A" : "B") scalar=\(scalar) targetTopLine=\(targetTopLine) curY=\(cur.y) targetY=\(targetY)")
                context.coordinator.isSyncing = true
                let targetPoint = CGPoint(x: scrollOffset.x, y: targetY)
                context.coordinator.lastProgrammaticOrigin = targetPoint
                scrollView.contentView.scroll(to: targetPoint)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                context.coordinator.isSyncing = false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: SyncedScrollCodeView
        weak var scrollView: NSScrollView?
        var isSyncing = false
        var isScrolling = false
        var lastProgrammaticOrigin: CGPoint?
        init(_ parent: SyncedScrollCodeView) { self.parent = parent }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView else { return }
            let origin = scrollView.contentView.bounds.origin
            if let lastProgrammaticOrigin,
               abs(lastProgrammaticOrigin.x - origin.x) < 1,
               abs(lastProgrammaticOrigin.y - origin.y) < 1 {
                self.lastProgrammaticOrigin = nil
                return
            }
            if parent.suppressScrollFeedback {
                return
            }
            guard !isSyncing else { return }
            isScrolling = true
            DispatchQueue.main.async {
                let topLine = Double(origin.y / SideCodeContentView.lineHeight)
                let contentView = scrollView.documentView as? SideCodeContentView
                let scalar = ConflictScrollSync.scalar(
                    forTopLine: topLine,
                    anchors: contentView?.displayAnchors ?? [],
                    totalLines: contentView?.displayLineCount ?? self.parent.lines.count
                )
                self.parent.scrollDriver = self.parent.side == .ours ? .sideA : .sideB
                conflictScrollDebugLog("scrollSide side=\(self.parent.side == .ours ? "A" : "B") topLine=\(topLine) scalar=\(scalar)")
                self.parent.scrollOffset = CGPoint(
                    x: origin.x,
                    y: CGFloat(scalar) * SideCodeContentView.lineHeight
                )
                self.isScrolling = false
            }
        }
    }
}

// MARK: - Output Editor View

struct ConflictOutputEditorView: NSViewRepresentable {
    @Binding var text: String
    let textRevision: Int
    let blocks: [ConflictEditorBlock]
    let lineOrigins: [ConflictEditorDocument.OutputLineOrigin]
    let currentBlockID: Int?
    @Binding var scrollOffset: CGPoint
    @Binding var scrollDriver: ConflictScrollDriver
    @Binding var suppressSideScrollFeedback: Bool
    let scrollTargetLine: Int?
    let scrollRequestID: Int
    var filePath: String = ""
    let undoManager: UndoManager
    let canUndoConflictAction: () -> Bool
    let canRedoConflictAction: () -> Bool
    let onUndoConflictAction: () -> Void
    let onRedoConflictAction: () -> Void
    let onSave: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = ConflictOutputTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.conflictUndoManager = undoManager
        textView.canUndoConflictAction = canUndoConflictAction
        textView.canRedoConflictAction = canRedoConflictAction
        textView.onUndoConflictAction = onUndoConflictAction
        textView.onRedoConflictAction = onRedoConflictAction
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        textView.insertionPointColor = .controlAccentColor
        let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.font = editorFont
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.typingAttributes = Self.baseAttributes(font: editorFont)
        textView.onSave = onSave

        scrollView.documentView = textView
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
        guard let textView = scrollView.documentView as? ConflictOutputTextView else { return }
        textView.conflictUndoManager = undoManager
        textView.canUndoConflictAction = canUndoConflictAction
        textView.canRedoConflictAction = canRedoConflictAction
        textView.onUndoConflictAction = onUndoConflictAction
        textView.onRedoConflictAction = onRedoConflictAction

        textView.configure(
            blocks: blocks,
            lineOrigins: lineOrigins,
            currentBlockID: currentBlockID,
            filePath: filePath
        )
        textView.onSave = onSave

        if !context.coordinator.isUpdating,
           context.coordinator.lastAppliedTextRevision != textRevision {
            let selection = textView.selectedRange()
            context.coordinator.isUpdating = true
            textView.textStorage?.setAttributedString(
                Self.highlightedText(text, filePath: filePath, font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
            )
            textView.setSelectedRange(selection)
            textView.typingAttributes = Self.baseAttributes(font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
            context.coordinator.lastAppliedTextRevision = textRevision
            context.coordinator.isUpdating = false
        }

        let anchorSignature = ConflictScrollSync.outputAnchors(for: blocks)
        let anchorSignatureChanged = context.coordinator.lastAnchorSignature != anchorSignature
        if anchorSignatureChanged {
            context.coordinator.lastAnchorSignature = anchorSignature
        }
        if scrollDriver == .output,
           context.coordinator.lastAppliedScrollRequestID == scrollRequestID,
           !context.coordinator.isScrolling,
           !context.coordinator.isSyncing,
           (anchorSignatureChanged || context.coordinator.pendingViewportRebase) {
            context.coordinator.pendingViewportRebase = false
            let topLine = textView.topVisibleLogicalPosition(in: scrollView)
            let scalar = ConflictScrollSync.scalar(
                forTopLine: topLine,
                anchors: anchorSignature,
                totalLines: textView.logicalLineCount
            )
                conflictScrollDebugLog("rebaseOutputMapping topLine=\(topLine) scalar=\(scalar) anchors=\(anchorSignature)")
                DispatchQueue.main.async {
                    self.suppressSideScrollFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.suppressSideScrollFeedback = false
                    }
                    self.scrollOffset = CGPoint(
                        x: scrollView.contentView.bounds.origin.x,
                        y: CGFloat(scalar) * SideCodeContentView.lineHeight
                    )
                }
        }

        if context.coordinator.lastAppliedScrollRequestID != scrollRequestID,
           let scrollTargetLine {
            context.coordinator.isSyncing = true
            conflictScrollDebugLog("jumpOutput request=\(scrollRequestID) targetLine=\(scrollTargetLine)")
            textView.scrollToLogicalLine(scrollTargetLine, in: scrollView)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            context.coordinator.lastAppliedScrollRequestID = scrollRequestID
            context.coordinator.isSyncing = false
        }

        if !context.coordinator.isScrolling,
           !context.coordinator.suppressSharedOutputSync,
           scrollDriver != .output,
           context.coordinator.lastAppliedScrollRequestID == scrollRequestID {
            let cur = scrollView.contentView.bounds.origin
            let scalar = Double(scrollOffset.y / SideCodeContentView.lineHeight)
            let targetTopLine = ConflictScrollSync.topLine(
                forScalar: scalar,
                anchors: ConflictScrollSync.outputAnchors(for: blocks),
                totalLines: textView.logicalLineCount
            )
            let currentTopLine = textView.topVisibleLogicalPosition(in: scrollView)
            if abs(currentTopLine - targetTopLine) > 0.05 || abs(cur.x - scrollOffset.x) > 1 {
                conflictScrollDebugLog("syncOutput scalar=\(scalar) currentTopLine=\(currentTopLine) targetTopLine=\(targetTopLine)")
                context.coordinator.isSyncing = true
                textView.scrollToLogicalPosition(targetTopLine, in: scrollView)
                if abs(scrollView.contentView.bounds.origin.x - scrollOffset.x) > 1 {
                    scrollView.contentView.scroll(
                        to: CGPoint(x: scrollOffset.x, y: scrollView.contentView.bounds.origin.y)
                    )
                }
                scrollView.reflectScrolledClipView(scrollView.contentView)
                context.coordinator.lastProgrammaticOrigin = scrollView.contentView.bounds.origin
                context.coordinator.isSyncing = false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func baseAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = ConflictEditorStyle.lineHeight
        paragraphStyle.maximumLineHeight = ConflictEditorStyle.lineHeight
        paragraphStyle.lineBreakMode = .byClipping

        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    static func paragraphAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = ConflictEditorStyle.lineHeight
        paragraphStyle.maximumLineHeight = ConflictEditorStyle.lineHeight
        paragraphStyle.lineBreakMode = .byClipping

        return [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
    }

    static func highlightedText(_ text: String, filePath: String, font: NSFont) -> NSAttributedString {
        let language = CodeSyntaxHighlighter.language(for: filePath)
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        let paragraphAttributes = paragraphAttributes(font: font)
        let newlineAttributes = baseAttributes(font: font)

        for index in lines.indices {
            let highlightedLine = NSMutableAttributedString(
                attributedString: CodeSyntaxHighlighter.highlight(lines[index], language: language, font: font)
            )
            highlightedLine.addAttributes(paragraphAttributes, range: NSRange(location: 0, length: highlightedLine.length))
            result.append(highlightedLine)
            if index < lines.count - 1 {
                result.append(
                    NSAttributedString(
                        string: "\n",
                        attributes: newlineAttributes
                    )
                )
            }
        }

        return result
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ConflictOutputEditorView
        weak var scrollView: NSScrollView?
        var isUpdating = false
        var isSyncing = false
        var isScrolling = false
        var lastAppliedTextRevision = -1
        var lastAppliedScrollRequestID = -1
        var lastAnchorSignature: [Int] = []
        var pendingViewportRebase = false
        var suppressSharedOutputSync = false
        var lastProgrammaticOrigin: CGPoint?

        init(_ parent: ConflictOutputEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? ConflictOutputTextView else { return }
            let selection = textView.selectedRange()
            isUpdating = true
            pendingViewportRebase = true
            suppressSharedOutputSync = true
            parent.scrollDriver = .output
            parent.suppressSideScrollFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.parent.suppressSideScrollFeedback = false
                self.suppressSharedOutputSync = false
            }
            parent.text = textView.string
            if let storage = textView.textStorage {
                storage.setAttributedString(
                    ConflictOutputEditorView.highlightedText(
                        textView.string,
                        filePath: parent.filePath,
                        font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                    )
                )
                textView.setSelectedRange(selection)
            }
            textView.typingAttributes = ConflictOutputEditorView.baseAttributes(
                font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            )
            textView.configure(
                blocks: parent.blocks,
                lineOrigins: parent.lineOrigins,
                currentBlockID: parent.currentBlockID,
                filePath: parent.filePath
            )
            isUpdating = false
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView else { return }
            let origin = scrollView.contentView.bounds.origin
            if let lastProgrammaticOrigin,
               abs(lastProgrammaticOrigin.x - origin.x) < 1,
               abs(lastProgrammaticOrigin.y - origin.y) < 1 {
                self.lastProgrammaticOrigin = nil
                return
            }
            guard !isSyncing else { return }
            isScrolling = true
            DispatchQueue.main.async {
                guard let textView = scrollView.documentView as? ConflictOutputTextView else {
                    self.parent.scrollOffset = origin
                    self.isScrolling = false
                    return
                }
                let topLine = textView.topVisibleLogicalPosition(in: scrollView)
                let scalar = ConflictScrollSync.scalar(
                    forTopLine: topLine,
                    anchors: ConflictScrollSync.outputAnchors(for: self.parent.blocks),
                    totalLines: textView.logicalLineCount
                )
                self.parent.scrollDriver = .output
                conflictScrollDebugLog("scrollOutput topLine=\(topLine) scalar=\(scalar) originY=\(origin.y)")
                self.parent.scrollOffset = CGPoint(
                    x: origin.x,
                    y: CGFloat(scalar) * SideCodeContentView.lineHeight
                )
                self.isScrolling = false
            }
        }
    }
}

final class ConflictOutputTextView: LineNumberTextView {
    private static let markerInsetX: CGFloat = 3
    private var blocks: [ConflictEditorBlock] = []
    private var lineOrigins: [ConflictEditorDocument.OutputLineOrigin] = []
    private var currentBlockID: Int?
    private var syntaxLanguage: CodeSyntaxHighlighter.Language = .unknown
    weak var conflictUndoManager: UndoManager?
    var canUndoConflictAction: (() -> Bool)?
    var canRedoConflictAction: (() -> Bool)?
    var onUndoConflictAction: (() -> Void)?
    var onRedoConflictAction: (() -> Void)?
    var onSave: (() -> Void)?
    var logicalLineCount: Int {
        max(string.components(separatedBy: "\n").count, 1)
    }

    func configure(
        blocks: [ConflictEditorBlock],
        lineOrigins: [ConflictEditorDocument.OutputLineOrigin],
        currentBlockID: Int?,
        filePath: String
    ) {
        self.blocks = blocks
        self.lineOrigins = lineOrigins
        self.currentBlockID = currentBlockID
        self.syntaxLanguage = CodeSyntaxHighlighter.language(for: filePath)
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSave?()
            return true
        }

        let normalized = event.charactersIgnoringModifiers?.lowercased()
        if normalized == "z",
           modifiers == .command || modifiers == [.command, .shift] {
            if modifiers == .command, canUndoConflictAction?() == true {
                onUndoConflictAction?()
                return true
            }
            if modifiers == [.command, .shift], canRedoConflictAction?() == true {
                onRedoConflictAction?()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    func scrollToLogicalLine(_ lineIndex: Int, in scrollView: NSScrollView) {
        scrollToLogicalPosition(Double(max(lineIndex, 0)), in: scrollView, withContextPadding: true)
    }

    func scrollToLogicalPosition(_ position: Double, in scrollView: NSScrollView, withContextPadding: Bool = false) {
        guard let layoutManager, let textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let clampedPosition = max(position, 0)
        let wholeLine = Int(floor(clampedPosition))
        let fractional = clampedPosition - Double(wholeLine)
        let targetCharIndex = characterIndex(forLogicalLine: wholeLine)
        guard targetCharIndex >= 0 else { return }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: targetCharIndex)
        var effectiveRange = NSRange()
        let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
        let lineHeight = max(fragmentRect.height, 1)
        let targetY = max(
            0,
            fragmentRect.minY
                + CGFloat(fractional) * lineHeight
                + textContainerInset.height
                - (withContextPadding ? SideCodeContentView.lineHeight * 2 : 0)
        )
        let currentX = scrollView.contentView.bounds.origin.x
        scrollView.contentView.scroll(to: CGPoint(x: currentX, y: targetY))
    }

    func topVisibleLogicalPosition(in scrollView: NSScrollView) -> Double {
        guard let layoutManager, let textContainer else { return 0 }

        layoutManager.ensureLayout(for: textContainer)
        let containerPoint = NSPoint(
            x: 0,
            y: max(scrollView.contentView.bounds.minY - textContainerInset.height, 0)
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        let visibleCharacterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let lineIndex = logicalLineIndex(forCharacterAt: visibleCharacterIndex)
        let lineCharIndex = characterIndex(forLogicalLine: lineIndex)
        let lineGlyphIndex = layoutManager.glyphIndexForCharacter(at: lineCharIndex)
        var effectiveRange = NSRange()
        let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphIndex, effectiveRange: &effectiveRange)
        let delta = max(containerPoint.y - fragmentRect.minY, 0)
        let fraction = min(max(delta / max(fragmentRect.height, 1), 0), 0.999)
        return Double(lineIndex) + fraction
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        enumerateVisibleLogicalLines(in: rect) { [weak self] lineNumber, _, fragmentRect in
            guard let self else { return }
            let lineIndex = lineNumber - 1
            guard lineIndex >= 0, lineIndex < self.lineOrigins.count else { return }
            let origin = self.lineOrigins[lineIndex]
            guard let color = self.highlightColor(for: origin) else { return }

            let isCurrent = self.block(containing: lineIndex)?.id == self.currentBlockID
            let fillRect = NSRect(
                x: self.pinnedViewportMinX(for: rect) + LineNumberTextView.gutterWidth + 2,
                y: fragmentRect.minY + self.textContainerInset.height,
                width: max(self.bounds.width - LineNumberTextView.gutterWidth - 8, 40),
                height: max(fragmentRect.height, 14)
            )
            color.withAlphaComponent(self.backgroundAlpha(for: origin, isCurrentBlock: isCurrent)).setFill()
            fillRect.fill()
            if let marker = self.lineMarker(for: origin) {
                self.drawOriginMarker(marker, color: color, fragmentRect: fragmentRect, visibleRect: rect)
            }
        }
    }

    private func block(containing lineIndex: Int) -> ConflictEditorBlock? {
        blocks.first { block in
            guard let range = block.activeRange else { return false }
            return range.contains(lineIndex)
        }
    }

    private func highlightColor(for origin: ConflictEditorDocument.OutputLineOrigin) -> NSColor? {
        switch origin {
        case .ancestor:
            return ConflictEditorStyle.unresolvedBaseColor
        case .current:
            return .systemBlue
        case .incoming:
            return .systemOrange
        case .common:
            return nil
        case .manual:
            return .systemPurple
        }
    }

    private func backgroundAlpha(
        for origin: ConflictEditorDocument.OutputLineOrigin,
        isCurrentBlock: Bool
    ) -> CGFloat {
        switch origin {
        case .common:
            return 0
        case .ancestor:
            return isCurrentBlock ? 0.22 : 0.10
        case .current, .incoming:
            return isCurrentBlock ? 0.24 : 0.11
        case .manual:
            return isCurrentBlock ? 0.20 : 0.10
        }
    }

    private func lineMarker(for origin: ConflictEditorDocument.OutputLineOrigin) -> Character? {
        switch origin {
        case .ancestor:
            return "="
        case .current:
            return "A"
        case .incoming:
            return "B"
        case .common:
            return nil
        case .manual:
            return "M"
        }
    }

    private func drawOriginMarker(
        _ marker: Character,
        color: NSColor,
        fragmentRect: NSRect,
        visibleRect: NSRect
    ) {
        let gutterMinX = pinnedViewportMinX(for: visibleRect)
        let badgeFont = NSFont.systemFont(ofSize: 8, weight: .bold)
        let badgeStr = NSAttributedString(
            string: String(marker),
            attributes: [.font: badgeFont, .foregroundColor: color]
        )
        let bSz = badgeStr.size()
        badgeStr.draw(
            at: NSPoint(
                x: gutterMinX + Self.markerInsetX,
                y: fragmentRect.minY + textContainerInset.height + (fragmentRect.height - bSz.height) / 2
            )
        )
    }

    private func characterIndex(forLogicalLine lineIndex: Int) -> Int {
        guard lineIndex > 0 else { return 0 }

        let nsString = string as NSString
        let length = nsString.length
        guard length > 0 else { return 0 }

        var currentLine = 0
        var searchIndex = 0
        while searchIndex < length {
            if currentLine == lineIndex {
                return searchIndex
            }

            let lineRange = nsString.lineRange(for: NSRange(location: searchIndex, length: 0))
            let nextIndex = NSMaxRange(lineRange)
            guard nextIndex > searchIndex else { break }
            searchIndex = nextIndex
            currentLine += 1
        }

        return length
    }

    private func logicalLineIndex(forCharacterAt characterIndex: Int) -> Int {
        let nsString = string as NSString
        let boundedIndex = min(max(characterIndex, 0), nsString.length)
        guard boundedIndex > 0 else { return 0 }

        var lineIndex = 0
        var searchIndex = 0
        while searchIndex < boundedIndex {
            let lineRange = nsString.lineRange(for: NSRange(location: searchIndex, length: 0))
            let nextIndex = NSMaxRange(lineRange)
            guard nextIndex > searchIndex else { break }
            searchIndex = nextIndex
            lineIndex += 1
        }

        return lineIndex
    }
}

// MARK: - Simple Syntax Highlighter

/// Provides basic syntax highlighting for code content using NSAttributedString.
/// Supports keywords, strings, comments, numbers, and type names based on file extension.
enum CodeSyntaxHighlighter {
    // Language detection from file path
    enum Language {
        case swift, javascript, typescript, python, ruby, java, kotlin, cSharp
        case go, rust, cpp, objc, dart, html, css, sql, shell, yaml, json, xml
        case unknown
    }

    static func language(for path: String) -> Language {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "py": return .python
        case "rb": return .ruby
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "cs": return .cSharp
        case "go": return .go
        case "rs": return .rust
        case "c", "h", "cpp", "hpp", "cc", "cxx", "hxx": return .cpp
        case "m", "mm": return .objc
        case "dart": return .dart
        case "html", "htm": return .html
        case "css", "scss", "less": return .css
        case "sql": return .sql
        case "sh", "bash", "zsh": return .shell
        case "yml", "yaml": return .yaml
        case "json": return .json
        case "xml", "plist", "xib", "storyboard": return .xml
        default: return .unknown
        }
    }

    private static func keywords(for lang: Language) -> Set<String> {
        switch lang {
        case .swift:
            return ["import", "class", "struct", "enum", "protocol", "extension", "func",
                    "var", "let", "if", "else", "guard", "return", "switch", "case", "default",
                    "for", "while", "repeat", "break", "continue", "throw", "throws", "try",
                    "catch", "do", "in", "where", "as", "is", "self", "Self", "super", "init",
                    "deinit", "nil", "true", "false", "public", "private", "internal", "fileprivate",
                    "open", "static", "final", "override", "mutating", "nonmutating", "lazy",
                    "weak", "unowned", "async", "await", "some", "any", "typealias", "associatedtype",
                    "operator", "infix", "prefix", "postfix", "inout", "defer", "willSet", "didSet",
                    "get", "set", "@Observable", "@MainActor", "@State", "@Binding", "@Published"]
        case .javascript, .typescript:
            return ["import", "export", "from", "const", "let", "var", "function", "class",
                    "extends", "return", "if", "else", "for", "while", "do", "switch", "case",
                    "default", "break", "continue", "throw", "try", "catch", "finally", "new",
                    "this", "super", "typeof", "instanceof", "void", "delete", "in", "of",
                    "async", "await", "yield", "true", "false", "null", "undefined",
                    "interface", "type", "enum", "implements", "abstract", "readonly", "as"]
        case .python:
            return ["import", "from", "class", "def", "return", "if", "elif", "else", "for",
                    "while", "break", "continue", "pass", "raise", "try", "except", "finally",
                    "with", "as", "in", "not", "and", "or", "is", "None", "True", "False",
                    "lambda", "yield", "global", "nonlocal", "assert", "del", "async", "await",
                    "self", "cls"]
        case .java, .kotlin:
            return ["import", "package", "class", "interface", "enum", "extends", "implements",
                    "public", "private", "protected", "static", "final", "abstract", "void",
                    "return", "if", "else", "for", "while", "do", "switch", "case", "default",
                    "break", "continue", "throw", "throws", "try", "catch", "finally", "new",
                    "this", "super", "true", "false", "null", "instanceof", "synchronized",
                    "val", "var", "fun", "when", "object", "companion", "data", "sealed",
                    "override", "open", "suspend", "lateinit", "by", "lazy"]
        case .dart:
            return ["import", "export", "class", "extends", "implements", "mixin", "with",
                    "abstract", "void", "return", "if", "else", "for", "while", "do", "switch",
                    "case", "default", "break", "continue", "throw", "try", "catch", "finally",
                    "new", "this", "super", "true", "false", "null", "var", "final", "const",
                    "late", "required", "async", "await", "yield", "dynamic", "typedef",
                    "static", "enum", "factory", "get", "set", "operator", "covariant"]
        case .go:
            return ["package", "import", "func", "return", "if", "else", "for", "range",
                    "switch", "case", "default", "break", "continue", "go", "defer", "chan",
                    "map", "struct", "interface", "type", "var", "const", "true", "false", "nil",
                    "select", "fallthrough", "goto"]
        case .rust:
            return ["use", "mod", "fn", "let", "mut", "const", "static", "struct", "enum",
                    "impl", "trait", "pub", "crate", "self", "super", "return", "if", "else",
                    "for", "while", "loop", "break", "continue", "match", "as", "in", "ref",
                    "move", "async", "await", "where", "type", "true", "false", "unsafe", "extern"]
        case .cpp, .objc:
            return ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                    "class", "struct", "enum", "union", "namespace", "using", "typedef",
                    "public", "private", "protected", "virtual", "override", "const", "static",
                    "extern", "inline", "volatile", "mutable", "explicit", "template", "typename",
                    "void", "return", "if", "else", "for", "while", "do", "switch", "case",
                    "default", "break", "continue", "throw", "try", "catch", "new", "delete",
                    "this", "true", "false", "nullptr", "NULL", "auto", "register",
                    "@interface", "@implementation", "@end", "@property", "@synthesize",
                    "@selector", "@protocol", "@optional", "@required", "self", "nil", "YES", "NO"]
        case .html, .xml:
            return []
        case .css:
            return ["important", "inherit", "initial", "unset", "none", "auto", "block",
                    "inline", "flex", "grid", "relative", "absolute", "fixed", "sticky"]
        case .sql:
            return ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP",
                    "ALTER", "TABLE", "INDEX", "VIEW", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER",
                    "ON", "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN", "LIKE", "ORDER", "BY",
                    "GROUP", "HAVING", "LIMIT", "OFFSET", "AS", "NULL", "TRUE", "FALSE",
                    "select", "from", "where", "insert", "update", "delete", "create", "drop",
                    "alter", "table", "join", "left", "right", "inner", "outer", "on", "and",
                    "or", "not", "in", "order", "by", "group", "having", "limit", "as", "null"]
        case .shell:
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case",
                    "esac", "function", "return", "exit", "echo", "export", "source", "local",
                    "readonly", "unset", "shift", "true", "false", "in"]
        case .yaml, .json:
            return ["true", "false", "null", "yes", "no"]
        default:
            return []
        }
    }

    private static let commentColor = NSColor.systemGreen
    private static let stringColor = NSColor.systemRed
    private static let keywordColor = NSColor.systemPink
    private static let numberColor = NSColor.systemPurple
    private static let typeColor = NSColor(calibratedRed: 0.42, green: 0.68, blue: 0.90, alpha: 1.0) // light blue

    /// Build an attributed string for a line of code with syntax highlighting.
    static func highlight(_ text: String, language lang: Language, font: NSFont) -> NSAttributedString {
        guard lang != .unknown, !text.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        }

        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let kws = keywords(for: lang)

        // 1. Detect line comments
        let lineCommentPrefixes: [String]
        switch lang {
        case .swift, .javascript, .typescript, .java, .kotlin, .dart, .go, .rust, .cpp, .objc, .cSharp:
            lineCommentPrefixes = ["//"]
        case .python, .ruby, .shell, .yaml:
            lineCommentPrefixes = ["#"]
        case .sql:
            lineCommentPrefixes = ["--"]
        case .html, .xml, .css, .json:
            lineCommentPrefixes = []
        default:
            lineCommentPrefixes = []
        }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for prefix in lineCommentPrefixes {
            if trimmed.hasPrefix(prefix) {
                result.addAttribute(.foregroundColor, value: commentColor, range: fullRange)
                return result
            }
        }

        // Find inline comment start (not inside a string)
        var commentStart: Int? = nil
        do {
            var inStr: Character? = nil
            var escaped = false
            for (idx, ch) in text.enumerated() {
                if escaped { escaped = false; continue }
                if ch == "\\" { escaped = true; continue }
                if let q = inStr {
                    if ch == q { inStr = nil }
                    continue
                }
                if ch == "\"" || ch == "'" || ch == "`" { inStr = ch; continue }
                for prefix in lineCommentPrefixes {
                    if text.dropFirst(idx).hasPrefix(prefix) {
                        commentStart = idx
                        break
                    }
                }
                if commentStart != nil { break }
            }
        }

        if let cs = commentStart {
            let commentRange = NSRange(location: cs, length: (text as NSString).length - cs)
            result.addAttribute(.foregroundColor, value: commentColor, range: commentRange)
        }

        let effectiveEnd = commentStart ?? (text as NSString).length

        // 2. Highlight strings
        let stringPattern = #"("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)"#
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: effectiveEnd))
            for match in matches {
                result.addAttribute(.foregroundColor, value: stringColor, range: match.range)
            }
        }

        // 3. Highlight numbers
        let numberPattern = #"\b(\d+\.?\d*([eE][+-]?\d+)?|0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+)\b"#
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: effectiveEnd))
            for match in matches {
                // Only color if not already colored (i.e., not inside a string)
                let existingColor = result.attribute(.foregroundColor, at: match.range.location, effectiveRange: nil)
                if existingColor as? NSColor == NSColor.labelColor {
                    result.addAttribute(.foregroundColor, value: numberColor, range: match.range)
                }
            }
        }

        // 4. Highlight keywords and type names
        let wordPattern = #"\b[A-Za-z_@][A-Za-z0-9_]*\b"#
        if let regex = try? NSRegularExpression(pattern: wordPattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: effectiveEnd))
            for match in matches {
                let word = (text as NSString).substring(with: match.range)
                // Only color if not already colored
                let existingColor = result.attribute(.foregroundColor, at: match.range.location, effectiveRange: nil)
                guard existingColor as? NSColor == NSColor.labelColor else { continue }

                if kws.contains(word) {
                    result.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
                } else if word.first?.isUppercase == true && word.count > 1 {
                    // Type names (PascalCase)
                    result.addAttribute(.foregroundColor, value: typeColor, range: match.range)
                }
            }
        }

        return result
    }
}

// MARK: - Side Code Content View (ours/theirs with checkboxes)

final class SideCodeContentView: NSView {
    static let lineHeight: CGFloat = 19
    private static let lineNumWidth: CGFloat = 56
    private static let checkboxSize: CGFloat = 14

    private var lines: [String] = []
    private var conflictRegions: [ConflictRegion] = []
    private var displayLayout = SideDisplayLayout(rows: [], regionDisplayRanges: [])
    private var side: ConflictSide = .ours
    private var highlightColor: NSColor = .systemBlue
    private var regionChoices: [Int: RepoViewModel.RegionChoice] = [:]
    private var onToggleRegion: ((Int) -> Void)?
    private var syntaxLanguage: CodeSyntaxHighlighter.Language = .unknown
    private var cachedContentLines: [Int: NSAttributedString] = [:]
    private var displayLineToRegionIndex: [Int?] = []
    private(set) var cachedEstimatedWidth: CGFloat = 400
    var displayLineCount: Int { displayLayout.rows.count }
    var displayAnchors: [Int] { displayLayout.anchors }

    override var isFlipped: Bool { true }

    private static func tabParagraphStyle(for font: NSFont) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let spaceAdvance = max(font.advancement(forGlyph: font.glyph(withName: "space")).width, 7)
        let tabWidth = spaceAdvance * 4
        paragraphStyle.defaultTabInterval = tabWidth
        paragraphStyle.tabStops = (1...32).map { index in
            NSTextTab(textAlignment: .left, location: CGFloat(index) * tabWidth, options: [:])
        }
        return paragraphStyle
    }

    func configure(
        lines: [String], conflictRegions: [ConflictRegion], side: ConflictSide,
        highlightColor: NSColor, regionChoices: [Int: RepoViewModel.RegionChoice],
        onToggleRegion: @escaping (Int) -> Void,
        filePath: String = ""
    ) -> Bool {
        let language = CodeSyntaxHighlighter.language(for: filePath)
        let linesChanged = lines != self.lines
        let sideChanged = side != self.side
        let regionsChanged = conflictRegions != self.conflictRegions
        let languageChanged = language != self.syntaxLanguage
        let highlightChanged = highlightColor != self.highlightColor
        let choicesChanged = regionChoices != self.regionChoices

        if linesChanged {
            let maxLen = lines.reduce(0) { max($0, $1.count) }
            cachedEstimatedWidth = CGFloat(maxLen) * 8.4 + 80
        }

        self.lines = lines
        self.conflictRegions = conflictRegions
        if linesChanged || sideChanged || regionsChanged {
            self.displayLayout = SideDisplayLayout.make(lines: lines, conflictRegions: conflictRegions, side: side)
            rebuildDisplayLineRegionIndex()
        }
        self.side = side
        self.highlightColor = highlightColor
        self.regionChoices = regionChoices
        self.onToggleRegion = onToggleRegion
        self.syntaxLanguage = language

        if linesChanged || languageChanged {
            cachedContentLines.removeAll(keepingCapacity: true)
        }

        return linesChanged || sideChanged || regionsChanged || languageChanged || highlightChanged || choicesChanged
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lineNumFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let contentParagraphStyle = Self.tabParagraphStyle(for: font)
        let lineH = Self.lineHeight
        let lnW = Self.lineNumWidth

        let visibleRect = self.visibleRect
        let startLine = max(0, Int(visibleRect.minY / lineH) - 1)
        let endLine = min(displayLayout.rows.count, Int(visibleRect.maxY / lineH) + 2)
        guard startLine <= endLine else { return }

        for i in startLine..<endLine {
            let y = CGFloat(i) * lineH
            let lineRect = NSRect(x: 0, y: y, width: bounds.width, height: lineH)
            let regionIdx = conflictRegionIndex(forDisplayLine: i)
            let isConflict = regionIdx != nil
            let isChecked: Bool = {
                guard let ri = regionIdx, let choice = regionChoices[ri] else { return false }
                return side == .ours ? choice.oursChecked : choice.theirsChecked
            }()

            if isConflict {
                ctx.setFillColor(highlightColor.withAlphaComponent(isChecked ? 0.24 : 0.11).cgColor)
                ctx.fill(lineRect)
            }

            // Checkbox for first line of each conflict region
            if isConflict, let ri = regionIdx, isFirstLineOfRegion(i, ri) {
                let ckX: CGFloat = 3
                let ckY = y + (lineH - Self.checkboxSize) / 2
                let ckRect = NSRect(x: ckX, y: ckY, width: Self.checkboxSize, height: Self.checkboxSize)
                let path = CGPath(roundedRect: ckRect.insetBy(dx: 1, dy: 1), cornerWidth: 2, cornerHeight: 2, transform: nil)

                if isChecked {
                    ctx.setFillColor(highlightColor.withAlphaComponent(0.42).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                    ctx.setStrokeColor(highlightColor.withAlphaComponent(0.98).cgColor)
                    ctx.setLineWidth(1.25)
                    ctx.addPath(path)
                    ctx.strokePath()
                    let checkAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                        .foregroundColor: NSColor.white
                    ]
                    let check = NSAttributedString(string: "\u{2713}", attributes: checkAttrs)
                    check.draw(at: NSPoint(x: ckX + 2, y: ckY))
                } else {
                    ctx.setFillColor(NSColor.textBackgroundColor.withAlphaComponent(0.85).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                    ctx.setStrokeColor(highlightColor.withAlphaComponent(0.92).cgColor)
                    ctx.setLineWidth(1.25)
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
            let lineNumberText = displayLayout.rows[i].sourceLineIndex.map { "\($0 + 1)" } ?? ""
            let numStr = NSAttributedString(
                string: lineNumberText,
                attributes: [.font: lineNumFont, .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.5)]
            )
            let numSz = numStr.size()
            numStr.draw(at: NSPoint(x: lnW - numSz.width - 4, y: y + (lineH - numSz.height) / 2))

            // Content text is cached by source line to avoid re-highlighting on every draw pass.
            let sourceIndex = displayLayout.rows[i].sourceLineIndex
            let textX: CGFloat = lnW + 8
            let contentStr = cachedContentLine(
                for: sourceIndex,
                font: font,
                paragraphStyle: contentParagraphStyle
            )
            let contentRect = NSRect(
                x: textX,
                y: y + 1,
                width: max(bounds.width - textX - 8, 40),
                height: lineH
            )
            contentStr.draw(with: contentRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let lineIdx = Int(loc.y / Self.lineHeight)
        guard lineIdx >= 0, lineIdx < displayLayout.rows.count else { super.mouseDown(with: event); return }
        if let ri = conflictRegionIndex(forDisplayLine: lineIdx), isFirstLineOfRegion(lineIdx, ri), loc.x < Self.lineNumWidth {
            onToggleRegion?(ri)
            return
        }
        super.mouseDown(with: event)
    }

    private func conflictRegionIndex(forDisplayLine lineIdx: Int) -> Int? {
        guard lineIdx >= 0, lineIdx < displayLineToRegionIndex.count else { return nil }
        return displayLineToRegionIndex[lineIdx]
    }

    private func isFirstLineOfRegion(_ lineIdx: Int, _ regionIdx: Int) -> Bool {
        displayLayout.regionDisplayRanges[regionIdx].lowerBound == lineIdx
    }

    private func rebuildDisplayLineRegionIndex() {
        displayLineToRegionIndex = Array(repeating: nil, count: displayLayout.rows.count)
        for (regionIndex, range) in displayLayout.regionDisplayRanges.enumerated() {
            for lineIndex in range {
                guard lineIndex < displayLineToRegionIndex.count else { continue }
                displayLineToRegionIndex[lineIndex] = regionIndex
            }
        }
    }

    private func cachedContentLine(
        for sourceIndex: Int?,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        guard let sourceIndex else {
            return NSAttributedString(string: " ", attributes: [.font: font, .paragraphStyle: paragraphStyle])
        }

        if let cached = cachedContentLines[sourceIndex] {
            return cached
        }

        let text = lines[sourceIndex].isEmpty ? " " : lines[sourceIndex]
        let contentStr = NSMutableAttributedString(
            attributedString: CodeSyntaxHighlighter.highlight(text, language: syntaxLanguage, font: font)
        )
        contentStr.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: contentStr.length)
        )
        let frozen = NSAttributedString(attributedString: contentStr)
        cachedContentLines[sourceIndex] = frozen
        return frozen
    }
}

// MARK: - Output Code Content View (with A/B origin markers)

final class OutputCodeContentView: NSView {
    static let lineHeight: CGFloat = 17
    private static let lineNumWidth: CGFloat = 56

    private var lines: [String] = []
    private var conflictSides: ConflictSides?
    private var regionChoices: [Int: RepoViewModel.RegionChoice] = [:]
    private var lineOrigins: [(origin: Character?, color: NSColor?)] = []
    private var syntaxLanguage: CodeSyntaxHighlighter.Language = .unknown
    private(set) var cachedEstimatedWidth: CGFloat = 400

    override var isFlipped: Bool { true }

    func configure(lines: [String], conflictSides: ConflictSides?, regionChoices: [Int: RepoViewModel.RegionChoice], filePath: String = "") {
        let linesChanged = lines.count != self.lines.count
        let sidesChanged = conflictSides != self.conflictSides
        let choicesChanged = regionChoices != self.regionChoices
        if linesChanged {
            let maxLen = lines.reduce(0) { max($0, $1.count) }
            cachedEstimatedWidth = CGFloat(maxLen) * 8.4 + 80
        }
        self.lines = lines
        self.conflictSides = conflictSides
        self.regionChoices = regionChoices
        self.syntaxLanguage = CodeSyntaxHighlighter.language(for: filePath)
        if linesChanged || sidesChanged || choicesChanged {
            computeLineOrigins()
        }
    }

    private func computeLineOrigins() {
        guard let sides = conflictSides else {
            lineOrigins = lines.map { _ in (nil, nil) }
            return
        }
        let oursLines = sides.oursLines
        let theirsLines = sides.theirsLines

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
                                origins.append(("=", ConflictEditorStyle.unresolvedBaseColor))
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

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lineNumFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
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

            // Content (with syntax highlighting)
            guard i < lines.count else { continue }
            let text = lines[i].isEmpty ? " " : lines[i]
            let contentStr = CodeSyntaxHighlighter.highlight(text, language: syntaxLanguage, font: font)
            let textSz = contentStr.size()
            contentStr.draw(at: NSPoint(x: lnW + 8, y: y + (lineH - textSz.height) / 2))
        }
    }
}
