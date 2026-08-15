import XCTest
@testable import GitN

/// Covers the pure click-vs-drag threshold decision used by the file row's
/// custom AppKit drag source (`ImmediateDragNSView`). A press that stays within
/// the threshold is a click; movement beyond it begins an immediate drag.
final class ImmediateDragDeciderTests: XCTestCase {
    func testNoMovementIsNotADrag() {
        let point = CGPoint(x: 10, y: 10)
        XCTAssertFalse(ImmediateDragDecider.shouldBeginDrag(from: point, to: point))
    }

    func testTinyJitterBelowThresholdIsNotADrag() {
        XCTAssertFalse(
            ImmediateDragDecider.shouldBeginDrag(
                from: CGPoint(x: 0, y: 0),
                to: CGPoint(x: 1, y: 1),
                threshold: 3
            )
        )
    }

    func testMovementBeyondThresholdIsADrag() {
        XCTAssertTrue(
            ImmediateDragDecider.shouldBeginDrag(
                from: CGPoint(x: 0, y: 0),
                to: CGPoint(x: 5, y: 0),
                threshold: 3
            )
        )
    }

    func testMovementExactlyAtThresholdIsADrag() {
        // Distance == threshold should count as a drag (>= comparison).
        XCTAssertTrue(
            ImmediateDragDecider.shouldBeginDrag(
                from: CGPoint(x: 0, y: 0),
                to: CGPoint(x: 3, y: 0),
                threshold: 3
            )
        )
    }

    func testDiagonalMovementUsesEuclideanDistance() {
        // (3,4) -> distance 5, above threshold 3.
        XCTAssertTrue(
            ImmediateDragDecider.shouldBeginDrag(
                from: CGPoint(x: 0, y: 0),
                to: CGPoint(x: 3, y: 4),
                threshold: 3
            )
        )
        // (2,2) -> distance ~2.83, below threshold 3.
        XCTAssertFalse(
            ImmediateDragDecider.shouldBeginDrag(
                from: CGPoint(x: 0, y: 0),
                to: CGPoint(x: 2, y: 2),
                threshold: 3
            )
        )
    }
}
