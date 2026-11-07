import XCTest
@testable import GitN

final class StructuralDiff3Tests: XCTestCase {
    private func merge(_ base: [String], _ ours: [String], _ theirs: [String]) -> ConflictSides {
        StructuralDiff3.makeSides(base: base, ours: ours, theirs: theirs, oursLabel: "A", theirsLabel: "B")
    }

    func testIdenticalChangesAndDisjointChangesAutoMerge() {
        XCTAssertEqual(merge(["a", "b"], ["x", "b"], ["x", "b"]).markers, [])
        let sides = merge(["a", "b", "c"], ["A", "b", "c"], ["a", "b", "C"])
        XCTAssertEqual(sides.outputLines, ["A", "b", "C"])
        XCTAssertTrue(sides.markers.isEmpty)
    }
    func testTouchingAncestorChangesClusterInsteadOfZdiff3Boundaries() {
        let sides = merge(["a", "b", "c"], ["A", "b", "c"], ["a", "B", "c"])
        XCTAssertEqual(sides.markers.count, 1)
        XCTAssertEqual(sides.markers.first?.baseRange, 0..<2)
        XCTAssertEqual(sides.markers.first?.currentLines, ["A", "b"])
        XCTAssertEqual(sides.markers.first?.incomingLines, ["a", "B"])
    }
    func testInsertionDeletionAndEmptyInputHaveExactCoordinates() {
        let inserted = merge([], ["ours"], ["theirs"])
        XCTAssertEqual(inserted.markers.first?.baseRange, 0..<0)
        XCTAssertEqual(inserted.markers.first?.oursRange, 0..<1)
        let deleted = merge(["base"], [], ["changed"])
        XCTAssertEqual(deleted.markers.first?.oursRange, 0..<0)
        XCTAssertEqual(deleted.markers.first?.theirsRange, 0..<1)
        XCTAssertEqual(merge([], [], []).outputLines, [])
    }
    func testLiteralMarkersAndRepeatedLinesAreOrdinarySourceContent() {
        let sides = merge(["same", "<<<<<<< literal", "same", "old", "same"],
            ["same", "<<<<<<< literal", "same", "A", "same"],
            ["same", "<<<<<<< literal", "same", "B", "same"])
        XCTAssertEqual(sides.markers.first?.oursRange, 3..<4)
        XCTAssertEqual(sides.outputLines[1], "<<<<<<< literal")
    }
    func testNewlinesCRAndUnicodeRemainExact() {
        let sides = merge(["🙂\r", "旧\r", ""], ["🙂\r", "甲\r", ""], ["🙂\r", "乙\r", ""])
        var doc = ConflictEditorDocument(sides: sides)
        doc.toggleCurrent(blockID: 0)
        XCTAssertEqual(doc.outputText, "🙂\r\n甲\r\n")
    }
    func testEditScriptsRoundTripRepeatedAndEmptyLines() {
        let alphabet = ["", "a", "a", "b", "🙂"]
        for seed in 0..<100 {
            let original = (0..<(seed % 11)).map { alphabet[($0 + seed) % alphabet.count] }
            let modified = (0..<(seed % 7)).map { alphabet[($0 * 3 + seed) % alphabet.count] }
            var result = original
            for edit in StructuralDiff3.edits(from: original, to: modified).reversed() {
                result.replaceSubrange(edit.base, with: modified[edit.side])
            }
            XCTAssertEqual(result, modified)
        }
    }

    func testInteractiveEditBudgetFallsBackToOneReplacement() {
        let before = ["a", "b", "c"]
        let after = ["x", "y", "z"]
        XCTAssertEqual(StructuralDiff3.edits(from: before, to: after, maxP: 0),
                       [.init(base: 0..<3, side: 0..<3)])
    }

    func testOrderedLineSelectionWholeSideAppendAndUnselection() {
        var doc = ConflictEditorDocument(sides: merge(["base"], ["A0", "A1"], ["B0", "B1"]))
        doc.toggleLine(blockID: 0, side: .incoming, line: 1)
        doc.toggleLine(blockID: 0, side: .current, line: 0)
        XCTAssertEqual(doc.outputText, "B1\nA0")
        // Whole-side take removes that side's partial contribution, then appends it.
        doc.toggleIncoming(blockID: 0)
        XCTAssertEqual(doc.outputText, "A0\nB0\nB1")
        doc.toggleLine(blockID: 0, side: .incoming, line: 0)
        XCTAssertEqual(doc.outputText, "A0\nB1")
        XCTAssertEqual(doc.selectedLineIndices(blockID: 0, side: .incoming), [1])
    }
    func testRepeatedSourceTextKeepsDistinctLineMembership() {
        var doc = ConflictEditorDocument(sides: merge(["base"], ["same", "same"], ["other"]))
        doc.toggleLine(blockID: 0, side: .current, line: 1)
        doc.toggleLine(blockID: 0, side: .current, line: 0)
        XCTAssertEqual(doc.outputText, "same\nsame")
        XCTAssertEqual(doc.selectedLineIndices(blockID: 0, side: .current), [1, 0])
        doc.toggleLine(blockID: 0, side: .current, line: 1)
        XCTAssertEqual(doc.outputText, "same")
        XCTAssertEqual(doc.selectedLineIndices(blockID: 0, side: .current), [0])
    }
    func testManualEditPreservesUntouchedSourceMembershipAndStableBlock() {
        var doc = ConflictEditorDocument(sides: merge(["base"], ["A0", "A1"], ["B"]))
        doc.toggleCurrent(blockID: 0)
        doc.updateOutputText("manual\nA1")
        XCTAssertEqual(doc.selectedLineIndices(blockID: 0, side: .current), [1])
        doc.toggleIncoming(blockID: 0)
        XCTAssertEqual(doc.outputText, "manual\nA1\nB")
        XCTAssertEqual(doc.blocks[0].activeRange, 0..<3)
        doc.resetAll()
        XCTAssertEqual(doc.outputText, "base")
        XCTAssertEqual(doc.unresolvedBlockIDs, [0])
    }
    func testEmptySideIsExplicitResolutionAndUndoSnapshotRestoresMembership() {
        var doc = ConflictEditorDocument(sides: merge(["base"], [], ["B"]))
        let snapshot = doc
        doc.toggleCurrent(blockID: 0)
        XCTAssertEqual(doc.outputText, "")
        XCTAssertEqual(doc.outputLines, [])
        XCTAssertEqual(doc.outputLineOrigins, [])
        XCTAssertTrue(doc.unresolvedBlockIDs.isEmpty)
        XCTAssertTrue(doc.blocks[0].selectedSources.current)
        doc = snapshot
        XCTAssertEqual(doc.unresolvedBlockIDs, [0])
        XCTAssertEqual(doc.outputText, "base")
    }

    func testSelectingSourceAfterKeepBaseReplacesExplicitAncestor() {
        var doc = ConflictEditorDocument(sides: merge(["base"], ["A"], ["B"]))
        doc.keepAncestor(blockID: 0)
        XCTAssertTrue(doc.unresolvedBlockIDs.isEmpty)
        doc.toggleLine(blockID: 0, side: .incoming, line: 0)
        XCTAssertEqual(doc.outputText, "B")
        XCTAssertEqual(doc.selectedLineIndices(blockID: 0, side: .incoming), [0])
        doc.toggleLine(blockID: 0, side: .incoming, line: 0)
        XCTAssertEqual(doc.outputText, "base")
        XCTAssertEqual(doc.unresolvedBlockIDs, [0])
    }

    func testNoOpEmptyTextDoesNotResolveEmptyAncestorConflict() {
        var doc = ConflictEditorDocument(sides: merge([], ["A"], ["B"]))
        doc.updateOutputText("")
        XCTAssertEqual(doc.unresolvedBlockIDs, [0])
        doc.updateOutputText("manual")
        XCTAssertEqual(doc.outputText, "manual")
        XCTAssertEqual(doc.blocks[0].activeRange, 0..<1)
        XCTAssertTrue(doc.unresolvedBlockIDs.isEmpty)
    }

    func testManualInsertionAtChunkBoundaryBelongsToPrecedingConflict() {
        let sides = merge(["head", "x", "between", "y", "tail"],
                          ["head", "A", "between", "B", "tail"],
                          ["head", "X", "between", "Y", "tail"])
        var doc = ConflictEditorDocument(sides: sides)
        doc.updateOutputText("head\nx\ninserted\nbetween\ny\ntail")
        XCTAssertEqual(doc.blocks[0].activeRange, 1..<3)
        XCTAssertEqual(doc.unresolvedBlockIDs, [1])
        doc.toggleIncoming(blockID: 1)
        XCTAssertEqual(doc.outputText, "head\nx\ninserted\nbetween\nY\ntail")
    }

    func testSeparatedManualEditsPreserveInterveningChunkAndBlockOwnership() {
        let sides = merge(["head", "x", "between", "y", "tail"],
                          ["head", "A", "between", "B", "tail"],
                          ["head", "X", "between", "Y", "tail"])
        var doc = ConflictEditorDocument(sides: sides)
        doc.toggleCurrent(blockID: 0)
        doc.toggleCurrent(blockID: 1)
        doc.updateOutputText("head\nmanual-A\nbetween\nmanual-B\ntail")
        XCTAssertEqual(doc.outputText, "head\nmanual-A\nbetween\nmanual-B\ntail")
        XCTAssertEqual(doc.outputLineOrigins, [.common, .manual, .common, .manual, .common])
        XCTAssertEqual(doc.blocks[0].activeRange, 1..<2)
        XCTAssertEqual(doc.blocks[1].activeRange, 3..<4)
        doc.toggleIncoming(blockID: 1)
        XCTAssertEqual(doc.outputText, "head\nmanual-A\nbetween\nmanual-B\nY\ntail")
    }
}
