import Foundation

enum ConflictScrollMapping {
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

    static func outputAnchors(for blocks: [ConflictEditorBlock]) -> [Int] {
        blocks.map { block in
            block.activeRange?.lowerBound ?? block.initialAttachedRange.lowerBound
        }
    }

    static func segmentPoints(anchors: [Int], totalLines: Int) -> [Int] {
        let clampedTotalLines = max(totalLines, 0)
        let orderedAnchors = anchors.map { min(max($0, 0), clampedTotalLines) }
        var points = [0]

        for anchor in orderedAnchors {
            if anchor >= (points.last ?? 0) {
                points.append(anchor)
            }
        }

        if points.last != clampedTotalLines {
            points.append(clampedTotalLines)
        } else if points.count == 1 {
            points.append(clampedTotalLines)
        }

        return points
    }
}
