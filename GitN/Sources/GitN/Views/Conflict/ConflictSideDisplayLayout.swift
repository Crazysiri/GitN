import Foundation

struct SideDisplayLayout: Equatable {
    struct Row: Equatable {
        let sourceLineIndex: Int?
    }

    let rows: [Row]
    let regionDisplayRanges: [Range<Int>]

    var anchors: [Int] {
        regionDisplayRanges.map(\.lowerBound)
    }

    static func make(lines: [String], conflictRegions: [ConflictRegion], side: ConflictSide) -> SideDisplayLayout {
        var rows: [Row] = []
        var regionDisplayRanges: [Range<Int>] = []
        var nextSourceLineIndex = 0

        for region in conflictRegions {
            let sideRange = side == .ours ? region.oursRange : region.theirsRange

            if sideRange.lowerBound > nextSourceLineIndex {
                for sourceLineIndex in nextSourceLineIndex..<sideRange.lowerBound {
                    rows.append(Row(sourceLineIndex: sourceLineIndex))
                }
            }

            let blockStart = rows.count
            for sourceLineIndex in sideRange {
                rows.append(Row(sourceLineIndex: sourceLineIndex))
            }

            let blockHeight = max(region.oursRange.count, region.theirsRange.count, 1)
            while rows.count - blockStart < blockHeight {
                rows.append(Row(sourceLineIndex: nil))
            }

            regionDisplayRanges.append(blockStart..<rows.count)
            nextSourceLineIndex = sideRange.upperBound
        }

        if nextSourceLineIndex < lines.count {
            for sourceLineIndex in nextSourceLineIndex..<lines.count {
                rows.append(Row(sourceLineIndex: sourceLineIndex))
            }
        }

        return SideDisplayLayout(rows: rows, regionDisplayRanges: regionDisplayRanges)
    }
}
