import XCTest
@testable import GitN

final class ConflictScrollMappingTests: XCTestCase {
    func testSegmentPointsPreserveDuplicateAnchorsInOrder() {
        XCTAssertEqual(
            ConflictScrollMapping.segmentPoints(anchors: [5, 5, 9], totalLines: 12),
            [0, 5, 5, 9, 12]
        )
    }

    func testTopLineUsesLaterDuplicateAnchorSegmentInsteadOfCollapsingConflictOrder() {
        let outputAnchors = [5, 5, 9]
        let sideAnchors = [5, 6, 10]

        let scalarNearThirdConflict = ConflictScrollMapping.scalar(
            forTopLine: 8.8,
            anchors: outputAnchors,
            totalLines: 12
        )

        let mappedSideTopLine = ConflictScrollMapping.topLine(
            forScalar: scalarNearThirdConflict,
            anchors: sideAnchors,
            totalLines: 14
        )

        XCTAssertGreaterThanOrEqual(mappedSideTopLine, 9.0)
        XCTAssertLessThan(mappedSideTopLine, 10.5)
    }
}
