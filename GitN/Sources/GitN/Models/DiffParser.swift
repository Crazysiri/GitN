import Foundation

// MARK: - Data Structures

struct ParsedDiff: Sendable {
    let fileHeader: String
    let hunks: [ParsedHunk]
    let isNewFile: Bool
}

struct ParsedHunk: Sendable {
    let rawHeader: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [HunkLine]

    var displayRange: String {
        if newCount > 0 {
            return "行 \(newStart)-\(newStart + newCount - 1)"
        }
        return "行 \(oldStart)-\(oldStart + oldCount - 1)"
    }

    var changeDisplayRange: String {
        let additions = lines.compactMap(\.newLineNum)
        let deletions = lines.compactMap(\.oldLineNum)

        if !additions.isEmpty {
            let start = additions.min() ?? newStart
            let end = additions.max() ?? start
            return start == end ? "新增行 \(start)" : "新增行 \(start)-\(end)"
        }

        if !deletions.isEmpty {
            let start = deletions.min() ?? oldStart
            let end = deletions.max() ?? start
            return start == end ? "删除行 \(start)" : "删除行 \(start)-\(end)"
        }

        return displayRange
    }
}

struct HunkLine: Identifiable, Sendable {
    let id: Int
    let kind: Kind
    let rawText: String
    let content: String
    let oldLineNum: Int?
    let newLineNum: Int?

    enum Kind: Sendable {
        case context, addition, deletion
    }
}

enum DiffHunkMapper {
    static func mapDisplayHunksToActionHunks(
        displayHunks: [ParsedHunk],
        actionHunks: [ParsedHunk]
    ) -> [Int: Int] {
        guard !displayHunks.isEmpty, !actionHunks.isEmpty else { return [:] }

        var mapping: [Int: Int] = [:]

        for (displayIndex, displayHunk) in displayHunks.enumerated() {
            if let exactMatch = actionHunks.enumerated().first(where: { _, actionHunk in
                actionHunk.contains(displayHunk)
            }) {
                mapping[displayIndex] = exactMatch.offset
                continue
            }

            if let overlappingMatch = actionHunks.enumerated().first(where: { _, actionHunk in
                actionHunk.overlaps(displayHunk)
            }) {
                mapping[displayIndex] = overlappingMatch.offset
            }
        }

        return mapping
    }

    static func actionLineIDs(
        for displayHunk: ParsedHunk,
        in actionHunk: ParsedHunk
    ) -> Set<Int> {
        let displayAddedLines = displayHunk.addedNewLines
        let displayDeletedLines = displayHunk.deletedOldLines
        let displayAddedContents = displayHunk.addedContents
        let displayDeletedContents = displayHunk.deletedContents

        var matchedIDs = Set<Int>()

        for line in actionHunk.lines {
            switch line.kind {
            case .addition:
                if let newLineNum = line.newLineNum,
                   displayAddedLines.contains(newLineNum) {
                    matchedIDs.insert(line.id)
                    continue
                }
                if displayAddedLines.isEmpty,
                   displayAddedContents.contains(line.content) {
                    matchedIDs.insert(line.id)
                }
            case .deletion:
                if let oldLineNum = line.oldLineNum,
                   displayDeletedLines.contains(oldLineNum) {
                    matchedIDs.insert(line.id)
                    continue
                }
                if displayDeletedLines.isEmpty,
                   displayDeletedContents.contains(line.content) {
                    matchedIDs.insert(line.id)
                }
            case .context:
                continue
            }
        }

        return matchedIDs
    }
}

private extension ParsedHunk {
    var addedNewLines: Set<Int> {
        Set(lines.compactMap(\.newLineNum))
    }

    var deletedOldLines: Set<Int> {
        Set(lines.compactMap(\.oldLineNum))
    }

    var addedContents: [String] {
        lines.filter { $0.kind == .addition }.map(\.content)
    }

    var deletedContents: [String] {
        lines.filter { $0.kind == .deletion }.map(\.content)
    }

    func contains(_ other: ParsedHunk) -> Bool {
        let otherAddedLines = other.addedNewLines
        let otherDeletedLines = other.deletedOldLines

        let lineNumbersContain =
            (!otherAddedLines.isEmpty && otherAddedLines.isSubset(of: addedNewLines)) ||
            (!otherDeletedLines.isEmpty && otherDeletedLines.isSubset(of: deletedOldLines))

        if lineNumbersContain {
            return true
        }

        let otherAddedContents = other.addedContents
        if !otherAddedContents.isEmpty &&
            Self.isOrderedSubset(candidate: otherAddedContents, of: addedContents) {
            return true
        }

        let otherDeletedContents = other.deletedContents
        if !otherDeletedContents.isEmpty &&
            Self.isOrderedSubset(candidate: otherDeletedContents, of: deletedContents) {
            return true
        }

        return false
    }

    func overlaps(_ other: ParsedHunk) -> Bool {
        !addedNewLines.isDisjoint(with: other.addedNewLines) ||
        !deletedOldLines.isDisjoint(with: other.deletedOldLines)
    }

    static func isOrderedSubset(candidate: [String], of source: [String]) -> Bool {
        guard !candidate.isEmpty else { return false }

        var sourceIndex = 0
        for item in candidate {
            var found = false
            while sourceIndex < source.count {
                defer { sourceIndex += 1 }
                if source[sourceIndex] == item {
                    found = true
                    break
                }
            }
            if !found {
                return false
            }
        }
        return true
    }
}

// MARK: - Parser

enum DiffParserEngine {
    static func parse(_ raw: String) -> ParsedDiff {
        let lines = raw.components(separatedBy: "\n")
        var headerLines = [String]()
        var hunks = [ParsedHunk]()
        var isNewFile = false

        var i = 0

        // Collect file header lines (diff --git, index, ---, +++)
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("@@") { break }
            if line.hasPrefix("new file") {
                isNewFile = true
                headerLines.append(line)
            } else if line.hasPrefix("diff --git") || line.hasPrefix("index ") ||
                        line.hasPrefix("--- ") || line.hasPrefix("+++ ") ||
                        line.hasPrefix("old mode") || line.hasPrefix("new mode") ||
                        line.hasPrefix("deleted file mode") ||
                        line.hasPrefix("similarity index ") ||
                        line.hasPrefix("rename from ") ||
                        line.hasPrefix("rename to ") {
                headerLines.append(line)
            } else {
                break
            }
            i += 1
        }

        let fileHeader = headerLines.joined(separator: "\n")

        // Parse hunks
        var hunkIndex = 0
        while i < lines.count {
            guard lines[i].hasPrefix("@@") else { i += 1; continue }

            let hunkHeaderLine = lines[i]
            let (oldStart, oldCount, newStart, newCount) = parseHunkHeader(hunkHeaderLine)
            i += 1

            var hunkLines = [HunkLine]()
            var oldNum = oldStart
            var newNum = newStart
            var lineId = 0

            while i < lines.count && !lines[i].hasPrefix("@@") &&
                    !lines[i].hasPrefix("diff --git") {
                let line = lines[i]
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    hunkLines.append(HunkLine(
                        id: lineId, kind: .addition, rawText: line,
                        content: String(line.dropFirst()),
                        oldLineNum: nil, newLineNum: newNum
                    ))
                    newNum += 1
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    hunkLines.append(HunkLine(
                        id: lineId, kind: .deletion, rawText: line,
                        content: String(line.dropFirst()),
                        oldLineNum: oldNum, newLineNum: nil
                    ))
                    oldNum += 1
                } else if line.hasPrefix(" ") || (!line.hasPrefix("\\") && !line.isEmpty) {
                    let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                    hunkLines.append(HunkLine(
                        id: lineId, kind: .context, rawText: line,
                        content: text,
                        oldLineNum: oldNum, newLineNum: newNum
                    ))
                    oldNum += 1
                    newNum += 1
                } else if line.hasPrefix("\\ No newline") {
                    i += 1; continue
                } else if line.isEmpty && i == lines.count - 1 {
                    break
                } else {
                    break
                }
                lineId += 1
                i += 1
            }

            hunks.append(ParsedHunk(
                rawHeader: hunkHeaderLine,
                oldStart: oldStart, oldCount: oldCount,
                newStart: newStart, newCount: newCount,
                lines: hunkLines
            ))
            hunkIndex += 1
        }

        return ParsedDiff(fileHeader: fileHeader, hunks: hunks, isNewFile: isNewFile)
    }

    private static func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int) {
        let pattern = #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else { return (1, 0, 1, 0) }

        func intAt(_ idx: Int) -> Int? {
            guard let range = Range(match.range(at: idx), in: line) else { return nil }
            return Int(line[range])
        }

        let oldStart = intAt(1) ?? 1
        let oldCount = intAt(2) ?? 1
        let newStart = intAt(3) ?? 1
        let newCount = intAt(4) ?? 1
        return (oldStart, oldCount, newStart, newCount)
    }
}

enum TextDiffEngine {
    static func diff(old oldText: String, new newText: String) -> ParsedDiff {
        let oldLines = textLines(oldText)
        let newLines = textLines(newText)
        let difference = newLines.difference(from: oldLines)

        var removals: [Int: [String]] = [:]
        var insertions: [Int: [String]] = [:]

        for change in difference {
            switch change {
            case let .remove(offset, element, _):
                removals[offset, default: []].append(element)
            case let .insert(offset, element, _):
                insertions[offset, default: []].append(element)
            }
        }

        var hunks: [ParsedHunk] = []
        var pendingLines: [HunkLine] = []
        var pendingOldStart = 1
        var pendingNewStart = 1
        var oldIndex = 0
        var newIndex = 0
        var lineID = 0

        func flushPendingHunk() {
            guard !pendingLines.isEmpty else { return }

            let oldCount = pendingLines.reduce(into: 0) { partialResult, line in
                if line.kind != .addition { partialResult += 1 }
            }
            let newCount = pendingLines.reduce(into: 0) { partialResult, line in
                if line.kind != .deletion { partialResult += 1 }
            }
            let header = "@@ -\(pendingOldStart),\(oldCount) +\(pendingNewStart),\(newCount) @@"
            hunks.append(
                ParsedHunk(
                    rawHeader: header,
                    oldStart: pendingOldStart,
                    oldCount: oldCount,
                    newStart: pendingNewStart,
                    newCount: newCount,
                    lines: pendingLines
                )
            )
            pendingLines.removeAll(keepingCapacity: true)
        }

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if let removedBatch = removals[oldIndex], !removedBatch.isEmpty {
                if pendingLines.isEmpty {
                    pendingOldStart = oldIndex + 1
                    pendingNewStart = newIndex + 1
                }
                for removed in removedBatch {
                    pendingLines.append(
                        HunkLine(
                            id: lineID,
                            kind: .deletion,
                            rawText: "-" + removed,
                            content: removed,
                            oldLineNum: oldIndex + 1,
                            newLineNum: nil
                        )
                    )
                    lineID += 1
                    oldIndex += 1
                }
                continue
            }

            if let insertedBatch = insertions[newIndex], !insertedBatch.isEmpty {
                if pendingLines.isEmpty {
                    pendingOldStart = oldIndex + 1
                    pendingNewStart = newIndex + 1
                }
                for inserted in insertedBatch {
                    pendingLines.append(
                        HunkLine(
                            id: lineID,
                            kind: .addition,
                            rawText: "+" + inserted,
                            content: inserted,
                            oldLineNum: nil,
                            newLineNum: newIndex + 1
                        )
                    )
                    lineID += 1
                    newIndex += 1
                }
                continue
            }

            flushPendingHunk()
            oldIndex += 1
            newIndex += 1
        }

        flushPendingHunk()

        return ParsedDiff(
            fileHeader: "",
            hunks: hunks,
            isNewFile: oldLines.isEmpty && !newLines.isEmpty
        )
    }

    private static func textLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

// MARK: - Patch Construction

extension ParsedDiff {
    var oldPath: String? {
        headerPath(prefix: "--- ")
    }

    var newPath: String? {
        headerPath(prefix: "+++ ")
    }

    private func headerPath(prefix: String) -> String? {
        let line = fileHeader
            .components(separatedBy: "\n")
            .first { $0.hasPrefix(prefix) }
        guard let line else { return nil }
        let rawPath = String(line.dropFirst(prefix.count))
        return Self.normalizeHeaderPath(rawPath)
    }

    private static func normalizeHeaderPath(_ rawPath: String) -> String? {
        guard !rawPath.isEmpty, rawPath != "/dev/null" else { return nil }
        if rawPath.hasPrefix("a/") || rawPath.hasPrefix("b/") {
            return String(rawPath.dropFirst(2))
        }
        return rawPath
    }

    /// Build a minimal file header for patch application.
    /// Falls back to the original header, stripping `index` lines.
    var minimalFileHeader: String {
        let lines = fileHeader.components(separatedBy: "\n")
        return lines.filter { !$0.hasPrefix("index ") }.joined(separator: "\n")
    }

    func reversed() -> ParsedDiff {
        ParsedDiff(
            fileHeader: reversedFileHeader,
            hunks: hunks.map(\.reversed),
            isNewFile: false
        )
    }

    private var reversedFileHeader: String {
        let lines = fileHeader.components(separatedBy: "\n")
        return lines.map { line in
            if line.hasPrefix("--- ") {
                return "+++ " + String(line.dropFirst(4))
            }
            if line.hasPrefix("+++ ") {
                return "--- " + String(line.dropFirst(4))
            }
            return line
        }.joined(separator: "\n")
    }

    /// Construct a full patch for a single hunk.
    func patchForHunk(_ hunkIndex: Int) -> String {
        guard hunkIndex < hunks.count else { return "" }
        let hunk = hunks[hunkIndex]
        var patch = minimalFileHeader + "\n"
        patch += hunk.rawHeader + "\n"
        for line in hunk.lines {
            patch += line.rawText + "\n"
        }
        return patch
    }

    /// Construct a patch containing only the selected lines from a hunk.
    /// Unselected additions are omitted; unselected deletions become context.
    func patchForLines(_ hunkIndex: Int, lineIndices: Set<Int>) -> String {
        guard hunkIndex < hunks.count else { return "" }
        let hunk = hunks[hunkIndex]

        var patchLines = [String]()
        var oldCount = 0
        var newCount = 0

        for line in hunk.lines {
            let selected = lineIndices.contains(line.id)
            switch line.kind {
            case .context:
                patchLines.append(" " + line.content)
                oldCount += 1
                newCount += 1
            case .deletion:
                if selected {
                    patchLines.append("-" + line.content)
                    oldCount += 1
                } else {
                    patchLines.append(" " + line.content)
                    oldCount += 1
                    newCount += 1
                }
            case .addition:
                if selected {
                    patchLines.append("+" + line.content)
                    newCount += 1
                }
                // Unselected additions are simply omitted
            }
        }

        let header = "@@ -\(hunk.oldStart),\(oldCount) +\(hunk.newStart),\(newCount) @@"
        var patch = minimalFileHeader + "\n"
        patch += header + "\n"
        patch += patchLines.joined(separator: "\n") + "\n"
        return patch
    }
}

private extension ParsedHunk {
    var reversed: ParsedHunk {
        let reversedLines = lines.map { line in
            switch line.kind {
            case .context:
                return HunkLine(
                    id: line.id,
                    kind: .context,
                    rawText: " " + line.content,
                    content: line.content,
                    oldLineNum: line.newLineNum,
                    newLineNum: line.oldLineNum
                )
            case .addition:
                return HunkLine(
                    id: line.id,
                    kind: .deletion,
                    rawText: "-" + line.content,
                    content: line.content,
                    oldLineNum: line.newLineNum,
                    newLineNum: nil
                )
            case .deletion:
                return HunkLine(
                    id: line.id,
                    kind: .addition,
                    rawText: "+" + line.content,
                    content: line.content,
                    oldLineNum: nil,
                    newLineNum: line.oldLineNum
                )
            }
        }

        let reversedHeader = "@@ -\(newStart),\(newCount) +\(oldStart),\(oldCount) @@"
        return ParsedHunk(
            rawHeader: reversedHeader,
            oldStart: newStart,
            oldCount: newCount,
            newStart: oldStart,
            newCount: oldCount,
            lines: reversedLines
        )
    }
}
