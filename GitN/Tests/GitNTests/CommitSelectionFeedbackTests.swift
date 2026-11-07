import AppKit
import XCTest
@testable import GitN

final class CommitSelectionFeedbackTests: XCTestCase {
    @MainActor
    func testCellReuseClearsSelectionAndDoesNotCarryAnimationToAnotherCommit() throws {
        let cell = CommitRowCellView(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        func commit(_ hash: String) -> CommitInfo {
            CommitInfo(hash: hash, shortHash: hash, parentHashes: [], authorName: "Test",
                       authorEmail: "test@example.com", date: "", message: hash, refs: [])
        }
        cell.commit = commit("first")
        cell.isSelectedRow = true
        let fill = try XCTUnwrap(cell.layer?.sublayers?.first)
        XCTAssertEqual(fill.opacity, 1)
        cell.commit = commit("second")
        cell.isSelectedRow = false
        XCTAssertEqual(fill.opacity, 0)
        XCTAssertTrue(fill.animationKeys()?.isEmpty ?? true)
        cell.isSelectedRow = true
        XCTAssertEqual(fill.opacity, 1)
        cell.isSelectedRow = false
        XCTAssertEqual(fill.opacity, 0)
    }
}
