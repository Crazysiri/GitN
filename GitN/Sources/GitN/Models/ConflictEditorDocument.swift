import Foundation

private func conflictDebugLog(_ message: @autoclosure () -> String) {
    print("[ConflictDebug] \(message())")
}

struct ConflictEditorBlock: Identifiable, Equatable, Sendable {
    enum SelectionSide: String, Equatable, Hashable, Sendable {
        case current
        case incoming
    }

    enum Mode: String, Equatable, Hashable, Sendable {
        case attached
        case detached
    }

    enum ContentState: String, Equatable, Hashable, Sendable {
        case auto
        case edited
        case manual
    }

    enum ResolutionIntent: String, Equatable, Hashable, Sendable {
        case unresolved
        case selected
        case manual
        case ancestor
    }

    enum BothOrder: String, Equatable, Hashable, Sendable {
        case currentFirst
        case incomingFirst
    }

    struct SelectedSources: Equatable, Sendable {
        var current: Bool
        var incoming: Bool

        var hasSelection: Bool {
            current || incoming
        }
    }

    struct ControlledRange: Equatable, Sendable {
        var lineRange: Range<Int>
        var lastGeneratedText: String
    }

    struct Anchor: Equatable, Sendable {
        var preferredLine: Int
        var beforeContext: String?
        var afterContext: String?
    }

    let id: Int
    let baseLines: [String]
    let currentLines: [String]
    let incomingLines: [String]
    let rawConflictLines: [String]
    var anchor: Anchor
    let initialAttachedRange: Range<Int>
    var selectedSources: SelectedSources
    var selectionOrder: [SelectionSide]
    var mode: Mode
    var contentState: ContentState
    var resolutionIntent: ResolutionIntent
    var controlledBlock: ControlledRange?
    var insertionSegment: ControlledRange?
    var currentDisplayRange: Range<Int>?
    var incomingDisplayRange: Range<Int>?
    var lastResolvedText: String
    var preferDirectAnchorInsertion: Bool
    var directInsertionLine: Int?

    var activeRange: Range<Int>? {
        let ranges = [currentDisplayRange, incomingDisplayRange].compactMap { $0 }
        if let first = ranges.first {
            let lower = ranges.map(\.lowerBound).min() ?? first.lowerBound
            let upper = ranges.map(\.upperBound).max() ?? first.upperBound
            return lower..<upper
        }
        switch mode {
        case .attached: return controlledBlock?.lineRange
        case .detached: return insertionSegment?.lineRange
        }
    }

    var isResolved: Bool { resolutionIntent != .unresolved }

    var modeBadgeText: String {
        switch (mode, contentState) {
        case (.attached, .auto):
            return "Replace"
        case (.attached, .edited):
            return "Replace · Edited"
        case (.attached, .manual):
            return "Replace · Manual"
        case (.detached, .auto):
            return "Insert"
        case (.detached, .edited):
            return "Insert · Edited"
        case (.detached, .manual):
            return "Insert · Manual"
        }
    }
}

struct ConflictEditorDocument: Equatable, Sendable {
    enum OutputLineOrigin: Equatable, Sendable {
        case common
        case ancestor
        case current
        case incoming
        case manual
    }

    let oursLabel: String
    let theirsLabel: String
    let baseLines: [String]
    let oursLines: [String]
    let theirsLines: [String]

    private let initialOutputText: String
    private let initialOutputLineOrigins: [OutputLineOrigin]
    private let initialBlocks: [ConflictEditorBlock]

    var outputText: String
    var outputLineOrigins: [OutputLineOrigin]
    var blocks: [ConflictEditorBlock]

    init(sides: ConflictSides) {
        oursLabel = sides.oursLabel
        theirsLabel = sides.theirsLabel
        baseLines = sides.baseLines
        oursLines = sides.oursLines
        theirsLines = sides.theirsLines

        let outputText = sides.outputLines.joined(separator: "\n")
        self.outputText = outputText
        let initialOutputLineOrigins = Self.makeInitialOutputLineOrigins(sides: sides)
        outputLineOrigins = initialOutputLineOrigins

        let initialBlocks = sides.markers.enumerated().map { index, marker in
            let beforeContext = marker.outputRange.lowerBound > 0
                ? sides.outputLines[marker.outputRange.lowerBound - 1]
                : nil
            let afterContext = marker.outputRange.upperBound < sides.outputLines.count
                ? sides.outputLines[marker.outputRange.upperBound]
                : nil

            let baseLines = marker.baseLines
            let currentLines = marker.currentLines
            let incomingLines = marker.incomingLines
            let generatedText = baseLines.joined(separator: "\n")

            return ConflictEditorBlock(
                id: index,
                baseLines: baseLines,
                currentLines: currentLines,
                incomingLines: incomingLines,
                rawConflictLines: marker.rawConflictLines,
                anchor: ConflictEditorBlock.Anchor(
                    preferredLine: marker.outputRange.lowerBound,
                    beforeContext: beforeContext,
                    afterContext: afterContext
                ),
                initialAttachedRange: marker.outputRange,
                selectedSources: ConflictEditorBlock.SelectedSources(current: false, incoming: false),
                selectionOrder: [],
                mode: .attached,
                contentState: .manual,
                resolutionIntent: .unresolved,
                controlledBlock: ConflictEditorBlock.ControlledRange(
                    lineRange: marker.outputRange,
                    lastGeneratedText: generatedText
                ),
                insertionSegment: nil,
                currentDisplayRange: nil,
                incomingDisplayRange: nil,
                lastResolvedText: generatedText,
                preferDirectAnchorInsertion: false,
                directInsertionLine: marker.outputRange.lowerBound
            )
        }

        initialOutputText = outputText
        self.initialOutputLineOrigins = initialOutputLineOrigins
        self.initialBlocks = initialBlocks
        blocks = initialBlocks
    }

    var outputLines: [String] {
        outputText.components(separatedBy: "\n")
    }

    var hasOutputChanges: Bool {
        outputText != initialOutputText
    }

    var unresolvedBlockIDs: [Int] {
        blocks.filter { !$0.isResolved }.map(\.id)
    }

    mutating func keepAncestor(blockID: Int) {
        guard let index = indexOfBlock(id: blockID), blocks[index].mode == .attached else { return }
        blocks[index].selectedSources = .init(current: false, incoming: false)
        blocks[index].selectionOrder = []
        applySelection(to: index)
        blocks[index].resolutionIntent = .ancestor
    }

    mutating func resetAll() {
        outputText = initialOutputText
        outputLineOrigins = initialOutputLineOrigins
        blocks = initialBlocks
    }

    mutating func toggleCurrent(blockID: Int) {
        guard let index = indexOfBlock(id: blockID) else { return }
        blocks[index].selectedSources.current.toggle()
        updateSelectionOrder(for: index, toggled: .current, isSelected: blocks[index].selectedSources.current)
        applySelection(to: index)
    }

    mutating func toggleIncoming(blockID: Int) {
        guard let index = indexOfBlock(id: blockID) else { return }
        blocks[index].selectedSources.incoming.toggle()
        updateSelectionOrder(for: index, toggled: .incoming, isSelected: blocks[index].selectedSources.incoming)
        applySelection(to: index)
    }

    mutating func setBothOrder(_ order: ConflictEditorBlock.BothOrder, for blockID: Int) {
        guard let index = indexOfBlock(id: blockID) else { return }
        blocks[index].selectionOrder = order == .currentFirst ? [.current, .incoming] : [.incoming, .current]
        applySelection(to: index)
    }

    mutating func setAllCurrentSelected(_ isSelected: Bool) {
        let ids = blocks.map(\.id)
        for id in ids {
            guard let index = indexOfBlock(id: id),
                  blocks[index].selectedSources.current != isSelected else { continue }
            blocks[index].selectedSources.current = isSelected
            updateSelectionOrder(for: index, toggled: .current, isSelected: isSelected)
            applySelection(to: index)
        }
    }

    mutating func setAllIncomingSelected(_ isSelected: Bool) {
        let ids = blocks.map(\.id)
        for id in ids {
            guard let index = indexOfBlock(id: id),
                  blocks[index].selectedSources.incoming != isSelected else { continue }
            blocks[index].selectedSources.incoming = isSelected
            updateSelectionOrder(for: index, toggled: .incoming, isSelected: isSelected)
            applySelection(to: index)
        }
    }

    mutating func updateOutputText(_ newText: String) {
        guard newText != outputText else { return }
        let oldLines = outputLines
        let newLines = newText.components(separatedBy: "\n")
        let change = LineChange.make(oldLines: oldLines, newLines: newLines)

        outputText = newText
        outputLineOrigins.replaceSubrange(
            change.oldRange,
            with: repeatElement(.manual, count: change.newRange.count)
        )
        remapBlocksAfterManualEdit(change: change, newLines: newLines)
    }

    private func indexOfBlock(id: Int) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    private func resolvedLines(for block: ConflictEditorBlock) -> [String] {
        let current = block.selectedSources.current
        let incoming = block.selectedSources.incoming

        switch (current, incoming) {
        case (true, false):
            return block.currentLines
        case (false, true):
            return block.incomingLines
        case (true, true):
            return orderedSides(for: block).flatMap { side in
                side == .current ? block.currentLines : block.incomingLines
            }
        case (false, false):
            return []
        }
    }

    private func orderedSides(for block: ConflictEditorBlock) -> [ConflictEditorBlock.SelectionSide] {
        let filtered = block.selectionOrder.filter {
            $0 == .current ? block.selectedSources.current : block.selectedSources.incoming
        }
        if filtered.count == 2 { return filtered }
        if block.selectedSources.current && block.selectedSources.incoming {
            return [.current, .incoming]
        }
        if block.selectedSources.current { return [.current] }
        if block.selectedSources.incoming { return [.incoming] }
        return []
    }

    private mutating func updateSelectionOrder(
        for index: Int,
        toggled side: ConflictEditorBlock.SelectionSide,
        isSelected: Bool
    ) {
        if isSelected {
            blocks[index].selectionOrder.removeAll { $0 == side }
            blocks[index].selectionOrder.append(side)
        } else {
            blocks[index].selectionOrder.removeAll { $0 == side }
        }
    }

    private mutating func applySelection(to index: Int) {
        var block = blocks[index]
        block.resolutionIntent = block.selectedSources.hasSelection ? .selected : .unresolved
        blocks[index] = block
        let replacementLines = resolvedLines(for: block)

        switch block.mode {
        case .attached:
            guard let controlled = block.controlledBlock else {
                block.mode = .detached
                blocks[index] = block
                applySelection(to: index)
                return
            }

            let shouldRestoreBase = !block.selectedSources.hasSelection
            let replacement = shouldRestoreBase ? block.baseLines : replacementLines
            let replacementOrigins = shouldRestoreBase
                ? Array(repeating: OutputLineOrigin.ancestor, count: block.baseLines.count)
                : lineOrigins(for: orderedSides(for: block), block: block)
            let newRange = replaceLineRange(
                controlled.lineRange,
                with: replacement,
                origins: replacementOrigins,
                targetBlockID: block.id,
                targetKind: .controlled
            )
            block = blocks[index]
            block.controlledBlock = ConflictEditorBlock.ControlledRange(
                lineRange: newRange,
                lastGeneratedText: replacement.joined(separator: "\n")
            )
            let display = displayRanges(
                for: block,
                insertedAt: newRange.lowerBound,
                using: replacement
            )
            block.currentDisplayRange = display.current
            block.incomingDisplayRange = display.incoming
            block.insertionSegment = nil
            block.lastResolvedText = replacement.joined(separator: "\n")
            block.contentState = shouldRestoreBase ? .manual : .auto
            blocks[index] = block

        case .detached:
            if !block.selectedSources.current, let range = block.currentDisplayRange {
                removeDisplayedRange(
                    range,
                    forBlockAt: index,
                    clearing: .current
                )
                block = blocks[index]
            }
            if !block.selectedSources.incoming, let range = block.incomingDisplayRange {
                removeDisplayedRange(
                    range,
                    forBlockAt: index,
                    clearing: .incoming
                )
                block = blocks[index]
            }

            if replacementLines.isEmpty {
                if let segment = block.insertionSegment {
                    removeDisplayedRange(
                        segment.lineRange,
                        forBlockAt: index,
                        clearing: nil
                    )
                }
                return
            }

            let selectedSides = orderedSides(for: block)
            let missingSides = selectedSides.filter { side in
                switch side {
                case .current: return block.currentDisplayRange == nil
                case .incoming: return block.incomingDisplayRange == nil
                }
            }
            let linesToApply: [String]
            let sidesToApply: [ConflictEditorBlock.SelectionSide]
            if missingSides.isEmpty {
                linesToApply = replacementLines
                sidesToApply = selectedSides
            } else {
                sidesToApply = missingSides
                linesToApply = missingSides.flatMap { side in
                    side == .current ? block.currentLines : block.incomingLines
                }
            }

            let hasExistingDisplayedSides = selectedSides.count > sidesToApply.count

            if hasExistingDisplayedSides {
                let insertionPoint = max(
                    block.currentDisplayRange?.upperBound ?? 0,
                    block.incomingDisplayRange?.upperBound ?? 0,
                    locateAnchor(for: block)
                )
                let newRange = insertLines(
                    linesToApply,
                    at: insertionPoint,
                    origins: lineOrigins(for: sidesToApply, block: block),
                    targetBlockID: block.id
                )
                block = blocks[index]
                block.insertionSegment = ConflictEditorBlock.ControlledRange(
                    lineRange: newRange,
                    lastGeneratedText: linesToApply.joined(separator: "\n")
                )
                let display = displayRanges(
                    forSides: sidesToApply,
                    block: block,
                    insertedAt: newRange.lowerBound
                )
                if let current = display.current { block.currentDisplayRange = current }
                if let incoming = display.incoming { block.incomingDisplayRange = incoming }
            } else if let segment = block.insertionSegment {
                let newRange = replaceLineRange(
                    segment.lineRange,
                    with: linesToApply,
                    origins: lineOrigins(for: sidesToApply, block: block),
                    targetBlockID: block.id,
                    targetKind: .insertion
                )
                block = blocks[index]
                block.insertionSegment = ConflictEditorBlock.ControlledRange(
                    lineRange: newRange,
                    lastGeneratedText: linesToApply.joined(separator: "\n")
                )
                let display = displayRanges(
                    forSides: sidesToApply,
                    block: block,
                    insertedAt: newRange.lowerBound
                )
                if let current = display.current { block.currentDisplayRange = current }
                if let incoming = display.incoming { block.incomingDisplayRange = incoming }
            } else {
                let insertionPoint = locateAnchor(for: block)
                let newRange = insertLines(
                    linesToApply,
                    at: insertionPoint,
                    origins: lineOrigins(for: sidesToApply, block: block),
                    targetBlockID: block.id
                )
                block = blocks[index]
                block.insertionSegment = ConflictEditorBlock.ControlledRange(
                    lineRange: newRange,
                    lastGeneratedText: linesToApply.joined(separator: "\n")
                )
                let display = displayRanges(
                    forSides: sidesToApply,
                    block: block,
                    insertedAt: newRange.lowerBound
                )
                if let current = display.current { block.currentDisplayRange = current }
                if let incoming = display.incoming { block.incomingDisplayRange = incoming }
            }
            block.lastResolvedText = linesToApply.joined(separator: "\n")
            block.contentState = .auto
            block.preferDirectAnchorInsertion = false
            blocks[index] = block
        }
    }

    private func displayRanges(
        for block: ConflictEditorBlock,
        insertedAt start: Int,
        using replacement: [String]
    ) -> (current: Range<Int>?, incoming: Range<Int>?) {
        displayRanges(
            forSides: orderedSides(for: block),
            block: block,
            insertedAt: start
        )
    }

    private func displayRanges(
        forSides sides: [ConflictEditorBlock.SelectionSide],
        block: ConflictEditorBlock,
        insertedAt start: Int
    ) -> (current: Range<Int>?, incoming: Range<Int>?) {
        var cursor = start
        var current: Range<Int>?
        var incoming: Range<Int>?

        for side in sides {
            let count = side == .current ? block.currentLines.count : block.incomingLines.count
            let range = cursor..<(cursor + count)
            switch side {
            case .current: current = range
            case .incoming: incoming = range
            }
            cursor += count
        }
        return (current, incoming)
    }

    private enum RangeKind {
        case controlled
        case insertion
    }

    private func lineOrigins(
        for sides: [ConflictEditorBlock.SelectionSide],
        block: ConflictEditorBlock
    ) -> [OutputLineOrigin] {
        sides.flatMap { side in
            let count = side == .current ? block.currentLines.count : block.incomingLines.count
            let origin: OutputLineOrigin = side == .current ? .current : .incoming
            return Array(repeating: origin, count: count)
        }
    }

    @discardableResult
    private mutating func insertLines(
        _ linesToInsert: [String],
        at lineIndex: Int,
        origins: [OutputLineOrigin],
        targetBlockID: Int
    ) -> Range<Int> {
        replaceLineRange(
            lineIndex..<lineIndex,
            with: linesToInsert,
            origins: origins,
            targetBlockID: targetBlockID,
            targetKind: .insertion
        )
    }

    @discardableResult
    private mutating func replaceLineRange(
        _ range: Range<Int>,
        with replacement: [String],
        origins: [OutputLineOrigin],
        targetBlockID: Int,
        targetKind: RangeKind
    ) -> Range<Int> {
        var lines = outputLines
        lines.replaceSubrange(range, with: replacement)
        outputText = lines.joined(separator: "\n")
        outputLineOrigins.replaceSubrange(range, with: origins)

        let delta = replacement.count - range.count
        let newRange = range.lowerBound..<(range.lowerBound + replacement.count)

        for blockIndex in blocks.indices {
            if blocks[blockIndex].id == targetBlockID {
                switch targetKind {
                case .controlled:
                    blocks[blockIndex].controlledBlock?.lineRange = newRange
                case .insertion:
                    blocks[blockIndex].insertionSegment?.lineRange = newRange
                }
                continue
            }

            remapStoredRanges(
                for: &blocks[blockIndex],
                replacedRange: range,
                delta: delta
            )
        }

        return newRange
    }

    private func locateAnchor(for block: ConflictEditorBlock) -> Int {
        let lines = outputLines
        let preferred = min(max(block.anchor.preferredLine, 0), lines.count)

        if block.preferDirectAnchorInsertion {
            let directLine = min(max(block.directInsertionLine ?? preferred, 0), lines.count)
            return directLine
        }

        if let exactGap = exactContextGap(for: block.anchor, in: lines, preferred: preferred) {
            return exactGap
        }

        if let nearbyGap = nearestContextGap(for: block.anchor, in: lines, preferred: preferred) {
            return nearbyGap
        }

        if let pairedGap = pairedContextGap(for: block.anchor, in: lines, preferred: preferred) {
            return pairedGap
        }

        if let before = block.anchor.beforeContext,
           let after = block.anchor.afterContext,
           let beforeIndex = nearestIndex(of: before, in: lines, around: preferred, preferBefore: true),
           let afterIndex = nearestIndex(of: after, in: lines, around: preferred, preferBefore: false),
           beforeIndex < afterIndex {
            return beforeIndex + 1
        }

        if let before = block.anchor.beforeContext,
           let beforeIndex = nearestIndex(of: before, in: lines, around: preferred, preferBefore: true) {
            return beforeIndex + 1
        }

        if let after = block.anchor.afterContext,
           let afterIndex = nearestIndex(of: after, in: lines, around: preferred, preferBefore: false) {
            return afterIndex
        }

        return preferred
    }

    private func exactContextGap(
        for anchor: ConflictEditorBlock.Anchor,
        in lines: [String],
        preferred: Int
    ) -> Int? {
        let beforeMatches = anchor.beforeContext == nil
            || (preferred > 0 && preferred - 1 < lines.count && lines[preferred - 1] == anchor.beforeContext)
        let afterMatches = anchor.afterContext == nil
            || (preferred < lines.count && lines[preferred] == anchor.afterContext)
        return beforeMatches && afterMatches ? preferred : nil
    }

    private func nearestContextGap(
        for anchor: ConflictEditorBlock.Anchor,
        in lines: [String],
        preferred: Int
    ) -> Int? {
        guard anchor.beforeContext != nil || anchor.afterContext != nil else { return nil }

        var candidates: [Int] = []
        for insertionIndex in 0...lines.count {
            let beforeMatches = anchor.beforeContext == nil
                || (insertionIndex > 0 && insertionIndex - 1 < lines.count && lines[insertionIndex - 1] == anchor.beforeContext)
            let afterMatches = anchor.afterContext == nil
                || (insertionIndex < lines.count && lines[insertionIndex] == anchor.afterContext)
            if beforeMatches && afterMatches {
                candidates.append(insertionIndex)
            }
        }

        return candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs - preferred)
            let rhsDistance = abs(rhs - preferred)
            if lhsDistance == rhsDistance {
                return lhs < rhs
            }
            return lhsDistance < rhsDistance
        }
    }

    private func pairedContextGap(
        for anchor: ConflictEditorBlock.Anchor,
        in lines: [String],
        preferred: Int
    ) -> Int? {
        guard let before = anchor.beforeContext, let after = anchor.afterContext else { return nil }

        let beforeMatches = lines.indices.filter { lines[$0] == before }
        let afterMatches = lines.indices.filter { lines[$0] == after }
        guard !beforeMatches.isEmpty, !afterMatches.isEmpty else { return nil }

        var candidates: [(gap: Int, span: Int)] = []
        for beforeIndex in beforeMatches {
            guard let afterIndex = afterMatches.first(where: { $0 >= beforeIndex + 1 }) else { continue }
            candidates.append((gap: beforeIndex + 1, span: afterIndex - beforeIndex))
        }

        return candidates.min { lhs, rhs in
            if lhs.span == rhs.span {
                let lhsDistance = abs(lhs.gap - preferred)
                let rhsDistance = abs(rhs.gap - preferred)
                if lhsDistance == rhsDistance {
                    return lhs.gap < rhs.gap
                }
                return lhsDistance < rhsDistance
            }
            return lhs.span < rhs.span
        }?.gap
    }

    private func nearestIndex(
        of value: String,
        in lines: [String],
        around preferred: Int,
        preferBefore: Bool
    ) -> Int? {
        let matches = lines.indices.filter { lines[$0] == value }
        guard !matches.isEmpty else { return nil }

        if preferBefore, let candidate = matches.filter({ $0 <= preferred }).max() {
            return candidate
        }

        if !preferBefore, let candidate = matches.filter({ $0 >= preferred }).min() {
            return candidate
        }

        return matches.min(by: { abs($0 - preferred) < abs($1 - preferred) })
    }

    private mutating func remapBlocksAfterManualEdit(change: LineChange, newLines: [String]) {
        for index in blocks.indices {
            remapBlockAfterManualEdit(&blocks[index], change: change, newLines: newLines)
        }
    }

    private func remapBlockAfterManualEdit(
        _ block: inout ConflictEditorBlock,
        change: LineChange,
        newLines: [String]
    ) {
        if let activeRange = block.activeRange {
            if activeRange.isEmpty,
               change.oldRange.lowerBound <= activeRange.lowerBound,
               activeRange.lowerBound <= change.oldRange.upperBound,
               (change.oldRange.count > 0 || change.newRange.count > 0) {
                block.resolutionIntent = .manual
            } else {
                switch remappedRangeOutcome(oldRange: activeRange, change: change) {
                case .unchanged: break
                case .edited, .deleted, .degraded: block.resolutionIntent = .manual
                }
            }
        }
        let currentInvalidated = invalidateEditedSelectionRange(
            side: .current,
            block: &block,
            change: change,
            newLines: newLines
        )
        let incomingInvalidated = invalidateEditedSelectionRange(
            side: .incoming,
            block: &block,
            change: change,
            newLines: newLines
        )

        if currentInvalidated || incomingInvalidated {
            block.mode = .detached
            block.controlledBlock = nil
            block.insertionSegment = nil
            block.contentState = .manual
        }

        if let controlled = block.controlledBlock {
            let outcome = remappedRangeOutcome(
                oldRange: controlled.lineRange,
                change: change
            )
            switch outcome {
            case .unchanged(let range):
                block.controlledBlock?.lineRange = range
            case .edited(let range):
                if !currentInvalidated && !incomingInvalidated && !block.selectedSources.hasSelection {
                    block.controlledBlock?.lineRange = range
                    block.contentState = .edited
                }
            case .deleted:
                if !currentInvalidated && !incomingInvalidated {
                    block.controlledBlock = nil
                    block.mode = .detached
                    block.contentState = .manual
                }
            case .degraded:
                if !currentInvalidated && !incomingInvalidated {
                    block.controlledBlock = nil
                    block.mode = .detached
                    block.contentState = .manual
                }
            }
        }

        if let segment = block.insertionSegment {
            let outcome = remappedRangeOutcome(
                oldRange: segment.lineRange,
                change: change
            )
            switch outcome {
            case .unchanged(let range):
                block.insertionSegment?.lineRange = range
            case .edited(let range):
                block.insertionSegment?.lineRange = range
                block.contentState = .edited
            case .deleted:
                block.insertionSegment = nil
                block.contentState = .manual
            case .degraded:
                block.insertionSegment = nil
                block.contentState = .manual
            }
        }

        remapAnchorPositionAfterManualEdit(&block, change: change, newLines: newLines)
    }

    private func remapAnchorPositionAfterManualEdit(
        _ block: inout ConflictEditorBlock,
        change: LineChange,
        newLines: [String]
    ) {
        let remappedPreferred = block.preferDirectAnchorInsertion
            ? remapLineIndex(block.anchor.preferredLine, through: change)
            : remapPreservingOverlappingLine(block.anchor.preferredLine, through: change)
        block.anchor.preferredLine = min(max(remappedPreferred, 0), newLines.count)

        if let directInsertionLine = block.directInsertionLine {
            let remappedDirectLine = block.preferDirectAnchorInsertion
                ? remapLineIndex(directInsertionLine, through: change)
                : remapPreservingOverlappingLine(directInsertionLine, through: change)
            block.directInsertionLine = min(max(remappedDirectLine, 0), newLines.count)
        }

        if block.preferDirectAnchorInsertion {
            let insertionLine = min(max(block.directInsertionLine ?? block.anchor.preferredLine, 0), newLines.count)
            let beforeContext = insertionLine > 0 && insertionLine - 1 < newLines.count ? newLines[insertionLine - 1] : nil
            let afterContext = insertionLine < newLines.count ? newLines[insertionLine] : nil
            block.anchor.beforeContext = beforeContext
            block.anchor.afterContext = afterContext
        }
    }

    private func remapLineIndex(_ line: Int, through change: LineChange) -> Int {
        if line <= change.oldRange.lowerBound {
            return line
        }
        if line >= change.oldRange.upperBound {
            return line + change.delta
        }
        return change.newRange.lowerBound
    }

    private func remapPreservingOverlappingLine(_ line: Int, through change: LineChange) -> Int {
        if line <= change.oldRange.lowerBound {
            return line
        }
        if line >= change.oldRange.upperBound {
            return line + change.delta
        }
        return line
    }

    private func invalidateEditedSelectionRange(
        side: ConflictEditorBlock.SelectionSide,
        block: inout ConflictEditorBlock,
        change: LineChange,
        newLines: [String]
    ) -> Bool {
        let oldRange: Range<Int>?
        switch side {
        case .current:
            oldRange = block.currentDisplayRange
        case .incoming:
            oldRange = block.incomingDisplayRange
        }

        guard let oldRange else { return false }
        let outcome = remappedRangeOutcome(oldRange: oldRange, change: change)
        switch outcome {
        case .unchanged(let newRange):
            switch side {
            case .current:
                block.currentDisplayRange = newRange
            case .incoming:
                block.incomingDisplayRange = newRange
            }
            return false
        case .edited(let newRange):
            let shrunk = newRange.count < oldRange.count
            let insertionLine = shrunk
                ? min(max(change.newRange.lowerBound, 0), newLines.count)
                : min(max(oldRange.upperBound, 0), newLines.count)
            clearSelectionAndDetachSide(
                &block,
                side: side,
                insertionLine: insertionLine,
                useDirectInsertionLine: shrunk,
                lines: newLines
            )
            return true
        case .degraded:
            clearSelectionAndDetachSide(
                &block,
                side: side,
                insertionLine: min(max(change.newRange.lowerBound, 0), newLines.count),
                useDirectInsertionLine: true,
                lines: newLines
            )
            return true
        case .deleted:
            clearSelectionAndDetachSide(
                &block,
                side: side,
                insertionLine: min(max(change.newRange.lowerBound, 0), newLines.count),
                useDirectInsertionLine: true,
                lines: newLines
            )
            return true
        }
    }

    private func clearSelectionAndDetachSide(
        _ block: inout ConflictEditorBlock,
        side: ConflictEditorBlock.SelectionSide,
        insertionLine: Int,
        useDirectInsertionLine: Bool,
        lines: [String]
    ) {
        let beforeContext = insertionLine > 0 && insertionLine - 1 < lines.count ? lines[insertionLine - 1] : nil
        let afterContext = insertionLine < lines.count ? lines[insertionLine] : nil

        switch side {
        case .current:
            block.selectedSources.current = false
            block.currentDisplayRange = nil
        case .incoming:
            block.selectedSources.incoming = false
            block.incomingDisplayRange = nil
        }
        block.selectionOrder.removeAll { $0 == side }
        block.anchor = .init(
            preferredLine: insertionLine,
            beforeContext: beforeContext,
            afterContext: afterContext
        )
        block.preferDirectAnchorInsertion = useDirectInsertionLine
        let stableInsertionLine = useDirectInsertionLine
            ? min(max(block.directInsertionLine ?? insertionLine, 0), insertionLine)
            : insertionLine
        block.directInsertionLine = stableInsertionLine
    }

    private enum RangeEditOutcome {
        case unchanged(Range<Int>)
        case edited(Range<Int>)
        case deleted
        case degraded
    }

    private func remappedRangeOutcome(
        oldRange: Range<Int>,
        change: LineChange
    ) -> RangeEditOutcome {
        if oldRange.upperBound <= change.oldRange.lowerBound {
            return .unchanged(oldRange)
        }
        if oldRange.lowerBound >= change.oldRange.upperBound {
            let shifted = (oldRange.lowerBound + change.delta)..<(oldRange.upperBound + change.delta)
            return .unchanged(shifted)
        }

        if change.oldRange.lowerBound >= oldRange.lowerBound &&
            change.oldRange.upperBound <= oldRange.upperBound {
            let newUpper = max(oldRange.lowerBound, oldRange.upperBound + change.delta)
            let newRange = oldRange.lowerBound..<newUpper
            return newRange.isEmpty ? .deleted : .edited(newRange)
        }

        return .degraded
    }

    private func remapStoredRanges(
        for block: inout ConflictEditorBlock,
        replacedRange: Range<Int>,
        delta: Int
    ) {
        block.controlledBlock = remapStoredRange(
            block.controlledBlock,
            replacedRange: replacedRange,
            delta: delta
        )
        block.insertionSegment = remapStoredRange(
            block.insertionSegment,
            replacedRange: replacedRange,
            delta: delta
        )
        block.currentDisplayRange = remapSimpleRange(
            block.currentDisplayRange,
            replacedRange: replacedRange,
            delta: delta
        )
        block.incomingDisplayRange = remapSimpleRange(
            block.incomingDisplayRange,
            replacedRange: replacedRange,
            delta: delta
        )
    }

    private mutating func removeDisplayedRange(
        _ range: Range<Int>,
        forBlockAt targetIndex: Int,
        clearing side: ConflictEditorBlock.SelectionSide?
    ) {
        var lines = outputLines
        lines.replaceSubrange(range, with: [])
        outputText = lines.joined(separator: "\n")
        outputLineOrigins.replaceSubrange(range, with: [])
        let delta = -range.count

        for blockIndex in blocks.indices {
            if blockIndex == targetIndex {
                var block = blocks[blockIndex]
                block.controlledBlock = remapStoredRange(
                    block.controlledBlock,
                    replacedRange: range,
                    delta: delta
                )
                block.insertionSegment = remapStoredRange(
                    block.insertionSegment,
                    replacedRange: range,
                    delta: delta
                )
                block.currentDisplayRange = remapSimpleRange(
                    block.currentDisplayRange,
                    replacedRange: range,
                    delta: delta
                )
                block.incomingDisplayRange = remapSimpleRange(
                    block.incomingDisplayRange,
                    replacedRange: range,
                    delta: delta
                )
                switch side {
                case .current:
                    block.currentDisplayRange = nil
                case .incoming:
                    block.incomingDisplayRange = nil
                case nil:
                    break
                }
                if side != nil {
                    let insertionLine = min(
                        min(max(block.anchor.preferredLine, 0), max(range.lowerBound, 0)),
                        outputLines.count
                    )
                    let beforeContext = insertionLine > 0 && insertionLine - 1 < outputLines.count
                        ? outputLines[insertionLine - 1]
                        : nil
                    let afterContext = insertionLine < outputLines.count
                        ? outputLines[insertionLine]
                        : nil
                    block.anchor = .init(
                        preferredLine: insertionLine,
                        beforeContext: beforeContext,
                        afterContext: afterContext
                    )
                    block.preferDirectAnchorInsertion = true
                    let stableInsertionLine = min(
                        max(block.directInsertionLine ?? insertionLine, 0),
                        insertionLine
                    )
                    block.directInsertionLine = stableInsertionLine
                }
                if block.currentDisplayRange == nil && block.incomingDisplayRange == nil {
                    block.insertionSegment = nil
                } else {
                    let lower = min(
                        block.currentDisplayRange?.lowerBound ?? Int.max,
                        block.incomingDisplayRange?.lowerBound ?? Int.max
                    )
                    let upper = max(
                        block.currentDisplayRange?.upperBound ?? Int.min,
                        block.incomingDisplayRange?.upperBound ?? Int.min
                    )
                    if lower != Int.max, upper != Int.min, lower < upper {
                        block.insertionSegment = ConflictEditorBlock.ControlledRange(
                            lineRange: lower..<upper,
                            lastGeneratedText: Array(outputLines[lower..<upper]).joined(separator: "\n")
                        )
                    }
                }
                blocks[blockIndex] = block
            } else {
                remapStoredRanges(
                    for: &blocks[blockIndex],
                    replacedRange: range,
                    delta: delta
                )
            }
        }
    }

    private func remapStoredRange(
        _ stored: ConflictEditorBlock.ControlledRange?,
        replacedRange: Range<Int>,
        delta: Int
    ) -> ConflictEditorBlock.ControlledRange? {
        guard var stored else { return nil }
        let range = stored.lineRange

        if range.upperBound <= replacedRange.lowerBound {
            return stored
        }
        if range.lowerBound >= replacedRange.upperBound {
            stored.lineRange = (range.lowerBound + delta)..<(range.upperBound + delta)
            return stored
        }
        return nil
    }

    private func remapSimpleRange(
        _ range: Range<Int>?,
        replacedRange: Range<Int>,
        delta: Int
    ) -> Range<Int>? {
        guard let range else { return nil }
        if range.upperBound <= replacedRange.lowerBound { return range }
        if range.lowerBound >= replacedRange.upperBound {
            return (range.lowerBound + delta)..<(range.upperBound + delta)
        }
        return nil
    }

    private struct LineChange {
        let oldRange: Range<Int>
        let newRange: Range<Int>

        var delta: Int {
            newRange.count - oldRange.count
        }

        static func make(oldLines: [String], newLines: [String]) -> LineChange {
            var sharedPrefix = 0
            while sharedPrefix < min(oldLines.count, newLines.count),
                  oldLines[sharedPrefix] == newLines[sharedPrefix] {
                sharedPrefix += 1
            }

            var sharedSuffix = 0
            while sharedSuffix < oldLines.count - sharedPrefix,
                  sharedSuffix < newLines.count - sharedPrefix,
                  oldLines[oldLines.count - sharedSuffix - 1] == newLines[newLines.count - sharedSuffix - 1] {
                sharedSuffix += 1
            }

            return LineChange(
                oldRange: sharedPrefix..<(oldLines.count - sharedSuffix),
                newRange: sharedPrefix..<(newLines.count - sharedSuffix)
            )
        }
    }

    private static func makeInitialOutputLineOrigins(sides: ConflictSides) -> [OutputLineOrigin] {
        var origins = Array(repeating: OutputLineOrigin.common, count: sides.outputLines.count)
        for marker in sides.markers {
            for lineIndex in marker.outputRange where lineIndex < origins.count {
                origins[lineIndex] = .ancestor
            }
        }
        return origins
    }

}
