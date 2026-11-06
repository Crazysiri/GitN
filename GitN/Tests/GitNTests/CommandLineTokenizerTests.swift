import XCTest
@testable import GitN

final class CommandLineTokenizerTests: XCTestCase {
    func testSimpleCommand() {
        let a = CommandLineTokenizer.analyze("git status", cursor: 10)
        XCTAssertEqual(a.commandWord, "git")
        XCTAssertEqual(a.tokens.count, 2)
        XCTAssertEqual(a.tokens[1].value, "status")
        XCTAssertEqual(a.activeTokenIndex, 1)
    }

    func testCursorAfterSpaceStartsNewToken() {
        let a = CommandLineTokenizer.analyze("git ", cursor: 4)
        XCTAssertEqual(a.commandWord, "git")
        XCTAssertNil(a.activeTokenIndex, "cursor in whitespace is a new token")
        XCTAssertEqual(a.activeArgumentPosition, 1)
    }

    func testQuotedPathWithSpaces() {
        let line = "git add 'my file.txt"
        let a = CommandLineTokenizer.analyze(line, cursor: line.count)
        XCTAssertEqual(a.tokens.count, 3)
        XCTAssertEqual(a.tokens[2].value, "my file.txt")
        XCTAssertTrue(a.tokens[2].isOpenQuoted)
    }

    func testDoubleQuoteEscaping() {
        let line = "echo \"a\\\"b\""
        let a = CommandLineTokenizer.analyze(line, cursor: line.count)
        XCTAssertEqual(a.tokens.last?.value, "a\"b")
    }

    func testPipeResetsToCurrentCommand() {
        let line = "cat x | grep fo"
        let a = CommandLineTokenizer.analyze(line, cursor: line.count)
        XCTAssertEqual(a.commandWord, "grep", "suggestions apply to the command after the pipe")
        XCTAssertEqual(a.tokens.last?.value, "fo")
    }

    func testBackslashEscapedSpace() {
        let line = "cd my\\ dir"
        let a = CommandLineTokenizer.analyze(line, cursor: line.count)
        XCTAssertEqual(a.tokens.last?.value, "my dir")
    }

    func testSemicolonResets() {
        let line = "ls; git che"
        let a = CommandLineTokenizer.analyze(line, cursor: line.count)
        XCTAssertEqual(a.commandWord, "git")
        XCTAssertEqual(a.tokens.last?.value, "che")
    }
}
