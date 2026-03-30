import XCTest
@testable import GitN

final class StageFileDragPayloadTests: XCTestCase {
    func testDecodePreservesStagedSourceAndPaths() {
        let payload = "staged:a.txt\nstaged:b.txt"

        let decoded = StageFileDragPayload.decode(payload)

        XCTAssertEqual(decoded.sourceArea, .staged)
        XCTAssertEqual(decoded.paths, ["a.txt", "b.txt"])
    }

    func testDecodeIgnoresLinesFromDifferentSourceAreas() {
        let payload = "unstaged:a.txt\nstaged:b.txt"

        let decoded = StageFileDragPayload.decode(payload)

        XCTAssertEqual(decoded.sourceArea, .unstaged)
        XCTAssertEqual(decoded.paths, ["a.txt"])
    }

    func testDecodeSupportsLegacyPlainPathPayloads() {
        let payload = "a.txt\nb.txt"

        let decoded = StageFileDragPayload.decode(payload)

        XCTAssertEqual(decoded.sourceArea, .unstaged)
        XCTAssertEqual(decoded.paths, ["a.txt", "b.txt"])
    }
}
