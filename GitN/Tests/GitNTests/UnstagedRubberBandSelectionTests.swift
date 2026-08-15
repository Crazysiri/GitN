import XCTest
@testable import GitN

/// Covers the pure containment check used as a defensive guard for the
/// blank-area rubber-band (marquee) selection path (`BlankSelectionNSView`).
/// Rows themselves no longer host any marquee gesture — `.draggable` is the
/// only recognizer attached to a row's hit area — so this check only matters
/// for the blank space below the last row, but it stays as a safety net in
/// case row layout ever changes.
final class UnstagedRubberBandSelectionTests: XCTestCase {
    func testPointInsideARowFrameIsDetected() {
        let frames: [String: CGRect] = [
            "a.txt": CGRect(x: 0, y: 0, width: 200, height: 20),
            "b.txt": CGRect(x: 0, y: 20, width: 200, height: 20)
        ]

        XCTAssertTrue(DetailPanelView.isPoint(CGPoint(x: 10, y: 25), insideAnyOf: frames))
    }

    func testPointOutsideAllRowFramesIsNotDetected() {
        let frames: [String: CGRect] = [
            "a.txt": CGRect(x: 0, y: 0, width: 200, height: 20),
            "b.txt": CGRect(x: 0, y: 20, width: 200, height: 20)
        ]

        XCTAssertFalse(DetailPanelView.isPoint(CGPoint(x: 10, y: 45), insideAnyOf: frames))
    }

    func testEmptyFrameMapNeverContainsAPoint() {
        XCTAssertFalse(DetailPanelView.isPoint(CGPoint(x: 10, y: 10), insideAnyOf: [:]))
    }

    func testPointOnRowFrameBoundaryIsDetected() {
        let frames: [String: CGRect] = [
            "a.txt": CGRect(x: 0, y: 0, width: 200, height: 20)
        ]

        // CGRect.contains treats the min edges as inclusive.
        XCTAssertTrue(DetailPanelView.isPoint(CGPoint(x: 0, y: 0), insideAnyOf: frames))
    }
}
