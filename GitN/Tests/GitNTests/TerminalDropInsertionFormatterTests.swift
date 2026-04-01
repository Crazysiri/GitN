import XCTest
@testable import GitN

final class TerminalDropInsertionFormatterTests: XCTestCase {
    func testPastedTextQuotesPathsAndAppendsTrailingSpace() {
        let text = TerminalDropInsertionFormatter.pastedText(for: ["/tmp/hello world"])

        XCTAssertEqual(text, "'/tmp/hello world' ")
    }

    func testPastedTextEscapesSingleQuotesForShell() {
        let text = TerminalDropInsertionFormatter.pastedText(for: ["/tmp/it's here"])

        XCTAssertEqual(text, "'/tmp/it'\\''s here' ")
    }

    func testPastedTextJoinsMultiplePathsWithSpaces() {
        let text = TerminalDropInsertionFormatter.pastedText(for: ["/tmp/a", "/tmp/b c"])

        XCTAssertEqual(text, "'/tmp/a' '/tmp/b c' ")
    }

    func testPastedTextSkipsEmptyPaths() {
        let text = TerminalDropInsertionFormatter.pastedText(for: ["", "/tmp/a"])

        XCTAssertEqual(text, "'/tmp/a' ")
    }
}
