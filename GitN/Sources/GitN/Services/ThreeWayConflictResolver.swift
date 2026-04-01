import Foundation
import Clibgit2

enum ThreeWayConflictResolverError: LocalizedError {
    case libgit2Failure(String)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .libgit2Failure(let detail):
            return detail
        case .invalidUTF8:
            return "Conflict merge result is not valid UTF-8 text"
        }
    }
}

enum ThreeWayConflictResolver {
    static func mergeZDdiff3(
        baseText: String,
        oursText: String,
        theirsText: String,
        filePath: String,
        oursLabel: String,
        theirsLabel: String
    ) throws -> String {
        var result = git_merge_file_result()
        let ancestorInput = MergeFileInputBuffer(text: baseText, path: filePath)
        let oursInput = MergeFileInputBuffer(text: oursText, path: filePath)
        let theirsInput = MergeFileInputBuffer(text: theirsText, path: filePath)
        var options = git_merge_file_options()

        git_merge_file_options_init(&options, UInt32(GIT_MERGE_FILE_OPTIONS_VERSION))

        options.flags = UInt32(GIT_MERGE_FILE_STYLE_ZDIFF3.rawValue)

        let cOursLabel = strdup(oursLabel)
        let cTheirsLabel = strdup(theirsLabel)
        defer {
            free(cOursLabel)
            free(cTheirsLabel)
        }
        options.our_label = UnsafePointer(cOursLabel)
        options.their_label = UnsafePointer(cTheirsLabel)

        let rc = withUnsafePointer(to: ancestorInput.input) { ancestorPtr in
            withUnsafePointer(to: oursInput.input) { oursPtr in
                withUnsafePointer(to: theirsInput.input) { theirsPtr in
                    git_merge_file(
                        &result,
                        ancestorPtr,
                        oursPtr,
                        theirsPtr,
                        &options
                    )
                }
            }
        }
        defer { git_merge_file_result_free(&result) }

        guard rc == 0 else {
            throw ThreeWayConflictResolverError.libgit2Failure(libgit2ErrorMessage(prefix: "Conflict merge failed", code: rc))
        }

        guard let ptr = result.ptr else { return "" }
        let data = Data(bytes: ptr, count: result.len)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ThreeWayConflictResolverError.invalidUTF8
        }
        return text
    }

    static func buildConflictSides(
        mergedText: String,
        baseLines: [String],
        oursLines: [String],
        theirsLines: [String],
        oursLabel: String,
        theirsLabel: String
    ) -> ConflictSides {
        let mergedLines = mergedText.components(separatedBy: "\n")
        var outputLines: [String] = []
        var regions: [ConflictRegion] = []
        var lineIndex = 0
        var regionID = 0
        var baseCursor = 0
        var oursCursor = 0
        var theirsCursor = 0

        while lineIndex < mergedLines.count {
            let line = mergedLines[lineIndex]

            if !line.hasPrefix("<<<<<<<") {
                outputLines.append(line)
                if let match = nextLineMatchIndex(for: line, in: baseLines, startingAt: baseCursor) {
                    baseCursor = match + 1
                }
                if let match = nextLineMatchIndex(for: line, in: oursLines, startingAt: oursCursor) {
                    oursCursor = match + 1
                }
                if let match = nextLineMatchIndex(for: line, in: theirsLines, startingAt: theirsCursor) {
                    theirsCursor = match + 1
                }
                lineIndex += 1
                continue
            }

            let parseResult = parseConflictBlock(in: mergedLines, startingAt: lineIndex)
            guard let parseResult else {
                lineIndex += 1
                continue
            }

            let beforeContext = outputLines.last
            let afterContext = parseResult.nextIndex < mergedLines.count ? mergedLines[parseResult.nextIndex] : nil

            let oursRange = locateRange(
                for: parseResult.currentLines,
                in: oursLines,
                cursor: &oursCursor,
                beforeContext: beforeContext,
                afterContext: afterContext
            )
            let theirsRange = locateRange(
                for: parseResult.incomingLines,
                in: theirsLines,
                cursor: &theirsCursor,
                beforeContext: beforeContext,
                afterContext: afterContext
            )
            let baseRange = locateRange(
                for: parseResult.baseLines,
                in: baseLines,
                cursor: &baseCursor,
                beforeContext: beforeContext,
                afterContext: afterContext
            )

            let outputStart = outputLines.count
            outputLines.append(contentsOf: parseResult.baseLines)
            let outputEnd = outputLines.count

            regions.append(
                ConflictRegion(
                    id: regionID,
                    oursRange: oursRange,
                    theirsRange: theirsRange,
                    baseRange: baseRange,
                    outputRange: outputStart..<outputEnd,
                    currentLines: parseResult.currentLines,
                    baseLines: parseResult.baseLines,
                    incomingLines: parseResult.incomingLines,
                    rawConflictLines: parseResult.rawConflictLines
                )
            )

            regionID += 1
            lineIndex = parseResult.nextIndex
        }

        return ConflictSides(
            oursLabel: oursLabel,
            theirsLabel: theirsLabel,
            baseLines: baseLines,
            outputLines: outputLines,
            oursLines: oursLines,
            theirsLines: theirsLines,
            mergedText: mergedText,
            markers: regions
        )
    }

    private struct ParsedConflictBlock {
        let currentLines: [String]
        let baseLines: [String]
        let incomingLines: [String]
        let rawConflictLines: [String]
        let nextIndex: Int
    }

    private final class MergeFileInputBuffer {
        var input = git_merge_file_input()
        private let contentPointer: UnsafeMutablePointer<CChar>?
        private let pathPointer: UnsafeMutablePointer<CChar>?

        init(text: String, path: String) {
            git_merge_file_input_init(&input, UInt32(GIT_MERGE_FILE_INPUT_VERSION))
            contentPointer = strdup(text)
            pathPointer = strdup(path)
            input.ptr = UnsafePointer(contentPointer)
            input.size = text.lengthOfBytes(using: .utf8)
            input.path = UnsafePointer(pathPointer)
            input.mode = 0
        }

        deinit {
            free(contentPointer)
            free(pathPointer)
        }
    }

    private static func parseConflictBlock(
        in lines: [String],
        startingAt startIndex: Int
    ) -> ParsedConflictBlock? {
        guard startIndex < lines.count, lines[startIndex].hasPrefix("<<<<<<<") else { return nil }

        var rawConflictLines = [lines[startIndex]]
        var currentLines: [String] = []
        var baseLines: [String] = []
        var incomingLines: [String] = []

        var index = startIndex + 1
        while index < lines.count,
              !lines[index].hasPrefix("|||||||"),
              !lines[index].hasPrefix("=======") {
            currentLines.append(lines[index])
            rawConflictLines.append(lines[index])
            index += 1
        }

        if index < lines.count, lines[index].hasPrefix("|||||||") {
            rawConflictLines.append(lines[index])
            index += 1
            while index < lines.count, !lines[index].hasPrefix("=======") {
                baseLines.append(lines[index])
                rawConflictLines.append(lines[index])
                index += 1
            }
        }

        guard index < lines.count, lines[index].hasPrefix("=======") else { return nil }
        rawConflictLines.append(lines[index])
        index += 1

        while index < lines.count, !lines[index].hasPrefix(">>>>>>>") {
            incomingLines.append(lines[index])
            rawConflictLines.append(lines[index])
            index += 1
        }

        guard index < lines.count, lines[index].hasPrefix(">>>>>>>") else { return nil }
        rawConflictLines.append(lines[index])

        return ParsedConflictBlock(
            currentLines: currentLines,
            baseLines: baseLines,
            incomingLines: incomingLines,
            rawConflictLines: rawConflictLines,
            nextIndex: index + 1
        )
    }

    private static func locateRange(
        for needle: [String],
        in haystack: [String],
        cursor: inout Int,
        beforeContext: String?,
        afterContext: String?
    ) -> Range<Int> {
        if needle.isEmpty {
            let preferred = min(max(cursor, 0), haystack.count)
            let insertionIndex =
                exactContextGap(
                    before: beforeContext,
                    after: afterContext,
                    in: haystack,
                    preferred: preferred
                ) ??
                nearestContextGap(
                    before: beforeContext,
                    after: afterContext,
                    in: haystack,
                    preferred: preferred
                ) ??
                pairedContextGap(
                    before: beforeContext,
                    after: afterContext,
                    in: haystack,
                    preferred: preferred
                ) ??
                splitContextGap(
                    before: beforeContext,
                    after: afterContext,
                    in: haystack,
                    preferred: preferred
                ) ??
                preferred
            cursor = insertionIndex
            return insertionIndex..<insertionIndex
        }

        if let start = nextSubsequenceStart(for: needle, in: haystack, startingAt: cursor) {
            let end = start + needle.count
            cursor = end
            return start..<end
        }

        let start = min(max(cursor, 0), haystack.count)
        let end = min(start + needle.count, haystack.count)
        cursor = end
        return start..<end
    }

    private static func exactContextGap(
        before: String?,
        after: String?,
        in lines: [String],
        preferred: Int
    ) -> Int? {
        let beforeMatches = before == nil
            || (preferred > 0 && preferred - 1 < lines.count && lines[preferred - 1] == before)
        let afterMatches = after == nil
            || (preferred < lines.count && lines[preferred] == after)
        return beforeMatches && afterMatches ? preferred : nil
    }

    private static func nearestContextGap(
        before: String?,
        after: String?,
        in lines: [String],
        preferred: Int
    ) -> Int? {
        guard before != nil || after != nil else { return nil }
        var candidates: [Int] = []
        for gap in 0...lines.count {
            let beforeMatches = before == nil || (gap > 0 && lines[gap - 1] == before)
            let afterMatches = after == nil || (gap < lines.count && lines[gap] == after)
            if beforeMatches && afterMatches {
                candidates.append(gap)
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

    private static func pairedContextGap(
        before: String?,
        after: String?,
        in lines: [String],
        preferred: Int
    ) -> Int? {
        guard let before, let after else { return nil }

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

    private static func splitContextGap(
        before: String?,
        after: String?,
        in lines: [String],
        preferred: Int
    ) -> Int? {
        if let before,
           let after,
           let beforeIndex = nearestLineIndex(of: before, in: lines, around: preferred, preferBefore: true),
           let afterIndex = nearestLineIndex(of: after, in: lines, around: preferred, preferBefore: false),
           beforeIndex < afterIndex {
            return beforeIndex + 1
        }

        if let before,
           let beforeIndex = nearestLineIndex(of: before, in: lines, around: preferred, preferBefore: true) {
            return beforeIndex + 1
        }

        if let after,
           let afterIndex = nearestLineIndex(of: after, in: lines, around: preferred, preferBefore: false) {
            return afterIndex
        }

        return nil
    }

    private static func nearestLineIndex(
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

        return matches.min { lhs, rhs in
            let lhsDistance = abs(lhs - preferred)
            let rhsDistance = abs(rhs - preferred)
            if lhsDistance == rhsDistance {
                return lhs < rhs
            }
            return lhsDistance < rhsDistance
        }
    }

    private static func nextLineMatchIndex(
        for line: String,
        in lines: [String],
        startingAt start: Int
    ) -> Int? {
        guard start < lines.count else { return nil }
        return lines[start...].firstIndex(of: line)
    }

    private static func nextSubsequenceStart(
        for needle: [String],
        in haystack: [String],
        startingAt start: Int
    ) -> Int? {
        if needle.isEmpty { return start }
        guard start < haystack.count, needle.count <= haystack.count else { return nil }
        let lastStart = haystack.count - needle.count
        guard start <= lastStart else { return nil }
        for candidate in start...lastStart {
            if Array(haystack[candidate..<(candidate + needle.count)]) == needle {
                return candidate
            }
        }
        return nil
    }

    private static func libgit2ErrorMessage(prefix: String, code: Int32) -> String {
        if let error = git_error_last(), let message = error.pointee.message {
            return "\(prefix): \(String(cString: message))"
        }
        return "\(prefix) (code \(code))"
    }
}
