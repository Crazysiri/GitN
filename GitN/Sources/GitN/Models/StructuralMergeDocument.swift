import Foundation

/// Stable chunks and ordered source membership, matching the diff3 editor model.
/// A source reference is identity (side + index), so duplicate text is never used
/// to infer whether a line is selected. Manual replacements drop only touched refs.
struct StructuralMergeDocument: Equatable, Sendable {
    struct Source: Equatable, Sendable {
        let side: ConflictEditorBlock.SelectionSide
        let line: Int
    }
    struct Line: Equatable, Sendable {
        let text: String
        let source: Source?
        var origin: ConflictEditorDocument.OutputLineOrigin
    }
    struct Chunk: Equatable, Sendable {
        let blockID: Int?
        let ancestor: [String]
        let current: [String]
        let incoming: [String]
        var output: [Line]
        var intent: ConflictEditorBlock.ResolutionIntent
        var hasBeenEdited = false
        var emptySides: Set<ConflictEditorBlock.SelectionSide> = []
        var displayed: [Line] {
            !hasBeenEdited && intent == .unresolved && output.isEmpty
                ? ancestor.map { Line(text: $0, source: nil, origin: .ancestor) } : output
        }
    }
    var chunks: [Chunk]

    init(sides: ConflictSides) {
        var chunks: [Chunk] = [], cursor = 0
        for (id, marker) in sides.markers.enumerated() {
            let common = Array(sides.outputLines[cursor..<marker.outputRange.lowerBound])
            chunks.append(Chunk(blockID: nil, ancestor: [], current: [], incoming: [],
                output: common.map { Line(text: $0, source: nil, origin: .common) }, intent: .manual))
            chunks.append(Chunk(blockID: id, ancestor: marker.baseLines, current: marker.currentLines,
                incoming: marker.incomingLines, output: [], intent: .unresolved))
            cursor = marker.outputRange.upperBound
        }
        chunks.append(Chunk(blockID: nil, ancestor: [], current: [], incoming: [],
            output: sides.outputLines[cursor...].map { Line(text: $0, source: nil, origin: .common) }, intent: .manual))
        self.chunks = chunks
    }

    var lines: [Line] { chunks.flatMap(\.displayed) }
    var text: String { lines.map(\.text).joined(separator: "\n") }

    func selectedLines(blockID: Int, side: ConflictEditorBlock.SelectionSide) -> [Int] {
        chunks.first { $0.blockID == blockID }?.output.compactMap {
            $0.source?.side == side ? $0.source?.line : nil
        } ?? []
    }
    func allSelected(blockID: Int, side: ConflictEditorBlock.SelectionSide) -> Bool {
        guard let chunk = chunks.first(where: { $0.blockID == blockID }) else { return false }
        let count = side == .current ? chunk.current.count : chunk.incoming.count
        return count == 0 ? chunk.emptySides.contains(side) : selectedLines(blockID: blockID, side: side).count == count
    }

    mutating func toggle(blockID: Int, side: ConflictEditorBlock.SelectionSide, line: Int? = nil) {
        guard let index = chunks.firstIndex(where: { $0.blockID == blockID }) else { return }
        let source = side == .current ? chunks[index].current : chunks[index].incoming
        if chunks[index].intent == .ancestor {
            // Keeping the ancestor is an explicit choice, not source membership.
            // A subsequent source choice starts a new selection from that source.
            chunks[index].output = []
            chunks[index].hasBeenEdited = false
        }
        if let line {
            guard source.indices.contains(line) else { return }
            let ref = Source(side: side, line: line)
            if chunks[index].output.contains(where: { $0.source == ref }) {
                chunks[index].output.removeAll { $0.source == ref }
            } else {
                chunks[index].output.append(Line(text: source[line], source: ref,
                    origin: side == .current ? .current : .incoming))
            }
        } else {
            let selected = allSelected(blockID: blockID, side: side)
            chunks[index].output.removeAll { $0.source?.side == side }
            if source.isEmpty {
                if selected { chunks[index].emptySides.remove(side) } else { chunks[index].emptySides.insert(side) }
            } else if !selected {
                chunks[index].output += source.enumerated().map {
                    Line(text: $0.element, source: Source(side: side, line: $0.offset),
                        origin: side == .current ? .current : .incoming)
                }
            }
        }
        chunks[index].intent = chunks[index].output.isEmpty && chunks[index].emptySides.isEmpty
            ? (chunks[index].hasBeenEdited ? .manual : .unresolved) : .selected
    }

    mutating func keepAncestor(blockID: Int) {
        guard let index = chunks.firstIndex(where: { $0.blockID == blockID }) else { return }
        chunks[index].output = chunks[index].ancestor.map { Line(text: $0, source: nil, origin: .ancestor) }
        chunks[index].emptySides = []; chunks[index].intent = .ancestor; chunks[index].hasBeenEdited = true
    }

    mutating func updateText(_ text: String) {
        guard text != self.text else { return }
        let old = lines.map(\.text), new = text.components(separatedBy: "\n")
        guard old != new else { return }
        var prefix = 0, suffix = 0
        while prefix < min(old.count, new.count) && old[prefix] == new[prefix] { prefix += 1 }
        while suffix < old.count - prefix && suffix < new.count - prefix && old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        let oldWindow = Array(old[prefix..<(old.count - suffix)])
        let newWindow = Array(new[prefix..<(new.count - suffix)])
        // Monaco may report several disjoint edits in one content event. Preserve
        // unchanged source membership and the intervening chunk boundaries.
        let edits = StructuralDiff3.edits(from: oldWindow, to: newWindow, maxP: 128)
        for edit in edits.reversed() {
            let removed = (prefix + edit.base.lowerBound)..<(prefix + edit.base.upperBound)
            let inserted = newWindow[edit.side].map { Line(text: $0, source: nil, origin: .manual) }
            replaceLines(removed, with: inserted)
        }
    }

    private mutating func replaceLines(_ removed: Range<Int>, with inserted: [Line]) {
        // Capture ownership before mutating. At a boundary, insert into the preceding
        // chunk (the line on which Monaco inserts a newline), retaining stable IDs.
        var offsets: [Range<Int>] = [], cursor = 0
        for chunk in chunks { let count = chunk.displayed.count; offsets.append(cursor..<(cursor + count)); cursor += count }
        let owner: Int
        if removed.isEmpty, let preceding = offsets.indices.reversed().first(where: {
            offsets[$0].upperBound == removed.lowerBound &&
                (!offsets[$0].isEmpty || chunks[$0].blockID != nil)
        }) {
            owner = preceding
        } else {
            owner = offsets.firstIndex { $0.contains(removed.lowerBound) }
                ?? offsets.lastIndex { $0.upperBound <= removed.lowerBound } ?? 0
        }
        for index in chunks.indices {
            let range = offsets[index]
            let lower = max(range.lowerBound, removed.lowerBound), upper = min(range.upperBound, removed.upperBound)
            guard lower < upper || index == owner else { continue }
            chunks[index].output = chunks[index].displayed
            if lower < upper { chunks[index].output.removeSubrange((lower - range.lowerBound)..<(upper - range.lowerBound)) }
            if index == owner {
                let at = min(max(removed.lowerBound - range.lowerBound, 0), chunks[index].output.count)
                chunks[index].output.insert(contentsOf: inserted, at: at)
            }
            chunks[index].intent = .manual
            chunks[index].hasBeenEdited = true
            // Manual empty output is an explicit resolution, unlike an untouched block.
            chunks[index].emptySides = []
        }
    }
}
