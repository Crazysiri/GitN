import Foundation

// MARK: - Data Structures

struct ParsedDiff {
    let fileHeader: String
    let hunks: [ParsedHunk]
    let isNewFile: Bool
}

struct ParsedHunk {
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
}

struct HunkLine: Identifiable {
    let id: Int
    let kind: Kind
    let rawText: String
    let content: String
    let oldLineNum: Int?
    let newLineNum: Int?

    enum Kind {
        case context, addition, deletion
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
                        line.hasPrefix("old mode") || line.hasPrefix("new mode") {
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

// MARK: - Patch Construction

extension ParsedDiff {
    /// Build a minimal file header for patch application.
    /// Falls back to the original header, stripping `index` lines.
    var minimalFileHeader: String {
        let lines = fileHeader.components(separatedBy: "\n")
        return lines.filter { !$0.hasPrefix("index ") }.joined(separator: "\n")
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
