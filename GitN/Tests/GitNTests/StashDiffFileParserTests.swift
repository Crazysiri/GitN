import Foundation
import XCTest
@testable import GitN

final class StashDiffFileParserTests: XCTestCase {
    func testMalformedNULFramingThrows() {
        XCTAssertThrowsError(try StashDiffFileParser.parse(
            status: Data("M\0path.md".utf8), numstat: Data(), untracked: nil
        ))
    }
}
