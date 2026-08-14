import XCTest
@testable import GitN

/// Regression tests for line splitting used by diff base-text reconstruction.
///
/// Swift treats `"\r\n"` as a single `Character` (grapheme cluster), so
/// `split(separator: "\n")` (a `Character` separator) silently fails to split
/// CRLF-terminated text and collapses an entire file into one element. That
/// produced phantom "whole block deleted" diffs in the file inspector for files
/// saved with Windows line endings. `DiffTextSplitter.lines` splits on the
/// scalar boundary instead, keeping each line (and its trailing `\r`) intact.
final class DiffTextSplitterTests: XCTestCase {
    func testSplitsLFContent() {
        XCTAssertEqual(
            DiffTextSplitter.lines("a\nb\nc"),
            ["a", "b", "c"]
        )
    }

    func testSplitsCRLFContentWithoutCollapsing() {
        let lines = DiffTextSplitter.lines("a\r\nb\r\nc")
        XCTAssertEqual(lines.count, 3, "CRLF text must split into individual lines, not collapse into one")
        XCTAssertEqual(lines, ["a\r", "b\r", "c"], "the trailing \\r must stay attached to each line")
    }

    func testSplitsMixedLineEndings() {
        let lines = DiffTextSplitter.lines("a\r\nb\nc\r\n")
        XCTAssertEqual(lines, ["a\r", "b", "c\r", ""])
    }

    func testTrailingNewlineProducesEmptyFinalLine() {
        XCTAssertEqual(DiffTextSplitter.lines("a\nb\n"), ["a", "b", ""])
    }

    func testEmptyStringProducesNoLines() {
        XCTAssertEqual(DiffTextSplitter.lines(""), [])
    }
}
