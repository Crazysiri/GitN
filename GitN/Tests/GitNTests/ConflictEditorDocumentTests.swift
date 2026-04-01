import XCTest
@testable import GitN

final class ConflictEditorDocumentTests: XCTestCase {
    func testAttachedSelectionReplacesControlledBlock() {
        var document = makeDocument()

        document.toggleIncoming(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "incoming-1",
                "incoming-2",
                "omega",
            ]
        )
        XCTAssertEqual(document.blocks[0].mode, .attached)
        XCTAssertEqual(document.blocks[0].contentState, .auto)
        XCTAssertEqual(
            document.outputLineOrigins,
            [.common, .incoming, .incoming, .common]
        )
    }

    func testInitialOutputLineOriginsMarkConflictLinesAsCurrent() {
        let document = makeDocument()

        XCTAssertEqual(
            document.outputLineOrigins,
            [.common, .ancestor, .ancestor, .common]
        )
    }

    func testEditingInsideAttachedBlockKeepsItAttached() {
        var document = makeDocument()

        document.updateOutputText(
            [
                "alpha",
                "current-edited",
                "omega",
            ].joined(separator: "\n")
        )

        XCTAssertEqual(document.blocks[0].mode, .attached)
        XCTAssertEqual(document.blocks[0].contentState, .edited)
        XCTAssertEqual(document.blocks[0].controlledBlock?.lineRange, 1..<2)
        XCTAssertEqual(
            document.outputLineOrigins,
            [.common, .manual, .common]
        )
    }

    func testDeletingAttachedBlockDetachesAndLaterSelectionInsertsAtAnchor() {
        var document = makeDocument()

        document.updateOutputText(
            [
                "alpha",
                "omega",
            ].joined(separator: "\n")
        )

        XCTAssertEqual(document.blocks[0].mode, .detached)
        XCTAssertNil(document.blocks[0].controlledBlock)

        document.toggleIncoming(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "incoming-1",
                "incoming-2",
                "omega",
            ]
        )
        XCTAssertEqual(document.blocks[0].mode, .detached)
        XCTAssertEqual(document.blocks[0].insertionSegment?.lineRange, 1..<3)
        XCTAssertEqual(
            document.outputLineOrigins,
            [.common, .incoming, .incoming, .common]
        )
    }

    func testDetachedSelectionUpdatesExistingInsertionSegmentWithoutDuplicating() {
        var document = makeDocument()
        document.updateOutputText(["alpha", "omega"].joined(separator: "\n"))
        document.toggleIncoming(blockID: 0)
        let firstRange = document.blocks[0].insertionSegment?.lineRange

        document.toggleCurrent(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "incoming-1",
                "incoming-2",
                "current-1",
                "omega",
            ]
        )
        XCTAssertEqual(firstRange?.lowerBound, 1)
        XCTAssertEqual(document.blocks[0].currentDisplayRange, 3..<4)
        XCTAssertEqual(document.blocks[0].insertionSegment?.lineRange, 3..<4)
    }

    func testDeletingInsertionSegmentAllowsRecreationOnNextSelection() {
        var document = makeDocument()
        document.updateOutputText(["alpha", "omega"].joined(separator: "\n"))
        document.toggleIncoming(blockID: 0)

        document.updateOutputText(["alpha", "omega"].joined(separator: "\n"))
        XCTAssertNil(document.blocks[0].insertionSegment)
        XCTAssertFalse(document.blocks[0].selectedSources.incoming)

        document.toggleIncoming(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "incoming-1",
                "incoming-2",
                "omega",
            ]
        )
    }

    func testAnchorStillFindsInsertionPointAfterLeadingLinesInserted() {
        var document = makeDocument()
        document.updateOutputText(
            [
                "prepended",
                "alpha",
                "omega",
            ].joined(separator: "\n")
        )

        document.toggleIncoming(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "prepended",
                "alpha",
                "incoming-1",
                "incoming-2",
                "omega",
            ]
        )
    }

    func testEditingConflictIntoBlankLinesStillAllowsSelectionReplacement() {
        var document = makeDocument()

        document.updateOutputText(
            [
                "alpha",
                "",
                "",
                "omega",
            ].joined(separator: "\n")
        )

        document.toggleIncoming(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "incoming-1",
                "incoming-2",
                "omega",
            ]
        )
    }

    func testDeletingSelectedConflictReinsertsAtDeletionStart() {
        var document = makeDocument()
        document.toggleCurrent(blockID: 0)

        document.updateOutputText(
            [
                "alpha",
                "omega",
            ].joined(separator: "\n")
        )

        XCTAssertFalse(document.blocks[0].selectedSources.current)
        XCTAssertEqual(document.blocks[0].anchor.preferredLine, 1)

        document.toggleCurrent(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "current-1",
                "omega",
            ]
        )
    }

    func testDeletingSelectedConflictWithRepeatedContextReinsertsAtNearestGap() {
        var document = ConflictEditorDocument(
            sides: makeSides(
                baseLines: ["prefix", "alpha", "base-1", "omega", "alpha", "omega", "suffix"],
                oursLines: ["prefix", "alpha", "current-1", "omega", "alpha", "omega", "suffix"],
                theirsLines: ["prefix", "alpha", "incoming-1", "omega", "alpha", "omega", "suffix"],
                mergedText: [
                    "prefix",
                    "alpha",
                    "<<<<<<< Current",
                    "current-1",
                    "||||||| Base",
                    "base-1",
                    "=======",
                    "incoming-1",
                    ">>>>>>> Incoming",
                    "omega",
                    "alpha",
                    "omega",
                    "suffix",
                ].joined(separator: "\n")
            )
        )
        document.toggleCurrent(blockID: 0)

        document.updateOutputText(
            [
                "prefix",
                "alpha",
                "omega",
                "alpha",
                "omega",
                "suffix",
            ].joined(separator: "\n")
        )

        document.toggleCurrent(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "prefix",
                "alpha",
                "current-1",
                "omega",
                "alpha",
                "omega",
                "suffix",
            ]
        )
    }

    func testDeletingBlankLineAndSelectedConflictReinsertsBeforeClosingDocstring() {
        var document = ConflictEditorDocument(
            sides: makeSides(
                baseLines: [
                    "#!/usr/bin/env python3",
                    "# -*- coding: utf-8 -*-",
                    "\"\"\"",
                    "通用开发执行器",
                    "",
                    "base-1",
                    "\"\"\"",
                    "",
                    "import logging",
                ],
                oursLines: [
                    "#!/usr/bin/env python3",
                    "# -*- coding: utf-8 -*-",
                    "\"\"\"",
                    "通用开发执行器",
                    "",
                    "current-1",
                    "current-2",
                    "\"\"\"",
                    "",
                    "import logging",
                ],
                theirsLines: [
                    "#!/usr/bin/env python3",
                    "# -*- coding: utf-8 -*-",
                    "\"\"\"",
                    "通用开发执行器",
                    "",
                    "incoming-1",
                    "\"\"\"",
                    "",
                    "import logging",
                ],
                mergedText: [
                    "#!/usr/bin/env python3",
                    "# -*- coding: utf-8 -*-",
                    "\"\"\"",
                    "通用开发执行器",
                    "",
                    "<<<<<<< Current",
                    "current-1",
                    "current-2",
                    "||||||| Base",
                    "base-1",
                    "=======",
                    "incoming-1",
                    ">>>>>>> Incoming",
                    "\"\"\"",
                    "",
                    "import logging",
                ].joined(separator: "\n")
            )
        )
        document.toggleCurrent(blockID: 0)

        document.updateOutputText(
            [
                "#!/usr/bin/env python3",
                "# -*- coding: utf-8 -*-",
                "\"\"\"",
                "通用开发执行器",
                "\"\"\"",
                "",
                "import logging",
            ].joined(separator: "\n")
        )

        XCTAssertEqual(document.blocks[0].directInsertionLine, 4)
        XCTAssertEqual(document.blocks[0].anchor.preferredLine, 4)

        document.toggleCurrent(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "#!/usr/bin/env python3",
                "# -*- coding: utf-8 -*-",
                "\"\"\"",
                "通用开发执行器",
                "current-1",
                "current-2",
                "\"\"\"",
                "",
                "import logging",
            ]
        )
    }

    func testDeletingSelectedConflictThenRemovingLeadingBlankLineMovesDirectInsertionUp() {
        var document = ConflictEditorDocument(
            sides: makeSides(
                baseLines: [
                    "#!/usr/bin/env python3",
                    "# -*- coding: utf-8 -*-",
                    "\"\"\"",
                    "通用开发执行器",
                    "",
                    "base-1",
                    "\"\"\"",
                    "",
                    "import logging",
                ],
                oursLines: [
                    "#!/usr/bin/env python3",
                    "# -*- coding: utf-8 -*-",
                    "\"\"\"",
                    "通用开发执行器",
                    "",
                    "current-1",
                    "current-2",
                    "\"\"\"",
                    "",
                    "import logging",
                ],
                theirsLines: [
                    "#!/usr/bin/env python3",
                    "# -*- coding: utf-8 -*-",
                    "\"\"\"",
                    "通用开发执行器",
                    "",
                    "incoming-1",
                    "\"\"\"",
                    "",
                    "import logging",
                ],
                mergedText: [
                    "#!/usr/bin/env python3",
                    "# -*- coding: utf-8 -*-",
                    "\"\"\"",
                    "通用开发执行器",
                    "",
                    "<<<<<<< Current",
                    "current-1",
                    "current-2",
                    "||||||| Base",
                    "base-1",
                    "=======",
                    "incoming-1",
                    ">>>>>>> Incoming",
                    "\"\"\"",
                    "",
                    "import logging",
                ].joined(separator: "\n")
            )
        )
        document.toggleCurrent(blockID: 0)

        document.updateOutputText(
            [
                "#!/usr/bin/env python3",
                "# -*- coding: utf-8 -*-",
                "\"\"\"",
                "通用开发执行器",
                "",
                "\"\"\"",
                "",
                "import logging",
            ].joined(separator: "\n")
        )

        XCTAssertEqual(document.blocks[0].directInsertionLine, 5)
        XCTAssertEqual(document.blocks[0].anchor.preferredLine, 5)

        document.updateOutputText(
            [
                "#!/usr/bin/env python3",
                "# -*- coding: utf-8 -*-",
                "\"\"\"",
                "通用开发执行器",
                "\"\"\"",
                "",
                "import logging",
            ].joined(separator: "\n")
        )

        XCTAssertEqual(document.blocks[0].directInsertionLine, 4)
        XCTAssertEqual(document.blocks[0].anchor.preferredLine, 4)

        document.toggleCurrent(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "#!/usr/bin/env python3",
                "# -*- coding: utf-8 -*-",
                "\"\"\"",
                "通用开发执行器",
                "current-1",
                "current-2",
                "\"\"\"",
                "",
                "import logging",
            ]
        )
    }

    func testReinsertedSelectionToggleOffAndOnAgainKeepsNearestAnchor() {
        var document = makeDocument()
        document.toggleCurrent(blockID: 0)

        document.updateOutputText(
            [
                "alpha",
                "omega",
            ].joined(separator: "\n")
        )

        document.toggleCurrent(blockID: 0)
        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "current-1",
                "omega",
            ]
        )

        document.toggleCurrent(blockID: 0)
        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "omega",
            ]
        )

        document.toggleCurrent(blockID: 0)
        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "current-1",
                "omega",
            ]
        )
        XCTAssertEqual(document.blocks[0].directInsertionLine, 1)
    }

    func testDetachedConflictCanInsertBackIntoHeavilyEditedOutput() {
        var document = makeDocument()

        document.updateOutputText(
            [
                "rewritten-start",
                "totally-different",
                "rewritten-end",
            ].joined(separator: "\n")
        )

        XCTAssertEqual(document.blocks[0].mode, .detached)

        document.toggleCurrent(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "rewritten-start",
                "current-1",
                "totally-different",
                "rewritten-end",
            ]
        )
    }

    func testEditingCheckedOutputClearsSelectionAndNextCheckInsertsBelowEditedContent() {
        var document = makeDocument()
        document.toggleCurrent(blockID: 0)

        document.updateOutputText(
            [
                "alpha",
                "current-1-edited",
                "omega",
            ].joined(separator: "\n")
        )

        XCTAssertFalse(document.blocks[0].selectedSources.current)
        XCTAssertFalse(document.blocks[0].selectedSources.incoming)
        XCTAssertEqual(document.blocks[0].mode, .detached)

        document.toggleIncoming(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "current-1-edited",
                "incoming-1",
                "incoming-2",
                "omega",
            ]
        )
    }

    func testEditingIncomingOnlyClearsIncomingSelectionAndKeepsCurrentSelection() {
        var document = makeDocument()
        document.toggleCurrent(blockID: 0)
        document.toggleIncoming(blockID: 0)

        document.updateOutputText(
            [
                "alpha",
                "current-1",
                "incoming-1-edited",
                "incoming-2",
                "omega",
            ].joined(separator: "\n")
        )

        XCTAssertTrue(document.blocks[0].selectedSources.current)
        XCTAssertFalse(document.blocks[0].selectedSources.incoming)
        XCTAssertNotNil(document.blocks[0].currentDisplayRange)
        XCTAssertNil(document.blocks[0].incomingDisplayRange)
    }

    func testEditingCurrentOnlyClearsCurrentSelectionAndKeepsIncomingSelection() {
        var document = makeDocument()
        document.toggleCurrent(blockID: 0)
        document.toggleIncoming(blockID: 0)

        document.updateOutputText(
            [
                "alpha",
                "current-1-edited",
                "incoming-1",
                "incoming-2",
                "omega",
            ].joined(separator: "\n")
        )

        XCTAssertFalse(document.blocks[0].selectedSources.current)
        XCTAssertTrue(document.blocks[0].selectedSources.incoming)
        XCTAssertNil(document.blocks[0].currentDisplayRange)
        XCTAssertNotNil(document.blocks[0].incomingDisplayRange)
    }

    func testReTogglingCurrentOffAfterReinsertKeepsIncomingVisible() {
        var document = makeDocument()
        document.toggleCurrent(blockID: 0)
        document.toggleIncoming(blockID: 0)

        document.updateOutputText(
            [
                "alpha",
                "current-1-edited",
                "incoming-1",
                "incoming-2",
                "omega",
            ].joined(separator: "\n")
        )

        document.toggleCurrent(blockID: 0)
        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "current-1-edited",
                "incoming-1",
                "incoming-2",
                "current-1",
                "omega",
            ]
        )

        document.toggleCurrent(blockID: 0)
        XCTAssertEqual(
            document.outputLines,
            [
                "alpha",
                "current-1-edited",
                "incoming-1",
                "incoming-2",
                "omega",
            ]
        )
        XCTAssertFalse(document.blocks[0].selectedSources.current)
        XCTAssertTrue(document.blocks[0].selectedSources.incoming)
    }

    func testAttachedSelectionUsesParsedConflictLinesWhenSideRangesDrift() {
        var document = ConflictEditorDocument(
            sides: makeSides(
                baseLines: [
                    "header",
                    "podfile_path = project_root / \"Podfile\"",
                    "try:",
                    "base-only",
                    "if not github_ok and not tuna_ok:",
                    "    logger.warning(\"skip\")",
                    "podfile_path = project_root / \"Podfile\"",
                    "try:",
                    "    result = subprocess.run()",
                ],
                oursLines: [
                    "header",
                    "podfile_path = project_root / \"Podfile\"",
                    "podfile_path = project_root / \"Podfile\"",
                    "try:",
                    "ours-only",
                    "if not github_ok and not tuna_ok:",
                    "    logger.warning(\"skip\")",
                    "podfile_path = project_root / \"Podfile\"",
                    "try:",
                    "    result = subprocess.run()",
                ],
                theirsLines: [
                    "header",
                    "podfile_path = project_root / \"Podfile\"",
                    "try:",
                    "if not github_ok and not tuna_ok:",
                    "    logger.warning(\"skip\")",
                    "podfile_path = project_root / \"Podfile\"",
                    "try:",
                    "    result = subprocess.run()",
                ],
                mergedText: [
                    "header",
                    "podfile_path = project_root / \"Podfile\"",
                    "podfile_path = project_root / \"Podfile\"",
                    "try:",
                    "<<<<<<< Current",
                    "ours-only",
                    "||||||| Base",
                    "base-only",
                    "=======",
                    ">>>>>>> Incoming",
                    "if not github_ok and not tuna_ok:",
                    "    logger.warning(\"skip\")",
                    "podfile_path = project_root / \"Podfile\"",
                    "try:",
                    "    result = subprocess.run()",
                ].joined(separator: "\n")
            )
        )

        document.toggleCurrent(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "header",
                "podfile_path = project_root / \"Podfile\"",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "ours-only",
                "if not github_ok and not tuna_ok:",
                "    logger.warning(\"skip\")",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "    result = subprocess.run()",
            ]
        )
    }

    func testSelectingEmptyIncomingInAttachedModeRemovesBaseLines() {
        var document = ConflictEditorDocument(
            sides: makeSides(
                baseLines: ["before", "base-1", "base-2", "after"],
                oursLines: ["before", "ours-1", "after"],
                theirsLines: ["before", "after"],
                mergedText: [
                    "before",
                    "<<<<<<< Current",
                    "ours-1",
                    "||||||| Base",
                    "base-1",
                    "base-2",
                    "=======",
                    ">>>>>>> Incoming",
                    "after",
                ].joined(separator: "\n")
            )
        )

        document.toggleIncoming(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "before",
                "after",
            ]
        )
        XCTAssertEqual(document.blocks[0].controlledBlock?.lineRange, 1..<1)
        XCTAssertEqual(document.blocks[0].incomingDisplayRange, 1..<1)
    }

    func testUnselectingEmptyIncomingInAttachedModeRestoresBaseLines() {
        var document = ConflictEditorDocument(
            sides: makeSides(
                baseLines: ["before", "base-1", "base-2", "after"],
                oursLines: ["before", "ours-1", "after"],
                theirsLines: ["before", "after"],
                mergedText: [
                    "before",
                    "<<<<<<< Current",
                    "ours-1",
                    "||||||| Base",
                    "base-1",
                    "base-2",
                    "=======",
                    ">>>>>>> Incoming",
                    "after",
                ].joined(separator: "\n")
            )
        )

        document.toggleIncoming(blockID: 0)
        document.toggleIncoming(blockID: 0)

        XCTAssertEqual(
            document.outputLines,
            [
                "before",
                "base-1",
                "base-2",
                "after",
            ]
        )
        XCTAssertEqual(document.blocks[0].controlledBlock?.lineRange, 1..<3)
        XCTAssertNil(document.blocks[0].incomingDisplayRange)
    }

    private func makeDocument() -> ConflictEditorDocument {
        ConflictEditorDocument(
            sides: makeSides(
                baseLines: ["alpha", "base-1", "base-2", "omega"],
                oursLines: ["alpha", "current-1", "omega"],
                theirsLines: ["alpha", "incoming-1", "incoming-2", "omega"],
                mergedText: [
                    "alpha",
                    "<<<<<<< Current",
                    "current-1",
                    "||||||| Base",
                    "base-1",
                    "base-2",
                    "=======",
                    "incoming-1",
                    "incoming-2",
                    ">>>>>>> Incoming",
                    "omega",
                ].joined(separator: "\n")
            )
        )
    }

    private func makeSides(
        baseLines: [String],
        oursLines: [String],
        theirsLines: [String],
        mergedText: String
    ) -> ConflictSides {
        GitService.buildConflictSides(
            mergedText: mergedText,
            baseLines: baseLines,
            oursLines: oursLines,
            theirsLines: theirsLines,
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )
    }
}
