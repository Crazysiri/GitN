import XCTest
@testable import GitN

/// The native highlighter was retired; verify source decorations from the model
/// rather than testing the removed NSTextView implementation.
final class ConflictOutputHighlightTests: XCTestCase {
    func testOriginsFollowSelectedAndManuallyEditedSourceLines() {
        let sides = StructuralDiff3.makeSides(base: ["head", "base", "tail"],
            ours: ["head", "A1", "A2", "tail"], theirs: ["head", "B", "tail"],
            oursLabel: "A", theirsLabel: "B")
        var document = ConflictEditorDocument(sides: sides)
        document.toggleLine(blockID: 0, side: .current, line: 1)
        XCTAssertEqual(document.outputText, "head\nA2\ntail")
        XCTAssertEqual(document.outputLineOrigins, [.common, .current, .common])
        document.updateOutputText("head\nmanual\ntail")
        XCTAssertEqual(document.outputLineOrigins, [.common, .manual, .common])
        XCTAssertEqual(document.selectedLineIndices(blockID: 0, side: .current), [])
    }
}
