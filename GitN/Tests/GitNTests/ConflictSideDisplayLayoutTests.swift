import XCTest
@testable import GitN

final class ConflictSideDisplayLayoutTests: XCTestCase {
    func testShorterSidePadsConflictBlockToMatchOtherSideHeight() {
        let regions = [
            ConflictRegion(
                id: 0,
                oursRange: 1..<4,
                theirsRange: 1..<2,
                baseRange: 1..<1,
                outputRange: 1..<1,
                currentLines: ["ours-1", "ours-2", "ours-3"],
                baseLines: [],
                incomingLines: ["theirs-1"],
                rawConflictLines: []
            )
        ]

        let ours = SideDisplayLayout.make(
            lines: ["before", "ours-1", "ours-2", "ours-3", "after"],
            conflictRegions: regions,
            side: .ours
        )
        let theirs = SideDisplayLayout.make(
            lines: ["before", "theirs-1", "after"],
            conflictRegions: regions,
            side: .theirs
        )

        XCTAssertEqual(ours.regionDisplayRanges[0], 1..<4)
        XCTAssertEqual(theirs.regionDisplayRanges[0], 1..<4)
        XCTAssertEqual(theirs.rows.map(\.sourceLineIndex), [0, 1, nil, nil, 2])
    }

    func testEmptySideStillReservesConflictRows() {
        let regions = [
            ConflictRegion(
                id: 0,
                oursRange: 1..<3,
                theirsRange: 1..<1,
                baseRange: 1..<1,
                outputRange: 1..<1,
                currentLines: ["ours-1", "ours-2"],
                baseLines: [],
                incomingLines: [],
                rawConflictLines: []
            )
        ]

        let theirs = SideDisplayLayout.make(
            lines: ["before", "after"],
            conflictRegions: regions,
            side: .theirs
        )

        XCTAssertEqual(theirs.regionDisplayRanges[0], 1..<3)
        XCTAssertEqual(theirs.rows.map(\.sourceLineIndex), [0, nil, nil, 1])
    }
}
